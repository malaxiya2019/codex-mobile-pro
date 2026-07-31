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

  // ─── Linux Runtime 目录（Ubuntu rootfs）──────────────────────
  /// Linux Runtime 根目录（Ubuntu rootfs）
  String get ubuntuDir => '$runtimeDir/ubuntu';

  /// Ubuntu rootfs 解压目录
  String get ubuntuRootfsDir => '$ubuntuDir/rootfs';

  /// proot 和 loader 安装目录
  String get ubuntuBinDir => '$ubuntuDir/bin';

  /// proot libexec 目录（loader/loader32 位置）
  String get ubuntuLibexecDir => '$ubuntuDir/libexec';

  /// proot loader 完整路径
  String get ubuntuLoaderPath => '$ubuntuLibexecDir/proot/loader';

  /// Linux Runtime 安装完成标记（防止半解压 rootfs 被误判为已安装）
  ///
  /// 只有完整通过「下载 → 验证 → 流式解压 → 原子替换 → 健康检查」
  /// 全链路后才会写入此标记。
  String get installCompleteMarker =>
      '$ubuntuRootfsDir/.codex_install_complete';

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

  /// 构建默认（Android 回退）环境变量
  ///
  /// Linux Runtime 环境由 LinuxRuntimeProvider 统一提供
  /// （HOME=/root、PATH、SHELL=/bin/bash 等）。
  /// 本方法仅用于 Linux Runtime 未就绪时的 Android 系统回退。
  Map<String, String> buildTerminalEnvironment() {
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

  /// ─── Linux Runtime 环境（Ubuntu rootfs）─────────────────────

  Map<String, String> _buildUbuntuEnvironment() {
    // Linux Runtime 的核心路径
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

    // HOME: rootfs 内默认 home
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
    final marker = File(installCompleteMarker);
    return prootFile.existsSync() &&
        rootfsBash.existsSync() &&
        marker.existsSync();
  }

  /// 是否存在不完整的 Ubuntu 安装（半解压 rootfs 或缺少完成标记）
  ///
  /// 用于 UI 提示「需要重新初始化」而不是误报已就绪。
  bool get hasPartialUbuntuInstall {
    final prootFile = File(path.join(ubuntuBinDir, 'proot'));
    final rootfsBash = File(path.join(ubuntuRootfsDir, 'usr', 'bin', 'bash'));
    final partial = prootFile.existsSync() || rootfsBash.existsSync();
    return partial && !isUbuntuInstalled();
  }

  /// Linux Runtime 是否已就绪（isUbuntuInstalled 的对外别名）
  bool get isLinuxReady => isUbuntuInstalled();

  /// 获取当前有效的 Runtime 类型
  RuntimeType getRuntimeType() {
    if (isUbuntuInstalled()) return RuntimeType.linux;
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
  /// Android 系统默认（/system/bin/sh，回退）
  system,

  /// Linux Runtime（PRoot + Ubuntu rootfs）
  linux,
}
