import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class Mimo2codexDetector extends Detector {
  @override
  String get id => 'mimo2codex';
  @override
  String get name => 'mimo2codex';
  @override
  String get icon => '🔌';
  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.coding;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      var result = await EnvironmentService.detectTool(
        'which mimo2codex 2>/dev/null && mimo2codex --version 2>/dev/null',
      );
      var elapsed = DateTime.now().difference(start).inMilliseconds;
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

      result = await EnvironmentService.detectTool(
        'npm list -g mimo2codex 2>/dev/null | grep mimo2codex',
      );
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: 'npm global',
          durationMs: elapsed,
          category: category,
        );
      }

      result = await EnvironmentService.detectTool(
        'lsof -i :8788 2>/dev/null | grep LISTEN || ss -tlnp 2>/dev/null | grep 8788 || netstat -tlnp 2>/dev/null | grep 8788',
      );
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: '运行中 (端口 8788)',
          durationMs: elapsed,
          category: category,
        );
      }

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
