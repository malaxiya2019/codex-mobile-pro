/// ====================================================================
/// TermuxRuntimeProvider
///
/// 将 Termux 封装为统一的 IRuntimeProvider。
/// 委托 TermuxRuntimeBridge 完成所有实际检测和执行。
///
/// 职责：
///   1. detect() — 检测 Termux Runtime 状态
///   2. getEnvironment() — 获取 Termux 环境变量
///   3. isAvailable() — 简化可用性检查
///   4. healthCheck() — 健康检查
///   5. capabilities — 提供的 Capability 列表
///
/// 通信机制（不变）：
///   TermuxRuntimeProvider → TermuxRuntimeBridge → MethodChannel
///   → TermuxBridge.kt → Termux RUN_COMMAND Intent
///
/// 不删除现有 termux_service.dart / termux_runtime_bridge.dart。
/// 旧引用保持工作（shell_detector, environment_service, termux_detector），
/// 新代码走 Provider。
/// ====================================================================
library;

import '../../core/logger/log_service.dart';
import '../../core/termux/termux_runtime_bridge.dart';
import 'runtime_capability.dart';
import 'runtime_provider.dart';

/// Termux Runtime Provider
class TermuxRuntimeProvider implements IRuntimeProvider {
  final TermuxRuntimeBridge _bridge;
  TermuxDiagnostics? _lastDiagnostics;
  TermuxEnvironment? _lastEnvironment;
  ProviderStatus _status = ProviderStatus.unavailable;
  List<RuntimeCapability> _cachedCapabilities = const [];

  TermuxRuntimeProvider({TermuxRuntimeBridge? bridge})
    : _bridge = bridge ?? TermuxRuntimeBridge.instance;

  // ─── IRuntimeProvider ────────────────────────────────────────

  @override
  String get id => 'termux';

  @override
  String get name => 'Termux Runtime';

  @override
  ProviderType get type => ProviderType.termux;

  @override
  ProviderStatus get status => _status;

  @override
  Future<ProviderInfo> detect() async {
    final start = DateTime.now();

    try {
      // 1. 完整诊断
      final diag = await _bridge.diagnose();
      _lastDiagnostics = diag;

      // 2. 获取环境信息
      TermuxEnvironment env;
      if (diag.isAvailable) {
        env = await _bridge.getEnvironment();
      } else {
        env = const TermuxEnvironment();
      }
      _lastEnvironment = env;

      // 3. 确定状态
      if (diag.isAvailable) {
        _status = ProviderStatus.available;
      } else if (diag.packageInstalled) {
        _status = ProviderStatus.degraded;
      } else {
        _status = ProviderStatus.unavailable;
      }

      // 4. 构建 Capability 列表
      _cachedCapabilities = _buildCapabilities(diag, env);

      // 5. 构建健康检查
      final health = ProviderHealth(
        healthy: diag.isAvailable,
        version: diag.version,
        latencyMs: DateTime.now().difference(start).inMilliseconds,
        detail: diag.statusDescription,
        checks: [
          DiagnosticCheck(
            name: 'Termux APK',
            passed: diag.packageInstalled,
            detail: diag.packageInstalled ? '已安装' : '未安装',
          ),
          DiagnosticCheck(
            name: 'RUN_COMMAND Intent',
            passed: diag.intentAvailable,
            detail: diag.intentAvailable ? '可用' : '不可用',
          ),
          DiagnosticCheck(
            name: '命令执行',
            passed: diag.works,
            detail: diag.works ? '正常' : diag.lastError,
          ),
          DiagnosticCheck(
            name: '包管理器',
            passed: diag.pkgManager != TermuxPackageManagerStatus.unavailable,
            detail: _pkgManagerLabel(diag.pkgManager),
          ),
        ],
      );

      // 6. 状态描述
      String description;
      if (diag.isAvailable) {
        final parts = <String>[];
        if (diag.version != null) parts.add('v${diag.version}');
        parts.add('PM: ${_pkgManagerLabel(diag.pkgManager)}');
        if (env.prefixPath != null) parts.add(env.prefixPath!);
        description = parts.join(' · ');
      } else if (diag.packageInstalled) {
        description = '已安装但不可用: ${diag.lastError}';
      } else {
        description = '未安装';
      }

      return ProviderInfo(
        type: type,
        status: _status,
        version: diag.version,
        description: description,
        capabilities: _cachedCapabilities,
        health: health,
        detectionDurationMs: DateTime.now().difference(start).inMilliseconds,
      );
    } catch (e) {
      LogService.error('TermuxProvider', '检测失败: $e');
      _status = ProviderStatus.error;

      return ProviderInfo(
        type: type,
        status: ProviderStatus.error,
        description: '检测异常: $e',
        detectionDurationMs: DateTime.now().difference(start).inMilliseconds,
      );
    }
  }

  @override
  Future<Map<String, String>> getEnvironment({String? appHome}) async {
    final env = await _bridge.getEnvironment();
    final result = <String, String>{};

    if (env.prefixPath != null) {
      result['PREFIX'] = env.prefixPath!;
    }
    if (env.homePath != null) {
      result['HOME'] = env.homePath!;
    }
    if (env.shellPath != null) {
      result['SHELL'] = env.shellPath!;
    }

    // Termux 标准 PATH
    if (env.prefixPath != null) {
      result['PATH'] = '${env.prefixPath}/bin:/system/bin:/system/xbin';
    }

    // Termux 数据目录
    result['TERMUX_APP__DATA_DIR'] =
        '/data/data/com.termux/files/home';

    return result;
  }

  @override
  Future<bool> isAvailable() async {
    // 使用缓存诊断结果（如果有）
    if (_lastDiagnostics != null) {
      return _lastDiagnostics!.isAvailable;
    }
    return await _bridge.isAvailable();
  }

  @override
  Future<ProviderHealth> healthCheck() async {
    final start = DateTime.now();
    final diag = _lastDiagnostics ?? await _bridge.diagnose();

    return ProviderHealth(
      healthy: diag.isAvailable,
      version: diag.version,
      latencyMs: DateTime.now().difference(start).inMilliseconds,
      detail: diag.statusDescription,
      checks: [
        DiagnosticCheck(
          name: 'Termux APK',
          passed: diag.packageInstalled,
          detail: diag.packageInstalled ? '已安装' : '未安装',
        ),
        DiagnosticCheck(
          name: 'RUN_COMMAND Intent',
          passed: diag.intentAvailable,
          detail: diag.intentAvailable ? '可用' : '不可用',
        ),
        DiagnosticCheck(
          name: '命令执行',
          passed: diag.works,
          detail: diag.works ? '正常' : diag.lastError,
        ),
        DiagnosticCheck(
          name: '包管理器',
          passed: diag.pkgManager != TermuxPackageManagerStatus.unavailable,
          detail: _pkgManagerLabel(diag.pkgManager),
        ),
      ],
    );
  }

  @override
  List<RuntimeCapability> get capabilities => _cachedCapabilities;

  // ─── 扩展方法 ────────────────────────────────────────────────

  /// 获取上一次诊断结果
  TermuxDiagnostics? get lastDiagnostics => _lastDiagnostics;

  /// 获取上一次环境信息
  TermuxEnvironment? get lastEnvironment => _lastEnvironment;

  /// 在 Termux 中执行命令
  ///
  /// 委托 TermuxRuntimeBridge.executeInTermux()。
  Future<TermuxCommandResult> executeInTermux(String command) =>
      _bridge.executeInTermux(command);

  /// 安装 Termux 包
  Future<TermuxCommandResult> installPackage(
    String packageName, {
    int timeoutMs = 120000,
  }) => _bridge.installPackage(packageName, timeoutMs: timeoutMs);

  /// 更新包列表
  Future<TermuxCommandResult> updatePackageList({int timeoutMs = 60000}) =>
      _bridge.updatePackageList(timeoutMs: timeoutMs);

  /// 查找 Termux 中的二进制文件
  Future<String?> which(String binaryName) => _bridge.which(binaryName);

  /// 获取 Termux 诊断信息
  Future<TermuxDiagnostics> diagnose() => _bridge.diagnose();

  /// 获取 Termux 环境信息
  Future<TermuxEnvironment> getTermuxEnvironment() =>
      _bridge.getEnvironment();

  // ─── 内部 ────────────────────────────────────────────────────

  /// 构建 Capability 列表
  List<RuntimeCapability> _buildCapabilities(
    TermuxDiagnostics diag,
    TermuxEnvironment env,
  ) {
    final result = <RuntimeCapability>[];

    // Termux Runtime 本身
    result.add(RuntimeCapability(
      type: CapabilityType.termux,
      provider: type,
      available: diag.isAvailable,
      version: diag.version,
      path: env.prefixPath,
      health:
          diag.isAvailable
              ? CapabilityHealth.healthy
              : diag.packageInstalled
              ? CapabilityHealth.degraded
              : CapabilityHealth.unavailable,
      reason:
          diag.isAvailable
              ? null
              : diag.packageInstalled
              ? diag.lastError.isNotEmpty
                  ? diag.lastError
                  : 'RUN_COMMAND Intent 不可用'
              : 'Termux 未安装',
    ));

    return result;
  }

  /// 包管理器标签
  static String _pkgManagerLabel(TermuxPackageManagerStatus status) {
    switch (status) {
      case TermuxPackageManagerStatus.pkg:
        return 'pkg';
      case TermuxPackageManagerStatus.apt:
        return 'apt';
      case TermuxPackageManagerStatus.dpkg:
        return 'dpkg';
      case TermuxPackageManagerStatus.unavailable:
        return '不可用';
    }
  }
}
