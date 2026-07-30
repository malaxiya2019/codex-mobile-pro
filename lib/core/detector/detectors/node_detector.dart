import 'dart:io';
import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class NodeDetector extends Detector {
  @override
  String get id => 'node';
  @override
  String get name => 'Node.js';
  @override
  String get icon => '🟢';
  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.coding;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();

    // 策略 1：通过 TermuxBridge（Termux Shell / 系统 Shell）检测
    try {
      final result = await EnvironmentService.detectTool(
        'which node 2>/dev/null && node --version 2>/dev/null',
      );
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: lines.length > 1 ? lines[1].trim() : null,
          path: lines.first.trim(),
          durationMs: elapsed,
          category: category,
        );
      }
    } catch (_) {
      // 忽略，继续尝试策略 2
    }

    // 策略 2：检查 App 私有 Runtime 目录
    try {
      final runtimeNode = await _checkAppPrivateRuntime();
      if (runtimeNode != null) {
        return runtimeNode;
      }
    } catch (_) {
      // 忽略
    }

    return DetectionResult(
      id: id, name: name, icon: icon,
      status: DetectionStatus.missing,
      durationMs: DateTime.now().difference(start).inMilliseconds,
      category: category,
    );
  }

  /// 检查 App 私有 Runtime 目录中的 node
  Future<DetectionResult?> _checkAppPrivateRuntime() async {
    // 通过 RuntimeEnvironment 获取 App 私有 Runtime 路径
    // RuntimeEnvironment.getInstance() 使用 getApplicationDocumentsDirectory()
    // 返回 <app-dir>/runtime/node/bin/node
    try {
      // 导入并通过 Process.run 直接检查 node 绝对路径
      // 使用 Android getprop 获取 data 目录
      final dataDir = await _getAppDataDir();
      if (dataDir == null) return null;

      final candidates = [
        '$dataDir/app_flutter/runtime/node/bin/node',
        '$dataDir/files/runtime/node/bin/node',
        '$dataDir/runtime/node/bin/node',
      ];

      for (final candidate in candidates) {
        final file = File(candidate);
        if (file.existsSync()) {
          try {
            final result = await Process.run(
              candidate,
              ['--version'],
            );
            if (result.exitCode == 0) {
              final version = (result.stdout as String).trim();
              return DetectionResult(
                id: id, name: name, icon: icon,
                status: DetectionStatus.installed,
                version: version,
                path: candidate,
                category: category,
              );
            }
          } catch (_) {
            continue;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 获取 Android App 数据目录
  Future<String?> _getAppDataDir() async {
    try {
      // 直接找 com.codexmobile.app 数据目录
      for (final dirName in ['com.codexmobile.app', 'com.codexmobile.app.debug', 'com.codexmobile.app.pro']) {
        final candidate = '/data/data/$dirName';
        if (Directory(candidate).existsSync()) {
          return candidate;
        }
      }
      // 尝试通过 HOME 环境变量推断
      final home = Platform.environment['HOME'];
      if (home != null && home.startsWith('/data/data/')) {
        // HOME 可能是 /data/data/com.codexmobile.app/...
        return home.split('/').take(4).join('/');
      }
    } catch (_) {}
    return null;
  }
}
