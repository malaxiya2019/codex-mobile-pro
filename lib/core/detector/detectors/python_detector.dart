import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class PythonDetector extends Detector {
  @override
  String get id => 'python';
  @override
  String get name => 'Python 3';
  @override
  String get icon => '🐍';
  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.coding;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      var result = await EnvironmentService.detectTool(
        'which python3 2>/dev/null && python3 --version 2>/dev/null',
      );
      var elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: lines.length > 1
              ? lines[1].trim().replaceAll('Python ', '')
              : null,
          path: lines.first.trim(),
          durationMs: elapsed,
          category: category,
        );
      }

      result = await EnvironmentService.detectTool(
        'which python 2>/dev/null && python --version 2>/dev/null',
      );
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        final path = lines.first.trim();
        final versionLine = lines.length > 1 ? lines[1].trim() : '';
        final isPy3 = versionLine.contains('Python 3');
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: isPy3
              ? versionLine.replaceAll('Python ', '')
              : '$versionLine (备选)',
          path: path,
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
