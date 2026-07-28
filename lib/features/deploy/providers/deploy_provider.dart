import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/detector/detection_result.dart';
import '../../../core/detector/detector_service.dart';

/// 检测状态
enum DeployState {
  idle,       // 未开始
  checking,   // 检测中
  completed,  // 检测完成
  error,      // 检测出错
}

/// 部署中心状态
class DeployStatus {
  final DeployState state;
  final List<DetectionResult> results;
  final int totalDetectors;
  final String? errorMessage;
  final DateTime? lastChecked;

  const DeployStatus({
    this.state = DeployState.idle,
    this.results = const [],
    this.totalDetectors = 10,
    this.errorMessage,
    this.lastChecked,
  });

  DeployStatus copyWith({
    DeployState? state,
    List<DetectionResult>? results,
    int? totalDetectors,
    String? errorMessage,
    DateTime? lastChecked,
  }) {
    return DeployStatus(
      state: state ?? this.state,
      results: results ?? this.results,
      totalDetectors: totalDetectors ?? this.totalDetectors,
      errorMessage: errorMessage ?? this.errorMessage,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  /// 已安装数量
  int get installedCount => results.where((r) => r.status == DetectionStatus.installed).length;

  /// 缺失数量
  int get missingCount => results.where((r) => r.status == DetectionStatus.missing).length;

  /// 总进度百分比
  double get progressPercent => results.isEmpty ? 0 : installedCount / totalDetectors;

  /// 是否所有工具都已安装
  bool get allInstalled => results.length == totalDetectors && results.every((r) => r.status == DetectionStatus.installed);

  /// 摘要文字
  String get summary {
    if (state == DeployState.idle) return '点击"开始检测"检查环境';
    if (state == DeployState.checking) return '正在检测 (${results.length}/$totalDetectors)...';
    if (state == DeployState.error) return '检测出错: $errorMessage';
    final pct = (progressPercent * 100).toInt();
    if (allInstalled) return '🎉 全部就绪！';
    return '✅ $installedCount/$totalDetectors 已安装 ($pct%)，❌ $missingCount 缺失';
  }
}

/// 部署中心 Provider
final deployStatusProvider = StateNotifierProvider<DeployNotifier, DeployStatus>((ref) {
  return DeployNotifier();
});

class DeployNotifier extends StateNotifier<DeployStatus> {
  DeployNotifier() : super(const DeployStatus());

  DetectorService? _service;

  /// 设置自定义检测器服务（测试用）
  void setService(DetectorService service) {
    _service = service;
  }

  /// 获取或创建检测器服务
  DetectorService _getService() {
    _service ??= DetectorService.create();
    return _service!;
  }

  /// 开始检测所有工具
  Future<void> checkAll() async {
    state = state.copyWith(state: DeployState.checking, results: [], errorMessage: null);

    final service = _getService();
    final results = <DetectionResult>[];

    // 逐个检测（而不是并行），让 UI 实时显示进度
    for (final id in service.detectorIds) {
      // 先添加一个"检测中"占位
      final detector = service.getDetector(id);
      if (detector != null) {
        results.add(DetectionResult(
          id: id,
          name: detector.name,
          icon: detector.icon,
          status: DetectionStatus.checking,
        ));
        state = state.copyWith(results: List.from(results));
      }

      // 执行检测
      final result = await service.detectOne(id);
      if (result != null) {
        final index = results.indexWhere((r) => r.id == id);
        if (index >= 0) {
          results[index] = result;
        } else {
          results.add(result);
        }
        state = state.copyWith(results: List.from(results));
      }
    }

    state = state.copyWith(
      state: DeployState.completed,
      results: results,
      lastChecked: DateTime.now(),
    );
  }

  /// 检测单个工具（刷新）
  Future<void> checkOne(String id) async {
    final service = _getService();
    final result = await service.detectOne(id);
    if (result == null) return;

    final results = List<DetectionResult>.from(state.results);
    final index = results.indexWhere((r) => r.id == id);
    if (index >= 0) {
      results[index] = result;
    } else {
      results.add(result);
    }

    state = state.copyWith(results: results, lastChecked: DateTime.now());
  }

  /// 重置
  void reset() {
    state = const DeployStatus();
  }
}
