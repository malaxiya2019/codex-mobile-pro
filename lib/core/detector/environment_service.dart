import '../logger/log_service.dart';
import '../termux/termux_service.dart';

/// Termux 环境检查结果
class TermuxEnvironmentCheck {
  final bool termuxInstalled;
  final bool hasTermuxHome;
  final bool hasTermuxUsr;
  final String? prefixPath;
  final String? homePath;

  const TermuxEnvironmentCheck({
    this.termuxInstalled = false,
    this.hasTermuxHome = false,
    this.hasTermuxUsr = false,
    this.prefixPath,
    this.homePath,
  });

  bool get isTermuxAvailable => termuxInstalled;
}

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
  /// Termux 是否可用（缓存）
  static bool? _termuxAvailable;

  /// 检查 Termux 是否可用
  static Future<bool> isTermuxAvailable() async {
    if (_termuxAvailable != null) return _termuxAvailable!;
    try {
      final env = await TermuxService.checkEnvironment();
      _termuxAvailable = env.termuxMode;
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

  /// 检查 Shell 环境
  static Future<TermuxEnvironmentCheck> checkTermux() async {
    LogService.info('EnvService', '检查 Shell 环境...');

    final available = await isTermuxAvailable();
    if (available) {
      LogService.info('EnvService', '  ✅ Termux 可用');
    } else {
      LogService.info('EnvService', '  ⚠️ Termux 不可用，使用系统 Shell');
    }

    // 测试系统 Shell
    try {
      final result = await executeInTermux(command: 'echo ok');
      if (result.isSuccess) {
        LogService.info('EnvService', '  ✅ Shell 可用 (source=${result.source})');
      } else {
        LogService.info('EnvService', '  ❌ Shell 不可用');
      }
    } catch (e) {
      LogService.error('EnvService', '  检查失败: $e');
    }

    return TermuxEnvironmentCheck(
      termuxInstalled: available,
    );
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
      // 使用 TermuxService.execute() — 自动降级
      final result = await TermuxService.execute(command);

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      LogService.info('EnvService',
          '  完成: exit=${result.exitCode}, source=${result.source}, ${elapsed}ms');

      return ShellCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout.trim(),
        stderr: result.stderr.trim(),
        durationMs: elapsed,
        source: result.source,
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
