import 'termux_service.dart';

/// Shell 类型
enum ShellType {
  termuxBash,   // Termux bash — 完整 Linux 环境（首选）
  termuxSh,     // Termux sh — 备用
  systemSh,     // /system/bin/sh — Android 系统 Shell（兜底）
}

/// Shell 信息
class ShellInfo {
  final ShellType type;
  final String shellPath;
  final String version;
  final bool isTermuxAvailable;

  const ShellInfo({
    this.type = ShellType.systemSh,
    this.shellPath = '/system/bin/sh',
    this.version = 'Android System Shell',
    this.isTermuxAvailable = false,
  });

  bool get isAvailable => true;
  bool get isTermuxBash => type == ShellType.termuxBash;

  /// 终端启动参数 — 交互模式
  List<String> get launchArgs => ['-i'];

  /// 绝对路径无需 runInShell
  bool get useRunInShell => false;

  /// 友好的中文描述
  String get friendlyDescription {
    switch (type) {
      case ShellType.termuxBash:
        return 'Termux Bash（完整 Linux 环境）';
      case ShellType.termuxSh:
        return 'Termux SH（兼容模式）';
      case ShellType.systemSh:
        return 'Android 系统 Shell';
    }
  }

  @override
  String toString() =>
      'ShellInfo(type=$type, path=$shellPath, version=$version, '
      'termux=$isTermuxAvailable)';
}

/// Shell 探测器
///
/// 检测可用 Shell，优先级：
/// 1. /data/data/com.termux/files/usr/bin/bash（Termux Bash）
/// 2. /data/data/com.termux/files/usr/bin/sh（Termux sh）
/// 3. /system/bin/sh（Android 系统 Shell，兜底）
class ShellDetector {
  /// 检测可用的 Shell
  static Future<ShellInfo> detect() async {
    // 先检测 Termux 是否可用
    try {
      final env = await TermuxService.checkEnvironment();
      if (env.termuxMode) {
        // Termux 可用，优先使用 bash
        return ShellInfo(
          type: ShellType.termuxBash,
          shellPath: '/data/data/com.termux/files/usr/bin/bash',
          version: 'Termux Bash',
          isTermuxAvailable: true,
        );
      }
    } catch (_) {
      // Termux 不可用，降级
    }

    // Termux 不可用，使用系统 Shell 兜底
    return const ShellInfo();
  }

  /// 获取终端环境变量
  ///
  /// [appHome] App 私有目录路径
  /// [shellInfo] 检测到的 Shell 信息
  static Map<String, String> getShellEnvironment(
    String appHome, {
    ShellInfo? shellInfo,
  }) {
    final info = shellInfo;
    if (info != null && info.isTermuxAvailable) {
      // Termux 环境
      return {
        'HOME': '/data/data/com.termux/files/home',
        'PATH': '/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin',
        'TERM': 'xterm-256color',
        'SHELL': info.shellPath,
        'PREFIX': '/data/data/com.termux/files/usr',
        'TMPDIR': '/data/data/com.termux/files/usr/tmp',
      };
    }

    // 系统 Shell 环境（兜底）
    return {
      'HOME': appHome,
      'PATH': '/system/bin:/system/xbin',
      'TERM': 'xterm-256color',
      'SHELL': '/system/bin/sh',
    };
  }
}
