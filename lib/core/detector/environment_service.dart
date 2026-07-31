/// ====================================================================
/// 环境服务
///
/// 统一负责通过 Termux（优先）或 Android 系统 Shell 执行检测命令。
/// 内部使用 TermuxTransport，不再直接依赖 TermuxService。
/// ====================================================================
library;

import '../../runtime/termux/termux_transport.dart';
import '../../runtime/termux/method_channel_transport.dart';
import '../logger/log_service.dart';

/// 通过 Shell 执行的命令结果
class ShellCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final String source; // "termux", "system_sh", "error"

  const ShellCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.source = 'system_sh',
  });

  bool get isSuccess => exitCode == 0;
}

/// 环境服务
///
/// 统一负责通过 Termux（优先）或 Android 系统 Shell 执行检测命令。
class EnvironmentService {
  static final TermuxTransport _transport = MethodChannelTermuxTransport();

  /// Termux 是否可用（缓存）
  static bool? _termuxAvailable;

  /// 检查 Termux 是否可用
  static Future<bool> isTermuxAvailable() async {
    if (_termuxAvailable != null) return _termuxAvailable!;
    try {
      final diag = await _transport.diagnose();
      _termuxAvailable = diag.isAvailable;
      LogService.info('EnvService', 'Termux 可用: $_termuxAvailable');
      return _termuxAvailable!;
    } catch (_) {
      _termuxAvailable = false;
      return false;
    }
  }

  /// 刷新 Termux 可用性缓存
  static Future<void> refreshTermuxStatus() async {
    _termuxAvailable = null;
    await isTermuxAvailable();
  }

  /// 通过 Termux（优先）或系统 Shell 执行命令
  static Future<ShellCommandResult> executeInTermux({
    required String command,
    String? shellPath,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final start = DateTime.now();
    LogService.info('EnvService', '执行: $command');

    try {
      // 使用 TermuxTransport 执行
      final result = await _transport.execute(command);

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      LogService.info('EnvService',
          '  完成: exit=${result.exitCode}, usedTermux=${result.usedTermux}, ${elapsed}ms');

      return ShellCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout.trim(),
        stderr: result.stderr.trim(),
        durationMs: elapsed,
        source: result.usedTermux ? 'termux' : 'system_sh',
      );
    } catch (e, stack) {
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      LogService.error('EnvService', '  失败: $e');
      LogService.error('EnvService', '  Stack: $stack');

      return ShellCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
        durationMs: elapsed,
        source: 'error',
      );
    }
  }

  /// 获取 DETECTION 风格的命令输出
  static Future<ShellCommandResult> detectTool(String command) {
    return executeInTermux(
      command: '$command 2>/dev/null',
    );
  }
}
