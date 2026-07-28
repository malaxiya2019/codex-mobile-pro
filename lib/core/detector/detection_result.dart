/// 工具检测状态
enum DetectionStatus {
  installed,    // ✅ 已安装
  missing,      // ❌ 未安装
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

  const DetectionResult({
    required this.id,
    required this.name,
    required this.icon,
    required this.status,
    this.version,
    this.path,
    this.errorMessage,
    this.durationMs = 0,
  });

  DetectionResult copyWith({
    DetectionStatus? status,
    String? version,
    String? path,
    String? errorMessage,
    int? durationMs,
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
    );
  }

  /// 状态对应的显示图标
  String get statusIcon {
    switch (status) {
      case DetectionStatus.installed:
        return '✅';
      case DetectionStatus.missing:
        return '❌';
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
        return 0xFF4CAF50; // green
      case DetectionStatus.missing:
        return 0xFFF44336; // red
      case DetectionStatus.checking:
        return 0xFFFF9800; // orange
      case DetectionStatus.error:
        return 0xFFFF9800; // orange
      case DetectionStatus.unknown:
        return 0xFF9E9E9E; // grey
    }
  }

  @override
  String toString() =>
      '[$statusIcon] $name ${version != null ? "v$version" : ""}'
      '${path != null ? " ($path)" : ""}'
      '${errorMessage != null ? " — $errorMessage" : ""}';
}
