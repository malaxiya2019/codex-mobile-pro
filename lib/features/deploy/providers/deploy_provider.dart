import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/detector/detectors/network_detector.dart';
import '../../../core/detector/detection_result.dart';
import '../../../runtime/runtime_manager.dart';
import '../../../runtime/runtime_dependency.dart';
import '../../../runtime/runtime_detector.dart';
import '../../../runtime/runtime_installer.dart';

/// 状态
enum DeployState {
  idle,       // 未开始
  checking,   // 检测中
  completed,  // 检测完成
  installing, // 安装中
  verifying,  // 验证中
  error,      // 出错
}

/// 部署中心状态
class DeployStatus {
  final DeployState state;
  final RuntimeDetectionResult? detectionResult;
  final String? errorMessage;
  final DateTime? lastChecked;

  /// 安装进度信息
  final InstallProgress? currentProgress;

  /// 安装结果列表
  final Map<RuntimeTool, InstallResult> installResults;

  const DeployStatus({
    this.state = DeployState.idle,
    this.detectionResult,
    this.errorMessage,
    this.lastChecked,
    this.currentProgress,
    this.installResults = const {},
  });

  DeployStatus copyWith({
    DeployState? state,
    RuntimeDetectionResult? detectionResult,
    String? errorMessage,
    DateTime? lastChecked,
    InstallProgress? currentProgress,
    Map<RuntimeTool, InstallResult>? installResults,
  }) {
    return DeployStatus(
      state: state ?? this.state,
      detectionResult: detectionResult ?? this.detectionResult,
      errorMessage: errorMessage ?? this.errorMessage,
      lastChecked: lastChecked ?? this.lastChecked,
      currentProgress: currentProgress ?? this.currentProgress,
      installResults: installResults ?? this.installResults,
    );
  }

  /// 摘要
  String get summary {
    if (state == DeployState.idle) return '点击「开始检测」检查环境';
    if (state == DeployState.checking) return '正在检测...';
    if (state == DeployState.installing) return currentProgress?.message ?? '安装中...';
    if (state == DeployState.verifying) return '验证环境中...';
    if (state == DeployState.error) return '出错: $errorMessage';

    if (detectionResult != null) return detectionResult!.summary;
    return '';
  }

  /// 是否有安装中的进度
  bool get isInstalling => state == DeployState.installing;

  /// 网络是否正常（用于安装前预检）
  bool get networkOk {
    if (detectionResult == null) return true;
    final networkResult = detectionResult!.basic
        .where((r) => r.id == 'network')
        .firstOrNull;
    if (networkResult == null) return true;
    return networkResult.status == DetectionStatus.installed;
  }

  /// 网络错误建议
  String? get networkSuggestion {
    if (detectionResult == null) return null;
    final networkResult = detectionResult!.basic
        .where((r) => r.id == 'network')
        .firstOrNull;
    if (networkResult == null) return null;
    if (networkResult.status == DetectionStatus.installed) return null;
    return networkResult.missingHint;
  }
}

/// 部署中心 Provider
final deployStatusProvider =
    StateNotifierProvider<DeployNotifier, DeployStatus>((ref) {
  return DeployNotifier();
});

class DeployNotifier extends StateNotifier<DeployStatus> {
  StreamSubscription<InstallProgress>? _progressSub;

  DeployNotifier() : super(const DeployStatus());

  /// 初始化
  Future<void> initialize() async {
    await RuntimeManager.instance.initialize();
  }

  /// 检测所有
  Future<void> checkAll() async {
    state = state.copyWith(
        state: DeployState.checking, errorMessage: null);

    try {
      await RuntimeManager.instance.initialize();
      final result = await RuntimeManager.instance.detectAll();

      state = state.copyWith(
        state: DeployState.completed,
        detectionResult: result,
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        state: DeployState.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 单工具检测
  Future<void> checkOne(String id) async {
    try {
      final detector = RuntimeDetector();
      final result = await detector.detectOne(id);
      if (result == null || state.detectionResult == null) return;

      final all = List<DetectionResult>.from(state.detectionResult!.all);
      final index = all.indexWhere((r) => r.id == id);
      if (index >= 0) {
        all[index] = result;
      } else {
        all.add(result);
      }

      final grouped = _groupResults(all);
      state = state.copyWith(
        detectionResult: grouped,
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      // ignore
    }
  }

  /// 一键部署 Coding Runtime
  Future<void> installCodingRuntime() async {
    final mgr = RuntimeManager.instance;

    // ─── 安装前网络预检 ───
    final networkOk = await NetworkDetector.quickCheck();
    if (!networkOk) {
      // 网络有问题，执行完整检测获取详细诊断
      state = state.copyWith(state: DeployState.checking);
      await checkAll();

      final suggestion = state.networkSuggestion;
      state = state.copyWith(
        state: DeployState.error,
        errorMessage: suggestion != null
            ? '❌ 网络不可用\n$suggestion'
            : '❌ 网络不可用\n请检查网络连接后重试',
      );
      return;
    }

    state = state.copyWith(
      state: DeployState.installing,
      installResults: {},
    );

    // 订阅进度
    _progressSub?.cancel();
    _progressSub = mgr.progressStream.listen((progress) {
      state = state.copyWith(currentProgress: progress);
    });

    // 执行安装
    final results = await mgr.installCodingRuntime().toList();

    // 安装完成后重新检测
    await checkAll();

    // 构建安装结果 map
    final resultMap = <RuntimeTool, InstallResult>{};
    for (final r in results) {
      resultMap[r.tool] = r;
    }

    state = state.copyWith(
      installResults: resultMap,
    );
  }

  /// 安装单个工具
  Future<void> installTool(RuntimeTool tool) async {
    final mgr = RuntimeManager.instance;

    // ─── 安装前网络预检 ───
    final networkOk = await NetworkDetector.quickCheck();
    if (!networkOk) {
      state = state.copyWith(state: DeployState.checking);
      await checkAll();

      final suggestion = state.networkSuggestion;
      state = state.copyWith(
        state: DeployState.error,
        errorMessage: suggestion != null
            ? '❌ 网络不可用\n$suggestion'
            : '❌ 网络不可用\n请检查网络连接后重试',
      );
      return;
    }

    state = state.copyWith(
      state: DeployState.installing,
    );

    _progressSub?.cancel();
    _progressSub = mgr.progressStream.listen((progress) {
      state = state.copyWith(currentProgress: progress);
    });

    final result = await mgr.install(tool);

    // 重新检测
    await checkAll();

    final resultMap = Map<RuntimeTool, InstallResult>.from(state.installResults);
    resultMap[tool] = result;
    state = state.copyWith(installResults: resultMap);
  }

  /// 验证环境
  Future<List<VerificationResult>> verifyEnvironment() async {
    state = state.copyWith(state: DeployState.verifying);
    try {
      final results = await RuntimeManager.instance.verifyEnvironment();
      await checkAll();
      return results;
    } catch (e) {
      state = state.copyWith(
        state: DeployState.error,
        errorMessage: e.toString(),
      );
      return [];
    }
  }

  /// 重置
  void reset() {
    _progressSub?.cancel();
    state = const DeployStatus();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  RuntimeDetectionResult _groupResults(List<DetectionResult> results) {
    // Reuse RuntimeDetector's grouping
        final basic = <DetectionResult>[];
    final coding = <DetectionResult>[];
    final ai = <DetectionResult>[];
    final development = <DetectionResult>[];

    for (final r in results) {
      switch (r.id) {
        case 'termux':
        case 'curl':
        case 'storage':
        case 'network':
          basic.add(r);
          break;
        case 'node':
        case 'git':
        case 'python':
        case 'codex':
        case 'mimo2codex':
        case 'ubuntu':
          coding.add(r);
          break;
        case 'deepseek_key':
          ai.add(r);
          break;
        case 'flutter':
          development.add(r);
          break;
      }
    }

    return RuntimeDetectionResult(
      basic: basic,
      coding: coding,
      ai: ai,
      development: development,
      all: results,
      isComplete: true,
    );
  }
}
