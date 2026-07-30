/// ====================================================================
/// Runtime 管理器
///
/// 统一的入口，协调检测、安装、环境管理。
///
/// 数据流：
///   Detector → Dependency Graph → Installer → Environment → Terminal
///
/// 当前支持两种 Runtime：
///   1. 系统默认 Runtime（/system/bin/sh）— 现有
///   2. Ubuntu Runtime（rootfs + proot）— 新增，推荐
/// ====================================================================

import 'dart:async';

import '../core/logger/log_service.dart';
import '../core/detector/detection_result.dart';
import 'runtime_dependency.dart';
import 'runtime_detector.dart';
import 'runtime_environment.dart';
import 'runtime_installer.dart';
import 'runtime_manifest.dart';
import 'ubuntu_runtime_installer.dart';

/// 管理器状态
enum RuntimeManagerState {
  uninitialized,
  ready,
  detecting,
  installing,
  verifying,
  error,
}

/// 安装进度信息
class InstallProgress {
  final RuntimeTool tool;
  final InstallPhase phase;
  final double progress;
  final String message;

  const InstallProgress({
    required this.tool,
    required this.phase,
    required this.progress,
    required this.message,
  });
}

/// Runtime 管理器
class RuntimeManager {
  static RuntimeManager? _instance;

  RuntimeManagerState _state = RuntimeManagerState.uninitialized;
  RuntimeEnvironment? _environment;
  RuntimeDetector? _detector;
  RuntimeInstaller? _installer;
  UbuntuRuntimeInstaller? _ubuntuInstaller;
  RuntimeDetectionResult? _lastDetection;

  /// 安装进度流
  final StreamController<InstallProgress> _progressController =
      StreamController<InstallProgress>.broadcast();
  Stream<InstallProgress> get progressStream => _progressController.stream;

  /// 状态
  RuntimeManagerState get state => _state;

  /// 最近检测结果
  RuntimeDetectionResult? get lastDetection => _lastDetection;

  /// 环境
  RuntimeEnvironment? get environment => _environment;

  RuntimeManager._();

  static RuntimeManager get instance {
    _instance ??= RuntimeManager._();
    return _instance!;
  }

  /// 初始化
  Future<void> initialize() async {
    LogService.info('RuntimeMgr', '初始化 Runtime Manager...');
    _environment = await RuntimeEnvironment.getInstance();
    await _environment!.ensureDirectories();
    _detector = RuntimeDetector();
    _installer = RuntimeInstaller(_environment!, _onInstallProgress);
    _ubuntuInstaller = UbuntuRuntimeInstaller(_environment!, _onInstallProgress);
    _state = RuntimeManagerState.ready;
    LogService.info('RuntimeMgr', 'Runtime Manager 就绪');
  }

  /// 检测所有 Runtime
  Future<RuntimeDetectionResult> detectAll() async {
    if (_detector == null) {
      await initialize();
    }

    _state = RuntimeManagerState.detecting;
    _lastDetection = await _detector!.detectAll(environment: _environment);
    _state = RuntimeManagerState.ready;

    LogService.info('RuntimeMgr', '检测完成: ${_lastDetection!.summary}');
    return _lastDetection!;
  }

  /// 一键安装 Coding Runtime
  ///
  /// 按依赖顺序安装所有缺失的 Coding Runtime 工具。
  /// 返回安装结果流。
  Stream<InstallResult> installCodingRuntime() {
    final controller = StreamController<InstallResult>.broadcast();

    _startInstallCoding(controller);

    return controller.stream;
  }

  Future<void> _startInstallCoding(
      StreamController<InstallResult> controller) async {
    _state = RuntimeManagerState.installing;

    final failedTools = <RuntimeTool>{};
    final unsupportedTools = <RuntimeTool>{};
    final blockedTools = <RuntimeTool>{};

    try {
      final order = RuntimeDependency.installOrder();
      LogService.info('RuntimeMgr', '一键部署顺序: ${order.map((t) => t.name).join(" → ")}');

      for (final tool in order) {
        final dep = RuntimeDependency.forTool(tool);
        if (dep == null || dep.category != RuntimeCategory.coding) continue;

        // 跳过已安装的
        if (await _environment!.isToolInstalled(tool)) {
          controller.add(InstallResult(
            tool: tool,
            success: true,
            version: '已安装',
          ));
          continue;
        }

        // 检查依赖是否已在本次安装中失败
        bool depBlocked = false;
        for (final d in dep.dependencies) {
          if (failedTools.contains(d)) {
            blockedTools.add(tool);
            controller.add(InstallResult(
              tool: tool,
              success: false,
              errorMessage: '⛔ 依赖 ${d.name} 安装失败，跳过',
              phase: InstallPhase.blocked,
            ));
            depBlocked = true;
            break;
          }
          if (unsupportedTools.contains(d)) {
            blockedTools.add(tool);
            controller.add(InstallResult(
              tool: tool,
              success: false,
              errorMessage: '⏭ 依赖 ${d.name} 暂不支持安装，跳过',
              phase: InstallPhase.blocked,
            ));
            depBlocked = true;
            break;
          }
        }
        if (depBlocked) continue;

        // 检查是否支持安装
        if (!RuntimeManifest.isSupported(tool) && tool != RuntimeTool.ubuntu) {
          unsupportedTools.add(tool);
          controller.add(InstallResult(
            tool: tool,
            success: false,
            errorMessage: '暂不支持自动安装',
            phase: InstallPhase.failed,
          ));
          continue;
        }

        // 执行安装 —— Ubuntu Runtime 使用专用安装器
        InstallResult result;
        if (tool == RuntimeTool.ubuntu) {
          result = await _ubuntuInstaller!.install();
        } else {
          result = await _installer!.install(tool);
        }

        if (!result.success) {
          failedTools.add(tool);
        }
        controller.add(result);
      }
    } catch (e) {
      LogService.error('RuntimeMgr', '一键部署失败: $e');
      controller.add(InstallResult(
        tool: RuntimeTool.node,
        success: false,
        errorMessage: '部署失败: $e',
        phase: InstallPhase.failed,
      ));
    } finally {
      _state = RuntimeManagerState.ready;
      // 安装完成后重新检测
      await detectAll();

      // 将 blocked 状态补丁到检测结果中
      if (blockedTools.isNotEmpty && _lastDetection != null) {
        _patchBlockedDetection(blockedTools, _lastDetection!);
      }
    }
  }

  /// 将 blocked 状态覆盖到检测结果中
  void _patchBlockedDetection(
    Set<RuntimeTool> blockedTools,
    RuntimeDetectionResult detection,
  ) {
    String toolToDetectorId(RuntimeTool t) {
      switch (t) {
        case RuntimeTool.codexCli: return 'codex';
        case RuntimeTool.mimo2codex: return 'mimo2codex';
        default: return t.name;
      }
    }

    final patched = detection.all.map((r) {
      final tool = RuntimeTool.values.where(
        (t) => toolToDetectorId(t) == r.id,
      );
      if (tool.isNotEmpty && blockedTools.contains(tool.first)) {
        return r.copyWith(status: DetectionStatus.blocked);
      }
      return r;
    }).toList();

    _lastDetection = _detector!.reGroupResults(patched);
  }

  /// 安装单个工具
  Future<InstallResult> install(RuntimeTool tool) async {
    _state = RuntimeManagerState.installing;

    try {
      InstallResult result;
      if (tool == RuntimeTool.ubuntu) {
        result = await _ubuntuInstaller!.install();
      } else {
        result = await _installer!.install(tool);
      }
      return result;
    } finally {
      _state = RuntimeManagerState.ready;
    }
  }

  /// 验证 Coding 环境
  Future<List<VerificationResult>> verifyEnvironment() async {
    _state = RuntimeManagerState.verifying;

    try {
      final results = await _detector!.verifyCodingEnvironment(
        environment: _environment,
      );
      return results;
    } finally {
      _state = RuntimeManagerState.ready;
    }
  }

  /// 获取终端环境变量
  ///
  /// 供 TerminalService 调用。
  /// 如果 Ubuntu Runtime 已安装，返回 proot 环境；
  /// 否则返回系统默认环境。
  Map<String, String> getTerminalEnvironment() {
    if (_environment == null) {
      return {};
    }
    return _environment!.buildTerminalEnvironment();
  }

  /// 检查工具是否已安装
  Future<bool> isInstalled(RuntimeTool tool) async {
    return await _environment?.isToolInstalled(tool) ?? false;
  }

  /// 获取当前 Runtime 类型
  RuntimeType getRuntimeType() {
    return _environment?.getRuntimeType() ?? RuntimeType.system;
  }

  /// 检查 Ubuntu Runtime 是否已就绪
  bool get isUbuntuReady {
    return _environment != null && _environment!.isUbuntuInstalled();
  }

  /// 安装进度回调
  void _onInstallProgress(
      RuntimeTool tool, InstallPhase phase, double progress, String message) {
    _progressController.add(InstallProgress(
      tool: tool,
      phase: phase,
      progress: progress,
      message: message,
    ));
  }

  /// 清理
  void dispose() {
    _progressController.close();
    _instance = null;
  }
}
