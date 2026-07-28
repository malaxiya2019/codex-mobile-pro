import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class GitDetector extends Detector {
  @override
  String get id => 'git';
  @override
  String get name => 'Git';
  @override
  String get icon => '🔀';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final result = await TermuxService.execute('which git 2>/dev/null && git --version 2>/dev/null');
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        final version = lines.length > 1 ? lines[1].trim().replaceAll('git version ', '') : null;
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: version,
          path: lines.first.trim(),
          durationMs: elapsed,
        );
      }
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: '未安装 Git',
      );
    } catch (e) {
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        errorMessage: e.toString(),
      );
    }
  }
}
