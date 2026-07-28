import 'detection_result.dart';

/// 环境检测器基类
///
/// 所有具体检测器（Flutter、Node.js、Git…）继承此类，
/// 实现 [detect] 方法返回检测结果。
abstract class Detector {
  /// 检测器唯一标识
  String get id;

  /// 显示名称（如 "Flutter SDK"）
  String get name;

  /// 显示图标（Emoji 或 Material Icon name）
  String get icon;

  /// 执行检测
  Future<DetectionResult> detect();
}
