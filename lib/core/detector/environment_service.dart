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
  static Future<TermuxEnvironmentCheck> checkTermux() async {
    LogService.info('EnvService', '检查 Termux 环境...');

    bool termuxInstalled = false;
    bool hasTermuxHome = false;
    bool hasTermuxUsr = false;

    try {
      // 检查 Termux 主目录
      final homeDir = Directory(_termuxHome);
      hasTermuxHome = await homeDir.exists();
      LogService.info('EnvService', '  $_termuxHome: ${hasTermuxHome ? "存在" : "不存在"}');

      // 检查 Termux usr 目录
      final usrDir = Directory(_termuxPrefix);
      hasTermuxUsr = await usrDir.exists();
      LogService.info('EnvService', '  $_termuxPrefix: ${hasTermuxUsr ? "存在" : "不存在"}');

      // 检查 Termux 包管理器（pkg 命令是否存在）
      if (hasTermuxUsr) {
        final pkgFile = File('$_termuxPrefix/bin/pkg');
        termuxInstalled = await pkgFile.exists();
      }

      // 如果 usr 存在但 pkg 不存在，可能还是 Termux（只是精简版）
      if (!termuxInstalled && hasTermuxUsr) {
        termuxInstalled = true;
      }
    } catch (e) {
      LogService.error('EnvService', '  检查失败: $e');
    }

    return TermuxEnvironmentCheck(
      termuxInstalled: termuxInstalled || hasTermuxHome,
      hasTermuxHome: hasTermuxHome,
      hasTermuxUsr: hasTermuxUsr,
      prefixPath: hasTermuxUsr ? _termuxPrefix : null,
      homePath: hasTermuxHome ? _termuxHome : null,
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
        final termuxBash = File('$_termuxPrefix/bin/bash');
        if (await termuxBash.exists()) {
          shell = '$_termuxPrefix/bin/bash';
          runInShell = false;
        } else {
          // 降级到系统 shell
          shell = '/system/bin/sh';
          runInShell = false;
          // 如果 /system/bin/sh 也不存在，用 sh
          if (!await File(shell).exists()) {
            shell = 'sh';
            runInShell = true;
          }
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
