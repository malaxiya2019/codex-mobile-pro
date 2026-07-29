import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'runtime_dependency.dart';

class RuntimeEnvironment {
  static RuntimeEnvironment? _instance;

  late final String _appFilesDir;

  String get runtimeDir => '$_appFilesDir/runtime';
  String get binDir => '$runtimeDir/bin';
  String get nodeDir => '$runtimeDir/node';
  String get nodeBinDir => '$nodeDir/bin';
  String get gitDir => '$runtimeDir/git';
  String get gitBinDir => '$gitDir/bin';
  String get pythonDir => '$runtimeDir/python';
  String get pythonBinDir => '$pythonDir/bin';
  String get npmGlobalDir => '$runtimeDir/npm-global';
  String get npmGlobalBinDir => '$npmGlobalDir/bin';
  String get nodeLibDir => '$nodeDir/lib';

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
      runtimeDir, binDir, nodeDir, nodeBinDir, nodeLibDir,
      gitDir, gitBinDir, pythonDir, pythonBinDir,
      npmGlobalDir, npmGlobalBinDir,
    ];
    for (final d in dirs) {
      await Directory(d).create(recursive: true);
    }
  }

  Map<String, String> buildTerminalEnvironment() {
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

  Future<bool> isToolInstalled(RuntimeTool tool) async {
    switch (tool) {
      case RuntimeTool.androidShell:
        return File('/system/bin/sh').existsSync();
      case RuntimeTool.curl:
        return await _binaryExists('curl');
      case RuntimeTool.storagePermission:
        return true;
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

  /// 检查二进制是否存在（先在 runtime bin 目录找，再遍历系统 PATH）
  Future<bool> _binaryExists(String name) async {
    // 检查 runtime 安装目录
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

    // 遍历系统 PATH 目录（不依赖 which 命令）
    final systemPaths = ['/system/bin', '/system/xbin', '/bin', '/usr/bin'];
    for (final dirPath in systemPaths) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        final f = File('$dirPath/$name');
        if (f.existsSync()) return true;
      }
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

  static void reset() {
    _instance = null;
  }
}
