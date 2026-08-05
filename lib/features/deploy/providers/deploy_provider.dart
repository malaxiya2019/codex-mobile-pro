import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/detector/detection_result.dart';
import '../../../core/detector/detectors/network_detector.dart';
import '../../../runtime/environment_doctor.dart';
import '../../../runtime/install_models.dart';
import '../../../runtime/runtime_dependency.dart';
import '../../../runtime/runtime_detector.dart';
import '../../../runtime/runtime_manager.dart';

/// 状态
enum DeployState {
  idle, // 未开始
  checking, // 检测中
  completed, // 检测完成
  installing, // 安装中
  verifying, // 验证中
  repairing, // 修复环境中
  error, // 出错（检测失败 或 部署失败）
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
    if (state == DeployState.installing) {
      return currentProgress?.message ?? '安装中...';
    }
    if (state == DeployState.verifying) return '验证环境中...';
    if (state == DeployState.repairing) return '修复环境中...';
    if (state == DeployState.error) return '出错: $errorMessage';

    if (detectionResult != null) return detectionResult!.summary;
    return '';
  }

  /// 是否有安装中的进度
  bool get isInstalling => state == DeployState.installing;

  /// 是否正在修复环境
  bool get isRepairing => state == DeployState.repairing;

  /// 是否处于进行中状态（安装 / 验证 / 修复）。
  ///
  /// 进行中时 UI 必须隐藏旧的检测结果卡片（deploy_page），
  /// 否则用户会看到「部署中 git 30%」与「部署前 Node exit=127」
  /// 同时并存 —— APK-240 真机反馈的「打开就 30%」状态混叠根因。
  bool get isBusy =>
      state == DeployState.installing ||
      state == DeployState.verifying ||
      state == DeployState.repairing;

  /// 网络是否正常（用于安装前预检）
  bool get networkOk {
    if (detectionResult == null) return true;
    final networkResult =
        detectionResult!.basic.where((r) => r.id == 'network').firstOrNull;
    if (networkResult == null) return true;
    return networkResult.status == DetectionStatus.installed;
  }

  /// 网络错误建议
  String? get networkSuggestion {
    if (detectionResult == null) return null;
    final networkResult =
        detectionResult!.basic.where((r) => r.id == 'network').firstOrNull;
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
    state = state.copyWith(state: DeployState.checking);

    try {
      await RuntimeManager.instance.initialize();
      final result = await RuntimeManager.instance.detectAll();

      // 检测成功必须显式清空旧 errorMessage：
      // copyWith 的 `??` 语义无法清空（传 null 会保留旧值），
      // 否则「检测成功」后 UI 仍显示上次失败的错误。
      // 直接构造新状态：errorMessage 取默认 null，清空旧错误
      state = DeployStatus(
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
  ///
  /// 安装完成后：
  ///   - 使用 RuntimeManager 内部已刷新过的检测结果（避免重复 detectAll）
  ///   - 任一工具失败 → 进入 error 状态并展示「阶段 + 原因 + 建议」，
  ///     不再把失败静默丢进 installResults 让 UI 黑盒。
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
        errorMessage:
            suggestion != null ? '❌ 网络不可用\n$suggestion' : '❌ 网络不可用\n请检查网络连接后重试',
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

    // 执行安装（等待完整结果流，含安装后的 detectAll 补丁）
    final results = await mgr.installCodingRuntime().toList();

    // 构建安装结果 map
    final resultMap = <RuntimeTool, InstallResult>{};
    for (final r in results) {
      resultMap[r.tool] = r;
    }

    // 失败 → 展示明确的失败信息（阶段 + 原因 + 建议）
    final failed = results.where((r) => !r.success).toList();
    if (failed.isNotEmpty) {
      state = state.copyWith(
        state: DeployState.error,
        detectionResult: mgr.lastDetection,
        installResults: resultMap,
        errorMessage: _buildFailureMessage(failed.first),
        lastChecked: DateTime.now(),
      );
      return;
    }

    state = state.copyWith(
      state: DeployState.completed,
      detectionResult: mgr.lastDetection,
      installResults: resultMap,
      lastChecked: DateTime.now(),
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
        errorMessage:
            suggestion != null ? '❌ 网络不可用\n$suggestion' : '❌ 网络不可用\n请检查网络连接后重试',
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

    final resultMap =
        Map<RuntimeTool, InstallResult>.from(state.installResults);
    resultMap[tool] = result;

    if (!result.success) {
      state = state.copyWith(
        state: DeployState.error,
        detectionResult: mgr.lastDetection,
        installResults: resultMap,
        errorMessage: _buildFailureMessage(result),
        lastChecked: DateTime.now(),
      );
      return;
    }

    // 成功后重新检测（单工具路径不经过 _startInstallCoding 的 detectAll）
    await checkAll();
    state = state.copyWith(installResults: resultMap);
  }

  /// 🔧 一键修复环境
  ///
  /// 统一环境诊断/修复：
  ///   PRoot → /tmp → dpkg interrupted → apt → 重新检测。
  /// 修复失败不会置空已有检测结果，仅进入 error 并展示报告摘要。
  Future<DoctorReport> repairEnvironment() async {
    state = state.copyWith(state: DeployState.repairing);
    try {
      final mgr = RuntimeManager.instance;
      final doctor = EnvironmentDoctor(
        runner: mgr.processRunner,
        linux: mgr.linuxProvider,
      );
      // 统一修复链路（幂等、顺序、安全中断）：
      //   PRoot → /tmp+TMPDIR/TMP/TEMP → dpkg recovery → apt → 工具链验证
      //   （node 已装、npm 缺失时由 doctor 内部补装 npm，不在此重复实现）
      final report = await doctor.runFullRepair();

      // 修复完成后刷新检测结果（Capability Registry 重建）
      await checkAll();
      state = state.copyWith(
        state: report.allPassed ? DeployState.completed : DeployState.error,
        errorMessage: report.allPassed ? null : '环境修复未完全成功:\n${report.summary}',
      );
      return report;
    } catch (e) {
      state = state.copyWith(
        state: DeployState.error,
        errorMessage: '环境修复失败: $e',
      );
      return DoctorReport([
        DoctorCheck(
          name: 'doctor',
          passed: false,
          detail: '异常: $e',
        ),
      ]);
    }
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

  /// 构建部署失败信息（阶段 + 原因 + 建议）
  ///
  /// npm 是随 Node.js 安装的组件（无独立 RuntimeTool）。
  /// npm 单独补装失败（errorMessage 含 npm 且不含 nodejs）时，
  /// 分类为「失败组件：npm / Node.js：已安装」，避免误显示
  /// 「部署失败（Node.js）」把已安装的 Node.js 判为失败。
  String _buildFailureMessage(InstallResult result) {
    const repairGuide =
        '\n\n💡 环境问题？点「🔧 修复环境」自动修复（PRoot / apt 源 / dpkg / 工具链）';
    final toolName =
        RuntimeDependency.forTool(result.tool)?.displayName ?? result.tool.name;
    final phase = result.phase.name;
    final base = result.errorMessage ?? '未知错误';
    final lower = base.toLowerCase();

    // npm-only 补装失败：node 已安装，仅 npm 组件失败
    final isNpmOnlyFailure = result.tool == RuntimeTool.node &&
        lower.contains('npm') &&
        !lower.contains('nodejs');
    if (isNpmOnlyFailure) {
      final buf = StringBuffer('❌ Coding Runtime 部署失败');
      buf.writeln();
      buf.write('失败组件：npm');
      buf.writeln();
      buf.write('Node.js：已安装');
      buf.writeln();
      buf.write('原因：$base');
      buf.write(repairGuide);
      return buf.toString();
    }

    // InstallResult.errorMessage 对 DeployError 已含「❌ 原因 + 💡 建议」
    final buf = StringBuffer('❌ 部署失败（$toolName）');
    buf.writeln();
    buf.write('阶段：$phase');
    buf.writeln();
    buf.write(base);
    buf.write(repairGuide);
    return buf.toString();
  }

  RuntimeDetectionResult _groupResults(List<DetectionResult> results) {
    // 使用 RuntimeDetector 的统一分组逻辑
    final detector = RuntimeDetector();
    return detector.reGroupResults(results);
  }
}
