/// ====================================================================
/// Runtime Provider 接口
///
/// 定义所有 Runtime Provider 的统一接口。
/// 参考 Phase 1 Audit Report 的调用链设计。
///
/// 当前 Provider：
///   AppRuntimeProvider     — 应用自身能力（fallback）
///   AndroidRuntimeProvider — Android 系统内置能力（/system/bin/sh 回退）
///   LinuxRuntimeProvider   — App 内置 Linux Runtime（PRoot + Ubuntu rootfs）
///
/// Node/Python/Git/Codex 工具链安装属于后续阶段。
/// ====================================================================
library;

import 'runtime_capability.dart';

/// Provider 状态
enum ProviderStatus {
  /// 不可用（未安装、未检测到）
  unavailable,

  /// 可用
  available,

  /// 降级可用（部分功能受限）
  degraded,

  /// 错误状态
  error,

  /// 实验性（可能不稳定）
  experimental,
}

/// Provider 健康检查结果
class ProviderHealth {
  final bool healthy;
  final String? version;
  final int latencyMs;
  final String? detail;
  final List<DiagnosticCheck> checks;

  const ProviderHealth({
    required this.healthy,
    this.version,
    this.latencyMs = 0,
    this.detail,
    this.checks = const [],
  });
}

/// 单项诊断检查
class DiagnosticCheck {
  final String name;
  final bool passed;
  final String? detail;

  const DiagnosticCheck({
    required this.name,
    required this.passed,
    this.detail,
  });
}

/// Provider 信息（detect() 的返回类型）
class ProviderInfo {
  final ProviderType type;
  final ProviderStatus status;
  final String? version;
  final String? description;
  final List<RuntimeCapability> capabilities;
  final ProviderHealth? health;
  final int detectionDurationMs;

  const ProviderInfo({
    required this.type,
    required this.status,
    this.version,
    this.description,
    this.capabilities = const [],
    this.health,
    this.detectionDurationMs = 0,
  });
}

/// ====================================================================
/// IRuntimeProvider
///
/// 所有 Runtime Provider 必须实现此接口。
///
/// 职责：
///   1. 检测自身是否可用
///   2. 提供环境变量
///   3. 提供 Capability 列表
///   4. 健康检查
/// ====================================================================
abstract class IRuntimeProvider {
  /// Provider 标识（如 "app", "android", "linux"）
  String get id;

  /// 显示名称（如 "Android 基础环境", "Linux Runtime"）
  String get name;

  /// Provider 类型
  ProviderType get type;

  /// 当前状态
  ProviderStatus get status;

  /// 检测 Provider 状态
  ///
  /// 返回完整的 Provider 信息，包括能力和健康状态。
  Future<ProviderInfo> detect();

  /// 获取环境变量
  ///
  /// 返回在此 Provider 环境中执行命令需要的环境变量。
  /// [appHome] — App 私有目录路径，用于设置 HOME 等变量。
  Future<Map<String, String>> getEnvironment({String? appHome});

  /// 是否可用
  Future<bool> isAvailable();

  /// 健康检查
  Future<ProviderHealth> healthCheck();

  /// 提供的 Capability 列表
  List<RuntimeCapability> get capabilities;
}

/// ====================================================================
/// IRuntimeInstaller
///
/// 统一安装接口。
/// 合并现有 EnvironmentManager 和 RuntimeInstaller 的安装职责。
///
/// 职责：
///   1. 安装 Capability
///   2. 卸载 Capability
///   3. 验证安装
///   4. 获取安装状态
/// ====================================================================
abstract class IRuntimeInstaller {
  /// 安装指定的 Capability
  Future<InstallResult> install(CapabilityType capability);

  /// 卸载指定的 Capability
  Future<bool> uninstall(CapabilityType capability);

  /// 验证安装
  Future<VerificationResult> verify(CapabilityType capability);

  /// 获取安装状态
  Future<InstallState> getInstallState(CapabilityType capability);
}

/// 安装状态
class InstallState {
  final CapabilityType capability;
  final bool installed;
  final String? version;
  final String? error;

  const InstallState({
    required this.capability,
    required this.installed,
    this.version,
    this.error,
  });
}

/// 验证结果
class VerificationResult {
  final CapabilityType capability;
  final bool success;
  final String? output;
  final String? error;

  const VerificationResult({
    required this.capability,
    required this.success,
    this.output,
    this.error,
  });
}

/// 安装结果（与现有 InstallResult 匹配）
class InstallResult {
  final CapabilityType capability;
  final bool success;
  final String? version;
  final String? errorMessage;

  const InstallResult({
    required this.capability,
    required this.success,
    this.version,
    this.errorMessage,
  });
}
