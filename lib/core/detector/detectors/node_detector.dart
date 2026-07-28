import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class NodeDetector extends Detector {
  @override
  String get id => 'node';
  @override
  String get name => 'Node.js';
  @override
  String get icon => '🟢';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final result = await TermuxService.execute('which node 2>/dev/null && node --version 2>/dev/null');
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: lines.length > 1 ? lines[1].trim() : null,
          path: lines.first.trim(),
          durationMs: elapsed,
        );
      }
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: '未安装 Node.js',
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
