/// ====================================================================
/// TermuxRuntimeProvider 测试
///
/// 测试 TermuxRuntimeProvider 的基本结构和接口。
/// 实际 Termux 检测需要 MethodChannel，这里只测试：
///   - Provider 属性
///   - 接口实现完整性
///   - 状态映射
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/provider/runtime_capability.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/provider/termux_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TermuxRuntimeProvider — 接口完整性', () {
    test('Provider 属性正确', () {
      final provider = TermuxRuntimeProvider();

      expect(provider.id, 'termux');
      expect(provider.name, 'Termux Runtime');
      expect(provider.type, ProviderType.termux);
    });

    test('capabilities 默认为空', () {
      final provider = TermuxRuntimeProvider();
      expect(provider.capabilities, isEmpty);
    });

    test('lastDiagnostics 初始为 null', () {
      final provider = TermuxRuntimeProvider();
      expect(provider.lastDiagnostics, isNull);
    });

    test('lastEnvironment 初始为 null', () {
      final provider = TermuxRuntimeProvider();
      expect(provider.lastEnvironment, isNull);
    });

    test('getEnvironment 返回 Map', () async {
      final provider = TermuxRuntimeProvider();
      final env = await provider.getEnvironment();
      expect(env, isA<Map<String, String>>());
    });

    test('healthCheck 返回健康检查结果', () async {
      final provider = TermuxRuntimeProvider();
      final health = await provider.healthCheck();
      expect(health.checks, isNotEmpty);
      expect(health.checks.any((c) => c.name == 'Termux APK'), true);
      expect(health.checks.any((c) => c.name == 'RUN_COMMAND Intent'), true);
      expect(health.checks.any((c) => c.name == '命令执行'), true);
      expect(health.checks.any((c) => c.name == '包管理器'), true);
    });

    test('detect 不抛出异常', () async {
      final provider = TermuxRuntimeProvider();
      await provider.detect();
    });

    test('detect 返回 ProviderInfo', () async {
      final provider = TermuxRuntimeProvider();
      final info = await provider.detect();

      expect(info.type, ProviderType.termux);
      expect(info.status, isA<ProviderStatus>());
      expect(info.detectionDurationMs, greaterThanOrEqualTo(0));
    });

    test('detect 后 capabilities 被填充', () async {
      final provider = TermuxRuntimeProvider();
      await provider.detect();

      expect(
        provider.capabilities.any((c) => c.type == CapabilityType.termux),
        true,
      );
    });

    test('isAvailable 返回 bool（不抛异常）', () async {
      final provider = TermuxRuntimeProvider();
      final available = await provider.isAvailable();
      expect(available, isA<bool>());
    });

    test('executeInTermux 不抛异常', () async {
      final provider = TermuxRuntimeProvider();
      final result = await provider.executeInTermux('echo test');
      expect(result, isA<TermuxCommandResult>());
    });

    test('installPackage 不抛异常', () async {
      final provider = TermuxRuntimeProvider();
      final result = await provider.installPackage('nodejs');
      expect(result, isA<TermuxCommandResult>());
    });

    test('which 不抛异常', () async {
      final provider = TermuxRuntimeProvider();
      final path = await provider.which('node');
      expect(path, isA<String?>());
    });
  });

  group('TermuxRuntimeProvider — 状态映射', () {
    test('初始 status 为 unavailable', () {
      final provider = TermuxRuntimeProvider();
      expect(provider.status, ProviderStatus.unavailable);
    });
  });
}
