import 'dart:io';
import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class TermuxDetector extends Detector {
  @override
  String get id => 'termux';
  @override
  String get name => 'Termux 环境';
  @override
  String get icon => '📱';
  @override
  DetectorCategory get category => DetectorCategory.runtime;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final check = await EnvironmentService.checkTermux();
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (check.isTermuxAvailable) {
        final bashFile = File('/data/data/com.termux/files/usr/bin/bash');
        final bashExists = await bashFile.exists();
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: bashExists ? 'Termux Bash' : 'Termux (受限)',
          path: '/data/data/com.termux',
          durationMs: elapsed,
          category: category,
        );
      }

      try {
        final shResult = await Process.run('/system/bin/sh', ['-c', 'echo ok'],
            runInShell: false);
        if (shResult.exitCode == 0) {
          return DetectionResult(
            id: id, name: name, icon: icon,
            status: DetectionStatus.installed,
            version: 'Android 系统 Shell',
            durationMs: elapsed,
            category: category,
          );
        }
      } catch (_) {}

      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        category: category,
      );
    } catch (e) {
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        errorMessage: e.toString(),
        category: category,
      );
    }
  }
}
