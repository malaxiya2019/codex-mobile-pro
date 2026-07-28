import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/termux/shell_detector.dart';

void main() {
  group('ShellInfo', () {
    test('Termux Bash 信息正确', () {
      final info = ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
        version: 'GNU bash, version 5.2.26(1)-release',
        hasPtySupport: true,
        hasTmuxSupport: true,
      );

      expect(info.type, ShellType.termuxBash);
      expect(info.shellPath, '/data/data/com.termux/files/usr/bin/bash');
      expect(info.version, contains('GNU bash'));
      expect(info.hasPtySupport, true);
      expect(info.hasTmuxSupport, true);
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, true);
      expect(info.friendlyDescription, 'Termux Bash');
    });

    test('System Bash 信息正确', () {
      final info = ShellInfo(
        type: ShellType.systemBash,
        shellPath: 'bash',
        version: 'GNU bash, version 5.0',
        hasPtySupport: false,
        hasTmuxSupport: false,
      );

      expect(info.type, ShellType.systemBash);
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, false);
      expect(info.friendlyDescription, '系统 Bash');
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
      expect(info.hasPtySupport, false);
      expect(info.hasTmuxSupport, false);
      expect(info.friendlyDescription, 'Android 系统 Shell');
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
      expect(ShellType.values.length, 4);
      expect(ShellType.values, contains(ShellType.termuxBash));
      expect(ShellType.values, contains(ShellType.systemBash));
      expect(ShellType.values, contains(ShellType.systemSh));
      expect(ShellType.values, contains(ShellType.unknown));
    });

    test('toString 包含完整信息', () {
      final info = ShellInfo(
        type: ShellType.termuxBash,
        shellPath: '/data/data/com.termux/files/usr/bin/bash',
        version: '5.2.26',
        hasPtySupport: true,
        hasTmuxSupport: false,
      );

      final str = info.toString();
      expect(str, contains('termuxBash'));
      expect(str, contains('/data/data/com.termux/files/usr/bin/bash'));
      expect(str, contains('5.2.26'));
      expect(str, contains('pty=true'));
      expect(str, contains('tmux=false'));
    });

    test('const 构造函数可用', () {
      const info = ShellInfo(
        type: ShellType.unknown,
        shellPath: '',
      );
      expect(info, isA<ShellInfo>());
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
        anyOf(ShellType.termuxBash, ShellType.systemBash, ShellType.systemSh),
        reason: 'Shell 类型应为 termuxBash / systemBash / systemSh 之一',
      );
    });
  });
}
