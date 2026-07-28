import 'dart:io';
import '../logger/log_service.dart';

/// Termux 环境检查结果
class TermuxEnvironmentCheck {
  final bool termuxInstalled;
  final bool hasTermuxHome;
  final bool hasTermuxUsr;
  final String? prefixPath;
  final String? homePath;

  const TermuxEnvironmentCheck({
    required this.termuxInstalled,
    required this.hasTermuxHome,
    required this.hasTermuxUsr,
    this.prefixPath,
    this.homePath,
  });

  bool get isTermuxAvailable => termuxInstalled && hasTermuxUsr;
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
/// 统一负责检测 Termux 环境，并通过 Termux Shell 执行检测命令。
/// 所有检测通过 Shell 环境执行（而非 Android App 的 PATH）。
class EnvironmentService {
  static const _termuxPrefix = '/data/data/com.termux/files/usr';
  static const _termuxHome = '/data/data/com.termux/files/home';

  /// 检查 Termux 环境
  ///
  /// 通过执行命令来检测 Termux 是否可用，
  /// 而非检查文件/目录是否存在。
  /// Android 11+ 的 Scoped Storage 限制 App 访问其他应用数据目录，
  /// 但通过 /system/bin/sh 执行命令可以绕过此限制。
  static Future<TermuxEnvironmentCheck> checkTermux() async {
    LogService.info('EnvService', '检查 Termux 环境...');

    bool termuxInstalled = false;
    bool hasTermuxHome = false;
    bool hasTermuxUsr = false;
    String? prefixPath;
    String? homePath;

    try {
      // 尝试直接运行 Termux bash 来检测
      // 使用 /system/bin/sh 来启动 Termux bash，绕过文件权限限制
      final bashResult = await Process.run(
        '/system/bin/sh',
        [
          '-c',
          'if [ -x $_termuxPrefix/bin/bash ]; then '
          'echo "TERMUX_OK"; '
          'echo "HOME:$_termuxHome"; '
          'echo "PREFIX:$_termuxPrefix"; '
          'else echo "TERMUX_NO"; fi',
        ],
        runInShell: false,
      );

      final stdout = (bashResult.stdout as String?)?.trim() ?? '';
      LogService.info('EnvService', '  Termux bash 检测结果: ${stdout.split("\n").first}');

      if (stdout.contains('TERMUX_OK')) {
        termuxInstalled = true;
        hasTermuxUsr = true;
        hasTermuxHome = true;
        prefixPath = _termuxPrefix;
        homePath = _termuxHome;
        LogService.info('EnvService', '  ✅ Termux 已安装 (bash 可执行)');
      } else {
        // 再检查下是否有 Termux 目录（仅日志，不依赖）
        final lsResult = await Process.run(
          '/system/bin/sh',
          ['-c', 'ls $_termuxPrefix/bin/ 2>/dev/null | head -5 || echo "NO_ACCESS"'],
          runInShell: false,
        );
        final lsOut = (lsResult.stdout as String?)?.trim() ?? '';
        if (lsOut.contains('bash') || lsOut.contains('pkg')) {
          termuxInstalled = true;
          hasTermuxUsr = true;
          hasTermuxHome = true;
          prefixPath = _termuxPrefix;
          homePath = _termuxHome;
          LogService.info('EnvService', '  ✅ Termux 已安装 (目录可访问)');
        } else {
          LogService.info('EnvService', '  ❌ Termux 未安装或不可访问');
        }
      }
    } catch (e) {
      LogService.error('EnvService', '  检查失败: $e');
    }

    return TermuxEnvironmentCheck(
      termuxInstalled: termuxInstalled || hasTermuxHome,
      hasTermuxHome: hasTermuxHome,
      hasTermuxUsr: hasTermuxUsr,
      prefixPath: prefixPath,
      homePath: homePath,
    );
  }

  /// 获取 Termux 环境变量
  static Map<String, String> getTermuxEnv() {
    return {
      'HOME': _termuxHome,
      'PREFIX': _termuxPrefix,
      'PATH': '$_termuxPrefix/bin:/system/bin:/usr/bin:/bin',
      'LANG': 'zh_CN.UTF-8',
      'TERM': 'xterm-256color',
      'TMPDIR': '$_termuxPrefix/tmp',
    };
  }

  /// 通过 Termux Shell 执行命令
  ///
  /// 优先使用 Termux Bash，如果不可用则自动降级到系统 Shell。
  /// 始终设置完整的 Termux 环境变量。
  static Future<ShellCommandResult> executeInTermux({
    required String command,
    String? shellPath,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final start = DateTime.now();
    LogService.info('EnvService', '执行: $command');

    try {
      // 如果未指定 shell，自动检测
      String shell;
      bool runInShell;

      if (shellPath != null) {
        shell = shellPath;
        runInShell = false;
      } else {
        // 自动检测 Termux Bash
        // 通过执行命令验证，而非 File.exists()（Android 沙箱限制）
        final bashCheck = await Process.run(
          '/system/bin/sh',
          ['-c', 'if [ -x $_termuxPrefix/bin/bash ]; then echo "YES"; else echo "NO"; fi'],
          runInShell: false,
        );
        final bashAvailable = (bashCheck.stdout as String?)?.trim() == 'YES';
        
        if (bashAvailable) {
          shell = '$_termuxPrefix/bin/bash';
          runInShell = false;
        } else {
          // 降级到系统 shell（绝对路径，确保可用）
          shell = '/system/bin/sh';
          runInShell = false;
        }
      }

      final env = getTermuxEnv();
      LogService.info('EnvService', '  Shell: $shell');
      LogService.info('EnvService', '  PATH: ${env['PATH']}');

      final result = await Process.run(
        shell,
        ['-c', command],
        runInShell: runInShell,
        environment: env,
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
  /// 例如：which node → /data/data/com.termux/files/usr/bin/node
  ///       node --version → v22.x.x
  static Future<ShellCommandResult> detectTool(String command) {
    return executeInTermux(
      command: '$command 2>/dev/null',
    );
  }
}
