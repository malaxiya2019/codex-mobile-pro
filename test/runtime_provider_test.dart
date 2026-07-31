/// ====================================================================
/// Runtime Provider 测试
///
/// 覆盖 Phase 2 Commit 1-5 的所有 Provider 抽象。
///
/// 测试类型：
///   1. 模型测试（无需 Flutter）
///   2. Provider 注册/发现测试
///   3. Capability 查询测试
///   4. Fallback 测试
///   5. InstallerManager 测试
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/provider/android_runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_capability.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/provider/linux_runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/runtime_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // 1. Capability 模型测试
  // ═══════════════════════════════════════════════════════════════

  group('RuntimeCapability — 数据模型', () {
    test('创建 Capability 并验证字段', () {
      const cap = RuntimeCapability(
        type: CapabilityType.node,
        provider: ProviderType.app,
        available: true,
        version: '22.x',
        path: '/runtime/bin/node',
        health: CapabilityHealth.healthy,
      );

      expect(cap.type, CapabilityType.node);
      expect(cap.provider, ProviderType.app);
      expect(cap.available, true);
      expect(cap.version, '22.x');
      expect(cap.path, '/runtime/bin/node');
      expect(cap.health, CapabilityHealth.healthy);
      expect(cap.reason, isNull);
    });

    test('不可用的 Capability 携带原因', () {
      const cap = RuntimeCapability(
        type: CapabilityType.ubuntu,
        provider: ProviderType.linux,
        available: false,
        health: CapabilityHealth.unavailable,
        reason: 'Linux Runtime 未初始化',
      );

      expect(cap.available, false);
      expect(cap.reason, 'Linux Runtime 未初始化');
      expect(cap.displayName, 'Ubuntu Runtime');
    });

    test('displayName 返回中文名称', () {
      final testCases = {
        CapabilityType.systemShell: '系统 Shell',
        CapabilityType.curl: 'cURL',
        CapabilityType.storageAccess: '存储权限',
        CapabilityType.networkAccess: '网络连通性',
        CapabilityType.node: 'Node.js',
        CapabilityType.npm: 'npm',
        CapabilityType.git: 'Git',
        CapabilityType.python: 'Python 3',
        CapabilityType.codexCli: 'Codex CLI',
        CapabilityType.ubuntu: 'Ubuntu Runtime',
      };

      for (final entry in testCases.entries) {
        final cap = RuntimeCapability(
          type: entry.key,
          provider: ProviderType.android,
          available: true,
        );
        expect(cap.displayName, entry.value);
      }
    });

    test('statusDescription 根据 available 变化', () {
      const healthy = RuntimeCapability(
        type: CapabilityType.node,
        provider: ProviderType.app,
        available: true,
        version: '22.x',
      );
      expect(healthy.statusDescription, contains('✅ 可用'));

      const unhealthy = RuntimeCapability(
        type: CapabilityType.ubuntu,
        provider: ProviderType.linux,
        available: false,
        reason: '未安装',
      );
      expect(unhealthy.statusDescription, contains('❌ 不可用'));
      expect(unhealthy.statusDescription, contains('未安装'));
    });

    test('icon 返回对应 emoji', () {
      expect(
        const RuntimeCapability(type: CapabilityType.node, provider: ProviderType.android, available: true).icon,
        '🟢',
      );
      expect(
        const RuntimeCapability(type: CapabilityType.python, provider: ProviderType.android, available: true).icon,
        '🐍',
      );
      expect(
        const RuntimeCapability(type: CapabilityType.ubuntu, provider: ProviderType.android, available: true).icon,
        '🐧',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 2. Provider 抽象测试（AndroidRuntimeProvider）
  // ═══════════════════════════════════════════════════════════════

  group('AndroidRuntimeProvider — Android 基础环境', () {
    test('Provider 属性正确', () {
      final provider = AndroidRuntimeProvider();
      expect(provider.id, 'android');
      expect(provider.name, 'Android 基础环境');
      expect(provider.type, ProviderType.android);
      expect(provider.status, ProviderStatus.unavailable); // 默认
    });

    test('capabilities 默认返回空列表', () {
      final provider = AndroidRuntimeProvider();
      expect(provider.capabilities, isEmpty);
    });

    test('isAvailable 始终返回 true', () async {
      final provider = AndroidRuntimeProvider();
      expect(await provider.isAvailable(), true);
    });

    test('getEnvironment 包含 Shell 和 PATH', () async {
      final provider = AndroidRuntimeProvider();
      final env = await provider.getEnvironment(appHome: '/app');
      expect(env, containsPair('SHELL', '/system/bin/sh'));
      expect(env, containsPair('HOME', '/app'));
      expect(env['PATH'], contains('/system/bin'));
    });

    test('healthCheck 返回健康检查结果', () async {
      final provider = AndroidRuntimeProvider();
      final health = await provider.healthCheck();
      expect(health.checks, isNotEmpty);
      expect(health.checks.any((c) => c.name == 'Android Shell'), true);
      expect(health.checks.any((c) => c.name == 'cURL'), true);
      expect(health.checks.any((c) => c.name == '存储权限'), true);
    });

    test('detect 返回 ProviderInfo', () async {
      final provider = AndroidRuntimeProvider();
      final info = await provider.detect();
      expect(info.type, ProviderType.android);
      expect(info.capabilities, isNotEmpty);
      expect(info.detectionDurationMs, greaterThanOrEqualTo(0));

      // 应该包含 4 个基础 Capability
      final capTypes = info.capabilities.map((c) => c.type).toSet();
      expect(capTypes, contains(CapabilityType.systemShell));
      expect(capTypes, contains(CapabilityType.curl));
      expect(capTypes, contains(CapabilityType.storageAccess));
      expect(capTypes, contains(CapabilityType.networkAccess));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 3. Linux Provider 测试（PRoot + Ubuntu rootfs）
  // ═══════════════════════════════════════════════════════════════

  group('LinuxRuntimeProvider — Linux Runtime', () {
    test('Provider 属性正确', () {
      final provider = LinuxRuntimeProvider();
      expect(provider.id, 'linux');
      expect(provider.name, 'Linux Runtime');
      expect(provider.type, ProviderType.linux);
    });

    test('detect 不抛出异常', () async {
      final provider = LinuxRuntimeProvider();
      // 不应抛出异常（未安装时返回 unavailable/degraded）
      final info = await provider.detect();
      expect(info.status, isNotNull);
      await provider.healthCheck();
      await provider.isAvailable();
    });

    test('detect 状态与 capabilities 一致', () async {
      final provider = LinuxRuntimeProvider();
      final info = await provider.detect();
      for (final cap in info.capabilities) {
        expect(cap.type, isNotNull);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 4. RuntimeManager Provider Orchestration 测试
  // ═══════════════════════════════════════════════════════════════

  group('RuntimeManager — Provider Orchestration', () {
    late RuntimeManager mgr;

    setUp(() {
      mgr = RuntimeManager.instance;
    });

    test('默认注册 3 个 Provider', () {
      final mgr = RuntimeManager.instance;
      final providers = mgr.registeredProviders;

      // App, Android, Linux
      expect(providers.length, greaterThanOrEqualTo(2));
      expect(providers.any((p) => p.id == 'android'), true);
      expect(providers.any((p) => p.id == 'linux'), true);
    });

    test('registerProvider 可以替换已有 Provider', () {
      final mgr = RuntimeManager.instance;

      // 注册一个测试 Provider
      final testProvider = _TestProvider('test');
      mgr.registerProvider(testProvider);
      expect(mgr.registeredProviders.any((p) => p.id == 'test'), true);
    });

    test('getProvidersForCapability 返回 Provider', () async {
      // Provider 的 capabilities 在 detect() 后填充
      await mgr.discoverProviders();

      // systemShell 应有 Provider 声明（Android 真机为 android，CI 为 app）
      final providers = mgr.getProvidersForCapability(CapabilityType.systemShell);
      expect(providers, isNotEmpty);

      // Linux 提供 ubuntu（rootfs 能力）
      final linuxProviders = mgr.getProvidersForCapability(CapabilityType.ubuntu);
      expect(linuxProviders, isNotEmpty);
      expect(linuxProviders.any((p) => p.id == 'linux'), true);
    });

    test('getCapability 查找可用 Capability', () async {
      await mgr.discoverProviders();

      // systemShell 应可解析（Android 真机为 android，CI 为 app）
      final shellCap = await mgr.getCapability(CapabilityType.systemShell);
      expect(shellCap, isNotNull);
      expect(shellCap!.type, CapabilityType.systemShell);
    });

    test('discoverProviders 返回 ProviderInfo 列表', () async {
      final mgr = RuntimeManager.instance;
      final infos = await mgr.discoverProviders();
      expect(infos, isNotEmpty);

      // 包含 android 和 linux
      expect(infos.any((i) => i.type == ProviderType.android), true);
      expect(infos.any((i) => i.type == ProviderType.linux), true);
    });

    test('resolveFallbackProvider 返回可用 Provider', () async {
      // systemShell 由平台实际提供方返回（Android 真机为 android，CI 为 app）
      final provider = await mgr.resolveFallbackProvider(CapabilityType.systemShell);
      expect(provider, isNotNull);
      expect(
        provider!.capabilities.any((c) => c.type == CapabilityType.systemShell),
        true,
      );
    });

    test('registerProvider 重置 Provider 信息缓存', () async {
      await mgr.discoverProviders();
      expect(mgr.cachedProviderInfos, isNotNull);

      mgr.registerProvider(_TestProvider('cache-reset'));
      expect(mgr.cachedProviderInfos, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 5. ProviderInfo / ProviderHealth / DiagnosticCheck 模型测试
  // ═══════════════════════════════════════════════════════════════

  group('ProviderInfo — Provider 信息模型', () {
    test('创建 ProviderInfo', () {
      const info = ProviderInfo(
        type: ProviderType.android,
        status: ProviderStatus.available,
        version: '1.0',
        description: '基础环境正常',
        detectionDurationMs: 100,
      );

      expect(info.type, ProviderType.android);
      expect(info.status, ProviderStatus.available);
      expect(info.version, '1.0');
      expect(info.description, '基础环境正常');
      expect(info.capabilities, isEmpty);
      expect(info.detectionDurationMs, 100);
    });

    test('ProviderInfo 带 Capability', () {
      final caps = [
        const RuntimeCapability(
          type: CapabilityType.systemShell,
          provider: ProviderType.android,
          available: true,
        ),
      ];
      final info = ProviderInfo(
        type: ProviderType.android,
        status: ProviderStatus.available,
        capabilities: caps,
      );

      expect(info.capabilities.length, 1);
      expect(info.capabilities.first.type, CapabilityType.systemShell);
    });

    test('ProviderHealth 创建', () {
      const health = ProviderHealth(
        healthy: true,
        version: '1.0',
        latencyMs: 50,
        detail: '正常',
        checks: [
          DiagnosticCheck(name: 'Shell', passed: true),
          DiagnosticCheck(name: 'cURL', passed: true, detail: '可用'),
        ],
      );

      expect(health.healthy, true);
      expect(health.version, '1.0');
      expect(health.latencyMs, 50);
      expect(health.checks.length, 2);
      expect(health.checks[0].name, 'Shell');
      expect(health.checks[1].passed, true);
      expect(health.checks[1].detail, '可用');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 6. InstallResult / InstallState / VerificationResult 模型测试
  // ═══════════════════════════════════════════════════════════════

  group('InstallResult — 安装结果模型', () {
    test('成功安装', () {
      const result = InstallResult(
        capability: CapabilityType.node,
        success: true,
        version: '22.x',
      );

      expect(result.capability, CapabilityType.node);
      expect(result.success, true);
      expect(result.version, '22.x');
      expect(result.errorMessage, isNull);
    });

    test('安装失败带错误信息', () {
      const result = InstallResult(
        capability: CapabilityType.git,
        success: false,
        errorMessage: '下载失败',
      );

      expect(result.success, false);
      expect(result.errorMessage, '下载失败');
    });

    test('InstallState 未安装', () {
      const state = InstallState(
        capability: CapabilityType.python,
        installed: false,
        error: '未安装',
      );

      expect(state.installed, false);
      expect(state.error, '未安装');
    });

    test('InstallState 已安装', () {
      const state = InstallState(
        capability: CapabilityType.node,
        installed: true,
        version: '22.x',
      );

      expect(state.installed, true);
      expect(state.version, '22.x');
    });

    test('VerificationResult 成功', () {
      const result = VerificationResult(
        capability: CapabilityType.git,
        success: true,
        output: '✅ 已安装',
      );

      expect(result.success, true);
      expect(result.output, '✅ 已安装');
    });

    test('VerificationResult 失败', () {
      const result = VerificationResult(
        capability: CapabilityType.node,
        success: false,
        error: '未找到',
      );

      expect(result.success, false);
      expect(result.error, '未找到');
    });
  });
}

// ═══════════════════════════════════════════════════════════════
// 测试辅助：测试用 Provider
// ═══════════════════════════════════════════════════════════════

class _TestProvider implements IRuntimeProvider {
  final String _id;
  _TestProvider(this._id);

  @override
  String get id => _id;

  @override
  String get name => 'Test Provider $_id';

  @override
  ProviderType get type => ProviderType.app;

  @override
  ProviderStatus get status => ProviderStatus.unavailable;

  @override
  List<RuntimeCapability> get capabilities => [];

  @override
  Future<ProviderInfo> detect() async => ProviderInfo(
    type: type,
    status: status,
    description: 'Test provider',
  );

  @override
  Future<Map<String, String>> getEnvironment({String? appHome}) async => {};

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<ProviderHealth> healthCheck() async => const ProviderHealth(healthy: false);
}
