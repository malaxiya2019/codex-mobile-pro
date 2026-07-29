import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/termux/shell_detector.dart';

void main() {
  group('ShellInfo', () {
    test('默认构造使用系统 Shell', () {
      const info = ShellInfo();

      expect(info.type, ShellType.systemSh);
      expect(info.shellPath, '/system/bin/sh');
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, false);
      expect(info.isTermuxAccessible, false);
      expect(info.friendlyDescription, 'Android 系统 Shell');
      expect(info.launchArgs, ['-i']);
      expect(info.useRunInShell, false);
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
  });

  group('ShellDetector', () {
    test('detect 始终返回 Android 系统 Shell', () async {
      final shell = await ShellDetector.detect();

      expect(shell.isAvailable, true);
      expect(shell.shellPath, '/system/bin/sh');
      expect(shell.type, ShellType.systemSh);
      expect(shell.friendlyDescription, 'Android 系统 Shell');
    });

    test('getShellEnvironment 返回基础环境变量', () {
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
  });
}
