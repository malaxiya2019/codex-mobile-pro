---
name: firecrawl-patterns
description: 参考 Firecrawl 高性能爬虫系统架构模式来优化 codex-mobile-pro 的部署中心。使用场景：DNS 缓存与网络检测优化、多引擎 fallback 安装策略、结构化错误处理、镜像切换与备用下载源。
---

# Firecrawl 架构模式 — codex-mobile-pro 适配指南

> 本文档系统性地梳理 Firecrawl（GitHub 25k+ ⭐ 开源爬虫 API）的核心架构模式，
> 并针对 codex-mobile-pro 的部署中心（Android Termux 环境）提出具体的改进方案。
> 所有模式均为移动端环境做了适配裁剪。

---

## 🔷 模式一：多引擎 Fallback 下载系统

### Firecrawl 做法

Firecrawl 的 scraping 引擎采用 **ordered fallback list** 机制：

1. **引擎注册表**：`/engines/index.ts` 中定义了 12+ 种引擎（fetch、playwright、fire-engine/chrome-cdp、fire-engine/tlsclient、pdf、document、index、exchange 等）
2. **引擎特征**：每个引擎声明支持的 feature flags（actions、screenshot、pdf、mobile、stealthProxy 等）和 quality 评分
3. **动态构建 fallback 列表**：`buildFallbackList()` 根据请求的特征动态排序：
   - 按 feature 匹配度评分（supportScore）
   - 按 quality 排序（正 quality 优先，负 quality 为兜底引擎）
   - 支持 `forceEngine` 强制指定
4. **兜底机制**：所有引擎失败抛出 `NoEnginesLeftError`，包含所有尝试过的引擎列表

### 移动端适配 — 多源下载 Fallback

```dart
// 镜像源注册表
enum DownloadSource {
  primary,      // 主源（packages.termux.dev / github.com）
  mirror1,      // 镜像1（Termux 国内镜像）
  mirror2,      // 镜像2（gitclone.com / ghproxy.com）
  ipDirect,     // IP 直连（绕过 DNS）
  cache,        // 本地缓存
}

// 下载源特征
class SourceCapability {
  final DownloadSource source;
  final int priority;          // 优先级（越高越优先尝试）
  final bool requiresDns;      // 是否需要 DNS 解析
  final bool requiresHttps;    // 是否需要 HTTPS
  final int speedGrade;        // 速度评级（1-5）
  final Set<String> regions;   // 可用区域
}

// 动态选择最佳下载源
List<DownloadSource> buildDownloadFallbackList({
  required bool dnsWorking,
  required bool hasNetwork,
  String? region,
}) {
  if (!dnsWorking) {
    // DNS 挂了 → 只用 IP 直连和缓存
    return [DownloadSource.ipDirect, DownloadSource.cache];
  }

  // DNS 正常 → 按优先级尝试
  return [
    DownloadSource.primary,    // 先试主源
    DownloadSource.mirror1,    // 再试镜像
    DownloadSource.mirror2,    // 备用镜像
    DownloadSource.ipDirect,   // IP 直连兜底
  ];
}
```

### 实施要点

1. **manifest 扩展**：在 `RuntimeManifest` 中为每个 artifact 添加备用 URL 列表
2. **下载层改造**：`artifact_manager.dart` 的 `_downloadFile` 支持按 fallback 列表顺序重试
3. **条件切换**：DNS 失败自动切 IP 直连；HTTPS 超时切 HTTP（安全域白名单内）

---

## 🔷 模式二：智能 DNS 缓存与解析器

### Firecrawl 做法

- 生产环境使用 `cacheable-lookup` NPM 包，包装 `dns.lookup`
- 开发环境直通（不缓存）
- 通过 `config.SENTRY_ENVIRONMENT` 区分环境

### 移动端适配 — 多层次 DNS 策略

```dart
/// DNS 解析器 — 多层 fallback
class DnsResolver {
  static const _resolvers = <DnsResolverStrategy>[
    _SystemResolver(),        // 方案1：系统 DNS（默认）
    _DnsOverHttpsResolver(),  // 方案2：DNS-over-HTTPS（8.8.8.8 / 1.1.1.1）
    _HostsFileResolver(),     // 方案3：硬编码 hosts（关键域名 IP 固化）
  ];

  static const _ipOverrides = <String, String>{
    // 当 DNS 完全挂掉时使用的 IP 直连映射
    'github.com':       '140.82.112.4',     // 可能过时，需定期更新
    'packages.termux.dev': '...',           // 需查实际 IP
    'api.github.com':   '140.82.112.10',
  };

  /// 解析域名，依次尝试每个解析器
  static Future<String?> resolve(String host) async {
    for (final resolver in _resolvers) {
      try {
        final ip = await resolver.resolve(host);
        if (ip != null) return ip;
      } catch (_) {
        continue; // 尝试下一个
      }
    }
    return null;
  }

  /// DNS-over-HTTPS 解析
  static Future<String?> _resolveDoH(String host) async {
    // 使用 curl 或 dart:io 调用 DoH API
    // https://dns.google/resolve?name=github.com&type=A
    // https://cloudflare-dns.com/dns-query?name=github.com&type=A
    final result = await Process.run('curl', [
      '-s', 'https://dns.google/resolve?name=$host&type=A',
    ]);
    // 解析 JSON 获取 answer[0].data
    return ip;
  }
}
```

### 缓存优化（已有基础上增强）

当前 `NetworkDetector` 已有 30s DNS 缓存，可增强：

| 特性 | 当前 | 增强后 |
|------|------|--------|
| TTL | 固定 30s | 跟随 DNS 记录的 TTL（最小 30s） |
| 范围 | 仅 3 个域名 | 所有下载目标域名 |
| 持久化 | 无 | 缓存到文件，跨会话持久 |
| 网络切换感知 | 手动 invalidate() | 自动监听网络变化 |
| DoH fallback | 无 | DNS 失败自动切 DoH |

---

## 🔷 模式三：结构化错误处理体系

### Firecrawl 做法

Firecrawl 定义了一套完整的错误体系：

1. **错误码枚举**：`ErrorCodes` 类型包含 35+ 精确错误码
2. **TransportableError**：可序列化的错误类，支持跨 worker 传输
3. **错误映射表**：`errorMap` 将错误码映射到具体错误类
4. **用户友好消息**：每个错误类内置可操作的建议文本
5. **分级处理**：按错误类型决定重试、降级或中止

### 移动端适配 — 部署错误体系

```dart
/// 部署错误码（增强现有 InstallErrorCode）
enum DeployErrorCode {
  // ─── 网络层 ───
  dnsResolutionFailed,        // DNS 解析失败
  dnsAllResolversExhausted,   // 所有解析器失败
  connectionTimeout,           // 连接超时
  connectionReset,             // 连接重置
  sslHandshakeFailed,          // SSL 握手失败
  httpError,                   // HTTP 错误（含状态码）

  // ─── 下载层 ───
  downloadInterrupted,        // 下载中断
  sizeMismatch,               // 大小不匹配
  sha256Mismatch,             // SHA256 校验失败
  allSourcesExhausted,        // 所有下载源失败
  partialDownload,            // 部分下载（断点续传机会）

  // ─── 解压/安装层 ───
  extractionFailed,           // 解压失败
  permissionDenied,           // 权限不足
  diskFull,                   // 磁盘空间不足
  binaryCorrupted,            // 二进制损坏
  healthCheckFailed,          // 健康检查失败

  // ─── 依赖层 ───
  dependencyMissing,          // 依赖缺失
  archNotSupported,           // 架构不支持
  versionMismatch,            // 版本不匹配

  // ─── 未知 ───
  unknown,
}

/// 可传输的部署错误（参照 Firecrawl TransportableError）
class DeployError implements Exception {
  final DeployErrorCode code;
  final String message;
  final String? detail;
  final String? userSuggestion;  // 用户可操作的建议
  final Map<String, dynamic>? context;  // 调试上下文

  const DeployError({
    required this.code,
    required this.message,
    this.detail,
    this.userSuggestion,
    this.context,
  });

  /// 序列化（用于跨 isolate/异步传输）
  Map<String, dynamic> toJson() => {
    'code': code.name,
    'message': message,
    'detail': detail,
    'suggestion': userSuggestion,
    'context': context,
  };

  /// 反序列化
  factory DeployError.fromJson(Map<String, dynamic> json) => DeployError(
    code: DeployErrorCode.values.byName(json['code']),
    message: json['message'],
    detail: json['detail'],
    userSuggestion: json['suggestion'],
    context: json['context'] as Map<String, dynamic>?,
  );

  /// 用户友好的完整错误信息
  String get userFriendly {
    final buf = StringBuffer('❌ $message');
    if (userSuggestion != null) {
      buf.writeln();
      buf.write('\n💡 建议：$userSuggestion');
    }
    return buf.toString();
  }

  /// 是否应当重试
  bool get isRetryable => switch (code) {
    DeployErrorCode.dnsResolutionFailed ||
    DeployErrorCode.connectionTimeout ||
    DeployErrorCode.connectionReset ||
    DeployErrorCode.downloadInterrupted ||
    DeployErrorCode.allSourcesExhausted => true,
    _ => false,
  };

  /// 是否需要降级方案
  bool get requiresDegradation => switch (code) {
    DeployErrorCode.dnsResolutionFailed ||
    DeployErrorCode.allSourcesExhausted => true,
    _ => false,
  };
}

/// 错误建议映射（参照 Firecrawl 每个错误类内置建议文本）
class DeployErrorSuggestions {
  static const Map<DeployErrorCode, String> suggestions = {
    DeployErrorCode.dnsResolutionFailed:
      'DNS 解析失败。① 切换 Wi-Fi ↔ 移动数据后重试 ② 开启飞行模式再关闭 ③ 配置公共 DNS：8.8.8.8',
    DeployErrorCode.connectionTimeout:
      '连接超时，服务器可能不可达。① 检查网络连接 ② 稍后重试 ③ 尝试使用镜像源',
    DeployErrorCode.sslHandshakeFailed:
      'SSL 握手失败。① 检查系统时间是否正确 ② 尝试 HTTP（非 HTTPS）镜像源',
    DeployErrorCode.permissionDenied:
      '权限不足。请确保：① 已授予存储权限 ② 重启应用后重试 ③ 清理缓存目录',
    DeployErrorCode.diskFull:
      '存储空间不足。请释放空间后重试，至少需要 500MB 可用空间',
    DeployErrorCode.allSourcesExhausted:
      '所有下载源均不可用。请检查网络连接，或等待一段时间后重试',
  };
}
```

---

## 🔷 模式四：并发队列与下载调度

### Firecrawl 做法

- **双后端队列**：支持 PostgreSQL（pg）和 FoundationDB（fdb）双后端
- **并发控制**：`concurrency-queue-reconciler.ts` 定时检查 backlog 队列，自动回填并发槽位
- **优先级队列**：`getJobPriority()` 计算每个任务的优先级
- **Backlog 恢复**：中断的任务自动回到待处理队列，不丢失

### 移动端适配 — 下载队列调度

```dart
/// 安装任务优先级
enum InstallPriority {
  critical,   // 内核级（Termux 环境本身）
  high,       // 核心运行时（Node.js / Ubuntu rootfs）
  normal,     // 工具（git / python）
  low,        // 可选组件
  background, // 后台预取
}

/// 下载任务
class DownloadJob {
  final String id;
  final RuntimeTool tool;
  final RuntimeArtifact artifact;
  final InstallPriority priority;
  final DateTime createdAt;
  final List<DownloadSource> fallbackSources;
  int retryCount;
  DownloadJobStatus status;

  /// 当前剩余尝试次数
  int get remainingAttempts => maxRetries - retryCount;

  /// 是否应该重试
  bool get shouldRetry => status == DownloadJobStatus.failed
    && retryCount < maxRetries
    && _currentError?.isRetryable == true;
}

/// 队列调度器（参照 Firecrawl NuQ 简化版）
class DownloadQueueScheduler {
  final Queue<DownloadJob> _queue = Queue();
  int _activeCount = 0;
  final int _maxConcurrent;

  /// 当前网络质量（影响并发数）
  NetworkQuality _networkQuality = NetworkQuality.unknown;

  /// 根据网络质量动态调整并发
  int get effectiveConcurrency => switch (_networkQuality) {
    NetworkQuality.excellent => _maxConcurrent,      // WiFi 强 → 全速
    NetworkQuality.good => (_maxConcurrent * 0.7).ceil(),
    NetworkQuality.fair => (_maxConcurrent * 0.4).ceil(),
    NetworkQuality.poor => 1,                          // 弱网 → 串行
    NetworkQuality.unknown => _maxConcurrent ~/ 2,
  };

  /// 入队（检查依赖 + 去重）
  void enqueue(DownloadJob job) {
    // 1. 检查是否已存在相同任务
    if (_isDuplicate(job)) return;
    // 2. 检查依赖是否已完成
    if (!_dependenciesSatisfied(job)) {
      _dependencyQueue.add(job);
      return;
    }
    // 3. 按优先级插入
    _queue.add(job);
  }

  /// Backlog 恢复——应用重启后扫描未完成下载
  Future<void> recoverBacklog() async {
    final incomplete = await _loadIncompleteDownloads();
    for (final job in incomplete) {
      job.status = DownloadJobStatus.pending;
      enqueue(job);
    }
  }
}
```

---

## 🔷 模式五：功能特征匹配（Feature Flag System）

### Firecrawl 做法

核心机制是 **feature flag matching**：
1. 每个请求附带一组 feature flags（actions、screenshot、mobile 等）
2. 每个引擎声明支持哪些 features
3. `buildFallbackList()` 只选择 supportScore >= threshold 的引擎
4. 支持 `forceEngine` 绕过自动选择

### 移动端适配 — 下载源特征匹配

```dart
/// 网络环境特征
class NetworkProfile {
  final bool dnsWorking;
  final bool httpsSupported;
  final bool isMetered;
  final int latencyMs;
  final int bandwidthKbps;     // 估算带宽
  final String? region;        // 地理区域
  final String? carrier;       // 运营商

  bool get isSlowNetwork => bandwidthKbps < 500;
  bool get isHighLatency => latencyMs > 1000;
}

/// 下载源特征
extension SourceMatching on DownloadSource {
  bool matches(NetworkProfile network) {
    return switch (this) {
      DownloadSource.primary => network.dnsWorking && !network.isMetered,
      DownloadSource.mirror1 => network.dnsWorking,
      DownloadSource.mirror2 => network.dnsWorking,
      DownloadSource.ipDirect => true,  // 始终可用
      DownloadSource.cache => true,
    };
  }

  /// 匹配度评分（0-100）
  int matchScore(NetworkProfile network) {
    int score = 50;
    if (this == DownloadSource.ipDirect && !network.dnsWorking) score += 30;
    if (this == DownloadSource.primary && network.bandwidthKbps > 1000) score += 20;
    if (this == DownloadSource.mirror1 && region == 'cn') score += 25;
    return score;
  }
}
```

---

## 🔷 模式六：健康检查与安装验证

### Firecrawl 做法

- 每个引擎有自己的 `maxReasonableTime`（MRT）—— 超过此时间认为引擎不可用
- 引擎失败后更新运行时状态，影响后续选择
- 请求级 abort manager 控制超时

### 移动端适配 — 安装后验证链

```dart
/// 验证步骤链（参照 Firecrawl engine quality 设计）
class HealthCheckChain {
  static List<HealthCheckStep> chainFor(RuntimeTool tool) => switch (tool) {
    RuntimeTool.node => [
      _CheckBinary('node'),
      _CheckVersion('node --version'),
      _CheckArch('node -e "console.log(process.arch)"'),
      _CheckNpm('npm --version'),
      _CheckLibs(['libc++_shared.so', 'libcrypto.so.3']),
      _CheckFunctional('node -e "require(\'fs\').writeFileSync(\'/tmp/test\', \'ok\')"'),
    ],
    RuntimeTool.ubuntu => [
      _CheckBinary('/usr/bin/bash'),
      _CheckBinary('/usr/bin/apt'),
      _CheckBinary('proot'),
      _CheckLoader('proot-loader'),
      _CheckSysdata(),
      _CheckProotExec('./proot -v 2>&1 | grep "proot"'),
    ],
  };
}

/// 验证超时（对应 Firecrawl engine MRT）
class CheckTimeout {
  static const Map<RuntimeTool, Duration> timeouts = {
    RuntimeTool.node:  Duration(seconds: 30),
    RuntimeTool.ubuntu: Duration(seconds: 60),
    RuntimeTool.git:   Duration(seconds: 10),
  };
}
```

---

## 🔷 模式七：安装清单扩展（多层镜像支持）

### Firecrawl 做法

每个 scrape 请求的参数（url, formats, actions 等）在 `ScrapeOptions` 中统一定义，引擎根据这些参数选择最优策略。

### 移动端适配 — 多镜像 Manifest

当前 `RuntimeManifest` 每个 artifact 只有一个 url。扩展方案：

```dart
/// 镜像下载源
class MirrorSource {
  final String url;
  final String? region;       // 适用区域
  final bool requiresDns;     // 是否需要 DNS
  final bool requiresHttps;   // 是否需要 HTTPS
  final int priority;         // 优先级
  final bool isIpDirect;      // 是否为 IP 直连
}

/// 增强 Artifact
class EnhancedRuntimeArtifact {
  final String name;
  final String primaryUrl;
  final List<MirrorSource> mirrors;  // 备用镜像
  final String sha256;
  final int size;
  final int stripComponents;

  /// 获取可用的下载 URL 列表（按网络状况排序）
  List<MirrorSource> getAvailableSources(NetworkProfile network) {
    final sources = <MirrorSource>[
      MirrorSource(url: primaryUrl, priority: 100, requiresDns: true),
      ...mirrors,
    ];

    // 过滤：排除网络不支持的方式
    sources.removeWhere((s) =>
      (s.requiresDns && !network.dnsWorking));

    // 排序：优先级高的优先
    sources.sort((a, b) => b.priority.compareTo(a.priority));
    return sources;
  }
}
```

---

## 实施路径建议

| 阶段 | 内容 | 影响范围 |
|------|------|----------|
| **P0** | 增强 DNS 解析（DoH fallback + IP 直连） | `NetworkDetector`、`artifact_manager.dart` |
| **P1** | 扩展 Manifest 支持多镜像 | `runtime_manifest.dart` |
| **P2** | 实现多引擎 fallback 下载 | `artifact_manager.dart` 核心下载逻辑 |
| **P3** | 结构化错误体系（DeployError） | `runtime_installer.dart`、`ubuntu_runtime_installer.dart` |
| **P4** | 下载队列调度 + Backlog 恢复 | 新增 `download_queue.dart`、修改 `runtime_manager.dart` |
| **P5** | 网络环境感知（带宽估算、运营商检测） | 新增 `network_profiler.dart` |

---

## 参考

- Firecrawl 源码: `apps/api/src/scraper/scrapeURL/engines/index.ts`
- Firecrawl 错误体系: `apps/api/src/lib/error.ts`, `apps/api/src/scraper/scrapeURL/error.ts`
- Firecrawl DNS 缓存: `apps/api/src/scraper/scrapeURL/lib/cacheableLookup.ts`
- Firecrawl 并发队列: `apps/api/src/lib/concurrency-queue-reconciler.ts`
- Firecrawl 双后端路由: `apps/api/src/services/worker/nuq-router.ts`
