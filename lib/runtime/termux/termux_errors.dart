/// ====================================================================
/// Termux 结构化错误
///
/// 所有 Termux 相关错误使用此类型，不抛出原始异常。
/// 防止 Termux 异常导致 App crash。
///
/// 错误类型：
///   TERMUX_NOT_INSTALLED      — Termux APK 未安装
///   TERMUX_UNAVAILABLE        — Termux 已安装但不可用
///   TERMUX_PERMISSION_DENIED  — 权限不足
///   TERMUX_IPC_FAILED         — IPC 通信失败
///   COMMAND_NOT_FOUND         — 可执行文件不存在
///   COMMAND_FAILED            — 命令执行失败（非零退出码）
///   TIMEOUT                   — 执行超时
///   CANCELLED                 — 被取消
/// ====================================================================
library;

/// Termux 错误类型
enum TermuxErrorType {
  termuxNotInstalled,
  termuxUnavailable,
  termuxPermissionDenied,
  termuxIpcFailed,
  commandNotFound,
  commandFailed,
  timeout,
  cancelled,
}

/// Termux 结构化错误
class TermuxError implements Exception {
  final TermuxErrorType type;
  final String message;
  final int? exitCode;
  final String? stderr;

  const TermuxError({
    required this.type,
    required this.message,
    this.exitCode,
    this.stderr,
  });

  /// 友好的用户消息
  String get userMessage {
    switch (type) {
      case TermuxErrorType.termuxNotInstalled:
        return 'Termux 未安装';
      case TermuxErrorType.termuxUnavailable:
        return 'Termux 不可用';
      case TermuxErrorType.termuxPermissionDenied:
        return '权限不足';
      case TermuxErrorType.termuxIpcFailed:
        return 'Termux 通信失败';
      case TermuxErrorType.commandNotFound:
        return '命令未找到';
      case TermuxErrorType.commandFailed:
        return '命令执行失败';
      case TermuxErrorType.timeout:
        return '执行超时';
      case TermuxErrorType.cancelled:
        return '执行已取消';
    }
  }

  @override
  String toString() => 'TermuxError[$type]: $message';
}
