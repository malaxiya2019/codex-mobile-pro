import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class GitDetector extends Detector {
  @override
  String get id => 'git';
  @override
  String get name => 'Git';
  @override
  String get icon => '🔀';
  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.coding;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final result = await EnvironmentService.detectTool(
        'which git 2>/dev/null && git --version 2>/dev/null',
      );
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        final version = lines.length > 1
            ? lines[1].trim().replaceAll('git version ', '')
            : null;
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: version,
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
