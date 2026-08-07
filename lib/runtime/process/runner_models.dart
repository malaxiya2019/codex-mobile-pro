/// ====================================================================
/// Runtime Process Runner — 数据模型
///
/// 统一、可靠、可测试地执行 Runtime 命令的核心模型。
///
/// 设计原则：
///   1. 不可变请求模型
///   2. 结构化结果模型
///   3. 清晰区分执行类型
///   4. 保留完整诊断信息
///
/// 使用方式：
///   final request = RuntimeProcessRequest(
///     executable: resolvedPath,
///     arguments: ['--version'],
///     environment: {'PATH': '/custom/path'},
///     workingDirectory: '/tmp',
///     timeout: Duration(seconds: 30),
///   );
///   final result = await runner.run(request);
/// ====================================================================
library;

/// ====================================================================
/// 执行请求 — 不可变模型
/// ====================================================================
class RuntimeProcessRequest {
  /// 可执行文件路径（已解析的绝对路径）
  final String executable;

  /// 命令行参数
  final List<String> arguments;

  /// 环境变量覆盖
  ///
  /// 与 Provider environment 合并规则（优先级从高到低）：
  ///   1. 此字段中的值（Request environment）
  ///   2. Runner 默认值（PATH / HOME / TMPDIR）
  ///   3. Provider 提供的 environment
  final Map<String, String>? environment;

  /// 工作目录
  final String? workingDirectory;

  /// 超时时间
  final Duration? timeout;

  /// 是否通过 shell 执行
  ///
  /// 默认 false（direct execution）。
  /// 仅当明确需要 shell 特性（管道、重定向、通配符）时设为 true。
  final bool runInShell;

  /// 标准输入
  final String? stdin;

  /// 运行时标识（用于 Provider 路由）
  ///
  /// 例如 "android", "linux"。
  /// 如果为 null，由 Runner 根据 executable 自动决定。
  final String? runtimeId;

  /// 自定义标签（用于日志/诊断）
  final String? label;

  /// 流式 stdout 回调（可选）
  ///
  /// 每收到一段 stdout 增量就调用一次。用于需要实时消费
  /// 输出流的场景（如 `codex exec --json` 的 JSONL 事件流）。
  /// 只读消费，不改变输出收集逻辑；null 表示不回调。
  final void Function(String chunk)? onStdoutChunk;

  const RuntimeProcessRequest({
    required this.executable,
    this.arguments = const [],
    this.environment,
    this.workingDirectory,
    this.timeout,
    this.runInShell = false,
    this.stdin,
    this.runtimeId,
    this.label,
    this.onStdoutChunk,
  });

  /// 创建带有 shell 包装的请求副本
  ///
  /// 将 executable + arguments 包装成：
  ///   /system/bin/sh -c "executable arg1 arg2"
  RuntimeProcessRequest withShell() {
    // 对参数进行 shell 转义
    final escapedArgs = arguments.map(_shellEscape).join(' ');
    final shellCommand = '$executable $escapedArgs';

    return RuntimeProcessRequest(
      executable: '/system/bin/sh',
      arguments: ['-c', shellCommand],
      environment: environment,
      workingDirectory: workingDirectory,
      timeout: timeout,
      stdin: stdin,
      runtimeId: runtimeId,
      label: label,
      onStdoutChunk: onStdoutChunk,
    );
  }

  /// Shell 转义单个参数
  static String _shellEscape(String arg) {
    if (arg.contains(' ') || arg.contains('"') || arg.contains('\'')) {
      return "'${arg.replaceAll("'", "'\\''")}'";
    }
    return arg;
  }

  @override
  String toString() =>
      'ProcessRequest(executable: $executable, args: $arguments, '
      'runtimeId: $runtimeId, label: $label)';
}

/// ====================================================================
/// 执行结果 — 不可变模型
/// ====================================================================
class RuntimeProcessResult {
  /// 退出码
  ///   - 0 — 成功
  ///   - >0 — 进程退出码
  ///   - -1 — 启动失败
  ///   - -2 — 超时
  ///   - -3 — 取消
  final int exitCode;

  /// 标准输出
  final String stdout;

  /// 标准错误
  final String stderr;

  /// 实际耗时
  final Duration duration;

  /// 是否超时
  final bool timedOut;

  /// 是否被取消
  final bool cancelled;

  /// 超时/取消后，stdout/stderr 管道未在 cleanupTimeout 内排空
  /// （tracee 仍持有写端，如 apt-get 卡 TCP connect 的 D 状态），
  /// 清理被强制终止。true = process cleanup timeout。
  final bool cleanupTimedOut;

  /// 进程信号（如果被信号终止）
  final String? signal;

  /// 错误信息（启动失败时）
  final String? error;

  /// 原始请求
  final RuntimeProcessRequest request;

  const RuntimeProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.duration = Duration.zero,
    this.timedOut = false,
    this.cancelled = false,
    this.cleanupTimedOut = false,
    this.signal,
    this.error,
    required this.request,
  });

  /// 是否成功执行（退出码为 0）
  bool get isSuccess => exitCode == 0;

  /// 是否启动失败
  bool get failedToStart => exitCode == -1;

  /// 所有输出（stdout + stderr）
  String get allOutput => '$stdout\n$stderr'.trim();

  @override
  String toString() =>
      'ProcessResult(exitCode: $exitCode, duration: $duration, '
      'stdout: ${stdout.length}ch, stderr: ${stderr.length}ch, '
      'timedOut: $timedOut, cancelled: $cancelled'
      '${cleanupTimedOut ? ", cleanupTimedOut: true" : ""}'
      '${error != null ? ", error: $error" : ""}'
      '${signal != null ? ", signal: $signal" : ""})';
}

/// ====================================================================
/// 结构化执行错误
/// ====================================================================
enum RuntimeProcessErrorType {
  /// 可执行文件不存在或无法访问
  executableNotFound,

  /// 权限不足
  permissionDenied,

  /// 进程启动失败
  startFailed,

  /// 执行超时
  timeout,

  /// 被取消
  cancelled,

  /// 进程退出码非零
  nonZeroExit,

  /// Runtime 不可用
  runtimeUnavailable,

  /// IPC 通信失败（远程执行）
  ipcFailed,

  /// 原生进程崩溃
  nativeProcessFailed,
}

/// 结构化执行错误
class RuntimeProcessError implements Exception {
  final RuntimeProcessErrorType type;
  final String message;
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final String? detail;

  const RuntimeProcessError({
    required this.type,
    required this.message,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.detail,
  });

  /// 从 RuntimeProcessResult 创建错误
  factory RuntimeProcessError.fromResult(
    RuntimeProcessResult result, {
    String? message,
  }) {
    RuntimeProcessErrorType type;
    if (result.failedToStart) {
      type = RuntimeProcessErrorType.startFailed;
    } else if (result.timedOut) {
      type = RuntimeProcessErrorType.timeout;
    } else if (result.cancelled) {
      type = RuntimeProcessErrorType.cancelled;
    } else if (!result.isSuccess) {
      type = RuntimeProcessErrorType.nonZeroExit;
    } else {
      type = RuntimeProcessErrorType.nonZeroExit;
    }

    return RuntimeProcessError(
      type: type,
      message: message ?? '进程执行失败 (exitCode=${result.exitCode})',
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  /// 从 ProcessException 创建
  factory RuntimeProcessError.fromProcessError(
    Object error, {
    String? executable,
  }) {
    if (error is RuntimeProcessError) return error;

    final msg = error.toString();
    final executable_ = executable ?? '<unknown>';

    RuntimeProcessErrorType type;
    if (msg.contains('Permission denied')) {
      type = RuntimeProcessErrorType.permissionDenied;
    } else if (msg.contains('No such file or directory') ||
        msg.contains('not found')) {
      type = RuntimeProcessErrorType.executableNotFound;
    } else {
      type = RuntimeProcessErrorType.startFailed;
    }

    return RuntimeProcessError(
      type: type,
      message: '$executable_: $msg',
      detail: msg,
    );
  }

  @override
  String toString() =>
      'RuntimeProcessError[$type]: $message'
      '${exitCode != null ? " (exit=$exitCode)" : ""}'
      '${detail != null ? "\n  detail: $detail" : ""}';
}

/// ====================================================================
/// 执行适配器接口
///
/// 不同的 Runtime 使用不同的底层执行方式：
///   - Android/App Runtime → LocalProcessExecution → Process.start
///   - Linux Runtime      → LinuxExecutionAdapter → PRoot → Ubuntu rootfs
///   - Android / App      → LocalProcessExecution
///
/// 所有适配器返回统一的 RuntimeProcessResult。
/// ====================================================================
abstract class IExecutionAdapter {
  /// 适配器标识
  String get id;

  /// 执行命令
  Future<RuntimeProcessResult> execute(RuntimeProcessRequest request);

  /// 是否支持此 executable
  bool supports(RuntimeProcessRequest request);
}

/// ====================================================================
/// 环境合并工具
///
/// 合并规则（优先级从高到低）：
///   1. Request environment
///   2. Runner 默认 environment（PATH / HOME / TMPDIR）
///   3. Provider environment
/// ====================================================================
class EnvironmentMerger {
  /// 合并环境变量
  ///
  /// [providerEnv] — Provider 提供的基础环境
  /// [requestEnv]  — 请求中的环境变量覆盖
  /// [defaults]    — Runner 默认值（PATH, HOME, TMPDIR）
  static Map<String, String> merge({
    required Map<String, String> providerEnv,
    Map<String, String>? requestEnv,
    Map<String, String>? defaults,
  }) {
    final result = Map<String, String>.from(providerEnv);

    // 第二层：Runner 默认值（不覆盖已存在的值）
    if (defaults != null) {
      for (final entry in defaults.entries) {
        result.putIfAbsent(entry.key, () => entry.value);
      }
    }

    // 第一层（最高优先级）：Request 环境变量
    if (requestEnv != null) {
      result.addAll(requestEnv);
    }

    return result;
  }

  /// 构建默认环境
  static Map<String, String> defaultEnvironment({String? appHome}) {
    final env = <String, String>{
      'PATH': '/system/bin:/system/xbin:/vendor/bin',
      'HOME': appHome ?? '/data/data/com.codexmobile.app/app_flutter',
      'TMPDIR': '/data/local/tmp',
    };
    return env;
  }
}
