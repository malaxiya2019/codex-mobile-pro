import 'dart:io';
import '../logger/log_service.dart';

/// Shell 类型
enum ShellType {
  termuxBash,   // $PREFIX/bin/bash — Termux Bash
  systemBash,   // /system/bin/bash — 系统 Bash（罕见）
  systemSh,     // /system/bin/sh — 系统 Shell
  unknown,      // 未知 / 无可用
}

/// Shell 检测结果
class ShellInfo {
  final ShellType type;
  final String shellPath;
  final String version;
  final bool hasPtySupport;
  final bool hasTmuxSupport;

  const ShellInfo({
    required this.type,
    required this.shellPath,
    this.version = '',
    this.hasPtySupport = false,
    this.hasTmuxSupport = false,
  });

  bool get isAvailable => type != ShellType.unknown;
  bool get isTermuxBash => type == ShellType.termuxBash;

  /// 友好的中文描述
  String get friendlyDescription {
    switch (type) {
      case ShellType.termuxBash:
        return 'Termux Bash';
      case ShellType.systemBash:
        return '系统 Bash';
      case ShellType.systemSh:
        return 'Android 系统 Shell';
      case ShellType.unknown:
        return '无可用 Shell';
    }
  }

  @override
  String toString() =>
      'ShellInfo(type=$type, path=$shellPath, version=$version, '
      'pty=$hasPtySupport, tmux=$hasTmuxSupport)';
}

/// Shell 探测器
///
/// 自动检测设备上可用的 Shell，优先级：
/// 1. $PREFIX/bin/bash（Termux Bash）
/// 2. bash（系统 PATH 中的 bash）
/// 3. sh
/// 4. /system/bin/sh
///
/// 使用方式：
/// ```dart
/// final shell = await ShellDetector.detect();
/// if (shell.isAvailable) {
///   Process.start(shell.shellPath, []);
/// }
/// ```
class ShellDetector {
  static const _termuxPrefix = '/data/data/com.termux/files/usr';
  static const _termuxHome = '/data/data/com.termux/files/home';

  /// 检测可用 Shell
  static Future<ShellInfo> detect() async {
    LogService.info('ShellDetector', '开始检测可用 Shell...');

    // 优先级 1：$PREFIX/bin/bash（Termux Bash）
    final termuxBash = await _checkShell(
      '$_termuxPrefix/bin/bash',
      'Termux Bash',
    );
    if (termuxBash != null) {
      LogService.info('ShellDetector', '✅ 使用 Termux Bash: $_termuxPrefix/bin/bash');
      return ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '$_termuxPrefix/bin/bash',
        version: termuxBash.version,
        hasPtySupport: true,
        hasTmuxSupport: true,
      );
    }

    // 优先级 2：系统 bash
    final systemBash = await _checkShell('bash', '系统 Bash');
    if (systemBash != null) {
      LogService.info('ShellDetector', '✅ 使用系统 Bash');
      return ShellInfo(
        type: ShellType.systemBash,
        shellPath: 'bash',
        version: systemBash.version,
        hasPtySupport: false,
        hasTmuxSupport: false,
      );
    }

    // 优先级 3：sh
    final sh = await _checkShell('sh', '系统 sh');
    if (sh != null) {
      LogService.info('ShellDetector', '✅ 使用系统 sh');
      return ShellInfo(
        type: ShellType.systemSh,
        shellPath: 'sh',
        version: sh.version,
        hasPtySupport: false,
        hasTmuxSupport: false,
      );
    }

    // 优先级 4：/system/bin/sh（兜底）
    final systemSh = await _checkShell('/system/bin/sh', 'Android 系统 Shell');
    if (systemSh != null) {
      LogService.info('ShellDetector', '✅ 使用 Android 系统 Shell: /system/bin/sh');
      return ShellInfo(
        type: ShellType.systemSh,
        shellPath: '/system/bin/sh',
        version: systemSh.version,
        hasPtySupport: false,
        hasTmuxSupport: false,
      );
    }

    LogService.error('ShellDetector', '❌ 无可用 Shell');
    return const ShellInfo(
      type: ShellType.unknown,
      shellPath: '',
    );
  }

  /// 检查指定 shell 是否可用，返回版本号
  static Future<_ShellCheckResult?> _checkShell(
    String shellPath,
    String label,
  ) async {
    try {
      // 先检查文件是否存在
      if (shellPath.startsWith('/')) {
        final file = File(shellPath);
        if (!await file.exists()) {
          LogService.info('ShellDetector', '  $label: 文件不存在 ($shellPath)');
          return null;
        }
      }

      // 尝试执行 --version
      final result = await Process.run(
        shellPath,
        ['--version'],
        runInShell: !shellPath.startsWith('/'),
        environment: _getDefaultEnv(),
      );

      if (result.exitCode == 0) {
        final output = (result.stdout as String?)?.trim() ?? '';
        final versionLine = output.split('\n').firstWhere(
          (l) => l.isNotEmpty,
          orElse: () => '',
        );
        return _ShellCheckResult(shellPath, versionLine);
      }

      // --version 失败，尝试 -c 'echo ok'
      final okResult = await Process.run(
        shellPath,
        ['-c', 'echo shell_ok'],
        runInShell: !shellPath.startsWith('/'),
      );
      if (okResult.exitCode == 0) {
        return _ShellCheckResult(shellPath, '');
      }

      LogService.info('ShellDetector', '  $label: 执行失败 (exit=${okResult.exitCode})');
      return null;
    } catch (e) {
      LogService.info('ShellDetector', '  $label: 异常 ($e)');
      return null;
    }
  }

  /// 获取 Termux 环境变量
  static Map<String, String> _getDefaultEnv() {
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

class _ShellCheckResult {
  final String path;
  final String version;
  _ShellCheckResult(this.path, this.version);
}
