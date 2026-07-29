import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/logger/log_service.dart';
import '../../../core/termux/shell_detector.dart';

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
///
/// 使用 Android 系统 Shell（/system/bin/sh）运行交互式终端。
/// 不依赖 Termux，不访问其他 App 的数据目录。
class TerminalSession {
  final String id;
  String name;
  final ShellInfo shellInfo;
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
    required this.shellInfo,
    required this.cwd,
    this.status = TerminalSessionStatus.running,
    List<TerminalLine>? outputBuffer,
  }) : outputBuffer = outputBuffer ?? [];

  bool get isDisposed => _disposed;
  String get shellPath => shellInfo.shellPath;

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

    // ── 日志：启动前记录关键信息 ──
    LogService.info('Terminal', '启动会话 $id');
    LogService.info('Terminal', '  Shell: /system/bin/sh');
    LogService.info('Terminal', '  工作目录: $cwd');

    try {
      // 使用 App 私有目录作为 HOME
      final appDir = await getApplicationDocumentsDirectory();
      final env = ShellDetector.getShellEnvironment(appDir.path);
      LogService.info('Terminal', '  HOME: ${env['HOME']}');
      LogService.info('Terminal', '  PATH: ${env['PATH']}');

      _process = await Process.start(
        '/system/bin/sh',
        ['-i'],
        workingDirectory: cwd,
        environment: env,
      );

      status = TerminalSessionStatus.running;
      LogService.info('Terminal', '  进程已启动 (PID: ${_process!.pid})');

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => addOutput(line),
            onError: (e) {
              LogService.error('Terminal', '  stdout 错误: $e');
              addOutput('stdout error: $e', isStderr: true);
            },
          );

      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => addOutput(line, isStderr: true),
            onError: (e) {
              LogService.error('Terminal', '  stderr 错误: $e');
              addOutput('stderr error: $e', isStderr: true);
            },
          );

      _process!.exitCode.then((code) {
        status = TerminalSessionStatus.exited;
        addOutput('进程退出 (exit code: $code)');
        LogService.info('Terminal', '  会话 $id 退出，code=$code');
      });

      return true;
    } catch (e, stack) {
      status = TerminalSessionStatus.error;
      final msg = '启动失败: $e';
      addOutput(msg, isStderr: true);

      LogService.error('Terminal', '❌ 会话 $id 启动失败');
      LogService.error('Terminal', '  错误: $e');
      LogService.error('Terminal', '  堆栈: $stack');

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
      LogService.error('Terminal', '  写入失败: $e');
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
        final pid = _process!.pid;
        _process!.kill();
        LogService.info('Terminal', '  已终止进程 (PID: $pid)');
        await _process!.exitCode.timeout(const Duration(seconds: 2));
      } catch (e) {
        LogService.info('Terminal', '  终止进程时: $e');
      }
    }

    _process = null;
    status = TerminalSessionStatus.exited;
    LogService.info('Terminal', '  会话 $id 已销毁');
  }
}

/// 终端服务
///
/// 管理所有终端会话，使用 Android 系统 Shell（/system/bin/sh）。
/// 不需要 ShellDetector 检测，不再访问 Termux 目录。
class TerminalService {
  final List<TerminalSession> _sessions = [];

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);

  /// 创建新终端会话
  Future<TerminalSession> createSession({
    String? name,
    String? cwd,
  }) async {
    // 使用 App 私有目录作为默认工作目录
    final appDir = await getApplicationDocumentsDirectory();
    final home = cwd ?? appDir.path;

    final session = TerminalSession(
      id: const Uuid().v4(),
      name: name ?? '终端 ${_sessions.length + 1}',
      shellInfo: const ShellInfo(),
      cwd: home,
    );

    _sessions.add(session);
    LogService.info('Terminal', '创建会话: ${session.id} (${session.name})');
    await session.start();
    return session;
  }

  /// 关闭终端会话
  Future<void> closeSession(String id) async {
    final session = _sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return;
    await session.dispose();
    _sessions.remove(session);
    LogService.info('Terminal', '关闭会话: $id');
  }

  /// 获取会话
  TerminalSession? getSession(String id) {
    return _sessions.where((s) => s.id == id).firstOrNull;
  }

  /// 清理所有会话
  Future<void> disposeAll() async {
    LogService.info('Terminal', '清理所有会话 (${_sessions.length} 个)');
    for (final session in _sessions.toList()) {
      await session.dispose();
    }
    _sessions.clear();
  }
}
