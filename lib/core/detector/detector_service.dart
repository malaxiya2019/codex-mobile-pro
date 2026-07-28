import 'detection_result.dart';
import 'detector.dart';
import 'detectors/flutter_detector.dart';
import 'detectors/termux_detector.dart';
import 'detectors/node_detector.dart';
import 'detectors/git_detector.dart';
import 'detectors/python_detector.dart';
import 'detectors/curl_detector.dart';
import 'detectors/codex_detector.dart';
import 'detectors/mimo2codex_detector.dart';
import 'detectors/deepseek_key_detector.dart';
import 'detectors/storage_permission_detector.dart';

/// 环境检测编排服务
///
/// 并行运行所有检测器，返回完整的系统状态仪表盘数据。
class DetectorService {
  final List<Detector> _detectors;

  DetectorService._(this._detectors);

  /// 创建默认检测器列表
  factory DetectorService.create() {
    return DetectorService._([
      FlutterDetector(),
      TermuxDetector(),
      NodeDetector(),
      GitDetector(),
      PythonDetector(),
      CurlDetector(),
      CodexDetector(),
      Mimo2codexDetector(),
      DeepSeekKeyDetector(),
      StoragePermissionDetector(),
    ]);
  }

  /// 创建特定检测器列表（测试用）
  factory DetectorService.custom(List<Detector> detectors) {
    return DetectorService._(detectors);
  }

  /// 所有检测器 ID 列表
  List<String> get detectorIds => _detectors.map((d) => d.id).toList();

  /// 获取单个检测器
  Detector? getDetector(String id) {
    for (final d in _detectors) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// 并行检测所有工具
  Future<List<DetectionResult>> detectAll() async {
    final futures = _detectors.map((d) => d.detect());
    return Future.wait(futures);
  }

  /// 检测单个工具
  Future<DetectionResult?> detectOne(String id) async {
    final detector = getDetector(id);
    if (detector == null) return null;
    return detector.detect();
  }

  /// 统计信息
  static Map<String, int> summarize(List<DetectionResult> results) {
    int installed = 0;
    int missing = 0;
    int errors = 0;

    for (final r in results) {
      switch (r.status) {
        case DetectionStatus.installed:
          installed++;
          break;
        case DetectionStatus.missing:
          missing++;
          break;
        case DetectionStatus.error:
          errors++;
          break;
        default:
          break;
      }
    }

    return {
      'total': results.length,
      'installed': installed,
      'missing': missing,
      'errors': errors,
    };
  }

  /// 按类别分组
  static Map<DetectorCategory, List<DetectionResult>> groupByCategory(
      List<DetectionResult> results) {
    final grouped = <DetectorCategory, List<DetectionResult>>{
      DetectorCategory.runtime: [],
      DetectorCategory.development: [],
    };
    for (final r in results) {
      grouped[r.category]?.add(r);
    }
    return grouped;
  }
}
