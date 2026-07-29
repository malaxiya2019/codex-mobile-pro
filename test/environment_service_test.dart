import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/detector/environment_service.dart';

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
    // 重置 Termux 缓存
    EnvironmentService.refreshTermuxStatus();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  group('TermuxEnvironmentCheck', () {
    test('默认构造函数正确', () {
      final check = TermuxEnvironmentCheck(
        termuxInstalled: true,
        hasTermuxHome: true,
        hasTermuxUsr: true,
        prefixPath: '/data/data/com.termux/files/usr',
        homePath: '/data/data/com.termux/files/home',
      );

      expect(check.termuxInstalled, true);
      expect(check.hasTermuxHome, true);
      expect(check.hasTermuxUsr, true);
      expect(check.prefixPath, '/data/data/com.termux/files/usr');
      expect(check.homePath, '/data/data/com.termux/files/home');
      expect(check.isTermuxAvailable, true);
    });

    test('isTermuxAvailable 需要 termuxInstalled', () {
      const check1 = TermuxEnvironmentCheck(
        termuxInstalled: true,
        hasTermuxHome: false,
        hasTermuxUsr: false,
      );
      expect(check1.isTermuxAvailable, true);

      const check2 = TermuxEnvironmentCheck(
        termuxInstalled: false,
        hasTermuxHome: false,
        hasTermuxUsr: false,
      );
      expect(check2.isTermuxAvailable, false);
    });

    test('const 构造函数可用', () {
      const check = TermuxEnvironmentCheck(
        termuxInstalled: false,
        hasTermuxHome: false,
        hasTermuxUsr: false,
      );
      expect(check, isA<TermuxEnvironmentCheck>());
    });
  });

  group('ShellCommandResult', () {
    test('成功结果正确', () {
      final result = ShellCommandResult(
        exitCode: 0,
        stdout: 'v22.0.0',
        stderr: '',
        durationMs: 100,
      );

      expect(result.isSuccess, true);
      expect(result.exitCode, 0);
      expect(result.stdout, 'v22.0.0');
      expect(result.stderr, '');
      expect(result.durationMs, 100);
    });

    test('失败结果正确', () {
      final result = ShellCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'command not found',
        durationMs: 50,
      );

      expect(result.isSuccess, false);
      expect(result.exitCode, 1);
      expect(result.stderr, 'command not found');
    });

    test('const 构造函数可用', () {
      const result = ShellCommandResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
        durationMs: 0,
      );
      expect(result, isA<ShellCommandResult>());
    });
  });

  group('EnvironmentService', () {
    test('isTermuxAvailable 返回 false 当 MethodChannel 未实现', () async {
      // 未设置 mock handler → catch 异常 → 返回 false
      final available = await EnvironmentService.isTermuxAvailable();
      expect(available, false);
    });

    test('isTermuxAvailable 返回 true 当 Termux 可用', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'checkEnvironment') {
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
          }
          return {'exitCode': 0, 'stdout': '', 'stderr': '', 'durationMs': 0, 'source': 'termux'};
        },
      );

      final available = await EnvironmentService.isTermuxAvailable();
      expect(available, true);
    });

    test('executeInTermux 返回结果', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          expect(methodCall.method, 'execute');
          return {
            'exitCode': 0,
            'stdout': 'hello_termux',
            'stderr': '',
            'durationMs': 42,
            'source': 'termux',
          };
        },
      );

      final result = await EnvironmentService.executeInTermux(
        command: 'echo "hello_termux"',
      );

      expect(result.isSuccess, true);
      expect(result.stdout, 'hello_termux');
      expect(result.exitCode, 0);
      expect(result.source, 'termux');
    });

    test('executeInTermux 失败命令返回非零退出码', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': 42,
            'stdout': '',
            'stderr': '',
            'durationMs': 10,
            'source': 'termux',
          };
        },
      );

      final result = await EnvironmentService.executeInTermux(
        command: 'exit 42',
      );

      expect(result.isSuccess, false);
      expect(result.exitCode, 42);
    });

    test('executeInTermux 执行时长大于 0', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': 0,
            'stdout': 'ok',
            'stderr': '',
            'durationMs': 15,
            'source': 'termux',
          };
        },
      );

      final result = await EnvironmentService.executeInTermux(
        command: 'echo "ok"',
      );

      expect(result.durationMs, greaterThanOrEqualTo(0));
    });

    test('detectTool 返回格式正确', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': 0,
            'stdout': 'tool_path\nv1.0.0',
            'stderr': '',
            'durationMs': 20,
            'source': 'termux',
          };
        },
      );

      final result = await EnvironmentService.detectTool(
        'echo "tool_path" && echo "v1.0.0"',
      );

      expect(result.isSuccess, true);
      expect(result.stdout, isNotEmpty);
    });

    test('detectTool 命令不存在时返回错误', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return {
            'exitCode': 127,
            'stdout': '',
            'stderr': 'command not found',
            'durationMs': 5,
            'source': 'system_sh',
          };
        },
      );

      final result = await EnvironmentService.detectTool(
        'nonexistent_command_xyz_123',
      );

      expect(result.stdout, isEmpty);
    });
  });
}
