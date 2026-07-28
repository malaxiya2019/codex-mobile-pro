import 'detection_result.dart';

/// 环境类别
enum DetectorCategory {
  /// 运行环境 — Termux、Shell、Node、Git、Python、Codex 等
  runtime,

  /// 开发环境 — Flutter SDK、Android SDK、Java、Gradle 等
  development,
}

/// 环境检测器基类
///
/// 所有具体检测器继承此类，实现 [detect] 方法返回检测结果。
abstract class Detector {
  /// 检测器唯一标识
  String get id;

  /// 显示名称
  String get name;

  /// 显示图标（Emoji）
  String get icon;

  /// 所属类别（Runtime / Development）
  DetectorCategory get category;

  /// 缺失时的友好提示（用于 Development 类工具）
  /// 例如 "Flutter SDK（可选，用于 Flutter 开发）"
  String? get missingHint => null;

  /// 执行检测
  Future<DetectionResult> detect();
}
