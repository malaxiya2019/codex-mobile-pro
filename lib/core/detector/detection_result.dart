import 'detector.dart';

/// 工具检测状态
enum DetectionStatus {
  installed,    // ✅ 已安装
  missing,      // ⬜ 未安装（支持自动安装）
  unsupported,  // ⚠️ 暂不支持自动安装
  failed,       // ❌ 安装失败
  blocked,      // ⛔ 依赖阻塞
  checking,     // ⏳ 检测中
  error,        // ⚠️ 检测出错
  unknown,      // ❓ 未知
}

/// 检测结果模型
class DetectionResult {
  final String id;
  final String name;
  final String icon;
  final DetectionStatus status;
  final String? version;
  final String? path;
  final String? errorMessage;
  final int durationMs;
  final DetectorCategory category;
  final RuntimeSubCategory subCategory;
  final String? missingHint;

  const DetectionResult({
    required this.id,
    required this.name,
    required this.icon,
    required this.status,
    this.version,
    this.path,
    this.errorMessage,
    this.durationMs = 0,
    this.category = DetectorCategory.runtime,
    this.subCategory = RuntimeSubCategory.coding,
    this.missingHint,
  });

  DetectionResult copyWith({
    DetectionStatus? status,
    String? version,
    String? path,
    String? errorMessage,
    int? durationMs,
    DetectorCategory? category,
    RuntimeSubCategory? subCategory,
    String? missingHint,
  }) {
    return DetectionResult(
      id: id,
      name: name,
      icon: icon,
      status: status ?? this.status,
      version: version ?? this.version,
      path: path ?? this.path,
      errorMessage: errorMessage ?? this.errorMessage,
      durationMs: durationMs ?? this.durationMs,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      missingHint: missingHint ?? this.missingHint,
    );
  }

  /// 状态对应的显示图标
  String get statusIcon {
    switch (status) {
      case DetectionStatus.installed:
        return '✅';
      case DetectionStatus.missing:
        return '⬜';
      case DetectionStatus.unsupported:
        return '⚠️';
      case DetectionStatus.failed:
        return '❌';
      case DetectionStatus.blocked:
        return '⛔';
      case DetectionStatus.checking:
        return '⏳';
      case DetectionStatus.error:
        return '⚠️';
      case DetectionStatus.unknown:
        return '❓';
    }
  }

  /// 状态对应的颜色值（用于 Material 主题）
  int get statusColor {
    switch (status) {
      case DetectionStatus.installed:
        return 0xFF4CAF50;
      case DetectionStatus.missing:
        return 0xFFFF9800;
      case DetectionStatus.unsupported:
        return 0xFF9E9E9E;
      case DetectionStatus.failed:
        return 0xFFF44336;
      case DetectionStatus.blocked:
        return 0xFF9E9E9E;
      case DetectionStatus.checking:
        return 0xFFFF9800;
      case DetectionStatus.error:
        return 0xFFFF9800;
      case DetectionStatus.unknown:
        return 0xFF9E9E9E;
    }
  }

  @override
  String toString() =>
      '[$statusIcon] $name ${version != null ? "v$version" : ""}'
      '${path != null ? " ($path)" : ""}'
      '${errorMessage != null ? " — $errorMessage" : ""}';
}
