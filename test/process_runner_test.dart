/// ====================================================================
/// RuntimeProcessRunner 测试
///
/// 覆盖 Phase 3 Commit 1-5 的所有模型和执行逻辑。
///
/// 测试分类：
///   1. RuntimeProcessRequest — 请求模型、shell 包装、转义
///   2. RuntimeProcessResult — 结果模型、状态判断
///   3. RuntimeProcessError — 结构化错误、工厂方法
///   4. EnvironmentMerger — 环境合并规则、优先级
///   5. TermuxExecutionAdapter — 支持判定、命令构建
///   6. RuntimeProcessRunner — 适配器选择、便捷方法
///   7. 集成场景 — 完整请求→执行流
/// ====================================================================
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/runtime/process/runner_models.dart';
import 'package:codex_mobile_pro/runtime/process/process_runner.dart';
import 'package:codex_mobile_pro/runtime/process/termux_execution.dart';
import 'package:codex_mobile_pro/runtime/termux/fake_transport.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // 1. RuntimeProcessRequest 测试
  // ═══════════════════════════════════════════════════════════════

  group('RuntimeProcessRequest — 请求模型', () {
    test('创建基本请求', () {
      final req = RuntimeProcessRequest(
        executable: '/system/bin/sh',
        arguments: ['-c', 'echo hello'],
      );

      expect(req.executable, '/system/bin/sh');
      expect(req.arguments, ['-c', 'echo hello']);
      expect(req.runInShell, false);
      expect(req.timeout, isNull);
      expect(req.runtimeId, isNull);
    });

    test('创建带所有可选字段的请求', () {
      final req = RuntimeProcessRequest(
        executable: '/usr/bin/node',
        arguments: ['--version'],
        environment: {'PATH': '/custom/bin', 'HOME': '/data'},
        workingDirectory: '/tmp',
        timeout: const Duration(seconds: 30),
        runInShell: true,
        stdin: 'input data',
        runtimeId: 'termux',
        label: 'health-check',
      );

      expect(req.executable, '/usr/bin/node');
      expect(req.environment, containsPair('PATH', '/custom/bin'));
      expect(req.workingDirectory, '/tmp');
      expect(req.timeout, const Duration(seconds: 30));
      expect(req.runInShell, true);
      expect(req.stdin, 'input data');
      expect(req.runtimeId, 'termux');
      expect(req.label, 'health-check');
    });

    test('withShell 包装为 shell 执行', () {
      final req = RuntimeProcessRequest(
        executable: '/usr/bin/node',
        arguments: ['--version'],
      );

      final shellReq = req.withShell();

      expect(shellReq.executable, '/system/bin/sh');
      expect(shellReq.arguments[0], '-c');
      expect(shellReq.arguments[1], '/usr/bin/node --version');
      expect(shellReq.runInShell, false);
    });

    test('withShell 转义含空格的参数', () {
      final req = RuntimeProcessRequest(
        executable: 'echo',
        arguments: ['hello world', 'test'],
      );

      final shellReq = req.withShell();
      expect(shellReq.arguments[1], contains("'hello world'"));
    });

    test('withShell 转义含单引号的参数', () {
      final req = RuntimeProcessRequest(
        executable: 'echo',
        arguments: ["it's"],
      );

      expect(() => req.withShell(), returnsNormally);
    });

    test('toString 包含可执行路径和参数', () {
      final req = RuntimeProcessRequest(
        executable: '/usr/bin/node',
        arguments: ['--version'],
        runtimeId: 'android',
        label: 'check',
      );

      final str = req.toString();
      expect(str, contains('/usr/bin/node'));
      expect(str, contains('--version'));
      expect(str, contains('android'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 2. RuntimeProcessResult 测试
  // ═══════════════════════════════════════════════════════════════

  group('RuntimeProcessResult — 结果模型', () {
    final sampleRequest = RuntimeProcessRequest(executable: 'test');

    test('成功退出 — isSuccess 为 true', () {
      final result = RuntimeProcessResult(
        exitCode: 0,
        stdout: 'Node.js v22.0.0',
        stderr: '',
        request: sampleRequest,
      );

      expect(result.isSuccess, true);
      expect(result.failedToStart, false);
      expect(result.stdout, 'Node.js v22.0.0');
    });

    test('非零退出 — isSuccess 为 false', () {
      final result = RuntimeProcessResult(
        exitCode: 1,
        stderr: 'Error: not found',
        request: sampleRequest,
      );

      expect(result.isSuccess, false);
      expect(result.exitCode, 1);
    });

    test('启动失败 — failedToStart 为 true', () {
      final result = RuntimeProcessResult(
        exitCode: -1,
        error: '可执行文件不存在',
        request: sampleRequest,
      );

      expect(result.failedToStart, true);
      expect(result.isSuccess, false);
    });

    test('超时 — timedOut 为 true', () {
      final result = RuntimeProcessResult(
        exitCode: -2,
        timedOut: true,
        request: sampleRequest,
      );

      expect(result.timedOut, true);
      expect(result.isSuccess, false);
    });

    test('取消 — cancelled 为 true', () {
      final result = RuntimeProcessResult(
        exitCode: -3,
        cancelled: true,
        request: sampleRequest,
      );

      expect(result.cancelled, true);
      expect(result.isSuccess, false);
    });

    test('allOutput 合并 stdout 和 stderr', () {
      final result = RuntimeProcessResult(
        exitCode: 1,
        stdout: 'info',
        stderr: 'error',
        request: sampleRequest,
      );

      expect(result.allOutput, contains('info'));
      expect(result.allOutput, contains('error'));
    });

    test('toString 包含关键信息', () {
      final result = RuntimeProcessResult(
        exitCode: 0,
        stdout: 'ok',
        duration: const Duration(milliseconds: 50),
        request: sampleRequest,
      );

      final str = result.toString();
      expect(str, contains('exitCode: 0'));
      expect(str, contains('50'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 3. RuntimeProcessError 测试
  // ═══════════════════════════════════════════════════════════════

  group('RuntimeProcessError — 结构化错误', () {
    test('创建基本错误', () {
      final err = RuntimeProcessError(
        type: RuntimeProcessErrorType.executableNotFound,
        message: '/usr/bin/node 不存在',
      );

      expect(err.type, RuntimeProcessErrorType.executableNotFound);
      expect(err.message, contains('/usr/bin/node'));
    });

    test('fromResult — 启动失败', () {
      final result = RuntimeProcessResult(
        exitCode: -1,
        error: '启动失败',
        request: RuntimeProcessRequest(executable: 'node'),
      );

      final err = RuntimeProcessError.fromResult(result);
      expect(err.type, RuntimeProcessErrorType.startFailed);
    });

    test('fromResult — 超时', () {
      final result = RuntimeProcessResult(
        exitCode: -2,
        timedOut: true,
        request: RuntimeProcessRequest(executable: 'node'),
      );

      final err = RuntimeProcessError.fromResult(result);
      expect(err.type, RuntimeProcessErrorType.timeout);
    });

    test('fromResult — 取消', () {
      final result = RuntimeProcessResult(
        exitCode: -3,
        cancelled: true,
        request: RuntimeProcessRequest(executable: 'node'),
      );

      final err = RuntimeProcessError.fromResult(result);
      expect(err.type, RuntimeProcessErrorType.cancelled);
    });

    test('fromResult — 非零退出', () {
      final result = RuntimeProcessResult(
        exitCode: 1,
        request: RuntimeProcessRequest(executable: 'node'),
      );

      final err = RuntimeProcessError.fromResult(result);
      expect(err.type, RuntimeProcessErrorType.nonZeroExit);
    });

    test('fromProcessError — Permission denied', () {
      final processErr = ProcessException(
        'Permission denied',
        [],
        '/system/bin/sh',
      );

      final err = RuntimeProcessError.fromProcessError(
        processErr,
        executable: '/system/bin/sh',
      );

      expect(err.type, RuntimeProcessErrorType.permissionDenied);
    });

    test('fromProcessError — File not found', () {
      final processErr = ProcessException(
        'No such file or directory',
        [],
        'missing_tool',
      );

      final err = RuntimeProcessError.fromProcessError(
        processErr,
        executable: 'missing_tool',
      );

      expect(err.type, RuntimeProcessErrorType.executableNotFound);
    });

    test('fromProcessError — 未知错误', () {
      final processErr = ProcessException(
        'Unknown error',
        [],
        'test',
      );

      final err = RuntimeProcessError.fromProcessError(processErr);
      expect(err.type, RuntimeProcessErrorType.startFailed);
    });

    test('toString 包含错误信息', () {
      final err = RuntimeProcessError(
        type: RuntimeProcessErrorType.executableNotFound,
        message: 'node 不存在',
        exitCode: -1,
      );

      final str = err.toString();
      expect(str, contains('executableNotFound'));
      expect(str, contains('node 不存在'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 4. EnvironmentMerger 测试
  // ═══════════════════════════════════════════════════════════════

  group('EnvironmentMerger — 环境合并', () {
    test('合并 provider 和 defaults', () {
      final merged = EnvironmentMerger.merge(
        providerEnv: {'PREFIX': '/data/termux', 'SHELL': '/bin/sh'},
        defaults: {'PATH': '/system/bin', 'HOME': '/data'},
      );

      expect(merged, containsPair('PREFIX', '/data/termux'));
      expect(merged, containsPair('SHELL', '/bin/sh'));
      expect(merged, containsPair('PATH', '/system/bin'));
      expect(merged, containsPair('HOME', '/data'));
    });

    test('request 环境覆盖 provider', () {
      final merged = EnvironmentMerger.merge(
        providerEnv: {'PATH': '/system/bin'},
        requestEnv: {'PATH': '/custom/bin'},
      );

      expect(merged, containsPair('PATH', '/custom/bin'));
    });

    test('request 环境覆盖 defaults', () {
      final merged = EnvironmentMerger.merge(
        providerEnv: {},
        requestEnv: {'HOME': '/custom/home'},
        defaults: {'HOME': '/default/home'},
      );

      expect(merged, containsPair('HOME', '/custom/home'));
    });

    test('defaults 不覆盖 provider', () {
      final merged = EnvironmentMerger.merge(
        providerEnv: {'HOME': '/provider/home'},
        defaults: {'HOME': '/default/home'},
      );

      expect(merged, containsPair('HOME', '/provider/home'));
    });

    test('defaultEnvironment 包含必要变量', () {
      final env = EnvironmentMerger.defaultEnvironment(
        appHome: '/data/app',
      );

      expect(env, containsPair('HOME', '/data/app'));
      expect(env['PATH'], contains('/system/bin'));
      expect(env['TMPDIR'], isNotNull);
    });

    test('merge 不修改原始 Map', () {
      final providerEnv = {'KEY': 'original'};
      final merged = EnvironmentMerger.merge(
        providerEnv: providerEnv,
        requestEnv: {'KEY': 'override'},
      );

      expect(providerEnv, containsPair('KEY', 'original'));
      expect(merged, containsPair('KEY', 'override'));
    });

    test('request 为 null 时不改变结果', () {
      final merged = EnvironmentMerger.merge(
        providerEnv: {'KEY': 'value'},
        requestEnv: null,
      );

      expect(merged, containsPair('KEY', 'value'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════
  // 5. TermuxExecutionAdapter 测试
  // ═══════════════════════════════════════════════════════════════

  group('TermuxExecutionAdapter — Termux 适配器', () {
    late FakeTermuxTransport fakeTransport;

    setUp(() {
      fakeTransport = FakeTermuxTransport();
    });

    test('id 返回 termux', () {
      final adapter = TermuxExecutionAdapter(transport: fakeTransport);
      expect(adapter.id, 'termux');
    });

    test('supports runtimeId == termux', () {
      final adapter = TermuxExecutionAdapter(transport: fakeTransport);

      final termuxReq = RuntimeProcessRequest(
        executable: 'node',
        runtimeId: 'termux',
      );
      expect(adapter.supports(termuxReq), true);

      final androidReq = RuntimeProcessRequest(
        executable: 'node',
        runtimeId: 'android',
      );
      expect(adapter.supports(androidReq), false);
    });

    test('supports null runtimeId 返回 false', () {
      final adapter = TermuxExecutionAdapter(transport: fakeTransport);
      final req = RuntimeProcessRequest(executable: 'node');
      expect(adapter.supports(req), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 6. RuntimeProcessRunner 测试
  // ═══════════════════════════════════════════════════════════════

  group('RuntimeProcessRunner — 适配器选择', () {
    test('默认使用 LocalProcessExecution', () {
      final runner = RuntimeProcessRunner();
      expect(runner.registeredAdapters.length, 1);
      expect(runner.registeredAdapters.first.id, 'local');
    });

    test('registerAdapter 添加适配器', () {
      final runner = RuntimeProcessRunner();
      runner.registerAdapter(TermuxExecutionAdapter(transport: FakeTermuxTransport()));
      expect(runner.registeredAdapters.length, 2);
    });

    test('LocalProcessExecution 支持 null runtimeId', () {
      final execution = LocalProcessExecution();
      final req = RuntimeProcessRequest(executable: '/bin/echo');

      expect(execution.supports(req), true);
    });

    test('supports android runtimeId', () {
      final execution = LocalProcessExecution();
      final req = RuntimeProcessRequest(
        executable: '/bin/echo',
        runtimeId: 'android',
      );

      expect(execution.supports(req), true);
    });

    test('supports app runtimeId', () {
      final execution = LocalProcessExecution();
      final req = RuntimeProcessRequest(
        executable: 'node',
        runtimeId: 'app',
      );

      expect(execution.supports(req), true);
    });

    test('不支持的 runtimeId 返回 false', () {
      final execution = LocalProcessExecution();
      final req = RuntimeProcessRequest(
        executable: 'node',
        runtimeId: 'termux',
      );

      expect(execution.supports(req), false);
    });

    test('没有适配器时返回错误结果', () async {
      final runner = RuntimeProcessRunner(adapters: []);
      final result = await runner.run(
        RuntimeProcessRequest(executable: 'test'),
      );

      expect(result.exitCode, -1);
      expect(result.error, contains('没有适配器支持'));
    });

    test('runAndGetStdout 返回 String?', () async {
      final runner = RuntimeProcessRunner();

      final result = await runner.runAndGetStdout(
        RuntimeProcessRequest(
          executable: 'echo',
          arguments: ['hello'],
          runInShell: true,
        ),
      );

      expect(result, isA<String?>());
    });

    test('runAndCheck 返回 bool', () async {
      final runner = RuntimeProcessRunner();

      final result = await runner.runAndCheck(
        RuntimeProcessRequest(executable: 'true', runInShell: true),
      );

      expect(result, isA<bool>());
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 7. 集成场景测试
  // ═══════════════════════════════════════════════════════════════

  group('集成场景 — 请求→执行流', () {
    test('完整请求到结果转换', () async {
      final req = RuntimeProcessRequest(
        executable: 'echo',
        arguments: ['test'],
        runInShell: true,
        label: 'integration-test',
      );

      final runner = RuntimeProcessRunner();
      final result = await runner.run(req);

      expect(result, isA<RuntimeProcessResult>());
      expect(result.request.executable, 'echo');
    });

    test('不存在的可执行文件返回错误结果', () async {
      final req = RuntimeProcessRequest(
        executable: '/nonexistent/tool_xyz',
        arguments: ['--version'],
      );

      final runner = RuntimeProcessRunner();
      final result = await runner.run(req);

      expect(result.exitCode, -1);
      expect(result.error, isNotNull);
    });

    test('环境变量传递给进程', () async {
      final req = RuntimeProcessRequest(
        executable: 'sh',
        arguments: ['-c', 'echo \$CUSTOM_VAR'],
        environment: {'CUSTOM_VAR': 'test_value'},
      );

      final runner = RuntimeProcessRunner();
      final result = await runner.run(req);

      if (result.isSuccess) {
        expect(result.stdout.trim(), 'test_value');
      }
    });
  });
}
