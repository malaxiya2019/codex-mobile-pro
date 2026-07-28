import 'dart:io';
import '../logger/log_service.dart';

/// Shell 类型
enum ShellType {
  termuxBash,   // $PREFIX/bin/bash — Termux Bash
  systemSh,     // /system/bin/sh — Android 系统 Shell
  unknown,      // 未知 / 无可用
}

/// Shell 检测结果
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
    // Android 系统 shell 不支持 -i 交互模式
    return [];
  }

  /// 终端启动是否使用 runInShell
  bool get useRunInShell => false; // 全部使用绝对路径

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
///
/// 优先级：
/// 1. /data/data/com.termux/files/usr/bin/bash（Termux Bash）
/// 2. /system/bin/sh（Android 系统 Shell）
class ShellDetector {
  static const _termuxPrefix = '/data/data/com.termux/files/usr';
  static const _termuxHome = '/data/data/com.termux/files/home';

  /// 检测可用 Shell
  static Future<ShellInfo> detect() async {
    LogService.info('ShellDetector', '开始检测可用 Shell...');

    // 优先级 1：$PREFIX/bin/bash（Termux Bash）
    // 尝试直接运行命令来验证，而非只检查文件存在（Scoped Storage 限制）
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
    // 这是 Android 上最可靠的 Shell，总是存在
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

    // 兜底：尝试 sh（绝对路径下的 sh）
    try {
      final whichResult = await Process.run(
        '/system/bin/sh',
        ['-c', 'command -v sh 2>/dev/null || which sh 2>/dev/null || echo "/system/bin/sh"'],
        runInShell: false,
      );
      final shPath = (whichResult.stdout as String?)?.trim() ?? '/system/bin/sh';
      if (shPath.isNotEmpty) {
        final shResult = await _tryExecuteShell(
          shellPath: shPath,
          label: '系统 sh (fallback)',
        );
        if (shResult != null) {
          LogService.info('ShellDetector', '✅ 兜底使用: $shPath');
          return ShellInfo(
            type: ShellType.systemSh,
            shellPath: shPath,
            version: shResult,
          );
        }
      }
    } catch (_) {}

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

      // 尝试执行 --version
      final result = await Process.run(
        shellPath,
        ['--version'],
        runInShell: false,
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
        runInShell: false,
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
    };
  }

  /// 获取终端启动所需的完整环境变量
  static Map<String, String> getTermuxEnvironment() {
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
}
