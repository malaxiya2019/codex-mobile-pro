import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/logger/log_service.dart';
import '../../../core/terminal/iterminal_backend.dart';
import '../../../core/terminal/native_pty_backend.dart';
import '../../../core/terminal/process_terminal_backend.dart';
import '../../../runtime/runtime_manager.dart';
import 'ring_buffer.dart';

// ─── Shell 信息（本地定义，替代旧 ShellDetector）─────────────


/// Shell 信息（Android 系统 Shell）
class ShellInfo {
  final String shellPath;
  final String version;
  final bool isTermuxAvailable;

  const ShellInfo()
      : shellPath = '/system/bin/sh',
        version = 'Android System Shell',
        isTermuxAvailable = false;

  bool get isAvailable => true;
  List<String> get launchArgs => ['-i'];
  bool get useRunInShell => false;
  String get friendlyDescription => 'Android 系统 Shell';

  @override
  String toString() => 'ShellInfo(type=systemSh, path=$shellPath, version=$version)';
}

/// 默认 Shell 信息
const _kDefaultShell = ShellInfo();
// ─── 终端运行环境 ─────────────────────────────────────────────

/// 构建终端环境变量
///
/// 基础环境来源于 RuntimeManager（可包含 Termux/App Runtime 信息），
/// 配合合理默认值。不再使用旧 ShellDetector.getShellEnvironment()。
Map<String, String> _buildTerminalEnvironment({
  required String home,
  required Map<String, String> runtimeEnv,
}) {
  return {
    'HOME': home,
    'PATH': '/system/bin:/system/xbin',
    'SHELL': '/system/bin/sh',
    'TERM': 'xterm-256color',
    'PWD': home,
    'TMPDIR': Directory.systemTemp.path,
    'LANG': 'en_US.UTF-8',
    'USER': 'user',
    'LOGNAME': 'user',
    ...runtimeEnv, // runtimeEnv 优先（覆盖基础值）
  };
}

// ─── 终端会话状态 ─────────────────────────────────────────────

/// 终端会话状态
enum TerminalSessionStatus { running, exited, error }

// ─── 终端输出行 ───────────────────────────────────────────────

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

// ─── 终端会话 ─────────────────────────────────────────────────

/// 终端会话
///
/// 使用 RuntimeManager 获取运行环境，不再依赖旧 ShellDetector。
class TerminalSession {
  final String id;
  String name;
  final ShellInfo shellInfo;
  String cwd;
  TerminalSessionStatus status;
  final RingBuffer<TerminalLine> outputBuffer;
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  bool _disposed = false;

  /// Native PTY 后端（可选）
  ITerminalBackend? _backend;
  SessionHandle? _nativeSession;

  static const int maxBufferSize = 10000;

  TerminalSession({
    required this.id,
    required this.name,
    required this.shellInfo,
    required this.cwd,
    this.status = TerminalSessionStatus.running,
    RingBuffer<TerminalLine>? outputBuffer,
    ITerminalBackend? backend,
  }) : outputBuffer = outputBuffer ?? RingBuffer<TerminalLine>(maxBufferSize),
       _backend = backend;

  bool get isDisposed => _disposed;
  String get shellPath => shellInfo.shellPath;

  /// 获取当前输出文本
  String get outputText => outputBuffer.toList().map((l) => l.text).join('\n');

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
  }

  /// 启动进程
  Future<bool> start() async {
    if (_process != null || _nativeSession != null) return true;

    // 日志：启动前记录关键信息
    LogService.info('Terminal', '启动会话 $id');
    LogService.info('Terminal', '  Shell: ${shellInfo.shellPath}');
    LogService.info('Terminal', '  类型: ${shellInfo.friendlyDescription}');
    LogService.info('Terminal', '  Termux: ${shellInfo.isTermuxAvailable}');
    LogService.info('Terminal', '  工作目录: $cwd');
    LogService.info('Terminal', '  后端: ${_backend?.name ?? "process"} (${_backend?.runtimeType ?? "null"})');

    try {
      // 如果设置了 Native PTY 后端，优先使用
      if (_backend != null && _backend is NativePtyBackend) {
        return await _startWithNativePty();
      }

      // 否则使用 Process.start()（回退）
      return await _startWithProcess();
    } catch (e, stack) {
      status = TerminalSessionStatus.error;
      final msg = '启动失败: $e';
      addOutput(msg, isStderr: true);

      LogService.error('Terminal', '会话 $id 启动失败');
      LogService.error('Terminal', '  Shell: ${shellInfo.shellPath}');
      LogService.error('Terminal', '  错误: $e');
      LogService.error('Terminal', '  堆栈: $stack');

      return false;
    }
  }

  /// 使用 Process.start() 启动（回退方案）
  Future<bool> _startWithProcess() async {
    final appDir = await getApplicationDocumentsDirectory();

    // 从 RuntimeManager 获取运行环境
    Map<String, String> runtimeEnv = {};
    try {
      runtimeEnv = RuntimeManager.instance.getTerminalEnvironment();
    } catch (_) {}

    final env = _buildTerminalEnvironment(home: appDir.path, runtimeEnv: runtimeEnv);

    LogService.info('Terminal', '  使用 Process 回退');
    LogService.info('Terminal', '  HOME: ${env['HOME']}');
    LogService.info('Terminal', '  SHELL: ${env['SHELL']}');

    _process = await Process.start(
      shellInfo.shellPath,
      shellInfo.launchArgs,
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
  }

  /// 使用 Native PTY 启动
  Future<bool> _startWithNativePty() async {
    final appDir = await getApplicationDocumentsDirectory();

    // 从 RuntimeManager 获取运行环境
    Map<String, String> runtimeEnv = {};
    try {
      runtimeEnv = RuntimeManager.instance.getTerminalEnvironment();
    } catch (_) {}

    final env = _buildTerminalEnvironment(home: appDir.path, runtimeEnv: runtimeEnv);

    try {
      _nativeSession = await _backend!.createSession(
        shellPath: shellInfo.shellPath,
        args: shellInfo.launchArgs,
        workingDirectory: cwd,
        environment: env,
      );

      status = TerminalSessionStatus.running;
      LogService.info('Terminal', '  Native PTY 会话已创建');

      // 订阅输出流
      _nativeSession!.outputStream.listen(
        (line) => addOutput(line),
        onError: (e) {
          LogService.error('Terminal', '  PTY 输出错误: $e');
          addOutput('PTY error: $e', isStderr: true);
        },
      );

      _nativeSession!.errorStream.listen(
        (line) => addOutput(line, isStderr: true),
        onError: (e) {
          LogService.error('Terminal', '  PTY 错误流: $e');
        },
      );

      return true;
    } catch (e) {
      LogService.error('Terminal', '  Native PTY 启动失败: $e，回退到 Process 后端');
      // 回退到 Process 启动
      _backend = null;
      return await _startWithProcess();
    }
  }

  /// 写入命令
  void write(String command) {
    if (_disposed) return;
    try {
      if (_nativeSession != null) {
        _nativeSession!.write(command);
      } else if (_process != null) {
        _process!.stdin.writeln(command);
      }
      addOutput('\$ $command');
    } catch (e) {
      addOutput('写入失败: $e', isStderr: true);
      LogService.error('Terminal', '  写入失败: $e');
    }
  }

  /// 写入原始数据（不添加回显，用于 ExtraKeys 工具栏）
  void writeRaw(String data) {
    if (_disposed || data.isEmpty) return;
    try {
      if (_nativeSession != null) {
        _nativeSession!.write(data);
      } else if (_process != null) {
        _process!.stdin.write(data);
      }
    } catch (e) {
      LogService.error('Terminal', '  写入原始数据失败: $e');
    }
  }

  /// 发送 Ctrl+C
  void sendSigint() {
    if (_disposed) return;
    try {
      if (_nativeSession != null) {
        _nativeSession!.sendSigint();
      } else if (_process != null) {
        _process!.stdin.write('\x03');
      }
    } catch (_) {}
  }

  /// 调整终端大小（仅 Native PTY 支持）
  void resize(int rows, int cols) {
    if (_disposed) return;
    if (_nativeSession != null) {
      _nativeSession!.resize(rows, cols);
    }
  }

  /// 销毁会话
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    if (_nativeSession != null) {
      await _nativeSession!.close();
      _nativeSession = null;
    }

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

// ─── 终端服务 ─────────────────────────────────────────────────

/// 终端服务
///
/// 管理所有终端会话，使用 RuntimeManager 获取运行环境。
/// 不再依赖旧 ShellDetector。
class TerminalService {
  final List<TerminalSession> _sessions = [];
  ShellInfo? _cachedShellInfo;
  ITerminalBackend? _backend;

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);

  /// 当前后端
  ITerminalBackend? get backend => _backend;

  /// Native PTY 后端的便捷访问
  NativePtyBackend? get nativePtyBackend {
    if (_backend is NativePtyBackend) {
      return _backend as NativePtyBackend;
    }
    return null;
  }

  /// 设置后端（运行时切换）
  void setBackend(ITerminalBackend backend) {
    _backend = backend;
    LogService.info('Terminal', '后端切换为: ${backend.name}');
  }

  /// 重置为 Process 后端
  void useProcessBackend() {
    _backend = ProcessTerminalBackend();
    LogService.info('Terminal', '后端切换为: ${_backend!.name}');
  }

  /// 初始化默认后端 — 优先 Native PTY
  Future<void> initDefaultBackend() async {
    if (_backend != null) return;

    // 尝试 Native PTY
    final native = NativePtyBackend();
    final initialized = await native.initialize();
    if (initialized) {
      setBackend(native);
      LogService.info('Terminal', '使用 Native PTY 后端');
      LogService.info('Terminal', '  backend runtimeType: ${_backend.runtimeType}');
      return;
    }

    // 回退到 Process 后端
    LogService.warning('Terminal', 'Native PTY 初始化失败，使用 Process 后端');
    setBackend(ProcessTerminalBackend());
      LogService.info('Terminal', '  backend runtimeType: ${_backend.runtimeType}');
  }

  /// 创建新终端会话
  Future<TerminalSession> createSession({
    String? name,
    String? cwd,
  }) async {
    // 确保后端已初始化
    await initDefaultBackend();
    LogService.info('Terminal', 'createSession 后端: ${_backend?.runtimeType ?? "null"}');

    // 使用默认 Shell（始终为 Android 系统 Shell）
    _cachedShellInfo ??= _kDefaultShell;
    final shellInfo = _cachedShellInfo!;

    // 使用 App 私有目录作为默认工作目录
    final appDir = await getApplicationDocumentsDirectory();
    final home = cwd ?? appDir.path;

    final session = TerminalSession(
      id: const Uuid().v4(),
      name: name ?? '终端 ${_sessions.length + 1}',
      shellInfo: shellInfo,
      cwd: home,
      backend: _backend,
    );

    _sessions.add(session);
    LogService.info('Terminal', '创建会话: ${session.id} (${session.name})');
    LogService.info('Terminal', '  Shell: ${shellInfo.shellPath} (${shellInfo.friendlyDescription})');
    LogService.info('Terminal', '  后端: ${_backend?.name ?? "process"} (${_backend?.runtimeType ?? "null"})');

    final started = await session.start();
    if (!started) {
      LogService.warning('Terminal', '会话 ${session.id} 启动失败');
    }
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
    _cachedShellInfo = null;
  }
}
