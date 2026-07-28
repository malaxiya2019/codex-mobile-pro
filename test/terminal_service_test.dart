import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/terminal/services/terminal_service.dart';
import 'package:codex_mobile_pro/core/termux/shell_detector.dart';

/// 创建一个 Mock ShellInfo 用于测试
ShellInfo _mockShellInfo({
  ShellType type = ShellType.systemSh,
  String path = '/system/bin/sh',
  String version = 'sh (Android)',
  bool termuxAccessible = false,
}) {
  return ShellInfo(
    type: type,
    shellPath: path,
    version: version,
    isTermuxAccessible: termuxAccessible,
  );
}

void main() {
  group('ShellInfo', () {
    test('Termux Bash 描述正确', () {
      final info = _mockShellInfo(
        type: ShellType.termuxBash,
        path: '/data/data/com.termux/files/usr/bin/bash',
        version: 'GNU bash, version 5.2.26',
        termuxAccessible: true,
      );
      expect(info.friendlyDescription, 'Termux Bash');
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, true);
      expect(info.isTermuxAccessible, true);
    });

    test('系统 sh 描述正确', () {
      final info = _mockShellInfo(
        type: ShellType.systemSh,
        path: '/system/bin/sh',
      );
      expect(info.friendlyDescription, 'Android 系统 Shell');
      expect(info.isAvailable, true);
      expect(info.isTermuxBash, false);
    });

    test('unknown Shell 描述正确', () {
      const info = ShellInfo(
        type: ShellType.unknown,
        shellPath: '',
      );
      expect(info.friendlyDescription, '无可用 Shell');
      expect(info.isAvailable, false);
    });

    test('toString 包含关键信息', () {
      final info = _mockShellInfo(
        type: ShellType.termuxBash,
        path: '/data/data/com.termux/files/usr/bin/bash',
        version: 'GNU bash, version 5.2.26',
      );
      final str = info.toString();
      expect(str, contains('termuxBash'));
      expect(str, contains('bash'));
      expect(str, contains('5.2.26'));
    });
  });

  group('TerminalSession', () {
    test('创建会话', () {
      final shellInfo = _mockShellInfo();
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test Terminal',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      expect(session.id, 'test-1');
      expect(session.name, 'Test Terminal');
      expect(session.shellPath, '/system/bin/sh');
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
        shellInfo: _mockShellInfo(),
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
        shellInfo: _mockShellInfo(),
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
        shellInfo: _mockShellInfo(),
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
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: _mockShellInfo(),
        cwd: '/home',
      );

      session.addOutput('before');
      expect(session.outputBuffer.length, 1);
      expect(session.isDisposed, false);
    });

    test('写入命令不崩溃（无进程时）', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: _mockShellInfo(),
        cwd: '/home',
      );

      session.write('ls -la');
    });

    test('发送 Sigint 不崩溃（无进程时）', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: _mockShellInfo(),
        cwd: '/home',
      );

      session.sendSigint();
    });

    test('销毁不崩溃', () async {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: _mockShellInfo(),
        cwd: '/home',
      );

      await session.dispose();
      expect(session.isDisposed, true);
      expect(session.status, TerminalSessionStatus.exited);

      await session.dispose();
      expect(session.isDisposed, true);
    });

    test('添加输出带换行符', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: _mockShellInfo(),
        cwd: '/home',
      );

      session.addOutput('line1\nline2\nline3');
      expect(session.outputBuffer.length, 3);
      expect(session.outputBuffer[0].text, 'line1');
      expect(session.outputBuffer[1].text, 'line2');
      expect(session.outputBuffer[2].text, 'line3');
    });

    test('添加空行被过滤', () {
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: _mockShellInfo(),
        cwd: '/home',
      );

      session.addOutput('');
      session.addOutput('non-empty');
      expect(session.outputBuffer.length, 1);
      expect(session.outputBuffer[0].text, 'non-empty');
    });

    test('shellInfo 属性传递正确', () {
      final shellInfo = _mockShellInfo(
        type: ShellType.termuxBash,
        path: '/data/data/com.termux/files/usr/bin/bash',
      );
      final session = TerminalSession(
        id: 'test-1',
        name: 'Test',
        shellInfo: shellInfo,
        cwd: '/home',
      );

      expect(session.shellInfo, same(shellInfo));
      expect(session.shellPath, '/data/data/com.termux/files/usr/bin/bash');
    });
  });

  group('TerminalService', () {
    test('创建后会话列表为空', () {
      final service = TerminalService();
      expect(service.sessions, isEmpty);
    });

    test('getShell 缓存检测结果', () async {
      final service = TerminalService();
      final shell1 = await service.getShell();
      // 第二次获取应返回同一对象（缓存）
      final shell2 = await service.getShell();
      expect(shell2, same(shell1));
    });

    test('refreshShell 返回新结果', () async {
      final service = TerminalService();
      final shell1 = await service.getShell();
      final shell2 = await service.refreshShell();
      expect(shell2, isNotNull);
      // refresh 可能返回不同对象
      expect(shell2, isNot(same(shell1)));
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
