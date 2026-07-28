import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class CurlDetector extends Detector {
  @override
  String get id => 'curl';
  @override
  String get name => 'cURL';
  @override
  String get icon => '🌐';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final result = await TermuxService.execute('which curl 2>/dev/null && curl --version 2>/dev/null | head -1');
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        final versionLine = lines.length > 1 ? lines[1].trim() : lines.first.trim();
        final version = versionLine.contains('curl') ? versionLine.split(' ').firstWhere((s) => s.startsWith(RegExp(r'\d')), orElse: () => '') : null;
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
        errorMessage: '未安装 cURL',
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
