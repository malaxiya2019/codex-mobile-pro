import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class TermuxDetector extends Detector {
  @override
  String get id => 'termux';
  @override
  String get name => 'Termux 环境';
  @override
  String get icon => '📱';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      final env = await TermuxService.checkEnvironment();
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (env.termuxInstalled && env.bashExists) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: env.termuxMode ? '原生模式' : '受限模式',
          path: '/data/data/com.termux',
          durationMs: elapsed,
        );
      }

      // 即使 Termux 未安装，系统 shell 降级也算"有运行环境"
      if (env.hasAnyShell) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: '系统 shell 降级',
          durationMs: elapsed,
        );
      }

      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: env.bashLastStderr.isNotEmpty ? env.bashLastStderr : 'Termux 未安装',
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
