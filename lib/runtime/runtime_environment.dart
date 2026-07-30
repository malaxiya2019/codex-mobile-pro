/// ====================================================================
/// Runtime 环境管理
///
/// 统一管理：
///   1. App 私有 Runtime 目录结构
///   2. PATH 及环境变量构建（唯一来源）
///   3. 工具安装状态检测
///
/// 所有环境变量必须由此处统一构建，禁止在其他模块中重复拼接 PATH。
/// ====================================================================
library;

import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'runtime_dependency.dart';

class RuntimeEnvironment {
  static RuntimeEnvironment? _instance;

  late final String _appFilesDir;

  // ─── 通用 Runtime 目录 ───────────────────────────────────────
  String get runtimeDir => '$_appFilesDir/runtime';
  String get binDir => '$runtimeDir/bin';

  // ─── 单包安装目录（deprecated） ───────────────────────────────
  String get nodeDir => '$runtimeDir/node';
  String get nodeBinDir => '$nodeDir/bin';
  String get nodeLibDir => '$nodeDir/lib';
  String get gitDir => '$runtimeDir/git';
  String get gitBinDir => '$gitDir/bin';
  String get pythonDir => '$runtimeDir/python';
  String get pythonBinDir => '$pythonDir/bin';
  String get npmGlobalDir => '$runtimeDir/npm-global';
  String get npmGlobalBinDir => '$npmGlobalDir/bin';

  // ─── Ubuntu Runtime 目录 ──────────────────────────────────────
  /// Ubuntu Runtime 根目录
  String get ubuntuDir => '$runtimeDir/ubuntu';

  /// Ubuntu rootfs 解压目录
  String get ubuntuRootfsDir => '$ubuntuDir/rootfs';

  /// proot 和 loader 安装目录
  String get ubuntuBinDir => '$ubuntuDir/bin';

  /// proot libexec 目录（loader/loader32 位置）
  String get ubuntuLibexecDir => '$ubuntuDir/libexec';

  /// proot loader 完整路径
  String get ubuntuLoaderPath => '$ubuntuLibexecDir/proot/loader';

  RuntimeEnvironment._();

  static Future<RuntimeEnvironment> getInstance() async {
    if (_instance != null) return _instance!;
    final instance = RuntimeEnvironment._();
    final dir = await getApplicationDocumentsDirectory();
    instance._appFilesDir = dir.path;
    _instance = instance;
    return instance;
  }

  Future<void> ensureDirectories() async {
    final dirs = [
      runtimeDir,
      binDir,
      // 单包目录
      nodeDir, nodeBinDir, nodeLibDir,
      gitDir, gitBinDir,
      pythonDir, pythonBinDir,
      npmGlobalDir, npmGlobalBinDir,
      // Ubuntu 目录
      ubuntuDir,
      ubuntuRootfsDir,
      ubuntuBinDir,
      ubuntuLibexecDir,
      path.join(ubuntuLibexecDir, 'proot'),
    ];
    for (final d in dirs) {
      await Directory(d).create(recursive: true);
    }
  }

  /// 构建终端环境变量
  ///
  /// 这是 Runtime 环境变量的唯一构建点。
  /// 所有模块（TerminalService、Detector、Installer）必须使用此方法。
  ///
  /// 如果 Ubuntu Runtime 已安装，自动使用 Ubuntu 环境。
  /// 否则使用系统默认环境。
  Map<String, String> buildTerminalEnvironment() {
    if (isUbuntuInstalled()) {
      return _buildUbuntuEnvironment();
    }
    return _buildDefaultEnvironment();
  }

  /// ─── 默认环境（/system/bin/sh） ─────────────────────────────

  Map<String, String> _buildDefaultEnvironment() {
    final paths = <String>[
      binDir, nodeBinDir, gitBinDir, pythonBinDir, npmGlobalBinDir,
      '/system/bin', '/system/xbin',
    ];
    final validPaths = paths.where((p) => Directory(p).existsSync()).toList();
    final pathStr = validPaths.join(':');

    final libDirPath = Directory(nodeLibDir).existsSync() ? nodeLibDir : '';
    final ldLibPath = libDirPath.isNotEmpty ? libDirPath : null;

    final env = <String, String>{
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

    if (ldLibPath != null) {
      final existing = Platform.environment['LD_LIBRARY_PATH'];
      env['LD_LIBRARY_PATH'] = existing != null
          ? '$ldLibPath:$existing'
          : ldLibPath;
    }

    return env;
  }

  /// ─── Ubuntu Runtime 环境 ─────────────────────────────────────

  Map<String, String> _buildUbuntuEnvironment() {
    // Ubuntu Runtime 的核心路径
    final rootfsPath = ubuntuRootfsDir;

    // PATH: 优先使用 rootfs 中的系统 bin，回退到 Android 系统 bin
    final paths = <String>[
      path.join(rootfsPath, 'usr', 'local', 'sbin'),
      path.join(rootfsPath, 'usr', 'local', 'bin'),
      path.join(rootfsPath, 'usr', 'sbin'),
      path.join(rootfsPath, 'usr', 'bin'),
      path.join(rootfsPath, 'sbin'),
      path.join(rootfsPath, 'bin'),
      ubuntuBinDir,     // proot 安装目录
      '/system/bin',
      '/system/xbin',
    ];

    final validPaths = paths.where((p) => Directory(p).existsSync()).toList();
    final pathStr = _deduplicatePath(validPaths.join(':'));

    // HOME: Ubuntu 默认 home
    final homeDir = path.join(rootfsPath, 'root');

    final env = <String, String>{
      'HOME': homeDir,
      'PATH': pathStr,
      'SHELL': path.join(rootfsPath, 'usr', 'bin', 'bash'),
      'TERM': 'xterm-256color',
      'PWD': homeDir,
      'TMPDIR': path.join(rootfsPath, 'tmp'),
      'LANG': 'en_US.UTF-8',
      'LC_ALL': 'en_US.UTF-8',
      'USER': 'root',
      'LOGNAME': 'root',
      'PROOT_LOADER': ubuntuLoaderPath,
    };

    return env;
  }

  /// ─── 安装状态检测 ───────────────────────────────────────────

  bool isUbuntuInstalled() {
    final prootFile = File(path.join(ubuntuBinDir, 'proot'));
    final rootfsBash = File(path.join(ubuntuRootfsDir, 'usr', 'bin', 'bash'));
    return prootFile.existsSync() && rootfsBash.existsSync();
  }

  /// 获取当前有效的 Runtime 类型
  RuntimeType getRuntimeType() {
    if (isUbuntuInstalled()) return RuntimeType.ubuntu;
    return RuntimeType.system;
  }

  Future<bool> isToolInstalled(RuntimeTool tool) async {
    switch (tool) {
      case RuntimeTool.androidShell:
        return File('/system/bin/sh').existsSync();
      case RuntimeTool.curl:
        return await _binaryExists('curl');
      case RuntimeTool.storagePermission:
        return true;
      case RuntimeTool.ubuntu:
        return isUbuntuInstalled();
      case RuntimeTool.node:
        return await _binaryExists('node');
      case RuntimeTool.git:
        return await _binaryExists('git');
      case RuntimeTool.python:
        return await _binaryExists('python3');
      case RuntimeTool.codexCli:
        return await _binaryExists('codex');
      case RuntimeTool.mimo2codex:
        return await _binaryExists('mimo2codex');
      case RuntimeTool.deepseekKey:
        return _configFileExists();
      case RuntimeTool.flutterSdk:
        return await _binaryExists('flutter');
    }
  }

  /// 检查二进制是否存在
  Future<bool> _binaryExists(String name) async {
    // 检查 Ubuntu rootfs
    if (isUbuntuInstalled()) {
      final ubuntuBins = [
        path.join(ubuntuRootfsDir, 'usr', 'bin', name),
        path.join(ubuntuRootfsDir, 'usr', 'local', 'bin', name),
        path.join(ubuntuRootfsDir, 'bin', name),
      ];
      for (final p in ubuntuBins) {
        if (File(p).existsSync()) return true;
      }
    }

    // 检查 runtime bin 目录
    final runtimeBins = [
      path.join(binDir, name),
      path.join(nodeBinDir, name),
      path.join(gitBinDir, name),
      path.join(pythonBinDir, name),
      path.join(npmGlobalBinDir, name),
    ];
    for (final p in runtimeBins) {
      if (File(p).existsSync()) return true;
    }

    // 遍历系统 PATH 目录
    final systemPaths = ['/system/bin', '/system/xbin', '/bin', '/usr/bin'];
    for (final dirPath in systemPaths) {
      final f = File('$dirPath/$name');
      if (f.existsSync()) return true;
    }
    return false;
  }

  bool _configFileExists() {
    final envFile = File('$_appFilesDir/.mimo2codex/.env');
    if (envFile.existsSync()) {
      final content = envFile.readAsStringSync();
      return content.contains('DS_API_KEY');
    }
    return false;
  }

  /// ─── 工具方法 ───────────────────────────────────────────────

  /// PATH 去重（保留首次出现的顺序）
  static String _deduplicatePath(String pathStr) {
    final parts = pathStr.split(':');
    final seen = <String>{};
    final unique = <String>[];
    for (final p in parts) {
      if (seen.add(p)) {
        unique.add(p);
      }
    }
    return unique.join(':');
  }

  static void reset() {
    _instance = null;
  }
}

/// Runtime 类型
enum RuntimeType {
  /// 系统默认（/system/bin/sh）
  system,

  /// Ubuntu Runtime（rootfs + proot）
  ubuntu,
}
