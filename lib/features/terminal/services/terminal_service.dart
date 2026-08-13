import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/logger/log_service.dart';
import '../../../core/terminal/iterminal_backend.dart';
import '../../../core/terminal/native_pty_backend.dart';
import '../../../core/terminal/process_terminal_backend.dart';
import '../../../runtime/process/guest_cwd.dart';
import '../../../runtime/runtime_manager.dart';
import 'ring_buffer.dart';

// ─── Shell 信息（本地定义，替代旧 ShellDetector）─────────────


/// Shell 信息
///
/// 运行时 Shell 来源：
///   1. Linux Runtime（PRoot → Ubuntu /bin/bash）— 主 Shell
///   2. Android 系统 Shell（/system/bin/sh）— 回退
class ShellInfo {
  /// 可执行文件绝对路径（proot 或 /system/bin/sh）
  final String shellPath;

  /// 启动参数（Linux 时为 PRoot 参数，如 -r rootfs /bin/bash -l）
  final List<String> args;

  final String version;

  /// 是否 Linux Runtime Shell
  final bool isLinux;

  const ShellInfo({
    this.shellPath = '/system/bin/sh',
    this.args = const ['-i'],
    this.version = 'Android System Shell',
    this.isLinux = false,
  });

  bool get isAvailable => true;
  List<String> get launchArgs => args;
  bool get useRunInShell => false;
  String get friendlyDescription => isLinux ? 'Linux Runtime Shell' : 'Android 系统 Shell';

  @override
  String toString() => 'ShellInfo(isLinux=$isLinux, path=$shellPath, args=$args, version=$version)';
}

/// 默认 Shell 信息
const _kDefaultShell = ShellInfo();
// ─── 命令输入解析 ───────────────────────────────────────────────

/// 把输入文本拆成命令行（逐行执行）。
///
/// 支持多行粘贴场景：终端输入框是多行 TextField（换行符保留），
/// 粘贴一段脚本（含注释行、空行）时按行拆分、过滤空行，
/// 每行作为一条独立命令写入 PTY —— 与真实终端粘贴多行脚本逐行
/// 执行的行为一致。
///
/// 注意：单行 TextField 会经 FilteringTextInputFormatter 删除 \n，
/// 导致多行脚本粘连（如 'dpkg --configure -aapt'），此处拆行依赖
/// 多行输入框保留换行符。
List<String> splitCommandLines(String text) {
  return text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

// ─── 终端运行环境 ─────────────────────────────────────────────

/// 构建终端环境变量
///
/// 基础环境来源于 RuntimeManager：
///   - Linux Runtime 就绪 → LinuxRuntimeProvider 环境（HOME=/root、PATH、SHELL=/bin/bash）
///   - 否则 → Android 系统默认环境（/system/bin/sh 回退）
/// 不再使用旧 ShellDetector。
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

  /// PTY 尺寸（App 内终端按此列宽排版，与后端一致；渲染器按 cols 截断行宽）
  int rows;
  int cols;
  final RingBuffer<TerminalLine> outputBuffer;
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  bool _disposed = false;

  /// Native PTY 后端（可选）
  ITerminalBackend? _backend;
  SessionHandle? _nativeSession;

  static const int maxBufferSize = 10000;

  /// 未完成输出行（流式模式：Native PTY 的 chunk 可能不带 \n，
  /// 例如 bash 的 prompt / resize 重绘序列，必须累积到同一行再提交）
  String _pendingLine = '';

  /// 流式模式：Native PTY 后端启用（chunk 按流处理，只有 \n 才提交行）。
  /// Process 后端（LineSplitter 已按行）保持逐行语义。
  bool _streamMode = false;

  /// 未完成行防失控上限：超过强制提交为一行（真实终端流异常保护，
  /// 正常交互下 prompt/重绘序列远小于该值，不会触发）。
  static const int maxPendingLength = 65536;

  TerminalSession({
    required this.id,
    required this.name,
    required this.shellInfo,
    required this.cwd,
    this.status = TerminalSessionStatus.running,
    this.rows = 60,
    this.cols = 120,
    RingBuffer<TerminalLine>? outputBuffer,
    ITerminalBackend? backend,
  }) : outputBuffer = outputBuffer ?? RingBuffer<TerminalLine>(maxBufferSize),
       _backend = backend;

  bool get isDisposed => _disposed;
  String get shellPath => shellInfo.shellPath;

  /// 获取当前输出文本
  String get outputText {
    final lines = outputBuffer.toList().map((l) => l.text).toList();
    if (_streamMode && _pendingLine.isNotEmpty) {
      lines.add(_pendingLine);
    }
    return lines.join('\n');
  }

  /// 添加输出
  ///
  /// 流式模式（Native PTY）：chunk 可能不带 \n（bash prompt、resize 重绘
  /// `\r\x1b[K\r<prompt>` 均无换行）。按行 split 会把同一逻辑行拆成多个
  /// buffer 行，outputText join 时人为插入 \n，导致 AnsiParser 的
  /// `\r` 覆盖语义跨行失效 —— resize 重绘的 prompt 在真机上堆叠成多行。
  /// 此处维护未完成行：只有真正出现 \n 才提交一行，\r/覆盖序列保留在
  /// 同一行内，交给 AnsiParser 行内覆盖。
  ///
  /// 逐行模式（Process 后端，LineSplitter 已按行切好）：保持原行为。
  void addOutput(String text, {bool isStderr = false}) {
    if (_disposed) return;
    if (!_streamMode) {
      final lines = text.split('\n');
      for (final line in lines) {
        if (line.isEmpty) continue;
        outputBuffer.add(
          TerminalLine(
              text: line, isStderr: isStderr, timestamp: DateTime.now()),
        );
      }
      return;
    }

    final combined = _pendingLine + text;
    final parts = combined.split('\n');
    _pendingLine = parts.removeLast();
    for (final part in parts) {
      // CRLF 换行：split 后行尾残留 \r（`\r\n`），与 Process 后端
      // LineSplitter 行为一致地剥掉；行中 \r（覆盖序列）不受影响。
      var line = part;
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) continue;
      outputBuffer.add(
        TerminalLine(text: line, isStderr: isStderr, timestamp: DateTime.now()),
      );
    }
    // 防失控：未完成行异常增长时强制提交
    if (_pendingLine.length > maxPendingLength) {
      outputBuffer.add(
        TerminalLine(
          text: _pendingLine,
          isStderr: isStderr,
          timestamp: DateTime.now(),
        ),
      );
      _pendingLine = '';
    }
  }

  /// 启动进程
  Future<bool> start() async {
    if (_process != null || _nativeSession != null) return true;

    // 日志：启动前记录关键信息
    LogService.info('Terminal', '启动会话 $id');
    LogService.info('Terminal', '  Shell: ${shellInfo.shellPath}');
    LogService.info('Terminal', '  类型: ${shellInfo.friendlyDescription}');
    LogService.info('Terminal', '  Linux Shell: ${shellInfo.isLinux}');
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

    // 从 RuntimeManager 获取运行环境（Linux 优先）
    Map<String, String> runtimeEnv = {};
    try {
      runtimeEnv = await RuntimeManager.instance.getTerminalEnvironment();
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

    // 从 RuntimeManager 获取运行环境（Linux 优先）
    Map<String, String> runtimeEnv = {};
    try {
      runtimeEnv = await RuntimeManager.instance.getTerminalEnvironment();
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

      // Native PTY 输出是字节流（非按行），启用流式缓冲，
      // 保证 resize 重绘 / prompt 等无换行输出不跨行堆叠。
      _streamMode = true;

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
  ///
  /// Native PTY 与 Process 两个后端行为保持一致：命令必须以换行符结尾，
  /// bash 收到回车才会执行（PTY 原始写入不会自动追加换行）。
  void write(String command) {
    if (_disposed) return;
    try {
      if (_nativeSession != null) {
        // 提交回车统一用 \r：
        //   - bash（canonical + ICRNL）把输入 \r 由内核转换为 \n 再执行，行为不变；
        //   - Codex TUI 等 raw-mode 全屏程序把 \r 识别为 Enter（\n 在某些
        //     crossterm 输入解析下不会被当成回车，导致命令无法提交）。
        _nativeSession!.write('$command\r');
      } else if (_process != null) {
        _process!.stdin.writeln(command);
      }
      // Native PTY 在 ICANON|ECHO 下由终端驱动回显输入行，UI 再追加
      // '$ command' 会与 ECHO 回显重复（真机可见命令回显两行）。
      // Process 后端无 ECHO，保留手动回显。
      if (!_streamMode) {
        addOutput('\$ $command');
      }
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
    this.rows = rows;
    this.cols = cols;
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

  /// 解析终端 Shell 来源
  ///
  /// 优先使用 Linux Runtime（RuntimeManager → LinuxRuntimeProvider → PRoot → /bin/bash）。
  /// Linux Runtime 未就绪时回退到 Android 系统 Shell。
  Future<ShellInfo> _resolveShellInfo({String? workingDirectory}) async {
    try {
      final spec = await RuntimeManager.instance.buildTerminalShellSpec(
        workingDirectory: workingDirectory,
      );
      if (spec != null) {
        LogService.info('Terminal', '  使用 Linux Runtime Shell (PRoot)');
        return ShellInfo(
          shellPath: spec.executable,
          args: spec.arguments,
          version: 'Linux Runtime Shell',
          isLinux: true,
        );
      }
    } catch (e) {
      LogService.error('Terminal', '  解析 Linux Shell 失败，回退 Android Shell: $e');
    }
    LogService.info('Terminal', '  使用 Android 系统 Shell（回退）');
    return _kDefaultShell;
  }

  /// 创建新终端会话
  Future<TerminalSession> createSession({
    String? name,
    String? cwd,
  }) async {
    // 确保后端已初始化
    await initDefaultBackend();
    LogService.info('Terminal', 'createSession 后端: ${_backend?.runtimeType ?? "null"}');

    // 使用 App 私有目录作为默认工作目录
    final appDir = await getApplicationDocumentsDirectory();
    final home = cwd ?? appDir.path;

    // guest cwd（PRoot rootfs 内）：host 路径不得直接作为 guest 工作目录，
    // 否则 proot 会报 can't chdir(...) in the guest rootfs 并回落到 "/"。
    // host 侧 workDir（home）仍用于 host chdir，PRoot 侧由 -w guestCwd 控制。
    final guestCwd = normalizeGuestCwd(home);

    // 解析 Shell 来源：
    //   1. Linux Runtime（PRoot → Ubuntu /bin/bash）— 优先
    //   2. Android 系统 Shell（/system/bin/sh）— 回退
    final shellInfo = await _resolveShellInfo(workingDirectory: guestCwd);

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
  }
}
