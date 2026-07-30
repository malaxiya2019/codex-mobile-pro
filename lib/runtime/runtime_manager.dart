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
///
/// Provider Orchestration（Phase 2 新增）：
///   1. registerProvider(IRuntimeProvider)
///   2. discoverProviders() → `List<ProviderInfo>`
///   3. getCapability(CapabilityType) → RuntimeCapability?
///   4. getProvidersForCapability(CapabilityType) → `List<IRuntimeProvider>`
///   5. resolveFallbackProvider(CapabilityType) → IRuntimeProvider?
///   6. status → ProviderStatus 聚合
///
/// 所有现有功能保持兼容。
/// ====================================================================
library;

import 'dart:async';

import '../core/detector/detection_result.dart';
import '../core/logger/log_service.dart';
import 'download_queue.dart';
import 'provider/android_runtime_provider.dart';
// Phase 2: Provider 导入
import 'provider/runtime_capability.dart';
import 'provider/runtime_provider.dart' hide InstallResult, VerificationResult;
import 'provider/termux_provider.dart';
import 'provider/ubuntu_runtime_provider.dart';
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
  DownloadQueueScheduler? _queue;
  RuntimeDetectionResult? _lastDetection;

  // ─── Phase 2: Provider Orchestration ─────────────────────────

  /// 已注册的 Provider
  final List<IRuntimeProvider> _providers = [];

  /// Provider 信息缓存（由 discoverProviders() 更新）
  List<ProviderInfo>? _cachedProviderInfos;

  // ─── 安装进度流 ──────────────────────────────────────────────

  final StreamController<InstallProgress> _progressController =
      StreamController<InstallProgress>.broadcast();
  Stream<InstallProgress> get progressStream => _progressController.stream;

  /// 状态
  RuntimeManagerState get state => _state;

  /// 最近检测结果
  RuntimeDetectionResult? get lastDetection => _lastDetection;

  /// 环境
  RuntimeEnvironment? get environment => _environment;

  RuntimeManager._() {
    // Phase 2: 注册默认 Provider（按优先级排序）
    _providers.addAll([
      AndroidRuntimeProvider(),
      TermuxRuntimeProvider(),
      UbuntuRuntimeProvider(),
    ]);
  }

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
    
    // 初始化下载队列
    _queue = DownloadQueueScheduler.instance;
    final backlogDir = '${_environment!.runtimeDir}/.queue_backlog';
    await _queue!.initialize(backlogDir: backlogDir);
    final recovered = await _queue!.recoverBacklog();
    if (recovered > 0) {
      LogService.info('RuntimeMgr', '恢复 $recovered 个未完成的下载任务');
    }
    
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

  /// 下载队列
  DownloadQueueScheduler get downloadQueue => _queue!;
  
  /// 下载队列事件流
  Stream<DownloadProgressEvent> get downloadQueueStream {
    final controller = StreamController<DownloadProgressEvent>.broadcast();
    _queue?.addListener((event) => controller.add(event));
    return controller.stream;
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

  // ═══════════════════════════════════════════════════════════════
  // Phase 2: Provider Orchestration API
  // ═══════════════════════════════════════════════════════════════

  /// 注册 Provider
  ///
  /// 按优先级排序：
  ///   android → termux → ubuntu
  void registerProvider(IRuntimeProvider provider) {
    // 如果同 id 已存在，替换
    final existingIndex = _providers.indexWhere((p) => p.id == provider.id);
    if (existingIndex >= 0) {
      _providers[existingIndex] = provider;
    } else {
      _providers.add(provider);
    }
    // 重置缓存
    _cachedProviderInfos = null;
  }

  /// 发现所有 Provider
  ///
  /// 对每个 Provider 调用 detect()，返回完整的 Provider 信息列表。
  Future<List<ProviderInfo>> discoverProviders() async {
    final results = <ProviderInfo>[];

    for (final provider in _providers) {
      try {
        final info = await provider.detect();
        results.add(info);
      } catch (e) {
        LogService.error('RuntimeMgr', 'Provider ${provider.id} 检测失败: $e');
        results.add(ProviderInfo(
          type: provider.type,
          status: ProviderStatus.error,
          description: '检测异常: $e',
        ));
      }
    }

    _cachedProviderInfos = results;
    return results;
  }

  /// 获取指定类型的 Capability
  ///
  /// 按 Provider 优先级查找：
  ///   1. android
  ///   2. termux
  ///   3. ubuntu（experimental）
  /// 返回第一个可用的 Capability。
  Future<RuntimeCapability?> getCapability(CapabilityType type) async {
    // 先尝试缓存
    final providersWithCap = getProvidersForCapability(type);
    if (providersWithCap.isEmpty) return null;

    // 查找可用（healthy 或 degraded）
    for (final provider in providersWithCap) {
      final caps = provider.capabilities.where((c) => c.type == type);
      for (final cap in caps) {
        if (cap.available) return cap;
      }
    }

    // 没有可用 → 返回第一个不可用的（附带原因）
    for (final provider in providersWithCap) {
      final caps = provider.capabilities.where((c) => c.type == type);
      if (caps.isNotEmpty) return caps.first;
    }

    return null;
  }

  /// 获取能提供指定 Capability 的 Provider 列表
  ///
  /// 按优先级排序：android → termux → ubuntu
  List<IRuntimeProvider> getProvidersForCapability(CapabilityType type) {
    return _providers.where((p) {
      return p.capabilities.any((c) => c.type == type);
    }).toList();
  }

  /// 解析 fallback Provider
  ///
  /// 查找能提供指定 Capability 的最高优先级可用 Provider。
  Future<IRuntimeProvider?> resolveFallbackProvider(
    CapabilityType type,
  ) async {
    for (final provider in _providers) {
      final caps = provider.capabilities.where(
        (c) => c.type == type && c.available,
      );
      if (caps.isNotEmpty) {
        return provider;
      }
    }

    // 缓存中没有 → 重新 detect
    for (final provider in _providers) {
      try {
        final info = await provider.detect();
        final hasCap = info.capabilities.any(
          (c) => c.type == type && c.available,
        );
        if (hasCap) return provider;
      } catch (_) {}
    }

    return null;
  }

  /// 获取已注册的 Provider 列表
  List<IRuntimeProvider> get registeredProviders =>
      List.unmodifiable(_providers);

  /// 获取 Provider 信息缓存
  List<ProviderInfo>? get cachedProviderInfos => _cachedProviderInfos;
}
