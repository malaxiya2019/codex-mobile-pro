import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class DeepSeekKeyDetector extends Detector {
  @override
  String get id => 'deepseek_key';
  @override
  String get name => 'DeepSeek API Key';
  @override
  String get icon => '🔑';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      // 检查 .mimo2codex/.env 文件
      var result = await TermuxService.execute('cat ~/.mimo2codex/.env 2>/dev/null | grep DS_API_KEY || echo "no_env_file"');
      var elapsed = DateTime.now().difference(start).inMilliseconds;

      if (result.isSuccess && result.stdout.isNotEmpty && !result.stdout.contains('no_env_file')) {
        final keyLine = result.stdout.trim();
        final hasKey = keyLine.contains('DS_API_KEY=') &&
            !keyLine.contains('你的API_KEY') &&
            keyLine.length > 'DS_API_KEY='.length + 5;
        if (hasKey) {
          final masked = keyLine.replaceAllMapped(
            RegExp(r'(sk-)(.{4})(.*)'),
            (m) => '${m[1]}${m[2]}****',
          );
          return DetectionResult(
            id: id, name: name, icon: icon,
            status: DetectionStatus.installed,
            version: masked.length > 20 ? '已配置' : null,
            path: '~/.mimo2codex/.env',
            durationMs: elapsed,
          );
        }
      }

      // 备选: 检查环境变量
      result = await TermuxService.execute('echo "${'$'}DEEPSEEK_API_KEY" | head -c 10');
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess && result.stdout.trim().isNotEmpty && result.stdout.trim() != '') {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: '环境变量',
          durationMs: elapsed,
        );
      }

      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: '未配置 API Key',
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
