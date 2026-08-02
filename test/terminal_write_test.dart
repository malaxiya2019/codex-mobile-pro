/// 回归测试：交互终端写入换行行为
///
/// 覆盖真实实现 `terminal_service.dart`（非测试桩）：
///   - `write()`（主输入栏提交）必须以换行符结尾，
///     bash 收到回车才执行命令 —— Native PTY 后端缺换行会导致
///     命令一直挂在 stdin 缓冲区（真机复现：终端里 apt 无输出）。
///   - `writeRaw()`（ExtraKeys 原始按键）不得追加换行。
///
/// 通过继承 NativePtyBackend 覆写 createSession + 注入记录型
/// SessionHandle 验证写入内容，避免触碰真实 MethodChannel / 平台。
library;

import 'dart:async';

import 'package:codex_mobile_pro/core/terminal/iterminal_backend.dart';
import 'package:codex_mobile_pro/core/terminal/native_pty_backend.dart';
import 'package:codex_mobile_pro/features/terminal/services/terminal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// path_provider mock：避免测试触碰真实平台目录
class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String> getApplicationDocumentsPath() async => '/tmp/fake-docs';
}

/// 记录型 SessionHandle：捕获所有 write 调用
class _RecordingSessionHandle extends SessionHandle {
  final List<String> writes = [];
  final _output = StreamController<String>.broadcast();
  final _error = StreamController<String>.broadcast();

  @override
  String get id => 'fake-session';

  @override
  bool get isAlive => true;

  @override
  int? get pid => 4242;

  @override
  void write(String text) => writes.add(text);

  @override
  void sendSigint() => write('\x03');

  @override
  void sendEof() => write('\x04');

  @override
  void resize(int rows, int cols) {}

  @override
  Future<void> close() async {
    await _output.close();
    await _error.close();
  }

  @override
  Stream<String> get outputStream => _output.stream;

  @override
  Stream<String> get errorStream => _error.stream;
}

/// 继承 NativePtyBackend（start() 仅对 NativePtyBackend 走 PTY 路径），
/// 覆写 createSession 返回记录句柄，不触碰 MethodChannel。
class _RecordingNativePtyBackend extends NativePtyBackend {
  final _RecordingSessionHandle handle;
  _RecordingNativePtyBackend(this.handle);

  @override
  Future<SessionHandle> createSession({
    required String shellPath,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    return handle;
  }
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  group('TerminalSession.write（真实实现）', () {
    late _RecordingSessionHandle handle;
    late TerminalSession session;

    setUp(() async {
      handle = _RecordingSessionHandle();
      session = TerminalSession(
        id: 'pty-write-test',
        name: 'PTY Test',
        shellInfo: const ShellInfo(
          shellPath: '/bin/bash',
          args: ['-l'],
          version: 'Linux Runtime Shell',
          isLinux: true,
        ),
        cwd: '/',
        backend: _RecordingNativePtyBackend(handle),
      );
      final started = await session.start();
      expect(started, isTrue,
          reason: 'start() 应成功（fake backend + mock path_provider）');
      expect(session.status, TerminalSessionStatus.running);
    });

    tearDown(() async {
      await session.dispose();
    });

    test('write() 提交命令以换行符结尾（bash 回车执行）', () {
      session.write('apt update --fix-missing');
      expect(handle.writes, ['apt update --fix-missing\n'],
          reason: 'Native PTY 后端必须追加 \\n，否则 bash 不执行命令');
    });

    test('write() 多命令均带换行', () {
      session.write('echo hello');
      session.write('cd /tmp');
      expect(handle.writes, ['echo hello\n', 'cd /tmp\n']);
    });

    test('writeRaw() 保持原始数据不追加换行（ExtraKeys 按键语义）', () {
      session.writeRaw('\x1b[A'); // ↑
      session.writeRaw('\t'); // TAB
      expect(handle.writes, ['\x1b[A', '\t'],
          reason: 'writeRaw 是瞬时按键，追加换行会破坏 ESC 序列/Tab 语义');
    });

    test('sendSigint 仍为控制字符', () {
      session.sendSigint();
      expect(handle.writes, ['\x03']);
    });
  });
}
