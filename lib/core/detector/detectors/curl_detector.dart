import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class CurlDetector extends Detector {
  @override
  String get id => 'curl';
  @override
  String get name => 'cURL';
  @override
  String get icon => '🌐';
  @override
  DetectorCategory get category => DetectorCategory.runtime;
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.basic;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final result = await EnvironmentService.detectTool(
        'which curl 2>/dev/null && curl --version 2>/dev/null | head -1',
      );
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        final versionLine =
            lines.length > 1 ? lines[1].trim() : lines.first.trim();
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: versionLine,
          path: lines.first.trim(),
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
