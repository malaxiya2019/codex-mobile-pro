/// Shell 类型
///
/// Android 上只有一个可用 Shell：系统 shell。
enum ShellType {
  systemSh, // /system/bin/sh — Android 系统 Shell
}

/// Shell 信息
///
/// 固定使用 Android 系统 Shell（/system/bin/sh）。
/// 不检测 Termux，不尝试访问其他 App 的数据目录。
class ShellInfo {
  final ShellType type;
  final String shellPath;
  final String version;

  const ShellInfo({
    this.type = ShellType.systemSh,
    this.shellPath = '/system/bin/sh',
    this.version = 'Android System Shell',
  });

  bool get isAvailable => true;
  bool get isTermuxBash => false;
  bool get isTermuxAccessible => false;

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
/// 简化版本：始终返回 Android 系统 Shell（/system/bin/sh）。
/// 不访问 /data/data/com.termux/，不检测其他 App 的二进制文件。
class ShellDetector {
  /// 检测可用的 Shell
  ///
  /// 始终返回 Android 系统 Shell。
  /// 在 Android 设备上 /system/bin/sh 始终存在。
  static Future<ShellInfo> detect() async {
    return const ShellInfo();
  }

  /// 获取环境变量
  ///
  /// 返回应用私有目录的基础环境变量。
  /// [appHome] 为应用私有目录路径（通过 path_provider 获取）。
  static Map<String, String> getShellEnvironment(String appHome) {
    return {
      'HOME': appHome,
      'PATH': '/system/bin:/system/xbin',
      'TERM': 'xterm-256color',
      'SHELL': '/system/bin/sh',
    };
  }
}
