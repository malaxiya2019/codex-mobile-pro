import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class CodexDetector extends Detector {
  @override
  String get id => 'codex';
  @override
  String get name => 'Codex CLI';
  @override
  String get icon => '🤖';
  @override
  DetectorCategory get category => DetectorCategory.runtime;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      var result = await EnvironmentService.detectTool(
        'which codex 2>/dev/null && codex --version 2>/dev/null',
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
        'npm list -g @openai/codex 2>/dev/null | grep codex',
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
        'ls ~/.local/share/codex/bin/codex 2>/dev/null || ls ~/.local/lib/codex/bin/codex 2>/dev/null',
      );
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          path: result.stdout.trim(),
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
