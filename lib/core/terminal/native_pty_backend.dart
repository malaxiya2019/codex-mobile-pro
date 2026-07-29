import 'dart:async';

import 'package:flutter/services.dart';

import 'iterminal_backend.dart';

/// Native PTY 终端后端
///
/// 通过 MethodChannel 与 Java/Kotlin PtyPlugin 通信，
/// 使用真实的 forkpty() 创建伪终端，通过 EventChannel 接收输出。
///
/// 依赖：
///   - android/app/src/main/jni/pty.c — JNI forkpty 实现
///   - PtyPlugin.kt — MethodChannel/EventChannel 桥接
///   - assets/busybox-arm64 — 静态编译的 BusyBox
class NativePtyBackend implements ITerminalBackend {
  static const MethodChannel _channel =
      MethodChannel('com.codexmobile.app/terminal/native');
  static const EventChannel _outputChannel =
      EventChannel('com.codexmobile.app/terminal/native/output');

  bool _initialized = false;
  String? _shellPath;
  String? _busyboxPath;

  /// BusyBox shell 路径
  String? get shellPath => _shellPath;

  /// BusyBox 二进制路径
  String? get busyboxPath => _busyboxPath;

  @override
  String get name => 'native_pty';

  @override
  String get description => 'Native PTY (forkpty + BusyBox) 后端';

  /// 初始化 BusyBox（解压 + 安装 applets）
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      final result = await _channel.invokeMethod<Map>('setupBusybox');
      if (result == null) return false;

      _busyboxPath = result['busyboxPath'] as String?;
      _shellPath = result['shellPath'] as String?;
      _initialized = true;
      return true;
    } on MissingPluginException {
      // Native 插件未注册，回退到 Process 后端
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 检查 BusyBox 是否就绪
  Future<bool> checkReady() async {
    try {
      final result = await _channel.invokeMethod<Map>('checkBusybox');
      return result?['ready'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 获取 BusyBox shell 路径
  Future<String?> getShellPath() async {
    try {
      final result = await _channel.invokeMethod<Map>('getShellPath');
      return result?['shellPath'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SessionHandle> createSession({
    required String shellPath,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) {
        throw StateError('Native PTY 后端未初始化');
      }
    }

    final result = await _channel.invokeMethod<Map>('createSession', {
      'rows': 60,
      'cols': 120,
      'workDir': workingDirectory,
    });

    if (result == null) {
      throw StateError('创建 PTY 会话失败');
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
  }

  @override
  Future<void> disposeAll() async {
    // 各 SessionHandle 在 close() 时会清理自身
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
    // 订阅 EventChannel 输出流
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
  int? get pid => null; // 通过 MethodChannel 无法直接获取

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
