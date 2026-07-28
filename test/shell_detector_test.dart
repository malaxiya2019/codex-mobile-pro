import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/termux/shell_detector.dart';

void main() {
  group('ShellInfo', () {
    test('Termux Bash 信息正确', () {
      final info = ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
        version: 'GNU bash, version 5.2.26(1)-release',
        isTermuxAccessible: true,
      );

      expect(info.type, ShellType.termuxBash);
      expect(info.shellPath, '/data/data/com.termux/files/usr/bin/bash');
      expect(info.version, contains('GNU bash'));
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, true);
      expect(info.friendlyDescription, 'Termux Bash');
      expect(info.launchArgs, isEmpty);
      expect(info.useRunInShell, false);
    });

    test('Android System Shell 信息正确', () {
      final info = ShellInfo(
        type: ShellType.systemSh,
        shellPath: '/system/bin/sh',
      );

      expect(info.type, ShellType.systemSh);
      expect(info.shellPath, '/system/bin/sh');
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, false);
      expect(info.isTermuxAccessible, false);
      expect(info.friendlyDescription, 'Android 系统 Shell');
      expect(info.launchArgs, isEmpty);
      expect(info.useRunInShell, false);
    });

    test('Unknown Shell 信息正确', () {
      const info = ShellInfo(
        type: ShellType.unknown,
        shellPath: '',
      );

      expect(info.type, ShellType.unknown);
      expect(info.isAvailable, false);
      expect(info.isTermuxBash, false);
      expect(info.friendlyDescription, '无可用 Shell');
    });

    test('ShellType 枚举值正确', () {
      expect(ShellType.values.length, 3);
      expect(ShellType.values, contains(ShellType.termuxBash));
      expect(ShellType.values, contains(ShellType.systemSh));
      expect(ShellType.values, contains(ShellType.unknown));
    });

    test('toString 包含完整信息', () {
      final info = ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
        version: '5.2.26',
        isTermuxAccessible: true,
      );

      final str = info.toString();
      expect(str, contains('termuxBash'));
      expect(str, contains('/data/data/com.termux/files/usr/bin/bash'));
      expect(str, contains('5.2.26'));
      expect(str, contains('termuxAccessible=true'));
    });

    test('const 构造函数可用', () {
      const info = ShellInfo(
        type: ShellType.unknown,
        shellPath: '',
      );
      expect(info, isA<ShellInfo>());
    });

    test('launchArgs 始终返回空列表（Android shell 不支持 -i）', () {
      final termuxInfo = ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
      );
      expect(termuxInfo.launchArgs, isEmpty);

      final shInfo = ShellInfo(
        type: ShellType.systemSh,
        shellPath: '/system/bin/sh',
      );
      expect(shInfo.launchArgs, isEmpty);

      const unknownInfo = ShellInfo(
        type: ShellType.unknown,
        shellPath: '',
      );
      expect(unknownInfo.launchArgs, isEmpty);
    });

    test('useRunInShell 始终返回 false（使用绝对路径）', () {
      final info = ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
      );
      expect(info.useRunInShell, false);
    });
  });

  group('ShellDetector', () {
    test('getTermuxEnvironment 返回完整环境变量', () {
      final env = ShellDetector.getTermuxEnvironment();

      expect(env['HOME'], '/data/data/com.termux/files/home');
      expect(env['PREFIX'], '/data/data/com.termux/files/usr');
      expect(env['PATH'], contains('/data/data/com.termux/files/usr/bin'));
      expect(env['LANG'], 'zh_CN.UTF-8');
      expect(env['TERM'], 'xterm-256color');
      expect(env['TMPDIR'], '/data/data/com.termux/files/usr/tmp');
      expect(env['SHELL'], '/data/data/com.termux/files/usr/bin/bash');
    });

    test('getTermuxEnvironment 所有字段非空', () {
      final env = ShellDetector.getTermuxEnvironment();
      for (final entry in env.entries) {
        expect(entry.value, isNotEmpty,
            reason: '环境变量 ${entry.key} 不应为空');
      }
    });

    test('detect 返回可用 Shell（Termux 环境）', () async {
      // 在 Termux 环境下，应检测到 Termux Bash 或至少系统 sh
      final shell = await ShellDetector.detect();

      expect(shell.isAvailable, true,
          reason: '应有可用的 Shell');
      expect(shell.shellPath, isNotEmpty,
          reason: 'Shell 路径不应为空');
    });

    test('detect 返回的 Shell 类型有效', () async {
      final shell = await ShellDetector.detect();

      expect(
        shell.type,
        anyOf(ShellType.termuxBash, ShellType.systemSh),
        reason: 'Shell 类型应为 termuxBash / systemSh 之一',
      );
    });
  });
}
