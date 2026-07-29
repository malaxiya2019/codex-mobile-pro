import 'package:codex_mobile_pro/core/termux/shell_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellInfo', () {
    test('默认构造使用系统 Shell（兜底）', () {
      const info = ShellInfo();

      expect(info.type, ShellType.systemSh);
      expect(info.shellPath, '/system/bin/sh');
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, false);
      expect(info.friendlyDescription, 'Android 系统 Shell');
      expect(info.launchArgs, ['-i']);
      expect(info.useRunInShell, false);
    });

    test('Termux Bash ShellInfo 正确', () {
      const info = ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
        version: 'Termux Bash',
        isTermuxAvailable: true,
      );

      expect(info.type, ShellType.termuxBash);
      expect(info.shellPath, '/data/data/com.termux/files/usr/bin/bash');
      expect(info.isTermuxBash, true);
      expect(info.isTermuxAvailable, true);
      expect(info.friendlyDescription, 'Termux Bash（完整 Linux 环境）');
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

    test('termuxSh 类型正确', () {
      const info = ShellInfo(
        type: ShellType.termuxSh,
        shellPath: '/data/data/com.termux/files/usr/bin/sh',
        version: 'Termux sh',
      );

      expect(info.type, ShellType.termuxSh);
      expect(info.shellPath, '/data/data/com.termux/files/usr/bin/sh');
      expect(info.friendlyDescription, 'Termux SH（兼容模式）');
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

    test('getShellEnvironment 无 shellInfo 返回系统环境', () {
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

    test('getShellEnvironment 传入 Termux ShellInfo 返回 Termux 环境', () {
      const shellInfo = ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
        isTermuxAvailable: true,
      );
      final env = ShellDetector.getShellEnvironment(
        '/data/app/home',
        shellInfo: shellInfo,
      );

      expect(env['HOME'], '/data/data/com.termux/files/home');
      expect(env['PATH'], contains('/data/data/com.termux/files/usr/bin'));
      expect(env['SHELL'], '/data/data/com.termux/files/usr/bin/bash');
      expect(env['PREFIX'], '/data/data/com.termux/files/usr');
      expect(env['TMPDIR'], '/data/data/com.termux/files/usr/tmp');
    });

    test('getShellEnvironment 传入非 Termux ShellInfo 返回系统环境', () {
      const shellInfo = ShellInfo(); // 默认 systemSh，isTermuxAvailable=false
      final env = ShellDetector.getShellEnvironment(
        '/data/app/home',
        shellInfo: shellInfo,
      );

      expect(env['HOME'], '/data/app/home');
      expect(env['PATH'], '/system/bin:/system/xbin');
      expect(env['SHELL'], '/system/bin/sh');
    });
  });
}
