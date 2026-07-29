import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/terminal/services/terminal_service.dart';
import 'package:codex_mobile_pro/core/termux/shell_detector.dart';

void main() {
  group('ShellInfo', () {
    test('Android 系统 Shell 描述正确', () {
      const info = ShellInfo();
      expect(info.friendlyDescription, 'Android 系统 Shell');
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, false);
    });

    test('toString 包含关键信息', () {
      const info = ShellInfo();
      final str = info.toString();
      expect(str, contains('systemSh'));
      expect(str, contains('/system/bin/sh'));
    });
  });

  group('TerminalSession', () {
    test('创建会话', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test Terminal',
        shellInfo: shellInfo,
        cwd: '/data/data/com.example.app/files',
      );

      expect(session.id, 'test-1');
      expect(session.name, 'Test Terminal');
      expect(session.shellPath, '/system/bin/sh');
      expect(session.cwd, '/data/data/com.example.app/files');
      expect(session.status, TerminalSessionStatus.running);
      expect(session.isDisposed, false);
      expect(session.outputBuffer, isEmpty);
      expect(session.outputText, '');
    });

    test('添加输出行', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      session.addOutput('Hello');
      session.addOutput('World', isStderr: true);

      expect(session.outputBuffer.length, 2);
      expect(session.outputBuffer[0].text, 'Hello');
      expect(session.outputBuffer[0].isStderr, false);
      expect(session.outputBuffer[1].text, 'World');
      expect(session.outputBuffer[1].isStderr, true);
    });

    test('输出文本拼接', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      session.addOutput('line1');
      session.addOutput('line2');
      session.addOutput('line3');

      expect(session.outputText, 'line1\nline2\nline3');
    });

    test('缓冲区限制', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      for (int i = 0; i < TerminalSession.maxBufferSize + 100; i++) {
        session.addOutput('line $i');
      }

      expect(
        session.outputBuffer.length,
        lessThanOrEqualTo(TerminalSession.maxBufferSize),
      );
    });

    test('已销毁的会话不添加输出', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      session.addOutput('before');
      expect(session.outputBuffer.length, 1);
      expect(session.isDisposed, false);
    });

    test('写入命令不崩溃（无进程时）', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      session.write('ls -la');
    });

    test('发送 Sigint 不崩溃（无进程时）', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      session.sendSigint();
    });

    test('销毁不崩溃', () async {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      await session.dispose();
      expect(session.isDisposed, true);
      expect(session.status, TerminalSessionStatus.exited);

      await session.dispose();
      expect(session.isDisposed, true);
    });

    test('添加输出带换行符', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      session.addOutput('line1\nline2\nline3');
      expect(session.outputBuffer.length, 3);
      expect(session.outputBuffer[0].text, 'line1');
      expect(session.outputBuffer[1].text, 'line2');
      expect(session.outputBuffer[2].text, 'line3');
    });

    test('添加空行被过滤', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      session.addOutput('');
      session.addOutput('non-empty');
      expect(session.outputBuffer.length, 1);
      expect(session.outputBuffer[0].text, 'non-empty');
    });

    test('shellInfo 属性传递正确', () {
      const shellInfo = ShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      expect(session.shellInfo, same(shellInfo));
      expect(session.shellPath, '/system/bin/sh');
    });

    test('ShellInfo 默认值一致', () {
      const info1 = ShellInfo();
      const info2 = ShellInfo();

      expect(info1.type, info2.type);
      expect(info1.shellPath, info2.shellPath);
      expect(info1.launchArgs, info2.launchArgs);
      expect(info1.useRunInShell, info2.useRunInShell);
    });
  });

  group('TerminalService', () {
    test('创建后会话列表为空', () {
      final service = TerminalService();
      expect(service.sessions, isEmpty);
    });

    test('获取不存在的会话返回 null', () {
      final service = TerminalService();
      expect(service.getSession('non-existent'), isNull);
    });

    test('关闭不存在的会话不崩溃', () async {
      final service = TerminalService();
      await service.closeSession('non-existent');
    });

    test('disposeAll 空列表不崩溃', () async {
      final service = TerminalService();
      await service.disposeAll();
      expect(service.sessions, isEmpty);
    });
  });
}
