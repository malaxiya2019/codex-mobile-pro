/// ====================================================================
/// 部署错误体系（P3）
///
/// 参照 Firecrawl 的 TransportableError + errorMap 模式：
/// - 统一错误码枚举
/// - 可序列化（跨 isolate 传输）
/// - 内置重试判定 / 降级判定 / 用户建议
/// - 取代 InstallException(×2) 和 ArtifactException
/// ====================================================================
library;

/// 部署错误码
///
/// 参照 Firecrawl ErrorCodes（35+ 精确码），按层分组：
///   网络层 → 下载层 → 解压安装层 → 依赖层 → 未知
enum DeployErrorCode {
  // ─── 网络层 ───
  dnsResolutionFailed,
  dnsAllResolversExhausted,
  connectionTimeout,
  connectionReset,
  sslHandshakeFailed,
  httpError,

  // ─── 下载层 ───
  downloadInterrupted,
  sizeMismatch,
  sha256Mismatch,
  allSourcesExhausted,

  // ─── 解压 / 安装层 ───
  extractionFailed,
  permissionDenied,
  diskFull,
  binaryCorrupted,
  healthCheckFailed,

  // ─── 依赖层 ───
  archNotSupported,
  dependencyMissing,
  toolInstallationFailed,
  versionMismatch,

  // ─── 工具链安装层（Coding Runtime apt/npm）───
  /// `apt-get update` 失败（源不可达 / DNS / 网络）
  aptUpdateFailed,

  /// `apt-get install` 失败（包不存在 / 依赖冲突 / 权限）
  aptInstallFailed,

  /// npm 全局安装失败
  npmInstallFailed,

  // ─── 并发 / 状态 ───
  deploymentInProgress,

  // ─── 未知 ───
  unknown,
}

/// 可传输的部署错误（参照 Firecrawl TransportableError）
class DeployError implements Exception {
  final DeployErrorCode code;
  final String message;
  final String? detail;
  final String? userSuggestion;
  final Map<String, dynamic>? context;

  const DeployError({
    required this.code,
    required this.message,
    this.detail,
    this.userSuggestion,
    this.context,
  });

  /// 序列化（用于跨 isolate / 异步传输）
  Map<String, dynamic> toJson() => {
        'code': code.name,
        'message': message,
        'detail': detail,
        'suggestion': userSuggestion,
        'context': context,
      };

  /// 反序列化
  factory DeployError.fromJson(Map<String, dynamic> json) => DeployError(
        code: DeployErrorCode.values.byName(json['code'] as String),
        message: json['message'] as String,
        detail: json['detail'] as String?,
        userSuggestion: json['suggestion'] as String?,
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

  /// 是否应当重试（网络波动类可重试，校验失败类不可重试）
  bool get isRetryable {
    switch (code) {
      case DeployErrorCode.dnsResolutionFailed:
      case DeployErrorCode.connectionTimeout:
      case DeployErrorCode.connectionReset:
      case DeployErrorCode.downloadInterrupted:
      case DeployErrorCode.allSourcesExhausted:
        return true;
      default:
        return false;
    }
  }

  /// 是否需要降级方案（DNS 问题 → IP 直连 / 镜像切换）
  bool get requiresDegradation {
    switch (code) {
      case DeployErrorCode.dnsResolutionFailed:
      case DeployErrorCode.allSourcesExhausted:
        return true;
      default:
        return false;
    }
  }

  @override
  String toString() => 'DeployError[$code]: $message';
}

/// 用户建议映射（参照 Firecrawl 每个错误类内置建议文本）
class DeployErrorSuggestions {
  static const Map<DeployErrorCode, String> suggestions = {
    DeployErrorCode.dnsResolutionFailed:
        'DNS 解析失败。① 切换 Wi-Fi ↔ 移动数据后重试 '
        '② 开启飞行模式再关闭 ③ 配置公共 DNS：8.8.8.8',
    DeployErrorCode.dnsAllResolversExhausted:
        '所有 DNS 解析器均失败。请检查网络连接，或等待一段时间后重试',
    DeployErrorCode.connectionTimeout:
        '连接超时。① 检查网络连接 ② 稍后重试 ③ 尝试使用镜像源',
    DeployErrorCode.connectionReset:
        '连接被重置。① 检查网络稳定性 ② 稍后重试',
    DeployErrorCode.sslHandshakeFailed:
        'SSL 握手失败。① 检查系统时间是否正确 ② 尝试使用 HTTP 镜像源',
    DeployErrorCode.httpError:
        '服务器返回错误状态码。请稍后重试',
    DeployErrorCode.downloadInterrupted:
        '下载中断。① 检查网络稳定性 ② 自动重试中...',
    DeployErrorCode.sizeMismatch:
        '文件大小不匹配，下载可能不完整。将自动重试',
    DeployErrorCode.sha256Mismatch:
        '文件校验失败，下载文件可能已损坏。将自动切换下载源重试',
    DeployErrorCode.allSourcesExhausted:
        '所有下载源均不可用。常见原因：① DNS 解析失败（将在后台自动尝试 DoH 加密DNS解析）② 运营商屏蔽（可切换 Wi-Fi/移动数据）③ 镜像源失效（将自动降级为 IP 直连模式）。请确保网络正常后重试',
    DeployErrorCode.extractionFailed:
        '解压失败。可能的原因是下载文件损坏，将自动重新下载',
    DeployErrorCode.permissionDenied:
        '权限不足。请确保：① 已授予存储权限 ② 重启应用后重试 ③ 清理缓存目录',
    DeployErrorCode.diskFull:
        '存储空间不足。请释放空间后重试，至少需要 500MB 可用空间',
    DeployErrorCode.binaryCorrupted:
        '下载的二进制文件已损坏。将自动重新下载',
    DeployErrorCode.healthCheckFailed:
        '安装后验证失败。请尝试重新安装',
    DeployErrorCode.archNotSupported:
        '当前设备架构暂不支持。该 Runtime 仅支持 arm64-v8a / aarch64',
    DeployErrorCode.dependencyMissing:
        '缺少依赖。请先安装所需依赖后重试',
    DeployErrorCode.toolInstallationFailed:
        '系统工具安装失败。请确保 Linux Runtime 已初始化且网络连接正常',
    DeployErrorCode.versionMismatch:
        '版本不匹配。将尝试安装兼容版本',
    DeployErrorCode.deploymentInProgress:
        '已有部署任务正在进行中。请等待当前任务完成后重试',
    DeployErrorCode.unknown:
        '未知错误。请查看日志了解更多信息',
  };

  /// 获取错误码对应的用户建议
  static String forCode(DeployErrorCode code) =>
      suggestions[code] ?? '请重试或联系支持';
}
