import 'dart:io';

/// Shell 类型
enum ShellType {
  /// Android 系统 Shell（/system/bin/sh）— 唯一可执行的 Shell
  systemSh,
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

  /// 终端启动参数 — 交互模式
  List<String> get launchArgs => ['-i'];

  /// 绝对路径无需 runInShell
  bool get useRunInShell => false;

  /// 友好的中文描述
  String get friendlyDescription => 'Android 系统 Shell';

  @override
  String toString() =>
      'ShellInfo(type=$type, path=$shellPath, version=$version)';
}

/// Shell 探测器
///
/// App 运行在独立 Linux 用户（u0_a34x），无法跨用户执行 Termux 二进制文件。
/// 始终使用 Android 系统 Shell（/system/bin/sh）。
class ShellDetector {
  /// 检测可用的 Shell
  /// 始终返回 Android 系统 Shell，因为 App 无法执行 Termux 的 bash。
  static Future<ShellInfo> detect() async {
    return const ShellInfo();
  }

  /// 获取终端环境变量
  ///
  /// 始终返回一组完整的环境变量，使用合理默认值。
  /// [appHome] 作为 HOME 的值。
  static Map<String, String> getShellEnvironment(String appHome) {
    return {
      'HOME': appHome,
      'PATH': '/system/bin:/system/xbin',
      'SHELL': '/system/bin/sh',
      'TERM': 'xterm-256color',
      'PWD': appHome,
      'TMPDIR': Directory.systemTemp.path,
      'LANG': 'en_US.UTF-8',
      'USER': 'user',
      'LOGNAME': 'user',
    };
  }
}
