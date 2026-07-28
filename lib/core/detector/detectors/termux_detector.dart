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
        // 通过执行命令验证 Termux Bash 是否可访问
        // 不使用 File.exists()，Android 11+ Scoped Storage 限制访问其他应用目录
        String version = 'Termux (受限)';
        try {
          final bashResult = await Process.run(
            '/system/bin/sh',
            [
              '-c',
              'if [ -x /data/data/com.termux/files/usr/bin/bash ]; then '
              '  /data/data/com.termux/files/usr/bin/bash --version 2>/dev/null | head -1; '
              'else '
              '  echo "BASH_NO"; '
              'fi',
            ],
            runInShell: false,
          );
          final bashOut = (bashResult.stdout as String?)?.trim() ?? '';
          if (bashOut.isNotEmpty && !bashOut.contains('BASH_NO')) {
            version = bashOut;
          }
        } catch (_) {
          // 降级为默认版本描述
        }

        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: version,
          path: '/data/data/com.termux',
          durationMs: elapsed,
          category: category,
        );
      }

      // 尝试检测 Android 系统 Shell
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
