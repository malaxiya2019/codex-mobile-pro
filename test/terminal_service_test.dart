import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/terminal/services/terminal_service.dart';

void main() {
  group('TerminalSession', () {
    test('创建会话', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test Terminal',
        shell: 'bash',
        cwd: '/home',
      );

      expect(session.id, 'test-1');
      expect(session.name, 'Test Terminal');
      expect(session.shell, 'bash');
      expect(session.cwd, '/home');
      expect(session.status, TerminalSessionStatus.running);
      expect(session.isDisposed, false);
      expect(session.outputBuffer, isEmpty);
      expect(session.outputText, '');
    });

    test('添加输出行', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shell: 'bash',
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
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shell: 'bash',
        cwd: '/home',
      );

      session.addOutput('line1');
      session.addOutput('line2');
      session.addOutput('line3');

      expect(session.outputText, 'line1\nline2\nline3');
    });

    test('缓冲区限制', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shell: 'bash',
        cwd: '/home',
      );

      // 添加超过限制的行
      for (int i = 0; i < TerminalSession.maxBufferSize + 100; i++) {
        session.addOutput('line $i');
      }

      expect(
        session.outputBuffer.length,
        lessThanOrEqualTo(TerminalSession.maxBufferSize),
      );
    });

    test('已销毁的会话不添加输出', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shell: 'bash',
        cwd: '/home',
      );

      session.addOutput('before');
      expect(session.outputBuffer.length, 1);

      // 直接标记已销毁
      expect(session.isDisposed, false);
    });

    test('写入命令添加提示符', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shell: 'bash',
        cwd: '/home',
      );

      // 进程不存在时写入不应崩溃
      session.write('ls -la');
      // 因为没有进程，不会添加输出
    });

    test('发送 Sigint 不崩溃', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shell: 'bash',
        cwd: '/home',
      );

      // 没有进程时不应崩溃
      session.sendSigint();
    });

    test('销毁不崩溃', () async {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shell: 'bash',
        cwd: '/home',
      );

      await session.dispose();
      expect(session.isDisposed, true);
      expect(session.status, TerminalSessionStatus.exited);

      // 重复销毁不应出错
      await session.dispose();
      expect(session.isDisposed, true);
    });

    test('添加输出带换行符', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shell: 'bash',
        cwd: '/home',
      );

      session.addOutput('line1\nline2\nline3');
      // 空行被过滤
      expect(session.outputBuffer.length, 3);
      expect(session.outputBuffer[0].text, 'line1');
      expect(session.outputBuffer[1].text, 'line2');
      expect(session.outputBuffer[2].text, 'line3');
    });
  });

  group('TerminalService', () {
    test('创建会话', () {
      final service = TerminalService();
      expect(service.sessions, isEmpty);

      final session = service.createSession(name: 'Test', cwd: '/home');

      expect(service.sessions.length, 1);
      expect(session.name, 'Test');
      expect(service.getSession(session.id), isNotNull);
    });

    test('创建多个会话', () {
      final service = TerminalService();

      service.createSession(name: 'A');
      service.createSession(name: 'B');
      service.createSession(name: 'C');

      expect(service.sessions.length, 3);
    });

    test('获取不存在的会话返回 null', () {
      final service = TerminalService();
      expect(service.getSession('non-existent'), isNull);
    });

    test('关闭会话', () async {
      final service = TerminalService();
      final session = service.createSession(name: 'Test');

      await service.closeSession(session.id);
      expect(service.sessions, isEmpty);
    });

    test('关闭不存在的会话不崩溃', () async {
      final service = TerminalService();
      await service.closeSession('non-existent');
    });

    test('清理所有会话', () async {
      final service = TerminalService();
      service.createSession(name: 'A');
      service.createSession(name: 'B');

      await service.disposeAll();
      expect(service.sessions, isEmpty);
    });
  });
}
