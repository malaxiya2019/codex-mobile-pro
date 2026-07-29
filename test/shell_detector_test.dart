import 'package:codex_mobile_pro/core/termux/shell_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellInfo', () {
    test('默认构造使用系统 Shell（兜底）', () {
      const info = ShellInfo();

      expect(info.type, ShellType.systemSh);
      expect(info.shellPath, '/system/bin/sh');
      expect(info.isAvailable, true);
      expect(info.friendlyDescription, 'Android 系统 Shell');
      expect(info.launchArgs, ['-i']);
      expect(info.useRunInShell, false);
    });

    test('自定义 Shell 信息正确', () {
      const info = ShellInfo(
        type: ShellType.systemSh,
        shellPath: '/system/bin/sh',
        version: 'sh (Android 10)',
        isTermuxAvailable: false,
      );

      expect(info.type, ShellType.systemSh);
      expect(info.shellPath, '/system/bin/sh');
      expect(info.isTermuxAvailable, false);
    });

    test('toString 包含完整信息', () {
      const info = ShellInfo();
      final str = info.toString();
      expect(str, contains('systemSh'));
      expect(str, contains('/system/bin/sh'));
    });

    test('const 构造函数可用', () {
      const info = ShellInfo(
        type: ShellType.systemSh,
        shellPath: '/system/bin/sh',
      );
      expect(info, isA<ShellInfo>());
    });

    test('版本号可设置', () {
      const info = ShellInfo(version: 'sh (Android 10)');
      expect(info.version, 'sh (Android 10)');
    });

    test('isTermuxAvailable 默认 false', () {
      const info = ShellInfo();
      expect(info.isTermuxAvailable, false);
    });

    test('shellPath 可通过构造设置', () {
      const info = ShellInfo(shellPath: '/custom/shell');
      expect(info.shellPath, '/custom/shell');
    });
  });

  group('ShellDetector', () {
    test('detect 在测试环境中返回系统 Shell（MethodChannel 不可用）', () async {
      final shell = await ShellDetector.detect();

      // TermuxService.checkEnvironment 在测试中会抛出 MissingPluginException，
      // 因此降级到系统 Shell
      expect(shell.isAvailable, true);
      expect(shell.type, ShellType.systemSh);
      expect(shell.shellPath, '/system/bin/sh');
      expect(shell.isTermuxAvailable, false);
    });

    test('getShellEnvironment 返回系统环境', () {
      final env = ShellDetector.getShellEnvironment('/data/app/home');

      expect(env['HOME'], '/data/app/home');
      expect(env['PATH'], '/system/bin:/system/xbin');
      expect(env['TERM'], 'xterm-256color');
      expect(env['SHELL'], '/system/bin/sh');
    });

    test('getShellEnvironment 可以设置不同路径', () {
      final env = ShellDetector.getShellEnvironment('/custom/path');

      expect(env['HOME'], '/custom/path');
      expect(env['PATH'], '/system/bin:/system/xbin');
    });

    test('getShellEnvironment 返回的环境变量包含所有必需键', () {
      final env = ShellDetector.getShellEnvironment('/data/app/home');

      expect(env.keys, containsAll(<String>['HOME', 'PATH', 'TERM', 'SHELL']));
    });

    test('getShellEnvironment TERM 默认为 xterm-256color', () {
      final env = ShellDetector.getShellEnvironment('/home');

      expect(env['TERM'], 'xterm-256color');
    });

    test('getShellEnvironment SHELL 默认为 /system/bin/sh', () {
      final env = ShellDetector.getShellEnvironment('/home');

      expect(env['SHELL'], '/system/bin/sh');
    });
  });
}
