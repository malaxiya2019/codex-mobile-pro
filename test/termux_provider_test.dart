/// ====================================================================
/// TermuxRuntimeProvider 测试
///
/// 使用 FakeTermuxTransport 模拟 Termux 环境。
/// 不依赖真实 Termux 或 MethodChannel。
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/provider/runtime_capability.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/provider/termux_provider.dart';
import 'package:codex_mobile_pro/runtime/termux/fake_transport.dart';
import 'package:codex_mobile_pro/runtime/termux/termux_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeTermuxTransport fakeTransport;
  late TermuxRuntimeProvider provider;

  setUp(() {
    fakeTransport = FakeTermuxTransport();
    provider = TermuxRuntimeProvider(transport: fakeTransport);
  });

  // ═══════════════════════════════════════════════════════════════
  // 1. Provider 接口完整性
  // ═══════════════════════════════════════════════════════════════

  group('接口完整性', () {
    test('Provider 属性正确', () {
      expect(provider.id, 'termux');
      expect(provider.name, 'Termux Runtime');
      expect(provider.type, ProviderType.termux);
    });

    test('capabilities 初始为空', () {
      expect(provider.capabilities, isEmpty);
    });

    test('lastDiagnostics 初始为 null', () {
      expect(provider.lastDiagnostics, isNull);
    });

    test('lastEnvironment 初始为 null', () {
      expect(provider.lastEnvironment, isNull);
    });

    test('transport 返回传入的 Transport', () {
      expect(provider.transport, same(fakeTransport));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 2. Termux 检测
  // ═══════════════════════════════════════════════════════════════

  group('detect — Termux 检测', () {
    test('Termux 可用时返回 available', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        packageInstalled: true,
        intentAvailable: true,
        works: true,
        version: 'v0.118.0',
      ));
      fakeTransport.setEnvResult(const TermuxEnvResult(
        prefixPath: '/data/data/com.termux/files/usr',
        homePath: '/data/data/com.termux/files/home',
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
        pkgManager: TermuxPkgManager.pkg,
      ));

      // which 返回可执行文件路径（模拟 node 存在，其他不存在）
      fakeTransport.setWhichResult('node', '/data/data/com.termux/files/usr/bin/node');

      final info = await provider.detect();

      expect(info.type, ProviderType.termux);
      expect(info.status, ProviderStatus.available);
      expect(info.version, 'v0.118.0');
      expect(info.health!.healthy, true);
      expect(info.health!.checks.length, 4);
    });

    test('Termux 不可用时返回 unavailable', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        lastError: 'Termux 未安装',
      ));

      final info = await provider.detect();

      expect(info.status, ProviderStatus.unavailable);
      expect(info.health!.healthy, false);
      expect(info.capabilities.any((c) => c.type == CapabilityType.termux), true);
      expect(
        info.capabilities.firstWhere((c) => c.type == CapabilityType.termux).available,
        false,
      );
    });

    test('Termux 已安装但不可用返回 degraded', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        packageInstalled: true,
        lastError: 'RUN_COMMAND Intent 无响应',
      ));

      final info = await provider.detect();

      expect(info.status, ProviderStatus.degraded);
      expect(info.health!.healthy, false);
      expect(info.capabilities.any((c) => c.type == CapabilityType.termux), true);
    });

    test('detect 不抛出异常', () async {
      // Transport 诊断失败
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        lastError: 'Transport 异常', // 没有 isAvailable
      ));

      // 不应该抛出异常
      await provider.detect();
    });

    test('检测耗时大于等于 0', () async {
      final info = await provider.detect();
      expect(info.detectionDurationMs, greaterThanOrEqualTo(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 3. 环境变量
  // ═══════════════════════════════════════════════════════════════

  group('getEnvironment — 环境变量', () {
    test('Termux 可用时返回完整环境', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        packageInstalled: true,
        intentAvailable: true,
        works: true,
      ));
      fakeTransport.setEnvResult(const TermuxEnvResult(
        prefixPath: '/data/data/com.termux/files/usr',
        homePath: '/data/data/com.termux/files/home',
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
        pkgManager: TermuxPkgManager.pkg,
      ));

      final env = await provider.getEnvironment();

      expect(env['HOME'], '/data/data/com.termux/files/home');
      expect(env['PREFIX'], '/data/data/com.termux/files/usr');
      expect(env['PATH'], contains('/data/data/com.termux/files/usr/bin'));
      expect(env['SHELL'], '/data/data/com.termux/files/usr/bin/bash');
      expect(env['TMPDIR'], isNotEmpty);
      expect(env['LANG'], 'en_US.UTF-8');
      expect(env['LC_ALL'], 'en_US.UTF-8');
    });

    test('Termux 不可用时使用 appHome', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult());
      fakeTransport.setEnvResult(const TermuxEnvResult());

      final env = await provider.getEnvironment(appHome: '/data/app');

      // 使用 appHome 而不是硬编码路径
      expect(env['HOME'], '/data/app');
      expect(env['PREFIX'], isNull);
      expect(env['PATH'], contains('/system/bin'));
    });

    test('包含 TMPDIR/LANG/LC_ALL', () async {
      final env = await provider.getEnvironment();

      expect(env.containsKey('TMPDIR'), true);
      expect(env.containsKey('LANG'), true);
      expect(env.containsKey('LC_ALL'), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 4. 可执行文件解析
  // ═══════════════════════════════════════════════════════════════

  group('resolveExecutable — 可执行文件解析', () {
    test('存在时返回路径', () async {
      fakeTransport.setWhichResult('node',
          '/data/data/com.termux/files/usr/bin/node');

      final path = await provider.resolveExecutable('node');

      expect(path, '/data/data/com.termux/files/usr/bin/node');
    });

    test('不存在时返回 null', () async {
      fakeTransport.setWhichResult('python3', null);

      final path = await provider.resolveExecutable('python3');

      expect(path, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 5. Capability 检测
  // ═══════════════════════════════════════════════════════════════

  group('capabilities — 能力检测', () {
    test('Termux 可用时包含 termux 能力', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        packageInstalled: true,
        intentAvailable: true,
        works: true,
      ));
      fakeTransport.setEnvResult(const TermuxEnvResult(
        prefixPath: '/data/data/com.termux/files/usr',
      ));
      // which 返回一些可执行文件
      fakeTransport.setWhichResult('node', '/data/data/com.termux/files/usr/bin/node');
      fakeTransport.setWhichResult('git', '/data/data/com.termux/files/usr/bin/git');

      await provider.detect();
      final caps = provider.capabilities;

      // 必须包含 termux 能力
      expect(caps.any((c) => c.type == CapabilityType.termux), true);

      // node 和 git 应可用
      expect(caps.any((c) => c.type == CapabilityType.node && c.available), true);
      expect(caps.any((c) => c.type == CapabilityType.git && c.available), true);
    });

    test('只报告真实存在的工具', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        packageInstalled: true,
        intentAvailable: true,
        works: true,
      ));
      fakeTransport.setEnvResult(const TermuxEnvResult(
        prefixPath: '/data/data/com.termux/files/usr',
      ));
      // 只安装了 node 和 bash
      fakeTransport.setWhichResult('node', '/data/data/com.termux/files/usr/bin/node');
      fakeTransport.setWhichResult('bash', '/data/data/com.termux/files/usr/bin/bash');
      // 其他明确未找到（null）
      fakeTransport.setWhichResult('python3', null);
      fakeTransport.setWhichResult('git', null);
      fakeTransport.setWhichResult('npm', null);

      await provider.detect();
      final caps = provider.capabilities;

      // node 和 bash 应可用
      expect(caps.any((c) => c.type == CapabilityType.node && c.available), true);
      expect(caps.any((c) => c.type == CapabilityType.bash && c.available), true);

      // python/git/npm 等应不可用
      expect(caps.any((c) => c.type == CapabilityType.python && !c.available), true);
      expect(caps.any((c) => c.type == CapabilityType.git && !c.available), true);
      expect(caps.any((c) => c.type == CapabilityType.npm && !c.available), true);
    });

    test('Termux 不可用时只有 termux 能力', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult());

      await provider.detect();
      final caps = provider.capabilities;

      // 只有 termux 能力
      expect(caps.length, 1);
      expect(caps.first.type, CapabilityType.termux);
      expect(caps.first.available, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 6. 健康检查
  // ═══════════════════════════════════════════════════════════════

  group('healthCheck — 健康检查', () {
    test('Termux 可用时返回健康', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        packageInstalled: true,
        intentAvailable: true,
        works: true,
      ));

      final health = await provider.healthCheck();

      expect(health.healthy, true);
      expect(health.checks.length, 4);
      expect(health.checks.any((c) => c.name == 'Termux APK' && c.passed), true);
      expect(health.checks.any((c) => c.name == '命令执行' && c.passed), true);
    });

    test('Termux 不可用时不健康', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult());

      final health = await provider.healthCheck();

      expect(health.healthy, false);
      expect(health.checks.any((c) => c.name == 'Termux APK' && !c.passed), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 7. 命令执行（委托 Transport）
  // ═══════════════════════════════════════════════════════════════

  group('executeInTermux — 命令执行', () {
    test('委托给 Transport', () async {
      fakeTransport.setExecResult('echo hello', const TermuxExecResult(
        exitCode: 0,
        stdout: 'hello\n',
        usedTermux: true,
      ));

      final result = await provider.executeInTermux('echo hello');

      expect(result.exitCode, 0);
      expect(result.stdout, 'hello\n');
      expect(result.usedTermux, true);
    });

    test('记录已执行的命令', () async {
      await provider.executeInTermux('node --version');
      await provider.executeInTermux('git --version');

      expect(fakeTransport.executedCommands, contains('node --version'));
      expect(fakeTransport.executedCommands, contains('git --version'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 8. isAvailable
  // ═══════════════════════════════════════════════════════════════

  group('isAvailable — 可用性', () {
    test('Termux 可用时返回 true', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult(
        packageInstalled: true,
        intentAvailable: true,
        works: true,
      ));

      expect(await provider.isAvailable(), true);
    });

    test('Termux 不可用时返回 false', () async {
      fakeTransport.setDiagnoseResult(const TermuxDiagnosticResult());

      expect(await provider.isAvailable(), false);
    });
  });
}
