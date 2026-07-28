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

/// Shell 检测结果
class _ResolvedShell {
  final String shellPath;
  final bool runInShell;
  const _ResolvedShell({required this.shellPath, required this.runInShell});
}

/// 环境服务
///
/// 统一负责检测 Termux 环境，并通过 Termux Shell 执行检测命令。
/// 所有检测通过 Shell 环境执行（而非 Android App 的 PATH）。
class EnvironmentService {
  static const _termuxPrefix = '/data/data/com.termux/files/usr';
  static const _termuxHome = '/data/data/com.termux/files/home';

  static _ResolvedShell? _cachedShell;

  /// 解析当前系统可用的 Shell
  ///
  /// 优先级：
  /// 1. /system/bin/sh（Android 系统 Shell，适用于真机）
  /// 2. bash（非 Android 环境，如 CI）
  /// 3. sh（兜底）
  static Future<_ResolvedShell> _resolveShell() async {
    if (_cachedShell != null) return _cachedShell!;

    // 优先级 1：/system/bin/sh（Android）
    try {
      final result = await Process.run(
        '/system/bin/sh',
        ['-c', 'echo ok'],
        runInShell: false,
      );
      if (result.exitCode == 0) {
        _cachedShell = const _ResolvedShell(
          shellPath: '/system/bin/sh',
          runInShell: false,
        );
        return _cachedShell!;
      }
    } catch (_) {
      // /system/bin/sh 不可用（非 Android 环境）
    }

    // 优先级 2：bash（CI/桌面环境）
    try {
      final result = await Process.run(
        'bash',
        ['-c', 'echo ok'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        _cachedShell = const _ResolvedShell(
          shellPath: 'bash',
          runInShell: true,
        );
        return _cachedShell!;
      }
    } catch (_) {}

    // 优先级 3：sh（兜底）
    _cachedShell = const _ResolvedShell(
      shellPath: 'sh',
      runInShell: true,
    );
    return _cachedShell!;
  }

  /// 清除缓存的 Shell（用于测试或重新检测）
  static void clearShellCache() {
    _cachedShell = null;
  }

  /// 检查 Termux 环境
  ///
  /// 通过执行命令来检测 Termux 是否可用，
  /// 而非检查文件/目录是否存在。
  /// Android 11+ 的 Scoped Storage 限制 App 访问其他应用数据目录，
  /// 但通过 /system/bin/sh 执行命令可以绕过此限制。
  /// 在非 Android 环境（如 CI）自动降级为普通 sh/bash 检测。
  static Future<TermuxEnvironmentCheck> checkTermux() async {
    LogService.info('EnvService', '检查 Termux 环境...');

    bool termuxInstalled = false;
    bool hasTermuxHome = false;
    bool hasTermuxUsr = false;
    String? prefixPath;
    String? homePath;

    try {
      final shell = await _resolveShell();

      // 尝试检测 Termux 环境
      // 优先通过 Android 系统 shell 检测 Termux bash
      // 在非 Android 环境，此命令会失败但不会崩溃
      final detectionCommand =
          'if [ -d $_termuxPrefix ]; then '
          '  echo "TERMUX_DIR_OK"; '
          '  if [ -x $_termuxPrefix/bin/bash ]; then '
          '    echo "TERMUX_BASH_OK"; '
          '    echo "HOME:$_termuxHome"; '
          '    echo "PREFIX:$_termuxPrefix"; '
          '  fi; '
          'else '
          '  echo "NO_TERMUX"; '
          'fi';

      final bashResult = await Process.run(
        shell.shellPath,
        ['-c', detectionCommand],
        runInShell: shell.runInShell,
      );

      final stdout = (bashResult.stdout as String?)?.trim() ?? '';
      LogService.info('EnvService', '  Termux bash 检测结果: ${stdout.split("\n").first}');

      if (stdout.contains('TERMUX_BASH_OK')) {
        termuxInstalled = true;
        hasTermuxUsr = true;
        hasTermuxHome = true;
        prefixPath = _termuxPrefix;
        homePath = _termuxHome;
        LogService.info('EnvService', '  ✅ Termux 已安装 (bash 可执行)');
      } else if (stdout.contains('TERMUX_DIR_OK')) {
        // 有目录但 bash 不可执行（精简版）
        termuxInstalled = true;
        hasTermuxUsr = true;
        hasTermuxHome = true;
        prefixPath = _termuxPrefix;
        homePath = _termuxHome;
        LogService.info('EnvService', '  ⚠️ Termux 目录存在 (bash 不可执行)');
      } else {
        LogService.info('EnvService', '  ❌ Termux 未安装或不可访问');
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
      'SHELL': '$_termuxPrefix/bin/bash',
    };
  }

  /// 通过 Termux Shell 执行命令
  ///
  /// 优先使用 Termux Bash，如果不可用则自动降级到系统 Shell。
  /// 始终设置完整的 Termux 环境变量。
  /// 在非 Android 环境（如 CI）自动使用系统 sh/bash。
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
        // 自动检测可用 Shell
        final resolvedShell = await _resolveShell();

        // 如果是 Android 环境，尝试检测 Termux Bash
        if (resolvedShell.shellPath == '/system/bin/sh') {
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
            shell = resolvedShell.shellPath;
            runInShell = resolvedShell.runInShell;
          }
        } else {
          // 非 Android 环境，直接使用解析的 shell
          shell = resolvedShell.shellPath;
          runInShell = resolvedShell.runInShell;
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
