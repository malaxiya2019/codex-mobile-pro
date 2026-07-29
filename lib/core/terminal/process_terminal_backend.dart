import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'iterminal_backend.dart';

/// 基于 Process.start() 的终端后端
///
/// 保持与现有实现完全兼容，使用 Dart 标准库的 Process API。
/// 适用于不支持真实 PTY 的环境。
class ProcessTerminalBackend implements ITerminalBackend {
  @override
  String get name => 'process';

  @override
  String get description => 'Dart Process.start() 后端';

  @override
  Future<SessionHandle> createSession({
    required String shellPath,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    final process = await Process.start(
      shellPath,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    return _ProcessSessionHandle(process: process);
  }

  @override
  Future<void> disposeAll() async {
    // ProcessSessionHandle 在 close() 时自动释放进程
  }
}

/// 基于 Process 的会话句柄
class _ProcessSessionHandle extends SessionHandle {
  final Process _process;
  final String _id;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  late final StreamSubscription<String> _stdoutSub;
  late final StreamSubscription<String> _stderrSub;
  bool _closed = false;

  _ProcessSessionHandle({required Process process})
      : _process = process,
        _id = 'proc-${process.pid}' {
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _outputController.add(line),
          onDone: () => _outputController.close(),
        );

    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _errorController.add(line),
          onDone: () => _errorController.close(),
        );
  }

  @override
  String get id => _id;

  @override
  bool get isAlive => !_closed;

  @override
  int? get pid => _process.pid;

  @override
  void write(String text) {
    if (!_closed) {
      _process.stdin.writeln(text);
    }
  }

  @override
  void sendSigint() {
    if (!_closed) {
      _process.stdin.write('\x03');
    }
  }

  @override
  void sendEof() {
    if (!_closed) {
      _process.stdin.close();
    }
  }

  @override
  void resize(int rows, int cols) {
    // Process.start() 不支持 resize，静默忽略
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 2));
  }

  @override
  Stream<String> get outputStream => _outputController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;
}
