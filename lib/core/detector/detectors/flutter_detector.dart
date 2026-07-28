import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class FlutterDetector extends Detector {
  @override
  String get id => 'flutter';
  @override
  String get name => 'Flutter SDK';
  @override
  String get icon => '🦋';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final result = await TermuxService.execute('which flutter 2>/dev/null && flutter --version 2>/dev/null | head -1');
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.contains('flutter')) {
        final lines = result.stdout.split('\n');
        final versionLine = lines.length > 1 ? lines[1].trim() : '';
        final version = versionLine.contains('Flutter') ? versionLine.replaceAll(RegExp(r'^Flutter\s+'), '').split(' ').first : null;
        final path = lines.first.trim();
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: version, path: path,
          durationMs: elapsed,
        );
      }
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: '未安装 Flutter SDK',
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
