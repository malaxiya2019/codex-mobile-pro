import 'dart:io';
import '../logger/log_service.dart';

/// Termux 环境检查结果（保留接口兼容）
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

  bool get isTermuxAvailable => false;
}

/// 通过 Shell 执行的命令结果
class ShellCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;

  const ShellCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
  });

  bool get isSuccess => exitCode == 0;
}

/// 环境服务
///
/// 统一负责通过 Android 系统 Shell 执行检测命令。
/// 不依赖 Termux，不访问 /data/data/com.termux/ 路径。
class EnvironmentService {
  /// 检查 Termux 环境
  ///
  /// 简化版本：始终返回未安装状态。
  /// 不再试图检测 /data/data/com.termux/ 目录。
  static Future<TermuxEnvironmentCheck> checkTermux() async {
    LogService.info('EnvService', '检查 Shell 环境...');

    // 只检测 /system/bin/sh 是否可用
    try {
      final result = await Process.run(
        '/system/bin/sh',
        ['-c', 'echo ok'],
      );
      if (result.exitCode == 0) {
        LogService.info('EnvService', '  ✅ Android 系统 Shell 可用');
      } else {
        LogService.info('EnvService', '  ❌ Shell 不可用');
      }
    } catch (e) {
      LogService.error('EnvService', '  检查失败: $e');
    }

    return const TermuxEnvironmentCheck();
  }

  /// 通过系统 Shell 执行命令
  static Future<ShellCommandResult> executeInTermux({
    required String command,
    String? shellPath,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final start = DateTime.now();
    LogService.info('EnvService', '执行: $command');

    try {
      final shell = shellPath ?? '/system/bin/sh';
      final result = await Process.run(
        shell,
        ['-c', command],
      ).timeout(timeout);

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      LogService.info('EnvService', '  完成: exit=${result.exitCode}, ${elapsed}ms');

      return ShellCommandResult(
        exitCode: result.exitCode,
        stdout: (result.stdout as String?)?.trim() ?? '',
        stderr: (result.stderr as String?)?.trim() ?? '',
        durationMs: elapsed,
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
      );
    }
  }

  /// 获取 DETECTION 风格的命令输出
  ///
  /// 返回格式：第一行是路径，第二行是版本号
  static Future<ShellCommandResult> detectTool(String command) {
    return executeInTermux(
      command: '$command 2>/dev/null',
    );
  }
}
