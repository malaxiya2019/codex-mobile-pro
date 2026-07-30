# Firecrawl 架构分析报告

> 分析日期：2026-07-30
> 分析对象：https://github.com/firecrawl/firecrawl
> 目标项目：codex-mobile-pro（Flutter/Dart 移动端 AI IDE）

---

## 1. 可直接借鉴（High Impact — Low Effort）

### 1.1 DNS 缓存层

- **源文件**：`apps/api/src/scraper/scrapeURL/lib/cacheableLookup.ts`
- **作用**：缓存 DNS 查询结果，避免每次网络请求都重新解析域名。开发环境走原生 `dns.lookup`，生产环境走 `CacheableLookup`。
- **迁移到 codex-mobile-pro 的落地方式**：
  - 当前 `NetworkDetector` 每次检测都 `ping` 3 个域名，耗时 3×3=9 秒
  - 可以在 `NetworkDetector` 中引入 **内存 DNS 缓存**：
    - `Map<String, { ip: String?, timestamp: DateTime }>` 
    - 缓存 TTL = 30 秒（移动网络变化快，TTL 不宜太长）
    - 安装过程中重复 DNS 查询先从缓存取
  - 更进一步的方案：Android 上通过 `getprop net.dns1` 获取 DNS 服务器 → 用 Dart `InternetAddress.lookup()` 解析并缓存
  - **优先级**：高（直接解决 DNS 频繁查询问题，减少 50%+ 的检测延迟）

### 1.2 引擎 quality 排序 + Fallback 链

- **源文件**：`apps/api/src/scraper/scrapeURL/engines/index.ts` 第 1-250 行
- **作用**：每个引擎有 `quality`（功能丰富度）和 `features` 矩阵；选择引擎时：按 quality 降序 → 剔除不满足 feature flag 的 → 逐个尝试 → 失败后 fallback
- **迁移到 codex-mobile-pro 的落地方式**：
  - 当前安装链路是固定的：`Node.js → Git → Python → Codex CLI → mimo2codex`，一个失败就 `blocked` 后续所有
  - 可以引入 **InstallEngine** 概念：
    ```dart
    abstract class InstallEngine {
      int get quality;        // 100=ubuntu方案, 50=deb方案, 10=源码编译
      Set<Feature> get features; // offline、air-gapped、fast等
      Future<InstallResult> install(RuntimeTool tool);
    }
    ```
  - 例如 Node.js 安装可以有 2 个引擎：
    - `UbuntuAptEngine` (quality: 100) — 通过 Ubuntu proot 内的 apt 安装
    - `TermuxDebEngine` (quality: 50) — 直接下载 .deb 包
  - **优先级**：中（当前 Ubuntu rootfs 还没稳定，先让 ubuntu 跑通再搞多引擎）

### 1.3 结构化错误处理 + 用户可操作建议

- **源文件**：`apps/api/src/scraper/scrapeURL/engines/` 各引擎的 error 处理
- **作用**：不同引擎返回统一的 `EngineScrapeResult` 结构，含 `error`、`statusCode`、`cacheInfo` 等字段；用户可见的错误信息结构化
- **迁移落地**：
  - 当前 `InstallResult` 只有 `errorMessage: String?`，太笼统
  - 可以扩展为结构化错误：
    ```dart
    class InstallError {
      final InstallErrorCode code;       // dnsFailure / httpTimeout / shaMismatch / diskFull / ...
      final String userMessage;          // 用户可读
      final String? techDetail;          // 技术细节（日志用）
      final List<String> suggestions;    // 【新增】可操作建议列表
    }
    ```
  - 例如 DNS 错误：`suggestions = ["切换 Wi-Fi", "开飞行模式重试", "配置 DNS: 8.8.8.8"]`
  - 这已经在 `network_detector.dart` 的 `suggestion` getter 里部分实现了，但还没推广到其他错误
  - **优先级**：高（改善用户体验，当前错误信息太模糊）

### 1.4 功能标志驱动的行为选择

- **源文件**：`apps/api/src/scraper/scrapeURL/engines/index.ts` 第 30-70 行的 `FeatureFlag` 类型和 `featureFlagOptions`
- **作用**：每个功能（screenshot、pdf、actions 等）有 `priority`，引擎根据 feature flags 集合计算 `supportScore`，超过 `priorityThreshold` 才被选中
- **迁移落地**：
  - 当前 install 逻辑是线性的：`if (tool == ubuntu) use ubuntuInstaller else use normalInstaller`
  - 可以引入 **InstallFeatureFlag**：
    ```dart
    enum InstallFeature {
      needsGpu,          // 需要 GPU 加速 → 跳过某些 arch
      needsLargeDisk,    // 需要 >500MB → 先检查存储
      needsNetwork,      // 需要网络 → 先做 DNS 预检
      offlineCapable,    // 支持离线安装 → cache 优先
      needsProot,        // 需要 proot → 必须 ubuntu
    }
    ```
  - 安装器声明自己支持的 features，管理器按需匹配
  - **优先级**：低（当前工具少，线性逻辑够用；等工具增多后才需要）

---

## 2. 可参考设计（Medium Impact — Medium Effort）

### 2.1 Rust napi 架构 → Flutter FFI 启发

- **源文件**：`apps/api/native/` 全部；`Cargo.toml` 使用 `napi` + `napi-derive`
- **作用**：Firecrawl 把 CPU 密集型操作（爬虫过滤、HTML 解析、PDF 处理、文档转换）挪到 Rust 中执行，通过 N-API 暴露给 Node.js，性能提升 10-100x
- **对 Flutter 的启发**：
  - Flutter 也有 **dart:ffi** 和 **Native Assets**（Flutter 3.x+）
  - performance-critical 路径可以写 Dart native extension 或 Rust → C ABI → Dart FFI
  - 具体到 codex-mobile-pro 的候选：
    - **tar.xz 解压**：当前 Dart 解压大文件慢；可以考虑用 zlib/C 解压
    - **SHA256 校验**：大文件校验时用 FFI 调用 BoringSSL 的 SHA256
    - **Deb 包解析**：ar + tar.xz 解析，当前 Dart 实现可能 slow
  - 不过移动端主要是 I/O bound（下载/解压），CPU bound 不是瓶颈，**暂时不需要**
  - **优先级**：低（先跑通功能，后续性能优化时再考虑）

### 2.2 统一的安装进度/状态流

- **源文件**：`apps/api/src/scraper/scrapeURL/engines/index.ts` 第 244-280 行的 `scrapeURLWithEngine` 统一接口
- **作用**：所有引擎实现同一个函数签名 `(meta: Meta) => Promise<EngineScrapeResult>`，主调度器不关心具体引擎实现
- **迁移落地**：
  - 当前 `RuntimeInstaller` 和 `UbuntuRuntimeInstaller` 有不同接口
  - 可以统一为：
    ```dart
    abstract class RuntimeInstallerStrategy {
      String get id;
      Future<InstallResult> install(RuntimeTool tool, RuntimeEnvironment env);
      Future<InstallProgress> dryRun(RuntimeTool tool); // 预检：需要多少空间/时间
    }
    ```
  - Ubuntu 安装器、Deb 安装器、源码编译安装器都实现这个接口
  - **优先级**：中（当前架构扩展性够用，但多引擎场景需要统一接口）

### 2.3 MaxReasonableTime (MRT) 超时策略

- **源文件**：`apps/api/src/scraper/scrapeURL/engines/index.ts` 第 80-110 行的 `engineMRTs`
- **作用**：每个引擎有自己的合理的最大等待时间（MRT），比全局超时更精细
- **迁移落地**：
  - 当前下载没有超时管理，大文件下载可能挂起很久
  - 可以在 `ArtifactManager` 中引入：
    ```dart
    class ArtifactTimeout {
      final Duration downloadTimeout;   // 文件下载超时
      final Duration extractTimeout;    // 解压超时
      final Duration verifyTimeout;     // 校验超时
    }
    ```
  - 对于不同大小的 artifact 使用不同的超时：rootfs (60MB) 给 120s，proot (100KB) 给 30s
  - **优先级**：中（防止大文件下载挂起）

### 2.4 URL 级别阻断/白名单

- **源文件**：`apps/api/src/scraper/WebScraper/utils/blocklist.ts`（通过 Exchange blocklist 引用）
- **作用**：某些 URL 被阻断时，只允许 Exchange 引擎访问，防止普通引擎泄露受限内容
- **迁移落地**：
  - 当前所有 artifact URL 都是硬编码的
  - 可以引入 **MirrorResolver**：
    ```dart
    class MirrorResolver {
      // 主 URL → 备用镜像列表
      static const _mirrors = {
        'packages.termux.dev': ['packages.termux.dev', 'mirrors.tuna.tsinghua.edu.cn/termux'],
        'github.com': ['github.com', 'hub.fastgit.org'],
      };
      
      // 根据 DNS 可用性选择最佳镜像
      static Future<String> resolve(String primaryUrl) async { ... }
    }
    ```
  - DNS 故障时自动切换到国内镜像
  - **优先级**：高（对国内用户至关重要，当前 DNS 问题很多源于墙）

---

## 3. 暂不适用（Low Impact / Context Mismatch）

| Firecrawl 特性 | 不适用原因 |
|:---|:---|
| **Branding/Logo 提取** | codex-mobile-pro 不需要从网页提取品牌信息 |
| **deterministicJson 管道** | LLM + DOM 分析是服务端场景；移动端没有大量结构化提取需求 |
| **Google Web Risk / Zscaler** | 企业级安全特性，移动端 AI IDE 不需要 |
| **SIEM 日志系统** | 企业安全审计，个人 App 不需要 |
| **Playwright / Chrome CDP** | 无头浏览器引擎，移动端无法运行 |
| **Exchange 引擎** | 企业数据交换，与 Runtime 安装无关 |
| **Sitemap 解析** | 爬虫特性，与 Runtime 无关 |

---

## 4. 当前问题对照分析

### 4.1 DNS 解析失败的问题 🎯 最紧急

**现状**：
- `NetworkDetector` 用 `ping -c 1 -W 3` 检测 3 个域名
- 失败后只给出用户建议（切换网络/配置 DNS）
- 但用户可能无法切换网络（例如在飞机上、公司内网）

**Firecrawl 的解法**：
- `cacheable-lookup` 缓存 DNS 结果，减少重复查询
- 通过 `https.globalAgent` 集成到所有 HTTP 请求中

**codex-mobile-pro 改进方案**：

1. **DNS 缓存层**（立即做）：
   - 在 `NetworkDetector` 中添加 `DnsCache` 类
   - TTL = 30s，减少重复 ping
   - 检测到 DNS 失败时，记录失败时间，30s 内不再重复检测

2. **镜像自动切换**（短期做）：
   - `MirrorResolver` 检测到主域名解析失败后，自动切换到国内镜像
   - 例如 `packages.termux.dev` → `mirrors.tuna.tsinghua.edu.cn/termux`

3. **DNS over HTTPS (DoH) 备用**（中期做）：
   - Android 上可以用 `curl -H "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=github.com&type=A"`
   - 绕过系统 DNS，直接通过 HTTPS 解析
   - 系统 DNS 挂了也能工作

### 4.2 Ubuntu 安装后闪退的问题 🔍

**现状**：
- 安装进度到 50%（解压 rootfs）后闪退
- 可能是 OOM（内存不足）或解压过程中断

**改进方向**：
- 添加解压前的**可用内存检测**
- 使用流式解压（边下载边解压），而不是全部下载到内存再解压
- 错误处理捕获解压异常，给出具体建议

### 4.3 安装器架构统一

**现状**：
- `RuntimeInstaller`（deb 单包）和 `UbuntuRuntimeInstaller`（rootfs）实现不同
- 选择逻辑是 `if-else` 硬编码

**参考 Firecrawl 改进**：
- 引入 `InstallStrategy` 抽象
- 每个工具可以有多个策略，按 quality 排序
- 策略失败后自动 fallback

---

## 5. 具体改进计划

### 5.1 立即执行（优先级高）

| 改进项 | 文件 | 说明 |
|:---|:---|:---|
| DNS 缓存层 | `lib/core/detector/detectors/network_detector.dart` | 加 `DnsCache`，减少重复 ping |
| 结构化错误 | `lib/runtime/runtime_installer.dart` | `InstallError` 加 `suggestions` |
| 镜像切换 | `lib/runtime/runtime_manifest.dart` | 每个 artifact URL 加备用镜像 |

### 5.2 短期执行（优先级中）

| 改进项 | 文件 | 说明 |
|:---|:---|:---|
| 统一 InstallStrategy | `lib/runtime/install_strategy.dart`（新建） | 抽象安装策略接口 |
| MRT 超时 | `lib/runtime/artifact_manager.dart` | 按 artifact 大小设超时 |
| 解压前内存检测 | `lib/runtime/ubuntu_runtime_installer.dart` | 解压前检查可用内存 |

### 5.3 中长期（优先级低）

| 改进项 | 说明 |
|:---|:---|
| DoH 备用 DNS | 系统 DNS 挂了后用 HTTPS 解析 |
| Flutter FFI 优化 | 大文件 SHA256 / 解压用原生加速 |
| 多引擎安装 | 同一工具多个安装策略，自动 fallback |

---

## 6. 总结

Firecrawl 最值得 codex-mobile-pro 借鉴的**三点**：

1. **DNS 缓存 + 智能降级** → 解决当前最紧迫的 DNS 解析失败问题
2. **引擎 quality 排序 + Fallback 链** → 安装器架构从线性变成多策略
3. **统一错误结构 + 可操作建议** → 改善用户体验

这三点的直接效果是：用户当前遇到的 `SocketException: Failed host lookup: 'github.com'` 可以得到自动修复（镜像切换）或更明确的指引（DNS 诊断 + 建议列表），而不是简单地"网络不可用"后退出。
