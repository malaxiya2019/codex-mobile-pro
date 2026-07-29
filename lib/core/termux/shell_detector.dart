import 'termux_service.dart';

/// Shell 类型
enum ShellType {
  systemSh,     // /system/bin/sh — Android 系统 Shell
  termuxBash,   // Termux bash — 完整 Linux 环境
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
  bool get isTermuxAccessible => isTermuxAvailable;

  /// 终端启动参数 — 交互模式
  List<String> get launchArgs => ['-i'];

  /// 绝对路径无需 runInShell
  bool get useRunInShell => false;

  /// 友好的中文描述
  String get friendlyDescription {
    if (isTermuxAvailable && isTermuxBash) {
      return 'Termux Bash（完整 Linux 环境）';
    }
    return 'Android 系统 Shell';
  }

  @override
  String toString() =>
      'ShellInfo(type=$type, path=$shellPath, version=$version, '
      'termux=$isTermuxAvailable)';
}

/// Shell 探测器
///
/// 检测可用 Shell：
/// 1. Termux Bash（通过 RUN_COMMAND Intent）
/// 2. Android 系统 Shell（/system/bin/sh）
class ShellDetector {
  /// 检测可用的 Shell
  static Future<ShellInfo> detect() async {
    // 先检测 Termux 是否可用
    try {
      final env = await TermuxService.checkEnvironment();
      if (env.termuxMode) {
        return ShellInfo(
          type: ShellType.termuxBash,
          shellPath: '/data/data/com.termux/files/usr/bin/bash',
          version: 'Termux Bash',
          isTermuxAvailable: true,
        );
      }
    } catch (_) {
      // Termux 不可用，降级到系统 Shell
    }

    return const ShellInfo();
  }

  /// 获取环境变量
  static Map<String, String> getShellEnvironment(String appHome) {
    return {
      'HOME': appHome,
      'PATH': '/system/bin:/system/xbin',
      'TERM': 'xterm-256color',
      'SHELL': '/system/bin/sh',
    };
  }
}
