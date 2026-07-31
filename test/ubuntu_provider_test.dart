/// ====================================================================
/// UbuntuRuntimeProvider 测试
///
/// 测试 Ubuntu Runtime Provider 的接口完整性和检测逻辑。
/// （archive 依赖问题需要 Flutter SDK 环境编译）
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/provider/runtime_capability.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/provider/ubuntu_runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UbuntuRuntimeProvider provider;

  setUp(() {
    provider = UbuntuRuntimeProvider();
  });

  group('UbuntuRuntimeProvider — 接口完整性', () {
    test('Provider 属性正确', () {
      expect(provider.id, 'ubuntu');
      expect(provider.name, 'Ubuntu Runtime（实验性）');
      expect(provider.type, ProviderType.ubuntu);
    });

    test('capabilities 初始为空', () {
      expect(provider.capabilities, isEmpty);
    });

    test('status 初始为 experimental', () {
      expect(provider.status, ProviderStatus.experimental);
    });
  });

  group('detect — 检测', () {
    test('不抛出异常', () async {
      await provider.detect();
      await provider.healthCheck();
      await provider.isAvailable();
    });

    test('返回 ProviderInfo', () async {
      final info = await provider.detect();
      expect(info.type, ProviderType.ubuntu);
      expect(info.detectionDurationMs, greaterThanOrEqualTo(0));
    });

    test('healthCheck 返回健康检查结果', () async {
      final health = await provider.healthCheck();
      expect(health.checks, isNotEmpty);
    });
  });

  group('capabilities — 能力检测', () {
    test('包含 ubuntu capability', () async {
      await provider.detect();
      final caps = provider.capabilities;
      expect(caps.any((c) => c.type == CapabilityType.ubuntu), true);
    });

    test('不包含非 ubuntu 能力', () async {
      await provider.detect();
      final caps = provider.capabilities;
      for (final cap in caps) {
        expect(cap.type, CapabilityType.ubuntu);
      }
    });
  });

  group('getEnvironment — 环境变量', () {
    test('不抛出异常', () async {
      final env = await provider.getEnvironment();
      expect(env, isNotNull);
    });

    test('包含 PATH（传 appHome 时）', () async {
      final env = await provider.getEnvironment(appHome: '/app');
      expect(env.containsKey('PATH'), true);
    });

    test('当 rootfs 不存在时返回基础变量', () async {
      final env = await provider.getEnvironment(appHome: '/app');
      // rootfs 不存在时，PATH 应该是系统路径
      if (!env.containsKey('PROOT_ROOTFS')) {
        expect(env['PATH'], contains('/system/bin'));
      }
    });
  });
}
