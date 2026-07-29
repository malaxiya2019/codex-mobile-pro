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
      null,
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
            'source': 'termux',
          };
        },
      );

      final result = await TermuxService.execute('echo hello');

      expect(result.exitCode, 0);
      expect(result.stdout, 'hello\n');
      expect(result.stderr, '');
      expect(result.durationMs, 42);
      expect(result.isSuccess, true);
      expect(result.source, 'termux');
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
            'source': 'system_sh',
          };
        },
      );

      final result = await TermuxService.execute('nonexistent_cmd');

      expect(result.exitCode, 127);
      expect(result.stderr, 'command not found');
      expect(result.isSuccess, false);
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
            'source': 'termux',
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
            'source': 'termux',
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
            'source': 'system_sh',
          };
        },
      );

      final result = await TermuxService.execute('true');

      expect(result.exitCode, 0);
      expect(result.stdout, '');
      expect(result.stderr, '');
      expect(result.isSuccess, true);
    });

    test('异常返回类型自动转换', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return <dynamic, dynamic>{
            'exitCode': 0,
            'stdout': 'ok',
            'stderr': '',
            'durationMs': 10,
            'source': 'termux',
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
            'termux_intent_available': true,
            'termux_works': true,
            'termux_last_stderr': '',
            'sh_works': true,
            'sh_last_stderr': '',
            'is_available': true,
            'fallback_available': true,
          };
        },
      );

      final env = await TermuxService.checkEnvironment();

      expect(env.termuxInstalled, true);
      expect(env.termuxWorks, true);
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
            'termux_intent_available': false,
            'termux_works': false,
            'termux_last_stderr': 'No such file',
            'sh_works': true,
            'sh_last_stderr': '',
            'is_available': false,
            'fallback_available': true,
          };
        },
      );

      final env = await TermuxService.checkEnvironment();

      expect(env.termuxInstalled, false);
      expect(env.termuxWorks, false);
      expect(env.isAvailable, false);
      expect(env.termuxMode, false);
      expect(env.fallbackAvailable, true);
      expect(env.hasAnyShell, true);
    });

    test('完全无 shell 环境', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'termux_installed': false,
            'termux_intent_available': false,
            'termux_works': false,
            'termux_last_stderr': '',
            'sh_works': false,
            'sh_last_stderr': 'Permission denied',
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

    test('toString 包含关键字段', () {
      final result = TermuxResult(exitCode: 0, stdout: 'hello', stderr: '', durationMs: 42);
      final str = result.toString();
      expect(str, contains('exitCode=0'));
      expect(str, contains('stdout=5chars'));
      expect(str, contains('duration=42ms'));
    });
  });

  group('TermuxEnvCheck', () {
    test('termuxMode = termuxInstalled && (termuxWorks || termuxIntentAvailable)', () {
      final env = TermuxEnvCheck(
        termuxInstalled: true,
        termuxIntentAvailable: true,
        termuxWorks: true,
        shWorks: true,
        isAvailable: true,
        fallbackAvailable: true,
      );
      expect(env.termuxMode, true);

      final env2 = TermuxEnvCheck(
        termuxInstalled: true,
        termuxIntentAvailable: false,
        termuxWorks: false,
        shWorks: true,
        isAvailable: false,
        fallbackAvailable: true,
      );
      expect(env2.termuxMode, false);
    });
  });
}
