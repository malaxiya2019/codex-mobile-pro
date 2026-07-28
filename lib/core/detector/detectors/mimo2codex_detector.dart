import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class Mimo2codexDetector extends Detector {
  @override
  String get id => 'mimo2codex';
  @override
  String get name => 'mimo2codex';
  @override
  String get icon => '🔌';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      // 检查二进制
      var result = await TermuxService.execute('which mimo2codex 2>/dev/null && mimo2codex --version 2>/dev/null');
      var elapsed = DateTime.now().difference(start).inMilliseconds;
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

      // 备选: npm global
      result = await TermuxService.execute('npm list -g mimo2codex 2>/dev/null | grep mimo2codex');
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: 'npm global',
          durationMs: elapsed,
        );
      }

      // 检查端口 8788 是否在监听（表示正在运行）
      result = await TermuxService.execute('lsof -i :8788 2>/dev/null | grep LISTEN || ss -tlnp 2>/dev/null | grep 8788 || netstat -tlnp 2>/dev/null | grep 8788');
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: '运行中 (端口 8788)',
          durationMs: elapsed,
        );
      }

      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: '未安装 mimo2codex',
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
