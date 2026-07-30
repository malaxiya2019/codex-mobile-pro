/// ====================================================================
/// AndroidRuntimeProvider
///
/// Android 系统基础能力的 Provider。
/// 对应 Layer 0：Android 基础环境。
///
/// 检测项（独立检测，不依赖 Detector 架构）：
///   - /system/bin/sh — Android 系统 Shell
///   - /system/bin/curl — Android 系统 cURL
///   - 存储权限 — /sdcard/Download 读写
///   - 网络连通性 — DNS + HTTP
///
/// 设计原则：
///   - 不依赖 Detector（检测器是独立的 UI 展示层）
///   - 不依赖 Termux
///   - 不依赖 Ubuntu
///   - 是所有 Runtime 的最低层
/// ====================================================================
library;

import 'dart:io';

import '../../core/logger/log_service.dart';
import 'runtime_capability.dart';
import 'runtime_provider.dart';

/// Android 基础环境 Provider
class AndroidRuntimeProvider implements IRuntimeProvider {
  ProviderStatus _status = ProviderStatus.unavailable;
  List<RuntimeCapability> _cachedCapabilities = const [];

  // ─── IRuntimeProvider ────────────────────────────────────────

  @override
  String get id => 'android';

  @override
  String get name => 'Android 基础环境';

  @override
  ProviderType get type => ProviderType.android;

  @override
  ProviderStatus get status => _status;

  @override
  Future<ProviderInfo> detect() async {
    final start = DateTime.now();

    try {
      // ─── 1. 检测 Android Shell ────────────────────────────────
      final shellCheck = _checkShell();
      final curlCheck = _checkCurl();
      final storageCheck = _checkStorage();

      // 网络检测较慢，异步执行
      final networkResult = await _checkNetwork();

      // ─── 2. 构建 Capability ───────────────────────────────────
      final capabilities = <RuntimeCapability>[
        RuntimeCapability(
          type: CapabilityType.systemShell,
          provider: type,
          available: shellCheck.passed,
          version: shellCheck.version,
          path: shellCheck.path,
          health:
              shellCheck.passed
                  ? CapabilityHealth.healthy
                  : CapabilityHealth.unavailable,
          reason: shellCheck.error,
        ),
        RuntimeCapability(
          type: CapabilityType.curl,
          provider: type,
          available: curlCheck.passed,
          version: curlCheck.version,
          path: curlCheck.path,
          health:
              curlCheck.passed
                  ? CapabilityHealth.healthy
                  : CapabilityHealth.unavailable,
          reason: curlCheck.error,
        ),
        RuntimeCapability(
          type: CapabilityType.storageAccess,
          provider: type,
          available: storageCheck.passed,
          version: storageCheck.version,
          path: storageCheck.path,
          health:
              storageCheck.passed
                  ? CapabilityHealth.healthy
                  : CapabilityHealth.unavailable,
          reason: storageCheck.error,
        ),
        RuntimeCapability(
          type: CapabilityType.networkAccess,
          provider: type,
          available: networkResult.dnsWorking || networkResult.ipDirectWorking,
          version: networkResult.summary,
          path: networkResult.localIp,
          health:
              (networkResult.dnsWorking && networkResult.internetReachable)
                  ? CapabilityHealth.healthy
                  : networkResult.ipDirectWorking
                  ? CapabilityHealth.degraded
                  : CapabilityHealth.unavailable,
          reason: networkResult.dnsWorking
              ? null
              : networkResult.ipDirectWorking
              ? 'DNS 故障，IP 直连已启用'
              : '网络不可用',
        ),
      ];
      _cachedCapabilities = capabilities;

      // ─── 3. 确定整体状态 ──────────────────────────────────────
      final allBasicPassed =
          shellCheck.passed && curlCheck.passed && storageCheck.passed;
      final networkOk =
          networkResult.dnsWorking || networkResult.ipDirectWorking;

      if (allBasicPassed && networkOk) {
        _status = ProviderStatus.available;
      } else if (allBasicPassed) {
        _status = ProviderStatus.degraded;
      } else {
        _status = ProviderStatus.available; // Android 环境始终认为可用
      }

      // ─── 4. 构建健康检查 ──────────────────────────────────────
      final health = ProviderHealth(
        healthy: allBasicPassed && networkOk,
        latencyMs: DateTime.now().difference(start).inMilliseconds,
        checks: [
          DiagnosticCheck(
            name: 'Android Shell',
            passed: shellCheck.passed,
            detail: shellCheck.version,
          ),
          DiagnosticCheck(
            name: 'cURL',
            passed: curlCheck.passed,
            detail: curlCheck.version,
          ),
          DiagnosticCheck(
            name: '存储权限',
            passed: storageCheck.passed,
            detail: storageCheck.version,
          ),
          DiagnosticCheck(
            name: '网络连通性',
            passed: networkResult.dnsWorking,
            detail: networkResult.summary,
          ),
        ],
      );

      // ─── 5. 状态描述 ──────────────────────────────────────────
      String description;
      if (allBasicPassed && networkOk) {
        description = '基础环境正常 · $shellCheck.version';
      } else if (allBasicPassed) {
        description = '基础环境正常 · 网络异常';
      } else {
        final missing = <String>[];
        if (!shellCheck.passed) missing.add('Shell');
        if (!curlCheck.passed) missing.add('cURL');
        if (!storageCheck.passed) missing.add('存储');
        description = '部分缺失: ${missing.join(", ")}';
      }

      return ProviderInfo(
        type: type,
        status: _status,
        description: description,
        capabilities: _cachedCapabilities,
        health: health,
        detectionDurationMs: DateTime.now().difference(start).inMilliseconds,
      );
    } catch (e) {
      LogService.error('AndroidProvider', '检测失败: $e');
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
      'SHELL': '/system/bin/sh',
      'PATH': '/system/bin:/system/xbin:/vendor/bin',
      if (appHome != null) 'HOME': appHome,
      if (appHome != null) 'TMPDIR': '$appHome/cache/tmp',
    };
  }

  @override
  Future<bool> isAvailable() async => true; // Android Runtime 始终可用

  @override
  Future<ProviderHealth> healthCheck() async {
    final start = DateTime.now();
    final shellCheck = _checkShell();
    final curlCheck = _checkCurl();
    final storageCheck = _checkStorage();

    return ProviderHealth(
      healthy: shellCheck.passed && curlCheck.passed && storageCheck.passed,
      latencyMs: DateTime.now().difference(start).inMilliseconds,
      checks: [
        DiagnosticCheck(
          name: 'Android Shell',
          passed: shellCheck.passed,
          detail: shellCheck.version,
        ),
        DiagnosticCheck(
          name: 'cURL',
          passed: curlCheck.passed,
          detail: curlCheck.version,
        ),
        DiagnosticCheck(
          name: '存储权限',
          passed: storageCheck.passed,
          detail: storageCheck.version,
        ),
      ],
    );
  }

  @override
  List<RuntimeCapability> get capabilities => _cachedCapabilities;

  // ─── 内部检测 ────────────────────────────────────────────────

  _CheckResult _checkShell() {
    final shFile = File('/system/bin/sh');
    if (shFile.existsSync()) {
      return const _CheckResult(passed: true, version: 'Android 系统 Shell', path: '/system/bin/sh');
    }
    return const _CheckResult(passed: false, error: '未找到 /system/bin/sh');
  }

  _CheckResult _checkCurl() {
    final curlFile = File('/system/bin/curl');
    if (curlFile.existsSync()) {
      String? version;
      try {
        final result = Process.runSync('/system/bin/curl', ['--version']);
        if (result.exitCode == 0) {
          version = (result.stdout as String).split('\n').first.trim();
        }
      } catch (_) {}
      return _CheckResult(passed: true, version: version ?? '可用', path: '/system/bin/curl');
    }
    return const _CheckResult(passed: false, error: '未找到 /system/bin/curl');
  }

  _CheckResult _checkStorage() {
    final downloadDir = Directory('/sdcard/Download');
    try {
      if (downloadDir.existsSync()) {
        final testFile = File('/sdcard/Download/.codex_storage_test');
        testFile.writeAsStringSync('ok');
        testFile.deleteSync();
        return const _CheckResult(passed: true, version: '可读写', path: '/sdcard/Download');
      }
    } catch (_) {
      if (downloadDir.existsSync()) {
        return const _CheckResult(passed: true, version: '只读', path: '/sdcard/Download');
      }
    }
    return const _CheckResult(passed: false, error: '存储目录不可访问');
  }

  Future<_NetworkCheckResult> _checkNetwork() async {
    // 轻量网络检测
    bool dnsOk = false;
    bool ipDirectOk = false;
    String? localIp;

    // 使用 ping 快速检测 DNS 和网络
    try {
      final pingResult = Process.runSync('ping', ['-c', '1', '-W', '2', 'github.com']);
      dnsOk = pingResult.exitCode == 0;
    } catch (_) {}

    if (!dnsOk) {
      // 尝试 IP 直连
      try {
        final ipResult = Process.runSync('ping', ['-c', '1', '-W', '2', '1.1.1.1']);
        ipDirectOk = ipResult.exitCode == 0;
      } catch (_) {}
    }

    // 获取本地 IP
    try {
      final ipResult = Process.runSync('ip', ['route', 'get', '1']);
      if (ipResult.exitCode == 0) {
        final match = RegExp(r'src\s+([\d.]+)').firstMatch(ipResult.stdout as String);
        if (match != null) localIp = match.group(1);
      }
    } catch (_) {}

    return _NetworkCheckResult(
      dnsWorking: dnsOk,
      ipDirectWorking: ipDirectOk || dnsOk,
      internetReachable: dnsOk || ipDirectOk,
      localIp: localIp,
    );
  }
}

/// 检测结果辅助类型
class _CheckResult {
  final bool passed;
  final String? version;
  final String? path;
  final String? error;
  const _CheckResult({required this.passed, this.version, this.path, this.error});
}

/// 网络检测结果辅助类型
class _NetworkCheckResult {
  final bool dnsWorking;
  final bool ipDirectWorking;
  final bool internetReachable;
  final String? localIp;

  const _NetworkCheckResult({
    required this.dnsWorking,
    required this.ipDirectWorking,
    required this.internetReachable,
    this.localIp,
  });

  String get summary {
    if (dnsWorking) return '网络正常';
    if (ipDirectWorking) return 'IP 直连模式';
    return '网络不可用';
  }
}
