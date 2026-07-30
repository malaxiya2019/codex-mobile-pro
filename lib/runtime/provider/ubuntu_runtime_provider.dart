/// ====================================================================
/// UbuntuRuntimeProvider
///
/// Ubuntu Runtime Provider（实验性）。
/// 只负责 detect/status，不处理安装或 native crash（Phase 8）。
///
/// 状态始终标记为 experimental。
/// 不作为 Coding Runtime 的强制依赖。
///
/// 检测项：
///   - proot 是否可用
///   - Ubuntu rootfs 是否存在
///   - proot-distro 是否可用
/// ====================================================================
library;

import 'dart:io';

import '../../core/logger/log_service.dart';
import 'runtime_capability.dart';
import 'runtime_provider.dart';

/// Ubuntu Runtime Provider（实验性）
class UbuntuRuntimeProvider implements IRuntimeProvider {
  ProviderStatus _status = ProviderStatus.experimental;
  List<RuntimeCapability> _cachedCapabilities = const [];

  // ─── IRuntimeProvider ────────────────────────────────────────

  @override
  String get id => 'ubuntu';

  @override
  String get name => 'Ubuntu Runtime（实验性）';

  @override
  ProviderType get type => ProviderType.ubuntu;

  @override
  ProviderStatus get status => _status;

  @override
  Future<ProviderInfo> detect() async {
    final start = DateTime.now();

    try {
      // ─── 1. 检测 proot ────────────────────────────────────────
      final prootCheck = _checkProot();
      final rootfsCheck = _checkRootfs();
      final prootDistroCheck = _checkProotDistro();

      // ─── 2. 确定状态 ──────────────────────────────────────────
      // Ubuntu 始终标记为 experimental
      final available = prootCheck.passed && rootfsCheck.passed;
      _status =
          available
              ? ProviderStatus.experimental
              : ProviderStatus.unavailable;

      // ─── 3. 构建 Capability ───────────────────────────────────────
      _cachedCapabilities = [
        RuntimeCapability(
          type: CapabilityType.ubuntu,
          provider: type,
          available: available,
          version: rootfsCheck.version,
          path: rootfsCheck.path,
          health:
              available
                  ? CapabilityHealth.healthy
                  : CapabilityHealth.unavailable,
          reason:
              available
                  ? null
                  : !prootCheck.passed
                  ? 'proot 不可用'
                  : 'Ubuntu rootfs 未安装',
        ),
      ];

      // ─── 4. 构建健康检查 ──────────────────────────────────────
      final health = ProviderHealth(
        healthy: available,
        latencyMs: DateTime.now().difference(start).inMilliseconds,
        checks: [
          DiagnosticCheck(
            name: 'proot',
            passed: prootCheck.passed,
            detail: prootCheck.version,
          ),
          DiagnosticCheck(
            name: 'Ubuntu rootfs',
            passed: rootfsCheck.passed,
            detail: rootfsCheck.version ?? '未安装',
          ),
          DiagnosticCheck(
            name: 'proot-distro',
            passed: prootDistroCheck.passed,
            detail: prootDistroCheck.version,
          ),
        ],
      );

      // ─── 5. 状态描述 ──────────────────────────────────────────
      String description;
      if (available) {
        final parts = <String>['实验性'];
        if (rootfsCheck.version != null) parts.add(rootfsCheck.version!);
        if (prootCheck.path != null) parts.add(prootCheck.path!);
        description = parts.join(' · ');
      } else if (prootCheck.passed) {
        description = 'proot 可用，rootfs 未安装';
      } else {
        description = 'proot 不可用';
      }

      return ProviderInfo(
        type: type,
        status: _status,
        version: rootfsCheck.version,
        description: description,
        capabilities: _cachedCapabilities,
        health: health,
        detectionDurationMs: DateTime.now().difference(start).inMilliseconds,
      );
    } catch (e) {
      LogService.error('UbuntuProvider', '检测失败: $e');
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
    final rootfsPath = _findRootfsPath();

    if (rootfsPath != null) {
      return {
        'PROOT_ROOTFS': rootfsPath,
        'UBUNTU_ROOTFS': rootfsPath,
      };
    }

    return {};
  }

  @override
  Future<bool> isAvailable() async {
    final info = await detect();
    return info.status == ProviderStatus.experimental;
  }

  @override
  Future<ProviderHealth> healthCheck() async {
    final start = DateTime.now();
    final prootCheck = _checkProot();
    final rootfsCheck = _checkRootfs();

    return ProviderHealth(
      healthy: prootCheck.passed && rootfsCheck.passed,
      version: rootfsCheck.version,
      latencyMs: DateTime.now().difference(start).inMilliseconds,
      checks: [
        DiagnosticCheck(
          name: 'proot',
          passed: prootCheck.passed,
          detail: prootCheck.version,
        ),
        DiagnosticCheck(
          name: 'Ubuntu rootfs',
          passed: rootfsCheck.passed,
          detail: rootfsCheck.version ?? '未安装',
        ),
      ],
    );
  }

  @override
  List<RuntimeCapability> get capabilities => _cachedCapabilities;

  // ─── 内部检测 ────────────────────────────────────────────────

  _CheckResult _checkProot() {
    // 检查常见 proot 位置
    final locations = [
      '/data/data/com.termux/files/usr/bin/proot',
      '/system/bin/proot',
      '/usr/bin/proot',
    ];

    for (final path in locations) {
      final file = File(path);
      if (file.existsSync()) {
        String? version;
        try {
          final result = Process.runSync(path, ['--version']);
          if (result.exitCode == 0) {
            version = (result.stdout as String).split('\n').first.trim();
          }
        } catch (_) {}
        return _CheckResult(passed: true, version: version ?? '可用', path: path);
      }
    }
    return const _CheckResult(passed: false);
  }

  _CheckResult _checkRootfs() {
    // 检查常见 rootfs 位置
    final locations = [
      '/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu',
      '/data/data/com.codexmobile.app/app_flutter/runtime/ubuntu/rootfs',
    ];

    // 还检查 App 私有目录
    for (final path in locations) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        // 检查是否是有效的 Ubuntu rootfs（包含 /bin 等）
        final binDir = Directory('$path/bin');
        if (binDir.existsSync()) {
          String? version;
          // 检查 /etc/os-release
          final osRelease = File('$path/etc/os-release');
          if (osRelease.existsSync()) {
            try {
              final content = osRelease.readAsStringSync();
              final match = RegExp(r'VERSION_ID="([^"]+)"').firstMatch(content);
              if (match != null) version = 'Ubuntu ${match.group(1)}';
            } catch (_) {}
          }
          return _CheckResult(passed: true, version: version ?? 'Ubuntu', path: path);
        }
      }
    }
    return const _CheckResult(passed: false);
  }

  _CheckResult _checkProotDistro() {
    final locations = [
      '/data/data/com.termux/files/usr/bin/proot-distro',
      '/data/data/com.termux/files/usr/bin/proot-distro.sh',
    ];

    for (final path in locations) {
      final file = File(path);
      if (file.existsSync()) {
        return _CheckResult(passed: true, version: '可用', path: path);
      }
    }
    return const _CheckResult(passed: false);
  }

  /// 查找 rootfs 路径
  String? _findRootfsPath() {
    final locations = [
      '/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu',
      '/data/data/com.codexmobile.app/app_flutter/runtime/ubuntu/rootfs',
    ];

    for (final path in locations) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        final binDir = Directory('$path/bin');
        if (binDir.existsSync()) {
          return path;
        }
      }
    }
    return null;
  }
}

/// 检测结果辅助类型
class _CheckResult {
  final bool passed;
  final String? version;
  final String? path;
  const _CheckResult({required this.passed, this.version, this.path});
}
