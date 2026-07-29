import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

/// Shell/环境检测器
///
/// 检测 Termux 环境和系统 Shell 是否可用。
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
      final env = await TermuxService.checkEnvironment();
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (env.termuxMode) {
        // Termux 可用
        final version = env.termuxWorks ? 'Termux Bash' : 'Termux (Intent)';
        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.installed,
          version: version,
          path: '/data/data/com.termux/files/usr/bin/bash',
          durationMs: elapsed,
          category: category,
        );
      } else if (env.fallbackAvailable) {
        // 只有系统 Shell
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
