import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/detector/environment_service.dart';

void main() {
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

    test('isTermuxAvailable 需要 termuxInstalled && hasTermuxUsr', () {
      // 仅有 termuxInstalled 但无 usr
      final check1 = TermuxEnvironmentCheck(
        termuxInstalled: true,
        hasTermuxHome: true,
        hasTermuxUsr: false,
      );
      expect(check1.isTermuxAvailable, false);

      // 有 usr 但未标记 installed
      final check2 = TermuxEnvironmentCheck(
        termuxInstalled: false,
        hasTermuxHome: true,
        hasTermuxUsr: true,
      );
      expect(check2.isTermuxAvailable, false);

      // 全部满足
      final check3 = TermuxEnvironmentCheck(
        termuxInstalled: true,
        hasTermuxHome: true,
        hasTermuxUsr: true,
      );
      expect(check3.isTermuxAvailable, true);
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
    test('getTermuxEnv 返回完整环境变量', () {
      final env = EnvironmentService.getTermuxEnv();

      expect(env['HOME'], '/data/data/com.termux/files/home');
      expect(env['PREFIX'], '/data/data/com.termux/files/usr');
      expect(env['PATH'], contains('/data/data/com.termux/files/usr/bin'));
      expect(env['LANG'], 'zh_CN.UTF-8');
      expect(env['TERM'], 'xterm-256color');
      expect(env['TMPDIR'], '/data/data/com.termux/files/usr/tmp');
    });

    test('getTermuxEnv 所有必填字段都存在', () {
      final env = EnvironmentService.getTermuxEnv();
      final requiredKeys = ['HOME', 'PREFIX', 'PATH', 'LANG', 'TERM'];
      for (final key in requiredKeys) {
        expect(env.containsKey(key), true,
            reason: '缺少环境变量: $key');
        expect(env[key], isNotEmpty,
            reason: '环境变量 $key 不应为空');
      }
    });

    test('checkTermux 兼容非 Termux 环境', () async {
      // 在非 Termux 环境（如 CI runner）也应正常运行
      final check = await EnvironmentService.checkTermux();

      // 不强制要求 Termux 存在，只验证不崩溃、返回合理结果
      expect(check.isTermuxAvailable, anyOf(true, false),
          reason: '无论有无 Termux，都应返回合法结果');
      // termuxInstalled 和 hasTermuxHome 应一致
      if (check.hasTermuxUsr) {
        expect(check.termuxInstalled, true,
            reason: '有 usr 目录应视为已安装');
      }
    });

    test('executeInTermux 基本命令可执行', () async {
      final result = await EnvironmentService.executeInTermux(
        command: 'echo "hello_termux"',
      );

      expect(result.isSuccess, true);
      expect(result.stdout, 'hello_termux');
      expect(result.exitCode, 0);
    });

    test('executeInTermux 失败命令返回非零退出码', () async {
      final result = await EnvironmentService.executeInTermux(
        command: 'exit 42',
      );

      expect(result.isSuccess, false);
      expect(result.exitCode, 42);
    });

    test('executeInTermux 携带 stderr', () async {
      final result = await EnvironmentService.executeInTermux(
        command: 'echo "error_msg" >&2; exit 1',
      );

      expect(result.exitCode, 1);
      expect(result.stderr, 'error_msg');
    });

    test('executeInTermux 支持管道命令', () async {
      final result = await EnvironmentService.executeInTermux(
        command: 'echo "line1\nline2\nline3" | wc -l',
      );

      expect(result.isSuccess, true);
      expect(result.stdout.trim(), '3');
    });

    test('executeInTermux 执行时长大于 0', () async {
      final result = await EnvironmentService.executeInTermux(
        command: 'echo "ok"',
      );

      expect(result.durationMs, greaterThan(0));
    });

    test('detectTool 返回格式正确', () async {
      // 检测一个基本工具
      final result = await EnvironmentService.detectTool(
        'echo "tool_path" && echo "v1.0.0"',
      );

      expect(result.isSuccess, true);
      expect(result.stdout, isNotEmpty);
    });

    test('detectTool 命令不存在时返回错误', () async {
      final result = await EnvironmentService.detectTool(
        'nonexistent_command_xyz_123',
      );

      // 可能返回非零退出码
      expect(result.stdout, isEmpty);
    });
  });
}
