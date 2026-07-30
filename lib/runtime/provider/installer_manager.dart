/// ====================================================================
/// Installer Manager
///
/// 统一安装管理入口。
/// 合并 RuntimeInstaller（.deb 下载解压）和 EnvironmentManager（pkg install）
/// 的安装能力，提供统一的 IRuntimeInstaller 实现。
///
/// 设计原则：
///   - RuntimeInstaller 作为主要安装器（优先使用 .deb 提取）
///   - EnvironmentManager 提供开发者环境检测（Flutter/Rust/Python 详情）
///    和 pkg install 降级方案
///   - 不删除现有实现，通过委托模式逐步迁移
/// ====================================================================
library;

import '../../features/deploy/services/environment_manager.dart' as em;
import '../../runtime/deploy_error.dart';
import '../../runtime/runtime_dependency.dart';
import '../../runtime/runtime_environment.dart';
import '../../runtime/runtime_installer.dart' as ri;
import 'runtime_capability.dart';
import 'runtime_provider.dart';

/// Installer Manager — 统一安装入口
class InstallerManager implements IRuntimeInstaller {
  static InstallerManager? _instance;

  final RuntimeEnvironment _env;
  final ri.RuntimeInstaller _primaryInstaller;
  bool _initialized = false;

  InstallerManager._(this._env, this._primaryInstaller);

  static InstallerManager get instance {
    if (_instance == null) {
      throw StateError('InstallerManager 未初始化，请先调用 initialize()');
    }
    return _instance!;
  }

  static Future<InstallerManager> initialize() async {
    if (_instance != null && _instance!._initialized) return _instance!;

    final env = await RuntimeEnvironment.getInstance();
    final primaryInstaller = ri.RuntimeInstaller(env);

    _instance = InstallerManager._(env, primaryInstaller);
    _instance!._initialized = true;
    return _instance!;
  }

  /// 重置单例（测试用）
  static void reset() {
    _instance = null;
  }

  // ─── IRuntimeInstaller ───────────────────────────────────────

  @override
  Future<InstallResult> install(CapabilityType capability) async {
    final tool = _capabilityToTool(capability);
    if (tool == null) {
      return InstallResult(
        capability: capability,
        success: false,
        errorMessage: '不支持安装此 Capability: $capability',
      );
    }

    try {
      // 优先使用 RuntimeInstaller（.deb 下载解压）
      final result = await _primaryInstaller.install(tool);
      return _convertResult(capability, result);
    } on DeployError catch (e) {
      // RuntimeInstaller 失败 → 尝试 EnvironmentManager（pkg install）
      return _tryEnvironmentManagerInstall(capability, tool, e);
    } catch (e) {
      return InstallResult(
        capability: capability,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<bool> uninstall(CapabilityType capability) async {
    // 当前不支持卸载，返回 false
    return false;
  }

  @override
  Future<VerificationResult> verify(CapabilityType capability) async {
    final tool = _capabilityToTool(capability);
    if (tool == null) {
      return VerificationResult(
        capability: capability,
        success: false,
        error: '不支持验证此 Capability: $capability',
      );
    }

    final installed = await _env.isToolInstalled(tool);
    return VerificationResult(
      capability: capability,
      success: installed,
      output: installed ? '✅ 已安装' : '❌ 未安装',
    );
  }

  @override
  Future<InstallState> getInstallState(CapabilityType capability) async {
    final tool = _capabilityToTool(capability);
    if (tool == null) {
      return InstallState(
        capability: capability,
        installed: false,
        error: '不支持此 Capability: $capability',
      );
    }

    final installed = await _env.isToolInstalled(tool);
    return InstallState(
      capability: capability,
      installed: installed,
      version: installed ? '已安装' : null,
    );
  }

  // ─── 环境管理特有功能（委托给 EnvironmentManager） ──────────

  /// 获取 Flutter 环境详情
  Future<em.FlutterEnvironment?> getFlutterDetail() =>
      em.EnvironmentManager.getFlutterDetail();

  /// 获取 Rust 环境详情
  Future<em.RustEnvironment?> getRustDetail() =>
      em.EnvironmentManager.getRustDetail();

  /// 获取 Python 环境详情
  Future<em.PythonEnvironment?> getPythonDetail() =>
      em.EnvironmentManager.getPythonDetail();

  /// 获取环境摘要
  Future<Map<String, String>> getEnvironmentSummary() =>
      em.EnvironmentManager.getEnvironmentSummary();

  // ─── 内部 ────────────────────────────────────────────────────

  RuntimeTool? _capabilityToTool(CapabilityType capability) {
    switch (capability) {
      case CapabilityType.node: return RuntimeTool.node;
      case CapabilityType.git: return RuntimeTool.git;
      case CapabilityType.python: return RuntimeTool.python;
      case CapabilityType.codexCli: return RuntimeTool.codexCli;
      case CapabilityType.mimo2codex: return RuntimeTool.mimo2codex;
      case CapabilityType.flutter: return RuntimeTool.flutterSdk;
      case CapabilityType.ubuntu: return RuntimeTool.ubuntu;
      default: return null;
    }
  }

  InstallResult _convertResult(
    CapabilityType capability,
    ri.InstallResult result,
  ) {
    return InstallResult(
      capability: capability,
      success: result.success,
      version: result.version,
      errorMessage: result.errorMessage,
    );
  }

  Future<InstallResult> _tryEnvironmentManagerInstall(
    CapabilityType capability,
    RuntimeTool tool,
    DeployError originalError,
  ) async {
    // EnvironmentManager 只支持 string 工具名
    String? toolName;
    switch (tool) {
      case RuntimeTool.node: toolName = 'node';
      case RuntimeTool.git: toolName = 'git';
      case RuntimeTool.python: toolName = 'python';
      default: toolName = null;
    }

    if (toolName == null) {
      return InstallResult(
        capability: capability,
        success: false,
        errorMessage: originalError.message,
      );
    }

    try {
      final result = await em.EnvironmentManager.install(toolName);
      return InstallResult(
        capability: capability,
        success: result.success,
        version: result.version,
        errorMessage: result.errorMessage,
      );
    } catch (e) {
      return InstallResult(
        capability: capability,
        success: false,
        errorMessage:
            '${originalError.message}; 降级安装也失败: $e',
      );
    }
  }
}
