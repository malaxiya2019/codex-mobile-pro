/// ====================================================================
/// TermuxRuntimeProvider
///
/// 将 Termux 封装为统一的 IRuntimeProvider。
/// 使用 TermuxTransport 完成所有实际检测和执行。
///
/// 职责：
///   1. detect() — 检测 Termux Runtime 状态
///   2. getEnvironment() — 获取 Termux 环境变量（HOME/PATH/PREFIX/TMPDIR/LANG）
///   3. isAvailable() — 简化可用性检查
///   4. healthCheck() — 健康检查
///   5. capabilities — 提供的 Capability 列表
///   6. resolveExecutable() — 解析可执行文件路径
///
/// 通信机制：
///   TermuxRuntimeProvider → TermuxTransport → MethodChannel → TermuxBridge.kt
///
/// Provider 不知道 RUN_COMMAND Intent 细节。
/// ====================================================================
library;

import '../../core/logger/log_service.dart';
import '../termux/termux_transport.dart';
import '../termux/method_channel_transport.dart';
import 'runtime_capability.dart';
import 'runtime_provider.dart';

/// Termux Runtime Provider
class TermuxRuntimeProvider implements IRuntimeProvider {
  final TermuxTransport _transport;
  TermuxDiagnosticResult? _lastDiagnostics;
  TermuxEnvResult? _lastEnvironment;
  ProviderStatus _status = ProviderStatus.unavailable;
  List<RuntimeCapability> _cachedCapabilities = const [];

  TermuxRuntimeProvider({TermuxTransport? transport})
    : _transport = transport ?? MethodChannelTermuxTransport();

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
      final diag = await _transport.diagnose();
      _lastDiagnostics = diag;

      // 2. 获取环境信息
      TermuxEnvResult env;
      if (diag.isAvailable) {
        env = await _transport.getEnvironment();
      } else {
        env = const TermuxEnvResult();
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
        detail: _statusDescription(diag, env),
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
            passed: diag.pkgManager != TermuxPkgManager.unavailable,
            detail: _pkgManagerLabel(diag.pkgManager),
          ),
        ],
      );

      return ProviderInfo(
        type: type,
        status: _status,
        version: diag.version,
        description: _statusDescription(diag, env),
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
    final env = await _transport.getEnvironment();
    final result = <String, String>{};

    // HOME — 优先真实检测，fallback 到 appHome
    result['HOME'] = env.homePath ?? appHome ?? '/data/data/com.termux/files/home';

    // PATH — Termux Prefix bin + 系统路径
    if (env.prefixPath != null) {
      result['PREFIX'] = env.prefixPath!;
      result['PATH'] = '${env.prefixPath}/bin:/system/bin:/system/xbin';
    } else {
      result['PATH'] = '/system/bin:/system/xbin';
    }

    // SHELL
    if (env.shellPath != null) {
      result['SHELL'] = env.shellPath!;
    }

    // TMPDIR
    result['TMPDIR'] = '/data/local/tmp';

    // 本地化
    result['LANG'] = 'en_US.UTF-8';
    result['LC_ALL'] = 'en_US.UTF-8';

    return result;
  }

  @override
  Future<bool> isAvailable() async {
    if (_lastDiagnostics != null) {
      return _lastDiagnostics!.isAvailable;
    }
    final diag = await _transport.diagnose();
    return diag.isAvailable;
  }

  @override
  Future<ProviderHealth> healthCheck() async {
    final start = DateTime.now();
    final diag = _lastDiagnostics ?? await _transport.diagnose();

    return ProviderHealth(
      healthy: diag.isAvailable,
      version: diag.version,
      latencyMs: DateTime.now().difference(start).inMilliseconds,
      detail: _statusDescription(diag, null),
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
          passed: diag.pkgManager != TermuxPkgManager.unavailable,
          detail: _pkgManagerLabel(diag.pkgManager),
        ),
      ],
    );
  }

  @override
  List<RuntimeCapability> get capabilities => _cachedCapabilities;

  // ─── 扩展方法 ────────────────────────────────────────────────

  /// 获取上一次诊断结果
  TermuxDiagnosticResult? get lastDiagnostics => _lastDiagnostics;

  /// 获取上一次环境信息
  TermuxEnvResult? get lastEnvironment => _lastEnvironment;

  /// 解析可执行文件路径
  ///
  /// 在 Termux 环境中查找可执行文件。
  /// 返回绝对路径如 /data/data/com.termux/files/usr/bin/node
  /// 如果未找到返回 null。
  Future<String?> resolveExecutable(String name) async {
    return _transport.which(name);
  }

  /// 安装 Termux 包
  Future<TermuxInstallResult> installPackage(
    String packageName, {
    int timeoutMs = 120000,
  }) => _transport.installPackage(packageName, timeoutMs: timeoutMs);

  /// 更新包列表
  Future<TermuxInstallResult> updatePackageList({int timeoutMs = 60000}) =>
      _transport.updatePackageList(timeoutMs: timeoutMs);

  /// 在 Termux 中执行命令
  Future<TermuxExecResult> executeInTermux(String command) =>
      _transport.execute(command);

  /// 获取底层 Transport
  TermuxTransport get transport => _transport;

  // ─── 内部 ────────────────────────────────────────────────────

  /// 构建 Capability 列表
  List<RuntimeCapability> _buildCapabilities(
    TermuxDiagnosticResult diag,
    TermuxEnvResult env,
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

  String _statusDescription(TermuxDiagnosticResult diag, TermuxEnvResult? env) {
    if (diag.isAvailable) {
      final parts = <String>[];
      if (diag.version != null) parts.add('v${diag.version}');
      parts.add('PM: ${_pkgManagerLabel(diag.pkgManager)}');
      if (env?.prefixPath != null) parts.add(env!.prefixPath!);
      return parts.join(' · ');
    } else if (diag.packageInstalled) {
      return '已安装但不可用: ${diag.lastError}';
    } else {
      return '未安装';
    }
  }

  static String _pkgManagerLabel(TermuxPkgManager status) {
    switch (status) {
      case TermuxPkgManager.pkg: return 'pkg';
      case TermuxPkgManager.apt: return 'apt';
      case TermuxPkgManager.dpkg: return 'dpkg';
      case TermuxPkgManager.unavailable: return '不可用';
    }
  }
}
