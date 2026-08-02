/// 回归测试：Native PTY 流式输出 — resize 重绘 prompt 不再堆叠
///
/// 真机根因（2026-08 复现）：
///   Terminal 冷启动时键盘弹出/布局变化触发多次 didChangeMetrics →
///   ioctl(TIOCSWINSZ) → bash 收到 SIGWINCH，readline 重绘 prompt，
///   输出 `\r\x1b[K\r<prompt>`（无换行符）。Kotlin 读循环每次 read 一个
///   chunk，addOutput 按 `\n` split 后把每个无换行 chunk 存成独立
///   buffer 行，outputText join('\n') 人为插入换行，AnsiParser 的
///   `\r` 覆盖语义跨行失效 → 屏幕上竖排堆叠多个 prompt。
///
/// 修复：Native PTY 后端启用流式缓冲（_streamMode），只有真正出现
///   `\n` 才提交一行；`\r\x1b[K` 覆盖序列保留在同一行内交给
///   AnsiParser 行内覆盖；`\r\n` 换行剥离 CR（与 Process 后端
///   LineSplitter 一致）。同时 Native PTY（ICANON|ECHO）命令由终端
///   驱动回显，UI 不再追加 `$ command`（消除双回显）。
library;

import 'dart:async';

import 'package:codex_mobile_pro/core/terminal/iterminal_backend.dart';
import 'package:codex_mobile_pro/core/terminal/native_pty_backend.dart';
import 'package:codex_mobile_pro/features/terminal/services/ansi_parser.dart';
import 'package:codex_mobile_pro/features/terminal/services/terminal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// path_provider mock：避免测试触碰真实平台目录
class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String> getApplicationDocumentsPath() async => '/tmp/fake-docs';
}

/// 记录型 SessionHandle：捕获 write 调用 + 支持测试侧注入 PTY 输出
class _RecordingSessionHandle extends SessionHandle {
  final List<String> writes = [];
  // sync: true — 测试内 emit() 后同步断言（与真实 Kotlin 读循环 push 到
  // Dart Stream 的语义一致：事件尽快派发，不依赖 microtask 冲刷）。
  final _output = StreamController<String>.broadcast(sync: true);
  final _error = StreamController<String>.broadcast(sync: true);

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

  /// 模拟 Kotlin 读循环一次 read 到的 chunk（同步推给已注册 listener）
  void emit(String data, {bool isStderr = false}) {
    if (isStderr) {
      _error.add(data);
    } else {
      _output.add(data);
    }
  }
}

/// 继承 NativePtyBackend，覆写 createSession 返回记录句柄
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

  late _RecordingSessionHandle handle;
  late TerminalSession session;

  setUp(() async {
    handle = _RecordingSessionHandle();
    session = TerminalSession(
      id: 'stream-test',
      name: 'Stream Test',
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

  group('流式输出缓冲', () {
    test('分块 resize 重绘不堆叠 prompt（核心回归）', () {
      // Kotlin 读循环每次 read 一个 chunk，模拟冷启动键盘弹起
      // 多次 resize 触发 bash 重绘（每次重绘一个独立 chunk）
      handle.emit(
          'bash: warning: setlocale: LC_ALL: cannot change locale (en_US.UTF-8)\n');
      handle.emit('groups: cannot find name for group ID 3003\n');
      handle.emit('root@localhost:~# ');
      handle.emit('\r\x1b[K\rroot@localhost:~# ');
      handle.emit('\r\x1b[K\rroot@localhost:~# ');
      handle.emit('\r\x1b[K\rroot@localhost:~# ');

      final text = session.outputText;
      // 2 个警告行 + 1 个 prompt 行 = 3 行；4 次重绘分块不得再堆叠出
      // 额外的 prompt 行（无重绘修复时这里会变成 6 行：2 警告 + 4 prompt）
      expect(text.split('\n'), hasLength(3), reason: '重绘序列必须保留在同一逻辑行内，禁止跨行堆叠');

      // AnsiParser 行内覆盖后只剩 1 个 prompt
      final segments = AnsiParser().parse(text);
      final plain = segments.map((s) => s.text).join();
      expect('root@localhost:~# '.allMatches(plain).length, 1,
          reason: '4 次重绘应被 \\r\\x1b[K 覆盖为单个 prompt');
    });

    test('连续无换行 chunk 合并为同一逻辑行（不人为插入 \\n）', () {
      handle.emit('line1');
      handle.emit('line2');
      handle.emit('line3');

      expect(session.outputText, 'line1line2line3',
          reason: '无 \\n 的内容是同一终端逻辑行，不得拆成多行');
    });

    test('完整行按 \\n 提交，未完成行保留在末尾', () {
      handle.emit('line1\nline2\npending-part');
      expect(session.outputText, 'line1\nline2\npending-part');
    });

    test('\\r 换行（ECHO 回显回车）提交当前行并清空未完成行', () {
      handle.emit('root@localhost:~# echo hi');
      handle.emit('\r\n');
      handle.emit('hi\n');
      handle.emit('root@localhost:~# ');

      expect(session.outputText,
          'root@localhost:~# echo hi\nhi\nroot@localhost:~# ');
    });

    test('空行被过滤（不产生空 TerminalLine）', () {
      handle.emit('\n\n');
      handle.emit('non-empty\n');
      expect(session.outputBuffer.length, 1);
      expect(session.outputBuffer[0].text, 'non-empty');
    });

    test('stderr chunk 标记正确传递', () {
      handle.emit('err-msg\n', isStderr: true);
      expect(session.outputBuffer[0].isStderr, isTrue);
      expect(session.outputBuffer[0].text, 'err-msg');
    });
  });

  group('命令回显', () {
    test('write() 提交命令带换行，且不追加 UI 回显（ECHO 已回显）', () {
      session.write('echo hi');
      expect(handle.writes, ['echo hi\n']);
      expect(session.outputText, isNot(contains('\$ echo hi')),
          reason: 'Native PTY ICANON|ECHO 下命令由终端驱动回显，UI 追加会造成双回显');
    });
  });
}
