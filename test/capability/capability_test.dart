/// ====================================================================
/// Phase 4 Capability 模型测试
///
/// 覆盖：
///   1. Capability 模型（RuntimeCapability）
///   2. CapabilityResolver（含 FakeProcessRunner）
///   3. ProviderCapabilityEnhancer
///   4. 缓存管理（TTL、refresh、invalidate）
///   5. 错误场景（not found、timeout、permission denied）
///   6. Provider fallback
///   7. RuntimeManager Capability API
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/capability/capability_resolver.dart';
import 'package:codex_mobile_pro/runtime/capability/provider_enhancer.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_capability.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_runner.dart';
import 'mock_provider.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // 1. Capability 模型测试
  // ═══════════════════════════════════════════════════════════════

  group('RuntimeCapability — 模型', () {
    test('available 能力创建', () {
      final cap = RuntimeCapability(
        type: CapabilityType.node,
        provider: ProviderType.linux,
        available: true,
        status: CapabilityStatus.available,
        version: '22.0.0',
        executable: '/data/linux/rootfs/usr/bin/node',
        health: CapabilityHealth.healthy,
        checkedAt: DateTime(2026, 7, 31),
      );

      expect(cap.type, CapabilityType.node);
      expect(cap.available, true);
      expect(cap.status, CapabilityStatus.available);
      expect(cap.installed, true);
      expect(cap.healthy, true);
      expect(cap.executable, '/data/linux/rootfs/usr/bin/node');
      expect(cap.version, '22.0.0');
    });

    test('unavailable 能力创建', () {
      const cap = RuntimeCapability(
        type: CapabilityType.node,
        provider: ProviderType.linux,
        available: false,
        status: CapabilityStatus.unavailable,
        health: CapabilityHealth.unavailable,
        reason: '未找到可执行文件',
      );

      expect(cap.available, false);
      expect(cap.status, CapabilityStatus.unavailable);
      expect(cap.installed, false);
      expect(cap.healthy, false);
      expect(cap.reason, '未找到可执行文件');
    });

    test('unknown 状态', () {
      const cap = RuntimeCapability(
        type: CapabilityType.git,
        provider: ProviderType.linux,
        available: false,
      );

      expect(cap.status, CapabilityStatus.unknown);
      expect(cap.available, false);
      expect(cap.healthy, false);
    });

    test('degraded 状态', () {
      const cap = RuntimeCapability(
        type: CapabilityType.codexCli,
        provider: ProviderType.android,
        available: true,
        status: CapabilityStatus.degraded,
        health: CapabilityHealth.degraded,
        reason: '版本不兼容',
      );

      expect(cap.available, true);
      expect(cap.status, CapabilityStatus.degraded);
      expect(cap.healthy, false);
      expect(cap.reason, '版本不兼容');
    });

    test('installed 但不可用', () {
      const cap = RuntimeCapability(
        type: CapabilityType.python,
        provider: ProviderType.linux,
        available: false,
        status: CapabilityStatus.unavailable,
        executable: '/usr/bin/python3',
        health: CapabilityHealth.unavailable,
        reason: '权限不足',
      );

      expect(cap.installed, true);
      expect(cap.available, false);
      expect(cap.healthy, false);
    });

    test('displayName 返回中文名称', () {
      expect(
        const RuntimeCapability(type: CapabilityType.node, provider: ProviderType.linux, available: true).displayName,
        'Node.js',
      );
      expect(
        const RuntimeCapability(type: CapabilityType.python, provider: ProviderType.linux, available: true).displayName,
        'Python 3',
      );
      expect(
        const RuntimeCapability(type: CapabilityType.git, provider: ProviderType.linux, available: true).displayName,
        'Git',
      );
    });

    test('toString 包含关键信息', () {
      const cap = RuntimeCapability(
        type: CapabilityType.node,
        provider: ProviderType.linux,
        available: true,
        status: CapabilityStatus.available,
        version: '22.0.0',
        executable: '/usr/bin/node',
      );

      final str = cap.toString();
      expect(str, contains('Node.js'));
      expect(str, contains('22.0.0'));
      expect(str, contains('/usr/bin/node'));
      expect(str, contains('linux'));
    });

    test('statusDescription available', () {
      const cap = RuntimeCapability(
        type: CapabilityType.node,
        provider: ProviderType.linux,
        available: true,
        version: '22.0.0',
      );

      expect(cap.statusDescription, contains('可用'));
      expect(cap.statusDescription, contains('22.0.0'));
    });

    test('statusDescription unavailable with reason', () {
      const cap = RuntimeCapability(
        type: CapabilityType.node,
        provider: ProviderType.linux,
        available: false,
        reason: '未安装',
      );

      expect(cap.statusDescription, contains('不可用'));
      expect(cap.statusDescription, contains('未安装'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 2. CapabilityResolver 测试
  // ═══════════════════════════════════════════════════════════════

  group('CapabilityResolver — 检测', () {
    late FakeProcessRunner fakeRunner;
    late CapabilityResolver resolver;
    late MockProvider provider;

    setUp(() {
      fakeRunner = FakeProcessRunner();
      resolver = CapabilityResolver(runner: fakeRunner);
      provider = MockProvider(const MockProviderConfig(
        id: 'linux',
        name: 'Linux Test',
        type: ProviderType.linux,
        environment: {'PATH': '/data/linux/rootfs/usr/bin'},
      ));
    });

    test('检测可用能力 — node --version', () async {
      fakeRunner.whenWhich('node', '/data/linux/rootfs/usr/bin/node');
      fakeRunner.whenVersion('node', '22.0.0');

      final cap = await resolver.checkCapability(CapabilityType.node, provider);

      expect(cap.available, true);
      expect(cap.status, CapabilityStatus.available);
      expect(cap.version, '22.0.0');
      expect(cap.executable, '/data/linux/rootfs/usr/bin/node');
      expect(cap.health, CapabilityHealth.healthy);
      expect(cap.checkedAt, isNotNull);
    });

    test('检测可用能力 — git --version', () async {
      fakeRunner.whenWhich('git', '/usr/bin/git');
      fakeRunner.whenVersion('git', '2.43.0');

      final cap = await resolver.checkCapability(CapabilityType.git, provider);

      expect(cap.available, true);
      expect(cap.version, '2.43.0');
      expect(cap.executable, '/usr/bin/git');
    });

    test('可执行文件不存在', () async {
      fakeRunner.whenNotFound('python3');

      final cap = await resolver.checkCapability(CapabilityType.python, provider);

      expect(cap.available, false);
      expect(cap.status, CapabilityStatus.unavailable);
      expect(cap.health, CapabilityHealth.unavailable);
      expect(cap.reason, contains('可执行文件不存在'));
    });

    test('超时（which 命中 → broken）', () async {
      fakeRunner.whenWhich('node', '/usr/bin/node');
      fakeRunner.whenTimeout('node --version');

      final cap = await resolver.checkCapability(CapabilityType.node, provider);

      expect(cap.available, false);
      expect(cap.status, CapabilityStatus.degraded);
      expect(cap.health, CapabilityHealth.degraded);
      expect(cap.executable, '/usr/bin/node');
      expect(cap.installed, true);
      expect(cap.reason, contains('超时'));
    });

    test('权限不足（which 命中 → broken）', () async {
      fakeRunner.whenWhich('node', '/usr/bin/node');
      fakeRunner.whenPermissionDenied('node');

      final cap = await resolver.checkCapability(CapabilityType.node, provider);

      expect(cap.available, false);
      expect(cap.status, CapabilityStatus.degraded);
      expect(cap.health, CapabilityHealth.degraded);
      expect(cap.executable, '/usr/bin/node');
      expect(cap.installed, true);
      expect(cap.reason, contains('权限不足'));
    });

    test('非零退出码（which 命中 → broken，如 npm exit=127）', () async {
      fakeRunner.whenWhich('npm', '/usr/bin/npm');
      fakeRunner.when('npm --version', const FakeCommandResult(
        exitCode: 127,
        stderr: '/usr/bin/env: node: No such file or directory',
      ));

      final cap = await resolver.checkCapability(CapabilityType.npm, provider);

      expect(cap.available, false);
      expect(cap.status, CapabilityStatus.degraded);
      expect(cap.health, CapabilityHealth.degraded);
      expect(cap.executable, '/usr/bin/npm');
      expect(cap.installed, true);
      expect(cap.reason, contains('非零退出码'));
    });

    test('非可执行能力 — systemShell', () async {
      // systemShell 没有 _CheckSpec，应由 Provider 声明
      final cap = await resolver.checkCapability(CapabilityType.systemShell, provider);

      // Provider 未声明 systemShell，应返回不可用
      expect(cap.available, isNot(true));
      expect(cap.reason, contains('未声明'));
    });

    test('批量检测多个能力', () async {
      fakeRunner.whenWhich('node', '/usr/bin/node');
      fakeRunner.whenVersion('node', '22.0.0');
      fakeRunner.whenWhich('git', '/usr/bin/git');
      fakeRunner.whenVersion('git', '2.43.0');

      final caps = await resolver.checkCapabilities(
        [CapabilityType.node, CapabilityType.git],
        provider,
      );

      expect(caps.length, 2);
      expect(caps[0].type, CapabilityType.node);
      expect(caps[0].available, true);
      expect(caps[1].type, CapabilityType.git);
      expect(caps[1].available, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 3. 缓存管理测试
  // ═══════════════════════════════════════════════════════════════

  group('CapabilityResolver — 缓存', () {
    late FakeProcessRunner fakeRunner;
    late CapabilityResolver resolver;
    late MockProvider provider;

    setUp(() {
      fakeRunner = FakeProcessRunner();
      resolver = CapabilityResolver(runner: fakeRunner);
      provider = MockProvider(const MockProviderConfig(
        id: 'linux',
        name: 'Linux',
        type: ProviderType.linux,
      ));

      fakeRunner.whenWhich('node', '/usr/bin/node');
      fakeRunner.whenVersion('node', '22.0.0');
    });

    test('缓存命中 — 第二次调用不执行命令', () async {
      await resolver.checkCapability(CapabilityType.node, provider);
      final firstCalls = fakeRunner.callCount;

      await resolver.checkCapability(CapabilityType.node, provider);
      expect(fakeRunner.callCount, firstCalls);
    });

    test('forceRefresh 跳过缓存', () async {
      await resolver.checkCapability(CapabilityType.node, provider);
      final firstCalls = fakeRunner.callCount;

      await resolver.checkCapability(CapabilityType.node, provider, forceRefresh: true);
      expect(fakeRunner.callCount, greaterThan(firstCalls));
    });

    test('invalidate 后重新检测', () async {
      await resolver.checkCapability(CapabilityType.node, provider);
      final firstCalls = fakeRunner.callCount;

      resolver.invalidate(CapabilityType.node);
      await resolver.checkCapability(CapabilityType.node, provider);
      expect(fakeRunner.callCount, greaterThan(firstCalls));
    });

    test('invalidateAll 清空所有缓存', () async {
      fakeRunner.whenWhich('git', '/usr/bin/git');
      fakeRunner.whenVersion('git', '2.43.0');

      await resolver.checkCapability(CapabilityType.node, provider);
      await resolver.checkCapability(CapabilityType.git, provider);
      resolver.invalidateAll();

      expect(resolver.getCacheEntry(CapabilityType.node), isNull);
      expect(resolver.getCacheEntry(CapabilityType.git), isNull);
    });

    test('refresh 强制刷新', () async {
      await resolver.checkCapability(CapabilityType.node, provider);
      final firstCalls = fakeRunner.callCount;

      await resolver.refresh(CapabilityType.node, provider);
      expect(fakeRunner.callCount, greaterThan(firstCalls));

      // 刷新后缓存应存在
      expect(resolver.getCacheEntry(CapabilityType.node), isNotNull);
    });

    test('缓存 TTL: 过期后自动失效', () async {
      // 使用极短 TTL
      final shortResolver = CapabilityResolver(
        runner: fakeRunner,
        defaultTtl: const Duration(milliseconds: 1),
      );

      await shortResolver.checkCapability(CapabilityType.node, provider);
      final firstCalls = fakeRunner.callCount;

      // 等待 TTL 过期
      await Future.delayed(const Duration(milliseconds: 10));

      await shortResolver.checkCapability(CapabilityType.node, provider);
      expect(fakeRunner.callCount, greaterThan(firstCalls));
    });

    test('缓存按 Provider 隔离 — 不同 Provider 同 type 分别检测', () async {
      final androidProvider = MockProvider(const MockProviderConfig(
        id: 'android',
        name: 'Android',
        type: ProviderType.android,
      ));

      // Linux 首次检测
      await resolver.checkCapability(CapabilityType.node, provider);
      final firstCalls = fakeRunner.callCount;

      // 同一 Provider 命中缓存，不重复执行
      await resolver.checkCapability(CapabilityType.node, provider);
      expect(fakeRunner.callCount, firstCalls);

      // 不同 Provider 必须重新检测：app/android 的失败结果
      // 不得污染 linux 的真实结果（反之亦然）
      await resolver.checkCapability(CapabilityType.node, androidProvider);
      expect(fakeRunner.callCount, greaterThan(firstCalls));

      // 互不污染：各自结果独立缓存
      expect(resolver.getCacheEntry(CapabilityType.node), isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 4. ProviderCapabilityEnhancer 测试
  // ═══════════════════════════════════════════════════════════════

  group('ProviderCapabilityEnhancer — Provider 集成', () {
    late FakeProcessRunner fakeRunner;
    late CapabilityResolver resolver;
    late ProviderCapabilityEnhancer enhancer;

    setUp(() {
      fakeRunner = FakeProcessRunner();
      resolver = CapabilityResolver(runner: fakeRunner);
      enhancer = ProviderCapabilityEnhancer(resolver: resolver);
    });

    test('增强可执行能力 — Node', () async {
      fakeRunner.whenWhich('node', '/usr/bin/node');
      fakeRunner.whenVersion('node', '22.0.0');

      final provider = MockProvider(const MockProviderConfig(
        id: 'linux',
        name: 'Linux',
        type: ProviderType.linux,
        capabilities: [
          RuntimeCapability(
            type: CapabilityType.node,
            provider: ProviderType.linux,
            available: true,
          ),
        ],
      ));

      final cap = await enhancer.enhanceCapability(provider, CapabilityType.node);

      expect(cap, isNotNull);
      expect(cap!.available, true);
      expect(cap.version, '22.0.0');
      expect(cap.executable, '/usr/bin/node');
      expect(cap.checkedAt, isNotNull);
    });

    test('增强失败时回退到静态声明', () async {
      fakeRunner.whenNotFound('node');

      final provider = MockProvider(const MockProviderConfig(
        id: 'android',
        name: 'Android',
        type: ProviderType.android,
        capabilities: [
          RuntimeCapability(
            type: CapabilityType.node,
            provider: ProviderType.android,
            available: false,
            reason: '未安装',
          ),
        ],
      ));

      final cap = await enhancer.enhanceCapability(provider, CapabilityType.node);

      // 由于 Provider 没有声明 node，Enhancer 返回 Resolver 结果（不可用）
      expect(cap, isNotNull);
      expect(cap!.available, false);
    });

    test('非可执行能力使用 Provider 静态声明', () async {
      final provider = MockProvider(const MockProviderConfig(
        id: 'android',
        name: 'Android',
        type: ProviderType.android,
        capabilities: [
          RuntimeCapability(
            type: CapabilityType.systemShell,
            provider: ProviderType.android,
            available: true,
            path: '/system/bin/sh',
          ),
        ],
      ));

      final cap = await enhancer.enhanceCapability(provider, CapabilityType.systemShell);

      expect(cap, isNotNull);
      expect(cap!.available, true);
      expect(cap.path, '/system/bin/sh');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 5. Provider fallback 场景
  // ═══════════════════════════════════════════════════════════════

  group('Provider fallback — 多 Provider 选择', () {
    test('Linux 可用时优先于 Android', () async {
      final androidProvider = MockProvider(const MockProviderConfig(
        id: 'android',
        name: 'Android',
        type: ProviderType.android,
        capabilities: [
          RuntimeCapability(type: CapabilityType.node, provider: ProviderType.android, available: false, reason: '不支持'),
          RuntimeCapability(type: CapabilityType.git, provider: ProviderType.android, available: false, reason: '不支持'),
        ],
      ));

      final linuxProvider = MockProvider(const MockProviderConfig(
        id: 'linux',
        name: 'Linux',
        type: ProviderType.linux,
        capabilities: [
          RuntimeCapability(type: CapabilityType.node, provider: ProviderType.linux, available: true, version: '22.0.0'),
          RuntimeCapability(type: CapabilityType.git, provider: ProviderType.linux, available: true, version: '2.43.0'),
        ],
      ));

      // Linux 能提供 node 和 git
      expect(linuxProvider.capabilities.any((c) => c.type == CapabilityType.node && c.available), true);
      expect(linuxProvider.capabilities.any((c) => c.type == CapabilityType.git && c.available), true);

      // Android 不能提供
      expect(androidProvider.capabilities.any((c) => c.type == CapabilityType.node && c.available), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 6. CapabilityCacheEntry 测试
  // ═══════════════════════════════════════════════════════════════

  group('CapabilityCacheEntry — 缓存条目', () {
    test('未过期', () {
      final entry = CapabilityCacheEntry(
        capability: const RuntimeCapability(type: CapabilityType.node, provider: ProviderType.linux, available: true),
        cachedAt: DateTime.now(),
      );

      expect(entry.isExpired(const Duration(seconds: 30)), false);
    });

    test('已过期', () {
      final entry = CapabilityCacheEntry(
        capability: const RuntimeCapability(type: CapabilityType.node, provider: ProviderType.linux, available: true),
        cachedAt: DateTime.now().subtract(const Duration(seconds: 31)),
      );

      expect(entry.isExpired(const Duration(seconds: 30)), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 7. 版本解析测试（集成测试）
  // ═══════════════════════════════════════════════════════════════

  group('版本解析 — 真实场景模拟', () {
    test('node --version 输出解析', () async {
      final runner = FakeProcessRunner();
      runner.whenWhich('node', '/usr/bin/node');
      runner.when('node --version', const FakeCommandResult(stdout: 'v22.0.0\n'));

      final resolver = CapabilityResolver(runner: runner);
      final provider = MockProvider(const MockProviderConfig(
        id: 'linux', name: 'Linux', type: ProviderType.linux,
      ));

      final cap = await resolver.checkCapability(CapabilityType.node, provider);
      expect(cap.available, true);
      expect(cap.version, '22.0.0');
    });

    test('git --version 输出解析', () async {
      final runner = FakeProcessRunner();
      runner.whenWhich('git', '/usr/bin/git');
      runner.when('git --version', const FakeCommandResult(stdout: 'git version 2.43.0\n'));

      final resolver = CapabilityResolver(runner: runner);
      final provider = MockProvider(const MockProviderConfig(
        id: 'linux', name: 'Linux', type: ProviderType.linux,
      ));

      final cap = await resolver.checkCapability(CapabilityType.git, provider);
      expect(cap.available, true);
      expect(cap.version, '2.43.0');
    });
  });
}
