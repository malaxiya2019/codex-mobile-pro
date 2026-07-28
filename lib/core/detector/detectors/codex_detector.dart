import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class CodexDetector extends Detector {
  @override
  String get id => 'codex';
  @override
  String get name => 'Codex CLI';
  @override
  String get icon => '🤖';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      // 直接 which codex
      var result = await TermuxService.execute('which codex 2>/dev/null && codex --version 2>/dev/null');
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
      result = await TermuxService.execute('npm list -g @openai/codex 2>/dev/null | grep codex');
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: 'npm global',
          durationMs: elapsed,
        );
      }

      // 备选: .local/lib/codex
      result = await TermuxService.execute('ls ~/.local/lib/codex/bin/codex 2>/dev/null');
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.isNotEmpty) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          path: '~/.local/lib/codex/bin/codex',
          durationMs: elapsed,
        );
      }

      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: '未安装 Codex CLI',
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
