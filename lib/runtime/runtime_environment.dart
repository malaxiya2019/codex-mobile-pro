import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'runtime_dependency.dart';

/// ====================================================================
/// Runtime 环境变量管理
///
/// 管理 App 私有目录下的 Runtime 二进制文件的 PATH 注入。
///
/// 目录结构：
///   <app-files>/runtime/
///   ├── bin/          ← 符号链接或直接存放可执行文件
///   ├── node/
///   ├── python/
///   ├── git/
///   └── npm-global/
/// ====================================================================

class RuntimeEnvironment {
  static RuntimeEnvironment? _instance;

  /// App 私有 files 目录
  late final String _appFilesDir;

  /// Runtime 根目录
  String get runtimeDir => '$_appFilesDir/runtime';

  /// Runtime bin 目录
  String get binDir => '$runtimeDir/bin';

  /// Node.js 安装目录
  String get nodeDir => '$runtimeDir/node';

  /// Node.js bin 目录
  String get nodeBinDir => '$nodeDir/bin';

  /// Git 安装目录
  String get gitDir => '$runtimeDir/git';

  /// Git bin 目录
  String get gitBinDir => '$gitDir/bin';

  /// Python 安装目录
  String get pythonDir => '$runtimeDir/python';

  /// Python bin 目录
  String get pythonBinDir => '$pythonDir/bin';

  /// npm 全局安装目录
  String get npmGlobalDir => '$runtimeDir/npm-global';

  /// npm 全局 bin 目录
  String get npmGlobalBinDir => '$npmGlobalDir/bin';

  RuntimeEnvironment._();

  static Future<RuntimeEnvironment> getInstance() async {
    if (_instance != null) return _instance!;
    final instance = RuntimeEnvironment._();
    final dir = await getApplicationDocumentsDirectory();
    instance._appFilesDir = dir.path;
    _instance = instance;
    return instance;
  }

  /// 确保 Runtime 目录结构存在
  Future<void> ensureDirectories() async {
    final dirs = [
      runtimeDir,
      binDir,
      nodeDir,
      nodeBinDir,
      gitDir,
      gitBinDir,
      pythonDir,
      pythonBinDir,
      npmGlobalDir,
      npmGlobalBinDir,
    ];
    for (final d in dirs) {
      await Directory(d).create(recursive: true);
    }
  }

  /// 构建终端环境变量
  ///
  /// 将 Runtime bin 目录加入 PATH，同时保留系统 PATH。
  /// 供 TerminalService / ShellDetector 使用。
  Map<String, String> buildTerminalEnvironment() {
    // 收集所有有效的 bin 路径
    final paths = <String>[
      binDir,
      nodeBinDir,
      gitBinDir,
      pythonBinDir,
      npmGlobalBinDir,
      // 系统默认路径
      '/system/bin',
      '/system/xbin',
    ];

    // 仅保留存在的目录
    final validPaths = paths.where((p) => Directory(p).existsSync()).toList();

    final pathStr = validPaths.join(':');

    return {
      'HOME': _appFilesDir,
      'PATH': pathStr,
      'SHELL': '/system/bin/sh',
      'TERM': 'xterm-256color',
      'PWD': _appFilesDir,
      'TMPDIR': Directory.systemTemp.path,
      'LANG': 'en_US.UTF-8',
      'USER': 'user',
      'LOGNAME': 'user',
      'NPM_CONFIG_PREFIX': npmGlobalDir,
      'NODE_PATH': '$npmGlobalDir/lib/node_modules',
    };
  }

  /// 检查某个工具是否已安装（二进制是否存在）
  bool isToolInstalled(RuntimeTool tool) {
    switch (tool) {
      case RuntimeTool.androidShell:
        return File('/system/bin/sh').existsSync();
      case RuntimeTool.curl:
        return _binaryExists('curl');
      case RuntimeTool.storagePermission:
        // 存储权限由 Android 运行时决定，默认假设有
        return true;
      case RuntimeTool.node:
        return _binaryExists('node');
      case RuntimeTool.git:
        return _binaryExists('git');
      case RuntimeTool.python:
        return _binaryExists('python3');
      case RuntimeTool.codexCli:
        return _binaryExists('codex');
      case RuntimeTool.mimo2codex:
        return _binaryExists('mimo2codex');
      case RuntimeTool.deepseekKey:
        return _configFileExists();
      case RuntimeTool.flutterSdk:
        return _binaryExists('flutter');
    }
  }

  /// 检查二进制是否存在（先在 runtime bin 找，再找系统 PATH）
  bool _binaryExists(String name) {
    // 先找 runtime 目录
    final runtimeBin = File('$binDir/$name');
    if (runtimeBin.existsSync()) return true;

    final nodeBin = File('$nodeBinDir/$name');
    if (nodeBin.existsSync()) return true;

    final gitBin = File('$gitBinDir/$name');
    if (gitBin.existsSync()) return true;

    final pythonBin = File('$pythonBinDir/$name');
    if (pythonBin.existsSync()) return true;

    final npmBin = File('$npmGlobalBinDir/$name');
    if (npmBin.existsSync()) return true;

    // 再找系统 PATH
    try {
      final result = Process.run('which', [name],
          runInShell: true,
          environment: {'PATH': '/system/bin:/system/xbin'});
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// DeepSeek API Key 配置文件是否存在
  bool _configFileExists() {
    final envFile = File('$_appFilesDir/.mimo2codex/.env');
    if (envFile.existsSync()) {
      final content = envFile.readAsStringSync();
      return content.contains('DS_API_KEY');
    }
    return false;
  }

  /// 清空缓存（用于重新检测时刷新）
  static void reset() {
    _instance = null;
  }
}
