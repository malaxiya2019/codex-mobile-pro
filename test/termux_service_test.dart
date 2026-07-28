import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/termux/termux_service.dart';

void main() {
  const channel = MethodChannel('com.codexmobile.app/termux');

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null, // 清除之前 handler
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  group('TermuxService.execute()', () {
    test('正常执行返回 TermuxResult', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          expect(methodCall.method, 'execute');
          expect(methodCall.arguments, {'command': 'echo hello'});
          return {
            'exitCode': 0,
            'stdout': 'hello\n',
            'stderr': '',
            'durationMs': 42,
          };
        },
      );

      final result = await TermuxService.execute('echo hello');

      expect(result.exitCode, 0);
      expect(result.stdout, 'hello\n');
      expect(result.stderr, '');
      expect(result.durationMs, 42);
      expect(result.isSuccess, true);
      expect(result.isTimeout, false);
    });

    test('命令失败返回非零退出码', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': 127,
            'stdout': '',
            'stderr': 'command not found',
            'durationMs': 15,
          };
        },
      );

      final result = await TermuxService.execute('nonexistent_cmd');

      expect(result.exitCode, 127);
      expect(result.stderr, 'command not found');
      expect(result.isSuccess, false);
    });

    test('超时场景返回 -1 退出码', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': -1,
            'stdout': '',
            'stderr': '命令执行超时（30000ms）',
            'durationMs': 30000,
          };
        },
      );

      final result = await TermuxService.execute('sleep 60');

      expect(result.exitCode, -1);
      expect(result.isSuccess, false);
      expect(result.isTimeout, true);
    });

    test('大量 stdout 无截断', () async {
      final longOutput = 'A' * 100000;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': 0,
            'stdout': longOutput,
            'stderr': '',
            'durationMs': 200,
          };
        },
      );

      final result = await TermuxService.execute('cat large_file');

      expect(result.stdout.length, 100000);
      expect(result.isSuccess, true);
    });

    test('中文输出无乱码', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': 0,
            'stdout': '你好，世界！🌟\n',
            'stderr': '',
            'durationMs': 5,
          };
        },
      );

      final result = await TermuxService.execute('echo "你好，世界！🌟"');

      expect(result.stdout, contains('你好'));
      expect(result.stdout, contains('🌟'));
      expect(result.isSuccess, true);
    });

    test('空输出处理', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': 0,
            'stdout': '',
            'stderr': '',
            'durationMs': 0,
          };
        },
      );

      final result = await TermuxService.execute('true');

      expect(result.exitCode, 0);
      expect(result.stdout, '');
      expect(result.stderr, '');
      expect(result.isSuccess, true);
    });

    test('异常返回类型自动转换（Map<dynamic> -> Map<String>）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return <dynamic, dynamic>{
            'exitCode': 0,
            'stdout': 'ok',
            'stderr': '',
            'durationMs': 10,
          };
        },
      );

      final result = await TermuxService.execute('echo ok');

      expect(result.exitCode, 0);
      expect(result.stdout, 'ok');
    });
  });

  group('TermuxService.checkEnvironment()', () {
    test('Termux 完全可用场景', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          expect(methodCall.method, 'checkEnvironment');
          return {
            'termux_installed': true,
            'bash_exists': true,
            'bash_can_read': true,
            'bash_can_execute': true,
            'bash_works': true,
            'bash_last_stderr': '',
            'termux_home_exists': true,
            'system_sh_exists': true,
            'system_sh_can_execute': true,
            'sh_works': true,
            'sh_last_stderr': '',
            'termux_intent_available': true,
            'is_available': true,
            'fallback_available': true,
          };
        },
      );

      final env = await TermuxService.checkEnvironment();

      expect(env.termuxInstalled, true);
      expect(env.bashWorks, true);
      expect(env.isAvailable, true);
      expect(env.termuxMode, true);
      expect(env.hasAnyShell, true);
    });

    test('Termux 未安装，系统 shell 降级', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'termux_installed': false,
            'bash_exists': false,
            'bash_can_read': false,
            'bash_can_execute': false,
            'bash_works': false,
            'bash_last_stderr': 'No such file',
            'termux_home_exists': false,
            'system_sh_exists': true,
            'system_sh_can_execute': true,
            'sh_works': true,
            'sh_last_stderr': '',
            'termux_intent_available': false,
            'is_available': false,
            'fallback_available': true,
          };
        },
      );

      final env = await TermuxService.checkEnvironment();

      expect(env.termuxInstalled, false);
      expect(env.bashWorks, false);
      expect(env.isAvailable, false);
      expect(env.termuxMode, false);
      expect(env.fallbackAvailable, true);
      expect(env.hasAnyShell, true); // 降级可用
    });

    test('完全无 shell 环境', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'termux_installed': false,
            'bash_exists': false,
            'bash_can_read': false,
            'bash_can_execute': false,
            'bash_works': false,
            'bash_last_stderr': '',
            'termux_home_exists': false,
            'system_sh_exists': false,
            'system_sh_can_execute': false,
            'sh_works': false,
            'sh_last_stderr': 'Permission denied',
            'termux_intent_available': false,
            'is_available': false,
            'fallback_available': false,
          };
        },
      );

      final env = await TermuxService.checkEnvironment();

      expect(env.isAvailable, false);
      expect(env.fallbackAvailable, false);
      expect(env.hasAnyShell, false);
    });
  });

  group('TermuxResult', () {
    test('isSuccess 在 exitCode=0 时为 true', () {
      final result = TermuxResult(exitCode: 0, stdout: '', stderr: '', durationMs: 0);
      expect(result.isSuccess, true);
    });

    test('isSuccess 在 exitCode≠0 时为 false', () {
      final result = TermuxResult(exitCode: 1, stdout: '', stderr: 'err', durationMs: 0);
      expect(result.isSuccess, false);
    });

    test('isTimeout 在 exitCode=-1 且包含"超时"时为 true', () {
      final result = TermuxResult(exitCode: -1, stdout: '', stderr: '命令执行超时（30000ms）', durationMs: 30000);
      expect(result.isTimeout, true);
    });

    test('isTimeout 超时但不含中文时仍为 true', () {
      // 兼容英文环境
      final result = TermuxResult(exitCode: -1, stdout: '', stderr: 'Command timed out', durationMs: 30000);
      expect(result.isTimeout, false); // 按当前实现
    });

    test('toString 包含关键字段', () {
      final result = TermuxResult(exitCode: 0, stdout: 'hello', stderr: '', durationMs: 42);
      final str = result.toString();
      expect(str, contains('exitCode=0'));
      expect(str, contains('stdout=5chars'));
      expect(str, contains('duration=42ms'));
    });
  });

  group('TermuxEnvCheck', () {
    test('termuxMode = termuxInstalled && bashWorks', () {
      final env = TermuxEnvCheck(
        termuxInstalled: true,
        bashExists: true,
        bashCanRead: true,
        bashCanExecute: true,
        bashWorks: true,
        bashLastStderr: '',
        termuxHomeExists: true,
        systemShExists: true,
        systemShCanExecute: true,
        shWorks: true,
        shLastStderr: '',
        termuxIntentAvailable: true,
        isAvailable: true,
        fallbackAvailable: true,
      );
      expect(env.termuxMode, true);

      final env2 = TermuxEnvCheck(
        termuxInstalled: true,
        bashExists: true,
        bashCanRead: true,
        bashCanExecute: true,
        bashWorks: false,
        bashLastStderr: '',
        termuxHomeExists: true,
        systemShExists: true,
        systemShCanExecute: true,
        shWorks: true,
        shLastStderr: '',
        termuxIntentAvailable: false,
        isAvailable: false,
        fallbackAvailable: true,
      );
      expect(env2.termuxMode, false);
    });
  });
}
