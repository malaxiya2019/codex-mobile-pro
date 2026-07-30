/// ====================================================================
/// Android 系统环境检测器
///
/// 检测 Android 系统基础能力：
///   - /system/bin/sh — Android 系统 Shell
///   - /system/bin/curl — Android 系统 cURL
///   存储权限 — 已通过 SAF/SAF
///
/// 这是 Layer 0：Android 基础能力。
/// 不检测 Termux、Node、Git 等。
/// ====================================================================
library;

import 'dart:io';
import '../detection_result.dart';
import '../detector.dart';

/// Android 系统 Shell 检测器
class AndroidShellDetector extends Detector {
  @override
  String get id => 'android_shell';
  @override
  String get name => 'Android Shell';
  @override
  String get icon => '📱';

  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.basic;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();

    final shFile = File('/system/bin/sh');
    if (shFile.existsSync()) {
      return DetectionResult(
        id: id,
        name: name,
        icon: icon,
        status: DetectionStatus.installed,
        version: 'Android 系统 Shell',
        path: '/system/bin/sh',
        durationMs: DateTime.now().difference(start).inMilliseconds,
        category: category,
      );
    }

    return DetectionResult(
      id: id,
      name: name,
      icon: icon,
      status: DetectionStatus.missing,
      durationMs: DateTime.now().difference(start).inMilliseconds,
      category: category,
    );
  }
}

/// Android 系统 cURL 检测器
class AndroidCurlDetector extends Detector {
  @override
  String get id => 'curl';
  @override
  String get name => 'cURL';
  @override
  String get icon => '🌐';

  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.basic;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();

    final curlFile = File('/system/bin/curl');
    if (curlFile.existsSync()) {
      // 获取版本
      String? version;
      try {
        final result = await Process.run('/system/bin/curl', ['--version']);
        if (result.exitCode == 0) {
          final firstLine = (result.stdout as String).split('\n').first;
          version = firstLine.trim();
        }
      } catch (_) {}

      return DetectionResult(
        id: id,
        name: name,
        icon: icon,
        status: DetectionStatus.installed,
        version: version,
        path: '/system/bin/curl',
        durationMs: DateTime.now().difference(start).inMilliseconds,
        category: category,
      );
    }

    return DetectionResult(
      id: id,
      name: name,
      icon: icon,
      status: DetectionStatus.missing,
      durationMs: DateTime.now().difference(start).inMilliseconds,
      category: category,
    );
  }
}

/// 存储权限检测器
class StoragePermissionDetector extends Detector {
  @override
  String get id => 'storage';
  @override
  String get name => '存储权限';
  @override
  String get icon => '💾';

  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.basic;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();

    // 检查 /sdcard/Download 是否可读写
    final downloadDir = Directory('/sdcard/Download');
    try {
      if (downloadDir.existsSync()) {
        // 尝试写测试文件
        final testFile = File('/sdcard/Download/.codex_storage_test');
        await testFile.writeAsString('ok');
        await testFile.delete();

        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.installed,
          version: '可读写',
          path: '/sdcard/Download',
          durationMs: DateTime.now().difference(start).inMilliseconds,
          category: category,
        );
      }
    } catch (_) {
      // 写失败说明只读
      if (downloadDir.existsSync()) {
        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.installed,
          version: '只读',
          path: '/sdcard/Download',
          durationMs: DateTime.now().difference(start).inMilliseconds,
          category: category,
        );
      }
    }

    return DetectionResult(
      id: id,
      name: name,
      icon: icon,
      status: DetectionStatus.missing,
      durationMs: DateTime.now().difference(start).inMilliseconds,
      category: category,
      missingHint: '需要存储权限来保存文件',
    );
  }
}
