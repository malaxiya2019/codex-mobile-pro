import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class PythonDetector extends Detector {
  @override
  String get id => 'python';
  @override
  String get name => 'Python 3';
  @override
  String get icon => '🐍';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      // 先尝试 python3，再降级到 python
      var result = await TermuxService.execute('which python3 2>/dev/null && python3 --version 2>/dev/null');
      var elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: lines.length > 1 ? lines[1].trim().replaceAll('Python ', '') : null,
          path: lines.first.trim(),
          durationMs: elapsed,
        );
      }

      // 备选：python 命令
      result = await TermuxService.execute('which python 2>/dev/null && python --version 2>/dev/null');
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        final lines = result.stdout.trim().split('\n');
        final path = lines.first.trim();
        final versionLine = lines.length > 1 ? lines[1].trim() : '';
        // 区分 Python 2 和 Python 3
        final isPy3 = versionLine.contains('Python 3');
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: isPy3 ? versionLine.replaceAll('Python ', '') : '$versionLine (备选)',
          path: path,
          durationMs: elapsed,
        );
      }

      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: '未安装 Python',
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
