import 'dart:io';
import '../logger/log_service.dart';

/// Shell 类型
enum ShellType {
  termuxBash,   // $PREFIX/bin/bash — Termux Bash
  systemSh,     // /system/bin/sh — Android 系统 Shell
  unknown,      // 未知 / 无可用
}

/// Shell 信息
class ShellInfo {
  final ShellType type;
  final String shellPath;
  final String version;
  final bool isTermuxAccessible;

  const ShellInfo({
    required this.type,
    required this.shellPath,
    this.version = '',
    this.isTermuxAccessible = false,
  });

  bool get isAvailable => type != ShellType.unknown;
  bool get isTermuxBash => type == ShellType.termuxBash;

  /// 终端启动参数
  List<String> get launchArgs {
    // 交互模式：Termux Bash 和 Android 系统 sh 都支持 -i
    return isAvailable ? ['-i'] : [];
  }

  /// 终端启动是否使用 runInShell
  bool get useRunInShell {
    // 非绝对路径（如 bash、sh）需要 runInShell
    return !shellPath.startsWith('/');
  }

  /// 友好的中文描述
  String get friendlyDescription {
    switch (type) {
      case ShellType.termuxBash:
        return 'Termux Bash';
      case ShellType.systemSh:
        return 'Android 系统 Shell';
      case ShellType.unknown:
        return '无可用 Shell';
    }
  }

  @override
  String toString() =>
      'ShellInfo(type=$type, path=$shellPath, version=$version, '
      'termuxAccessible=$isTermuxAccessible)';
}

/// Shell 探测器
///
/// 自动检测设备上可用的 Shell。
/// 只返回绝对路径，避免 Process.start 因 PATH 找不到文件而崩溃。
/// 在非 Android 环境（如 CI）自动降级为 sh/bash。
///
/// 优先级：
/// 1. /data/data/com.termux/files/usr/bin/bash（Termux Bash）
/// 2. /system/bin/sh（Android 系统 Shell）
/// 3. bash（非 Android 环境，如 CI）
/// 4. sh（兜底）
class ShellDetector {
  static const _termuxPrefix = '/data/data/com.termux/files/usr';
  static const _termuxHome = '/data/data/com.termux/files/home';

  /// 检测可用的 Shell
  static Future<ShellInfo> detect() async {
    LogService.info('ShellDetector', '开始检测可用 Shell...');

    // 优先级 1：$PREFIX/bin/bash（Termux Bash）
    final termuxBash = await _tryExecuteShell(
      shellPath: '$_termuxPrefix/bin/bash',
      label: 'Termux Bash',
      env: _getTermuxEnv(),
    );

    if (termuxBash != null) {
      LogService.info(
          'ShellDetector', '✅ 使用 Termux Bash: $_termuxPrefix/bin/bash');
      return ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '$_termuxPrefix/bin/bash',
        version: termuxBash,
        isTermuxAccessible: true,
      );
    }

    // 优先级 2：/system/bin/sh（Android 系统 Shell）
    final systemSh = await _tryExecuteShell(
      shellPath: '/system/bin/sh',
      label: 'Android 系统 Shell',
    );
    if (systemSh != null) {
      LogService.info(
          'ShellDetector', '✅ 使用 Android 系统 Shell: /system/bin/sh');
      return ShellInfo(
        type: ShellType.systemSh,
        shellPath: '/system/bin/sh',
        version: systemSh,
      );
    }

    // 优先级 3：bash（非 Android 环境，如 CI）
    final bash = await _tryExecuteShell(
      shellPath: 'bash',
      label: '系统 Bash',
    );
    if (bash != null) {
      LogService.info('ShellDetector', '✅ 使用系统 Bash');
      return ShellInfo(
        type: ShellType.systemSh,
        shellPath: 'bash',
        version: bash,
      );
    }

    // 优先级 4：sh（兜底）
    final sh = await _tryExecuteShell(
      shellPath: 'sh',
      label: '系统 sh',
    );
    if (sh != null) {
      LogService.info('ShellDetector', '✅ 使用系统 sh');
      return ShellInfo(
        type: ShellType.systemSh,
        shellPath: 'sh',
        version: sh,
      );
    }

    LogService.error('ShellDetector', '❌ 无可用 Shell');
    return const ShellInfo(
      type: ShellType.unknown,
      shellPath: '',
    );
  }

  /// 尝试执行指定 Shell
  ///
  /// 返回版本号字符串，如果无法执行返回 null。
  /// 使用 Process.run 而非 File.exists()，
  /// 避免 Android 11+ Scoped Storage 限制。
  static Future<String?> _tryExecuteShell({
    required String shellPath,
    required String label,
    Map<String, String>? env,
  }) async {
    try {
      // 先检查文件是否存在（仅当路径以 / 开头）
      if (shellPath.startsWith('/')) {
        final file = File(shellPath);
        if (await file.exists()) {
          LogService.info('ShellDetector', '  $label: 文件存在 ($shellPath)');
        } else {
          LogService.info(
              'ShellDetector', '  $label: 文件不存在，尝试直接执行');
        }
      }

      // 非绝对路径的 shell 需要 runInShell
      final useRunInShell = !shellPath.startsWith('/');

      // 尝试执行 --version
      final result = await Process.run(
        shellPath,
        ['--version'],
        runInShell: useRunInShell,
        environment: env,
      );

      if (result.exitCode == 0) {
        final output = (result.stdout as String?)?.trim() ?? '';
        final versionLine = output.split('\n').firstWhere(
              (l) => l.isNotEmpty && l.length > 3,
              orElse: () => '',
            );
        if (versionLine.isNotEmpty) {
          return versionLine;
        }
        return 'available';
      }

      // --version 失败（Android sh 可能不支持），尝试 -c 'echo ok'
      final okResult = await Process.run(
        shellPath,
        ['-c', 'echo shell_available'],
        runInShell: useRunInShell,
        environment: env,
      );
      if (okResult.exitCode == 0) {
        return 'available';
      }

      LogService.info(
          'ShellDetector', '  $label: 执行失败 (exit=${okResult.exitCode})');
      return null;
    } catch (e) {
      LogService.info('ShellDetector', '  $label: 异常 ($e)');
      return null;
    }
  }

  /// 获取 Termux 环境变量
  static Map<String, String> _getTermuxEnv() {
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

  /// 公开的 Termux 环境变量获取方法
  static Map<String, String> getTermuxEnvironment() {
    return _getTermuxEnv();
  }
}
