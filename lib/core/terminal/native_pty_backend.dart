import 'dart:async';

import 'package:flutter/services.dart';

import 'iterminal_backend.dart';

/// Native PTY 终端后端
///
/// 通过 MethodChannel 与 Java/Kotlin PtyPlugin 通信，
/// 使用 Native PTY（posix_openpt / fork + execve）创建伪终端，
/// 通过 EventChannel 接收输出。
///
/// 本后端直接使用 ShellDetector 提供的 shell（如 /system/bin/sh），
/// 不依赖 BusyBox。BusyBox 模式保留用于向后兼容。
class NativePtyBackend implements ITerminalBackend {
  static const MethodChannel _channel =
      MethodChannel('com.codexmobile.app/terminal/native');
  static const EventChannel _outputChannel =
      EventChannel('com.codexmobile.app/terminal/native/output');

  bool _initialized = false;

  @override
  String get name => 'native_pty';

  @override
  String get description => 'Native PTY (posix_openpt) 后端';

  /// 初始化
  Future<bool> initialize() async {
    if (_initialized) return true;
    // Native PTY 后端不需要特殊初始化（libpty_native.so 由 PtyPlugin 按需加载）
    _initialized = true;
    return true;
  }

  @override
  Future<SessionHandle> createSession({
    required String shellPath,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('createSession', {
        'shellPath': shellPath,
        'args': args,
        'environment': environment,
        'rows': 60,
        'cols': 120,
        'workDir': workingDirectory,
      });

      if (result == null) {
        throw StateError('创建 PTY 会话失败（返回 null）');
      }

      final sessionId = result['sessionId'] as String?;
      if (sessionId == null) {
        throw StateError('PTY 会话 ID 为空');
      }

      return _NativeSessionHandle(
        sessionId: sessionId,
        channel: _channel,
        outputChannel: _outputChannel,
      );
    } on MissingPluginException {
      throw StateError('Native PTY 插件未注册');
    }
  }

  @override
  Future<void> disposeAll() async {
    // 各 SessionHandle 在 close() 时会自行清理
  }
}

/// Native PTY 会话句柄
class _NativeSessionHandle extends SessionHandle {
  final String _sessionId;
  final MethodChannel _channel;
  final EventChannel _outputChannel;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _eventSub;
  bool _closed = false;

  _NativeSessionHandle({
    required String sessionId,
    required MethodChannel channel,
    required EventChannel outputChannel,
  })  : _sessionId = sessionId,
        _channel = channel,
        _outputChannel = outputChannel {
    _eventSub = _outputChannel
        .receiveBroadcastStream(sessionId)
        .listen(_onOutput, onError: _onError);
  }

  void _onOutput(dynamic event) {
    if (event is Map) {
      final data = event['data'] as String? ?? '';
      final isStderr = event['isStderr'] == true;
      final closed = event['closed'] == true;

      if (closed) {
        _outputController.close();
        _errorController.close();
        return;
      }

      if (isStderr) {
        _errorController.add(data);
      } else {
        _outputController.add(data);
      }
    }
  }

  void _onError(Object error) {
    _outputController.addError(error);
    _errorController.addError(error);
  }

  @override
  String get id => _sessionId;

  @override
  bool get isAlive => !_closed;

  @override
  int? get pid => null;

  @override
  void write(String text) {
    if (_closed) return;
    _channel.invokeMethod('write', {
      'sessionId': _sessionId,
      'data': text,
    });
  }

  @override
  void sendSigint() {
    write('\x03'); // Ctrl+C
  }

  @override
  void sendEof() {
    write('\x04'); // Ctrl+D
  }

  @override
  void resize(int rows, int cols) {
    if (_closed) return;
    _channel.invokeMethod('resize', {
      'sessionId': _sessionId,
      'rows': rows,
      'cols': cols,
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _eventSub?.cancel();
    await _channel.invokeMethod('closeSession', {
      'sessionId': _sessionId,
    });
    await _outputController.close();
    await _errorController.close();
  }

  @override
  Stream<String> get outputStream => _outputController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;
}
