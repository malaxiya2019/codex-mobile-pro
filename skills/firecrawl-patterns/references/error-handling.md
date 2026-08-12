# 结构化错误处理

> 来源：Firecrawl `apps/api/src/scraper/scrapeURL/engines/index.ts` 的 `EngineScrapeResult`

## 模式描述

错误信息结构化，包含错误码、用户可读消息、可操作建议列表。
用户看到错误后能按建议操作，而不是看到一堆技术术语。

## Firecrawl 原型

Firecrawl 的 `EngineScrapeResult` 包含 `error`（错误描述）和 `statusCode`（HTTP 状态码），部分引擎还有 `cacheInfo`。所有引擎返回统一结构，调度器不关心具体错误类型。

## codex-mobile-pro 适配

### 结构化 InstallError

```dart
/// 安装错误码
enum InstallErrorCode {
  dnsFailure,           // DNS 解析失败
  httpTimeout,          // 下载超时
  httpConnectionReset,  // 连接被重置（常见于墙）
  shaMismatch,          // SHA256 校验失败
  diskFull,             // 磁盘空间不足
  memoryLow,            // 内存不足
  extractionFailed,     // 解压失败
  archNotSupported,     // 架构不支持
  permissionDenied,     // 权限不足
  unknown,              // 未知错误
}

/// 结构化安装错误
class InstallError {
  final InstallErrorCode code;
  final String userMessage;        // 用户可读的错误信息（简短）
  final String? techDetail;        // 技术细节（仅日志使用）
  final List<String> suggestions;  // 可操作建议列表
  
  const InstallError({
    required this.code,
    required this.userMessage,
    this.techDetail,
    this.suggestions = const [],
  });
  
  /// 根据错误码提供默认建议
  static InstallError fromCode(InstallErrorCode code, {String? detail}) {
    switch (code) {
      case InstallErrorCode.dnsFailure:
        return InstallError(
          code: code,
          userMessage: '网络域名解析失败',
          techDetail: detail,
          suggestions: [
            '切换 Wi-Fi ↔ 移动数据后重试',
            '开关飞行模式（5 秒后关闭）',
            '在 Wi-Fi 设置中配置 DNS 为 8.8.8.8',
          ],
        );
      case InstallErrorCode.httpConnectionReset:
        return InstallError(
          code: code,
          userMessage: '下载连接被重置（可能是网络限制）',
          techDetail: detail,
          suggestions: [
            '切换网络环境（Wi-Fi → 移动数据 或反之）',
            '开启 VPN 后重试',
            '系统会在 30 秒后自动切换到备用镜像源',
          ],
        );
      case InstallErrorCode.diskFull:
        return InstallError(
          code: code,
          userMessage: '存储空间不足',
          techDetail: detail,
          suggestions: [
            '清理无用文件或应用缓存',
            '卸载不常用的 App',
            '至少需要 500MB 可用空间',
          ],
        );
      case InstallErrorCode.memoryLow:
        return InstallError(
          code: code,
          userMessage: '内存不足',
          techDetail: detail,
          suggestions: [
            '关闭后台运行的 App',
            '重启手机后重试',
            '至少需要 256MB 可用内存',
          ],
        );
      default:
        return InstallError(
          code: code,
          userMessage: '安装失败',
          techDetail: detail,
          suggestions: ['请重试，如果持续失败请联系支持'],
        );
    }
  }
}
```

### 当前 InstallResult 扩展

```dart
class InstallResult {
  final RuntimeTool tool;
  final bool success;
  final InstallError? error;       // ← 新增，替代 String? errorMessage
  final String? version;
  final InstallPhase phase;
  final int retryCount;            // ← 新增，跟踪重试次数
  
  // 兼容旧代码
  String? get errorMessage => error?.userMessage;
}
```

### 集成位置

- `RuntimeInstaller` 和 `UbuntuRuntimeInstaller` 抛出 `InstallException` 时使用 `InstallError.fromCode()`
- 安装前预检（`NetworkDetector.quickCheck()`）失败→ `dnsFailure`
- 下载异常（`SocketException`、`HttpException`）→ 识别错误码并映射
- UI 显示 `error.suggestions` 作为可点击的快速操作按钮

## 关键决策

| 设计点 | 决策 | 原因 |
|:---|:---|:---|
| code + suggestions | 每层错误都带建议 | 减少用户困惑，有明确操作方向 |
| techDetail 不进 UI | 只在日志中记录 | 避免技术术语吓到用户 |
| 兼容性 | `errorMessage` 保留为 getter | 不影响现有 UI 层代码 |
