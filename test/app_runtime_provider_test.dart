/// ====================================================================
/// AppRuntimeProvider 测试
///
/// 测试 App Runtime 自身能力检测。
/// 不依赖 FakeTransport — AppRuntimeProvider 使用 dart:io Process。
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/provider/app_runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_capability.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppRuntimeProvider provider;

  setUp(() {
    provider = AppRuntimeProvider();
  });

  group('AppRuntimeProvider — 接口完整性', () {
    test('Provider 属性正确', () {
      expect(provider.id, 'app');
      expect(provider.name, 'App Runtime');
      expect(provider.type, ProviderType.app);
    });

    test('capabilities 初始为空', () {
      expect(provider.capabilities, isEmpty);
    });

    test('isAvailable 始终返回 true', () async {
      expect(await provider.isAvailable(), true);
    });
  });

  group('detect — 检测', () {
    test('返回可用状态', () async {
      final info = await provider.detect();
      expect(info.type, ProviderType.app);
      expect(info.status, ProviderStatus.available);
      expect(info.detectionDurationMs, greaterThanOrEqualTo(0));
    });

    test('不抛出异常', () async {
      await provider.detect();
      await provider.healthCheck();
      await provider.isAvailable();
    });
  });

  group('capabilities — 能力列表', () {
    test('Shell 执行可用', () async {
      await provider.detect();
      final caps = provider.capabilities;
      expect(
        caps.any((c) => c.type == CapabilityType.systemShell && c.available),
        true,
      );
    });

    test('Node.js 不可用', () async {
      await provider.detect();
      final caps = provider.capabilities;
      expect(
        caps.any((c) => c.type == CapabilityType.node && !c.available),
        true,
      );
    });

    test('Python 不可用', () async {
      await provider.detect();
      final caps = provider.capabilities;
      expect(
        caps.any((c) => c.type == CapabilityType.python && !c.available),
        true,
      );
    });

    test('Git 不可用', () async {
      await provider.detect();
      final caps = provider.capabilities;
      expect(
        caps.any((c) => c.type == CapabilityType.git && !c.available),
        true,
      );
    });

    test('npm 不可用', () async {
      await provider.detect();
      final caps = provider.capabilities;
      expect(
        caps.any((c) => c.type == CapabilityType.npm && !c.available),
        true,
      );
    });

    test('Codex CLI 不可用', () async {
      await provider.detect();
      final caps = provider.capabilities;
      expect(
        caps.any((c) => c.type == CapabilityType.codexCli && !c.available),
        true,
      );
    });

    test('所有不可用能力携带原因', () async {
      await provider.detect();
      final unavailable = provider.capabilities.where((c) => !c.available);
      for (final cap in unavailable) {
        expect(cap.reason, isNotEmpty,
            reason: '${cap.type.name} 应有不可用原因');
      }
    });
  });

  group('healthCheck — 健康检查', () {
    test('返回健康结果', () async {
      final health = await provider.healthCheck();
      expect(health.healthy, true);
      expect(health.checks, isNotEmpty);
    });
  });

  group('getEnvironment — 环境变量', () {
    test('包含 PATH', () async {
      final env = await provider.getEnvironment(appHome: '/app');
      expect(env.containsKey('PATH'), true);
      expect(env['PATH']!.contains('/system/bin'), true);
    });

    test('包含 HOME（指定 appHome 时）', () async {
      final env = await provider.getEnvironment(appHome: '/app');
      expect(env['HOME'], '/app');
    });

    test('不抛出异常（不传 appHome）', () async {
      final env = await provider.getEnvironment();
      expect(env.containsKey('PATH'), true);
    });
  });

  group('resolveExecutable — 可执行文件解析', () {
    test('sh 存在', () async {
      final path = await provider.resolveExecutable('sh');
      expect(path, isNotNull);
      expect(path!.isNotEmpty, true);
    });

    test('不存在的返回 null', () async {
      final path = await provider.resolveExecutable('nonexistent_tool_xyz123');
      expect(path, isNull);
    });
  });
}
