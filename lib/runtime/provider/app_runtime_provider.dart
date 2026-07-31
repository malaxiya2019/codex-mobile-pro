/// ====================================================================
/// AppRuntimeProvider
///
/// 应用自身可提供的 Runtime 能力。
/// 不依赖 Termux、Ubuntu 或其他外部 Runtime。
///
/// 能力说明：
///   - Shell/Command execution — 通过 RuntimeProcessRunner 本地执行
///   - Environment — 基本 PATH、HOME、TMPDIR
///   - Executable resolution — 搜索系统 PATH
///
/// 当前不提供（明确返回 unavailable）：
///   - Node.js
///   - Python
///   - Git
///   - npm
///   - Codex CLI
///
/// 这些能力需要 Termux 或 Ubuntu Provider。
/// 未来如果应用捆绑了二进制文件，可在此 Provider 中声明。
/// ====================================================================
library;

import 'dart:io';

import '../../core/logger/log_service.dart';
import 'runtime_capability.dart';
import 'runtime_provider.dart';

/// App Runtime Provider
///
/// 代表 Flutter 应用自身可提供的运行能力。
class AppRuntimeProvider implements IRuntimeProvider {
  ProviderStatus _status = ProviderStatus.available;
  List<RuntimeCapability> _cachedCapabilities = const [];

  @override
  String get id => 'app';

  @override
  String get name => 'App Runtime';

  @override
  ProviderType get type => ProviderType.app;

  @override
  ProviderStatus get status => _status;

  @override
  Future<ProviderInfo> detect() async {
    final start = DateTime.now();

    try {
      final shellCheck = _checkShellExecution();

      final capabilities = <RuntimeCapability>[
        // Shell execution — available via dart:io Process
        RuntimeCapability(
          type: CapabilityType.systemShell,
          provider: type,
          available: shellCheck.passed,
          path: shellCheck.path,
          health: shellCheck.passed
              ? CapabilityHealth.healthy
              : CapabilityHealth.unavailable,
          reason: shellCheck.error,
        ),
        // Node.js — not bundled
        RuntimeCapability(
          type: CapabilityType.node,
          provider: type,
          available: false,
          health: CapabilityHealth.unavailable,
          reason: 'App Runtime 不捆绑 Node.js',
        ),
        // Python — not bundled
        RuntimeCapability(
          type: CapabilityType.python,
          provider: type,
          available: false,
          health: CapabilityHealth.unavailable,
          reason: 'App Runtime 不捆绑 Python',
        ),
        // Git — not bundled
        RuntimeCapability(
          type: CapabilityType.git,
          provider: type,
          available: false,
          health: CapabilityHealth.unavailable,
          reason: 'App Runtime 不捆绑 Git',
        ),
        // npm — depends on Node
        RuntimeCapability(
          type: CapabilityType.npm,
          provider: type,
          available: false,
          health: CapabilityHealth.unavailable,
          reason: 'App Runtime 不捆绑 npm',
        ),
        // Codex CLI — depends on Node
        RuntimeCapability(
          type: CapabilityType.codexCli,
          provider: type,
          available: false,
          health: CapabilityHealth.unavailable,
          reason: 'App Runtime 不捆绑 Codex CLI',
        ),
      ];
      _cachedCapabilities = capabilities;

      final health = ProviderHealth(
        healthy: shellCheck.passed,
        latencyMs: DateTime.now().difference(start).inMilliseconds,
        detail: 'App Runtime 可用',
        checks: [
          DiagnosticCheck(
            name: 'Shell 执行',
            passed: shellCheck.passed,
            detail: shellCheck.version,
          ),
        ],
      );

      return ProviderInfo(
        type: type,
        status: _status,
        version: '1.0',
        description: 'App Runtime · 基础 Shell 执行可用',
        capabilities: _cachedCapabilities,
        health: health,
        detectionDurationMs: DateTime.now().difference(start).inMilliseconds,
      );
    } catch (e) {
      LogService.error('AppRuntimeProvider', '检测失败: $e');
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
    return {
      'PATH': Platform.environment['PATH'] ?? '/system/bin:/system/xbin',
      if (appHome != null) 'HOME': appHome,
      if (appHome != null) 'TMPDIR': '$appHome/cache/tmp',
      if (Platform.environment['LANG'] != null) 'LANG': Platform.environment['LANG']!,
    };
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProviderHealth> healthCheck() async {
    final start = DateTime.now();
    final shellCheck = _checkShellExecution();
    return ProviderHealth(
      healthy: shellCheck.passed,
      latencyMs: DateTime.now().difference(start).inMilliseconds,
      checks: [
        DiagnosticCheck(
          name: 'Shell 执行',
          passed: shellCheck.passed,
          detail: shellCheck.version,
        ),
      ],
    );
  }

  @override
  List<RuntimeCapability> get capabilities => _cachedCapabilities;

  /// Resolve executable path from system PATH.
  Future<String?> resolveExecutable(String name) async {
    try {
      final result = await Process.run('which', [name]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }

  _CheckResult _checkShellExecution() {
    try {
      final result = Process.runSync('sh', ['-c', 'echo ok']);
      if (result.exitCode == 0) {
        return const _CheckResult(
          passed: true, version: 'Shell 执行可用', path: 'sh',
        );
      }
    } catch (_) {}
    return const _CheckResult(passed: false, error: 'Shell 执行不可用');
  }
}

class _CheckResult {
  final bool passed;
  final String? version;
  final String? path;
  final String? error;
  const _CheckResult({required this.passed, this.version, this.path, this.error});
}
