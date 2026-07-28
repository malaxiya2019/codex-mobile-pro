import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../../core/logger/log_service.dart';

/// 终端会话状态
enum TerminalSessionStatus { running, exited, error }

/// 终端输出行
class TerminalLine {
  final String text;
  final bool isStderr;
  final DateTime timestamp;

  const TerminalLine({
    required this.text,
    this.isStderr = false,
    required this.timestamp,
  });
}

/// 终端会话
class TerminalSession {
  final String id;
  String name;
  final String shell;
  String cwd;
  TerminalSessionStatus status;
  final List<TerminalLine> outputBuffer;
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  bool _disposed = false;

  static const int maxBufferSize = 1000;

  TerminalSession({
    required this.id,
    required this.name,
    required this.shell,
    required this.cwd,
    this.status = TerminalSessionStatus.running,
    List<TerminalLine>? outputBuffer,
  }) : outputBuffer = outputBuffer ?? [];

  bool get isDisposed => _disposed;

  /// 获取当前输出文本
  String get outputText => outputBuffer.map((l) => l.text).join('\n');

  /// 添加输出行
  void addOutput(String text, {bool isStderr = false}) {
    if (_disposed) return;

    final lines = text.split('\n');
    for (final line in lines) {
      if (line.isEmpty) continue;
      outputBuffer.add(
        TerminalLine(text: line, isStderr: isStderr, timestamp: DateTime.now()),
      );
    }

    while (outputBuffer.length > maxBufferSize) {
      outputBuffer.removeAt(0);
    }
  }

  /// 启动进程
  Future<bool> start() async {
    if (_process != null) return true;

    try {
      _process = await Process.start(
        shell,
        [],
        workingDirectory: cwd,
        runInShell: true,
        environment: {
          'HOME': '/data/data/com.termux/files/home',
          'TERM': 'xterm-256color',
          'PATH':
              '/data/data/com.termux/files/usr/bin:/system/bin:/usr/bin:/bin',
        },
      );

      status = TerminalSessionStatus.running;

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => addOutput(line),
            onError: (e) => addOutput('stdout error: $e', isStderr: true),
          );

      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => addOutput(line, isStderr: true),
            onError: (e) => addOutput('stderr error: $e', isStderr: true),
          );

      _process!.exitCode.then((code) {
        status = TerminalSessionStatus.exited;
        addOutput('进程退出 (exit code: $code)');
        LogService.info('Terminal', '会话 $id 退出，code=$code');
      });

      return true;
    } catch (e) {
      status = TerminalSessionStatus.error;
      addOutput('启动失败: $e', isStderr: true);
      LogService.error('Terminal', '会话 $id 启动失败: $e');
      return false;
    }
  }

  /// 写入命令
  void write(String command) {
    if (_process == null || _disposed) return;
    try {
      _process!.stdin.writeln(command);
      addOutput('\$ $command');
    } catch (e) {
      addOutput('写入失败: $e', isStderr: true);
    }
  }

  /// 发送 Ctrl+C
  void sendSigint() {
    if (_process == null || _disposed) return;
    try {
      _process!.stdin.write('\x03');
    } catch (_) {}
  }

  /// 销毁会话
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();

    if (_process != null) {
      try {
        _process!.kill();
        await _process!.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    _process = null;
    status = TerminalSessionStatus.exited;
    LogService.info('Terminal', '会话 $id 已销毁');
  }
}

/// 终端服务
///
/// 管理所有终端会话，支持多标签、实时 I/O。
class TerminalService {
  final List<TerminalSession> _sessions = [];

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);

  /// 创建新终端会话
  TerminalSession createSession({
    String? name,
    String? cwd,
    String shell = 'bash',
  }) {
    final session = TerminalSession(
      id: const Uuid().v4(),
      name: name ?? 'Terminal ${_sessions.length + 1}',
      shell: shell,
      cwd: cwd ?? '/data/data/com.termux/files/home',
    );

    _sessions.add(session);
    LogService.info('Terminal', '创建会话: ${session.id} (${session.name})');
    session.start();
    return session;
  }

  /// 关闭终端会话
  Future<void> closeSession(String id) async {
    final session = _sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return;
    await session.dispose();
    _sessions.remove(session);
  }

  /// 获取会话
  TerminalSession? getSession(String id) {
    return _sessions.where((s) => s.id == id).firstOrNull;
  }

  /// 清理所有会话
  Future<void> disposeAll() async {
    for (final session in _sessions.toList()) {
      await session.dispose();
    }
    _sessions.clear();
  }
}
