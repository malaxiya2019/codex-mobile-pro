import 'dart:async';
import '../core/logger/log_service.dart';
import 'runtime_dependency.dart';
import 'runtime_detector.dart';
import 'runtime_environment.dart';
import 'runtime_installer.dart';

/// ====================================================================
/// Runtime 管理器
///
/// 统一的入口，协调检测、安装、环境管理。
///
/// 数据流：
///   Detector → Dependency Graph → Installer → Environment → Terminal
/// ====================================================================

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
    _state = RuntimeManagerState.ready;
    LogService.info('RuntimeMgr', 'Runtime Manager 就绪');
  }

  /// 检测所有 Runtime
  Future<RuntimeDetectionResult> detectAll() async {
    if (_detector == null) {
      await initialize();
    }

    _state = RuntimeManagerState.detecting;
    _lastDetection = await _detector!.detectAll();
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

    try {
      final order = RuntimeDependency.installOrder();
      LogService.info('RuntimeMgr', '一键部署顺序: ${order.map((t) => t.name).join(" → ")}');

      for (final tool in order) {
        final dep = RuntimeDependency.forTool(tool);
        if (dep == null || dep.category != RuntimeCategory.coding) continue;

        // 跳过已安装的
        if (_environment!.isToolInstalled(tool)) {
          controller.add(InstallResult(
            tool: tool,
            success: true,
            version: '已安装',
          ));
          continue;
        }

        // 安装
        final result = await _installer!.install(tool);
        controller.add(result);

        if (!result.success) {
          LogService.error('RuntimeMgr', '部署中止: ${tool.name} 安装失败');
          break;
        }
      }
    } catch (e) {
      LogService.error('RuntimeMgr', '一键部署失败: $e');
      controller.addError(e);
    } finally {
      _state = RuntimeManagerState.ready;
      // 安装完成后重新检测
      await detectAll();
    }
  }

  /// 安装单个工具
  Future<InstallResult> install(RuntimeTool tool) async {
    _state = RuntimeManagerState.installing;

    try {
      final result = await _installer!.install(tool);
      return result;
    } finally {
      _state = RuntimeManagerState.ready;
    }
  }

  /// 验证 Coding 环境
  Future<List<VerificationResult>> verifyEnvironment() async {
    _state = RuntimeManagerState.verifying;

    try {
      final results = await _detector!.verifyCodingEnvironment();
      return results;
    } finally {
      _state = RuntimeManagerState.ready;
    }
  }

  /// 获取终端环境变量
  ///
  /// 供 TerminalService 调用。
  Map<String, String> getTerminalEnvironment() {
    if (_environment == null) {
      return {};
    }
    return _environment!.buildTerminalEnvironment();
  }

  /// 检查工具是否已安装
  bool isInstalled(RuntimeTool tool) {
    return _environment?.isToolInstalled(tool) ?? false;
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
