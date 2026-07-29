import 'dart:io';
import '../detection_result.dart';
import '../detector.dart';

/// Shell 环境检测器
///
/// 检测 Android 系统 Shell（/system/bin/sh）是否可用。
/// 不检测 Termux，不访问 /data/data/com.termux/ 路径。
class TermuxDetector extends Detector {
  @override
  String get id => 'termux';
  @override
  String get name => 'Shell 环境';
  @override
  String get icon => '📱';
  @override
  DetectorCategory get category => DetectorCategory.runtime;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      // 检测 /system/bin/sh 是否可执行
      final result = await Process.run(
        '/system/bin/sh',
        ['-c', 'echo ok'],
      );
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (result.exitCode == 0) {
        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.installed,
          version: 'Android 系统 Shell',
          path: '/system/bin/sh',
          durationMs: elapsed,
          category: category,
        );
      }

      return DetectionResult(
        id: id,
        name: name,
        icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        category: category,
      );
    } catch (e) {
      return DetectionResult(
        id: id,
        name: name,
        icon: icon,
        status: DetectionStatus.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        errorMessage: e.toString(),
        category: category,
      );
    }
  }
}
