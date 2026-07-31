/// 终端数据模型
///
/// 纯数据层，不依赖平台通道（MethodChannel / path_provider）。
/// 测试文件导入此文件避免平台相关加载问题。
/// ============================================================
library;

import 'dart:async';

import '../../../core/terminal/iterminal_backend.dart';
import '../../../core/terminal/process_terminal_backend.dart';
import 'ring_buffer.dart';

// ─── Shell 类型 ───────────────────────────────────────────────

/// Shell 类型
enum ShellType {
  /// Android 系统 Shell（/system/bin/sh）— 唯一可执行的 Shell
  systemSh,
}

/// Shell 信息
class ShellInfo {
  final ShellType type;
  final String shellPath;
  final String version;

  const ShellInfo({
    this.type = ShellType.systemSh,
    this.shellPath = '/system/bin/sh',
    this.version = 'Android System Shell',
  });

  bool get isAvailable => true;

  /// 终端启动参数 — 交互模式
  List<String> get launchArgs => ['-i'];

  /// 绝对路径无需 runInShell
  bool get useRunInShell => false;

  /// 友好的中文描述
  String get friendlyDescription => 'Android 系统 Shell';

  @override
  String toString() =>
      'ShellInfo(type=$type, path=$shellPath, version=$version)';
}

// ─── 枚举 ─────────────────────────────────────────────────────

/// 终端会话状态
enum TerminalSessionStatus { running, exited, error }

// ─── 输出行 ───────────────────────────────────────────────────

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

// ─── 会话 ─────────────────────────────────────────────────────

/// 终端会话（纯数据层）
///
/// 包含数据字段和纯逻辑方法（addOutput/outputText/dispose）。
/// 不包含 Process / MethodChannel / path_provider 依赖。
class TerminalSession {
  final String id;
  String name;
  final ShellInfo shellInfo;
  String cwd;
  TerminalSessionStatus status;
  final RingBuffer<TerminalLine> outputBuffer;
  bool _disposed = false;

  /// 后端引用（仅在运行时由 TerminalService 设置）
  final ITerminalBackend? _backend;

  /// 后端引用 getter
  ITerminalBackend? get backend => _backend;

  static const int maxBufferSize = 10000;

  TerminalSession({
    required this.id,
    required this.name,
    required this.shellInfo,
    required this.cwd,
    this.status = TerminalSessionStatus.running,
    RingBuffer<TerminalLine>? outputBuffer,
    ITerminalBackend? backend,
  })  : outputBuffer = outputBuffer ?? RingBuffer<TerminalLine>(maxBufferSize),
        _backend = backend;

  bool get isDisposed => _disposed;
  String get shellPath => shellInfo.shellPath;

  /// 获取当前输出文本
  String get outputText =>
      outputBuffer.toList().map((l) => l.text).join('\n');

  /// 添加输出行
  void addOutput(String text, {bool isStderr = false}) {
    if (_disposed) return;
    final lines = text.split('\n');
    for (final line in lines) {
      if (line.isEmpty) continue;
      outputBuffer.add(
        TerminalLine(
          text: line,
          isStderr: isStderr,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  /// 写入命令（无后端时为空操作）
  void write(String command) {
    if (_disposed) return;
    addOutput('\$ $command');
  }

  /// 写入原始数据（无后端时为空操作）
  void writeRaw(String data) {
    if (_disposed || data.isEmpty) return;
  }

  /// 发送 Ctrl+C（无后端时为空操作）
  void sendSigint() {
    if (_disposed) return;
  }

  /// 调整终端大小（无后端时为空操作）
  void resize(int rows, int cols) {
    if (_disposed) return;
  }

  /// 销毁会话
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    status = TerminalSessionStatus.exited;
  }
}

// ─── 服务 ─────────────────────────────────────────────────────

/// 终端服务（纯数据层）
///
/// 管理会话列表和后端引用。
/// 不包含 CreateSession（需平台通道）、日志、异步初始化。
class TerminalService {
  final List<TerminalSession> _sessions = [];
  ITerminalBackend? _backend;

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);

  /// 当前后端
  ITerminalBackend? get backend => _backend;

  /// 设置后端
  void setBackend(ITerminalBackend backend) {
    _backend = backend;
  }

  /// 重置为 Process 后端
  void useProcessBackend() {
    _backend = ProcessTerminalBackend();
  }

  /// 获取会话
  TerminalSession? getSession(String id) {
    return _sessions.where((s) => s.id == id).firstOrNull;
  }

  /// 关闭会话
  Future<void> closeSession(String id) async {
    final session = _sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return;
    await session.dispose();
    _sessions.remove(session);
  }

  /// 清理所有会话
  Future<void> disposeAll() async {
    for (final session in _sessions.toList()) {
      await session.dispose();
    }
    _sessions.clear();
  }
}
