import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class FlutterDetector extends Detector {
  @override
  String get id => 'flutter';
  @override
  String get name => 'Flutter SDK';
  @override
  String get icon => '🦋';
  @override
  DetectorCategory get category => DetectorCategory.development;
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.development;
  @override
  String? get missingHint => 'Flutter SDK（可选，用于 Flutter 开发）';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final result = await EnvironmentService.detectTool(
        'which flutter 2>/dev/null && flutter --version 2>/dev/null | head -5',
      );
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.contains('Flutter')) {
        final lines = result.stdout.split('\n');
        final versionLine = lines.length > 1 ? lines[1].trim() : '';
        final version = versionLine.contains('Flutter')
            ? versionLine
                .replaceAll(RegExp(r'^Flutter\s+'), '')
                .split(' ')
                .first
            : null;
        final path = lines.first.trim();
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: version,
          path: path,
          durationMs: elapsed,
          category: category,
          missingHint: missingHint,
        );
      }
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        category: category,
        missingHint: missingHint,
      );
    } catch (e) {
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        errorMessage: e.toString(),
        category: category,
        missingHint: missingHint,
      );
    }
  }
}
