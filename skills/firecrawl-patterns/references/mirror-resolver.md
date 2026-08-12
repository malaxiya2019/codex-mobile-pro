# 镜像切换策略

> 来源：Firecrawl `apps/api/src/scraper/WebScraper/utils/blocklist.ts`（阻断/放行）的启发

## 模式描述

所有外网下载 URL 配置备用镜像源。主域名解析失败或连接超时后，自动切换到镜像源重试。

## 核心结构

```dart
class MirrorResolver {
  /// URL 镜像映射（主 URL → 备用镜像列表）
  static const _mirrorMap = <String, List<String>>{
    'packages.termux.dev': [
      'packages.termux.dev',
      'mirrors.tuna.tsinghua.edu.cn/termux',
      'mirrors.aliyun.com/termux',
    ],
    'github.com': [
      'github.com',
      'hub.gitmirror.com',
    ],
  };
  
  /// 镜像切换状态（当前正在使用哪个镜像源）
  static final _activeMirrors = <String, int>{};
  static const _failureThreshold = 2;  // 连续失败 2 次后切换镜像
  static final _failureCount = <String, int>{};
  
  /// 获取最佳下载 URL
  ///
  /// [originalUrl] — 原始 URL（如 https://packages.termux.dev/.../node.deb）
  /// 返回替换域名后的 URL
  static Future<String> resolve(String originalUrl) async {
    final uri = Uri.parse(originalUrl);
    final mirrors = _mirrorMap[uri.host] ?? [uri.host];
    final startIndex = _activeMirrors[uri.host] ?? 0;
    
    for (var i = startIndex; i < mirrors.length; i++) {
      final mirror = mirrors[i];
      final mirrorUrl = originalUrl.replace(uri.host, mirror);
      
      // 测试镜像连通性（快速 ping）
      if (await _testMirror(mirror, timeout: Duration(seconds: 2))) {
        _activeMirrors[uri.host] = i;
        return mirrorUrl;
      }
    }
    
    // 全部镜像不可用 → 返回原始 URL，调用方处理错误
    return originalUrl;
  }
  
  /// 记录失败（调用方在下载失败后调用）
  static void recordFailure(String url) {
    final uri = Uri.parse(url);
    _failureCount[uri.host] = (_failureCount[uri.host] ?? 0) + 1;
    
    if ((_failureCount[uri.host] ?? 0) >= _failureThreshold) {
      final current = _activeMirrors[uri.host] ?? 0;
      _activeMirrors[uri.host] = current + 1;  // 切到下一个镜像
      _failureCount[uri.host] = 0;
    }
  }
  
  /// 检测镜像可用性
  static Future<bool> _testMirror(String host, {required Duration timeout}) async {
    try {
      final result = await Process.run(
        'ping', ['-c', '1', '-W', '${timeout.inSeconds}', host],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
```

## 集成位置

- `ArtifactManager.downloadAndExtract()` 中下载前调用 `MirrorResolver.resolve(url)`
- 下载失败后调用 `MirrorResolver.recordFailure(url)`
- 在 `NetworkDetector` 中也可用 — DNS 检测时顺便测试所有镜像的可用性

## 镜像列表维护原则

1. **主镜像始终是官方源** — 优先走官方，保证文件最新
2. **国内镜像优先清华/阿里** — 对国内用户友好，延迟低
3. **镜像不验证 SHA256 差异** — 同一文件在不同镜像的哈希应相同
4. **按需扩展** — 发现某个镜像失效时更新列表

## 关键决策

| 设计点 | 决策 | 原因 |
|:---|:---|:---|
| 探测方式 | ping（ICMP） | 轻量，不依赖 HTTP 服务 |
| 探测超时 | 2s | 快速失败，不阻塞安装 |
| 切换阈值 | 连续 2 次失败 | 1 次可能是偶然超时 |
| 持久化 | 不持久化 | 每次启动重新探测，适应网络变化 |
