import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class DeepSeekKeyDetector extends Detector {
  @override
  String get id => 'deepseek_key';
  @override
  String get name => 'DeepSeek API Key';
  @override
  String get icon => '🔑';
  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.ai;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      var result = await EnvironmentService.detectTool(
        'cat ~/.mimo2codex/.env 2>/dev/null | grep DS_API_KEY || echo "no_env_file"',
      );
      var elapsed = DateTime.now().difference(start).inMilliseconds;

      if (result.isSuccess &&
          result.stdout.isNotEmpty &&
          !result.stdout.contains('no_env_file')) {
        final keyLine = result.stdout.trim();
        final hasKey = keyLine.contains('DS_API_KEY=') &&
            !keyLine.contains('你的API_KEY') &&
            keyLine.length > 'DS_API_KEY='.length + 5;
        if (hasKey) {
          return DetectionResult(
            id: id, name: name, icon: icon,
            status: DetectionStatus.installed,
            version: '已配置',
            path: '~/.mimo2codex/.env',
            durationMs: elapsed,
            category: category,
          );
        }
      }

      result = await EnvironmentService.detectTool(
        'echo "\${DEEPSEEK_API_KEY:-\$DS_API_KEY}" | head -c 10',
      );
      elapsed = DateTime.now().difference(start).inMilliseconds;
      if (result.isSuccess &&
          result.stdout.trim().isNotEmpty &&
          result.stdout.trim() != '') {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: '环境变量',
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
