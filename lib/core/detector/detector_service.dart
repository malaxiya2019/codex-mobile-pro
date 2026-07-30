import 'detection_result.dart';
import 'detector.dart';
import 'detectors/android_system_detector.dart';
import 'detectors/codex_detector.dart';
import 'detectors/deepseek_key_detector.dart';
import 'detectors/git_detector.dart';
import 'detectors/mimo2codex_detector.dart';
import 'detectors/network_detector.dart';
import 'detectors/node_detector.dart';
import 'detectors/python_detector.dart';
import 'detectors/termux_detector.dart';

/// 环境检测编排服务
///
/// 按分层检测：
///   Layer 0: Android 系统环境（shell, curl, 存储）
///   Layer 1: Termux Runtime（Termux 包 + Prefix + 包管理器）
///   Layer 2: Coding Runtime（Node, Git, Python — 依赖 Termux）
///   Layer 3: 高级工具（Codex CLI, mimo2codex — 依赖 Node）
///   AI: DeepSeek Key
///   Dev: Flutter SDK（由 RuntimeDetector 补充）
class DetectorService {
  final List<Detector> _detectors;

  DetectorService._(this._detectors);

  /// 创建默认检测器列表
  factory DetectorService.create() {
    return DetectorService._([
      // Layer 0: Android 系统环境
      AndroidShellDetector(),
      AndroidCurlDetector(),
      StoragePermissionDetector(),

      // Layer 1: Termux Runtime
      TermuxDetector(),

      // Layer 2: Coding Runtime（依赖 Termux）
      NodeDetector(),
      GitDetector(),
      PythonDetector(),

      // Layer 3: 高级工具（依赖 Node）
      CodexDetector(),
      Mimo2codexDetector(),

      // Network（跨层依赖）
      NetworkDetector(),

      // AI
      DeepSeekKeyDetector(),
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
    int failCount = 0;
    int blocked = 0;
    int errors = 0;

    for (final r in results) {
      switch (r.status) {
        case DetectionStatus.installed:
          installed++;
          break;
        case DetectionStatus.missing:
          missing++;
          break;
        case DetectionStatus.failed:
          failCount++;
          break;
        case DetectionStatus.blocked:
          blocked++;
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
      'failed': failCount,
      'blocked': blocked,
      'errors': errors,
    };
  }

  /// 按子类别分组
  static Map<RuntimeSubCategory, List<DetectionResult>> groupBySubCategory(
      List<DetectionResult> results) {
    final grouped = <RuntimeSubCategory, List<DetectionResult>>{
      RuntimeSubCategory.basic: [],
      RuntimeSubCategory.coding: [],
      RuntimeSubCategory.ai: [],
      RuntimeSubCategory.development: [],
    };
    for (final r in results) {
      grouped[r.subCategory]?.add(r);
    }
    return grouped;
  }
}
