/// ====================================================================
/// CodexRunner — 在 Linux Runtime（PRoot + Ubuntu rootfs）内流式执行
/// `codex exec --json`，并把 JSONL 事件流解析为强类型事件。
///
/// 关键事实（已实测验证，rootfs = Ubuntu noble + codex-cli 0.147）：
///   1. codex 运行在 rootfs 内（npm -g → /usr/local/bin/codex），
///      通过 PRoot 启动，`--link2symlink --change-id=0:0` 保证 apt/dpkg
///      基建可用（与部署链路一致）。
///   2. 用户工作目录在 rootfs 外（App 私有目录），通过
///      `proot -b <hostDir> <guestDir>` 绑定进去，codex 可真实读写
///      宿主文件（这是「AI 编程助手」能改项目文件的前提）。
///   3. codex 在 rootfs 内直连 DeepSeek（rootfs 里 rustls↔CloudFront
///      TLS 正常，无需宿主 fwd-proxy）；API key 从 rootfs
///      `/root/.mimo2codex/.env`（DS_API_KEY=）读取并注入
///      `DEEPSEEK_API_KEY` 环境变量（codex config.toml env_key）。
///   4. 必须 `--dangerously-bypass-approvals-and-sandbox`：
///      `--sandbox workspace-write` 的 fs sandbox helper 与 PRoot 不兼容
///      （实测所有命令 exit=182），bypass 才能让 codex 真实执行命令。
///   5. stdin 必须 `</dev/null`：`codex exec` 检测到 stdin 是 pipe 时会
///      等待追加 `<stdin>` block，导致进程挂起。
///   6. `thread.started` 返回 thread_id，可存 session 供将来
///      `codex exec resume` 续跑。
///
/// 事件流（codex 0.147 实测）：
///   thread.started → turn.started → item.* （agent_message /
///   command_execution）→ turn.completed
/// ====================================================================
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../runtime/process/process_runner.dart';
import '../../runtime/process/runner_models.dart';
import '../../runtime/provider/linux_runtime_provider.dart';

// ══════════════════════════════════════════════
// 强类型事件模型
// ══════════════════════════════════════════════

/// codex exec 事件基类
sealed class CodexEvent {
  const CodexEvent();
}

/// thread 已创建（含 thread_id，供 resume）
class CodexThreadStarted extends CodexEvent {
  final String threadId;
  const CodexThreadStarted({required this.threadId});
}

/// 一轮生成开始
class CodexTurnStarted extends CodexEvent {
  const CodexTurnStarted();
}

/// 智能体文本消息（增量语义：每次出现即一段新文本）
class CodexAgentMessage extends CodexEvent {
  final String text;
  const CodexAgentMessage({required this.text});
}

/// 命令开始执行
class CodexCommandStarted extends CodexEvent {
  final String id;
  final String command;
  const CodexCommandStarted({required this.id, required this.command});
}

/// 命令执行完成（含退出码与累积输出）
class CodexCommandCompleted extends CodexEvent {
  final String id;
  final String command;
  final int? exitCode;
  final String output;
  const CodexCommandCompleted({
    required this.id,
    required this.command,
    this.exitCode,
    this.output = '',
  });
}

/// 一轮生成完成（含 token 用量）
class CodexTurnCompleted extends CodexEvent {
  final int? inputTokens;
  final int? outputTokens;
  const CodexTurnCompleted({this.inputTokens, this.outputTokens});
}

/// codex 事件错误（多为无害 fallback 警告，如 model metadata）
class CodexErrorEvent extends CodexEvent {
  final String message;
  const CodexErrorEvent({required this.message});
}

// ══════════════════════════════════════════════
// 监听器
// ══════════════════════════════════════════════

/// codex exec 事件监听器
abstract class CodexEventListener {
  /// 收到一个解析后的事件
  void onCodexEvent(CodexEvent event);

  /// 进程退出
  void onCodexExit(int exitCode);
}

// ══════════════════════════════════════════════
// CodexRunner
// ══════════════════════════════════════════════

/// CodexRunner 执行结果
class CodexRunResult {
  final int exitCode;
  final bool timedOut;
  final bool cancelled;
  final bool cleanupTimedOut;
  final String? error;
  final String? threadId;

  const CodexRunResult({
    required this.exitCode,
    this.timedOut = false,
    this.cancelled = false,
    this.cleanupTimedOut = false,
    this.error,
    this.threadId,
  });

  bool get isSuccess => exitCode == 0 && !cancelled && !timedOut;
}

/// 在 rootfs 内执行 codex 的 Runner
///
/// [provider] 用于解析 PRoot/rootfs 路径与环境；[inner] 为实际进程
/// 执行器（测试可注入 Fake，重写 execute 输出假 JSONL）。
class CodexRunner {
  final LinuxRuntimeProvider _provider;
  final LocalProcessExecution _inner;

  /// guest（rootfs 内）工作目录挂载点
  static const String guestWorkspaceDir = '/workspace';

  CodexRunner({
    LinuxRuntimeProvider? provider,
    LocalProcessExecution? inner,
  }) : _provider = provider ?? LinuxRuntimeProvider(),
       _inner = inner ?? LocalProcessExecution();

  /// 请求停止当前执行（kill 进程）
  void stop() => _inner.requestCancel();

  /// 执行一轮 codex exec
  ///
  /// [prompt] — 用户指令（追加到 systemPrompt 之后）
  /// [hostWorkingDir] — 宿主工作目录（codex 将真实读写此处）
  /// [systemPrompt] — 系统提示词（非空时拼到 prompt 前部）
  /// [timeout] — 单轮超时（null 表示不超时）
  /// [listener] — 事件监听
  Future<CodexRunResult> run({
    required String prompt,
    required String hostWorkingDir,
    String? systemPrompt,
    Duration? timeout,
    required CodexEventListener listener,
  }) async {
    try {
      final paths = await _provider.resolvePaths();

      // ─── 1. 校验 codex 已安装 ────────────────────────────────
      final codexExecutable = await _provider.resolveExecutable('codex');
      if (codexExecutable == null) {
        return const CodexRunResult(
          exitCode: -1,
          error: 'Codex CLI 未安装，请先在「部署中心」安装 Codex CLI',
        );
      }

      // ─── 2. 读取 DeepSeek API key（rootfs 内 codex 读取位置）──
      final apiKey = _readDeepSeekKey(paths);
      if (apiKey == null) {
        return const CodexRunResult(
          exitCode: -1,
          error: '未配置 DeepSeek API Key，请先在「部署中心」保存 API Key',
        );
      }

      // ─── 3. 确保宿主工作目录存在 ─────────────────────────────
      try {
        await Directory(hostWorkingDir).create(recursive: true);
      } catch (e) {
        return CodexRunResult(
          exitCode: -1,
          error: '无法创建/访问工作目录 $hostWorkingDir: $e',
        );
      }

      // ─── 4. 组装完整 prompt（system + user）─────────────────
      final fullPrompt = (systemPrompt != null && systemPrompt.trim().isNotEmpty)
          ? '$systemPrompt\n\n$prompt'
          : prompt;

      // ─── 5. 统一生成 PRoot 参数（绑定用户工作目录）──────────
      final codexBin = _toRootfsPath(paths.rootfsDir, codexExecutable);
      // `exec` 关键字让 bash 进程替换为 codex，信号直接送达 codex
      final innerCommand =
          'exec $codexBin exec --json --skip-git-repo-check '
          '--dangerously-bypass-approvals-and-sandbox '
          '"\$CODEX_PROMPT" </dev/null';

      final arguments = <String>[
        '-r', paths.rootfsDir,
        ...LinuxRuntimeProvider.prootBindArguments(),
        '-b', hostWorkingDir, guestWorkspaceDir,
        '-w', guestWorkspaceDir,
        '/bin/bash',
        '-lc',
        innerCommand,
      ];

      // ─── 6. 环境合并：Linux 基础环境 + key + prompt ─────────
      final hostTmpDir = '${paths.rootfsDir}/tmp';
      try {
        await Directory(hostTmpDir).create(recursive: true);
      } catch (_) {}
      final environment = _provider.buildEnvironment(paths);
      environment['PROOT_TMP_DIR'] = hostTmpDir;
      environment['DEEPSEEK_API_KEY'] = apiKey;
      // prompt 经环境变量传递，避免 shell 转义（可含引号/换行）
      environment['CODEX_PROMPT'] = fullPrompt;

      // ─── 7. 执行（带流式 stdout 解析 + 超时）────────────────
      final lineBuffer = StringBuffer();
      var threadId = '';

      final request = RuntimeProcessRequest(
        executable: paths.prootExecutable,
        arguments: arguments,
        environment: environment,
        workingDirectory: guestWorkspaceDir,
        timeout: timeout,
        label: 'proot:codex-exec',
        onStdoutChunk: (chunk) {
          threadId = _consumeChunk(
            chunk,
            lineBuffer,
            listener,
            currentThreadId: threadId,
          );
        },
      );

      final result = await _inner.execute(request);

      // ─── 8. 解析尾随缓冲（最后一行可能无换行）───────────────
      _flushLineBuffer(lineBuffer, listener);

      if (result.failedToStart) {
        return CodexRunResult(
          exitCode: result.exitCode,
          error: '启动 codex 失败: ${result.error}',
          threadId: threadId.isEmpty ? null : threadId,
        );
      }

      return CodexRunResult(
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        cancelled: result.cancelled,
        cleanupTimedOut: result.cleanupTimedOut,
        error: result.error,
        threadId: threadId.isEmpty ? null : threadId,
      );
    } catch (e) {
      return CodexRunResult(exitCode: -1, error: 'codex 执行异常: $e');
    }
  }

  // ─── JSONL 解析 ─────────────────────────────────────────────

  /// 消费一段 stdout 增量：按行缓冲，完整行解析为事件。
  ///
  /// 返回当前 threadId（若本段解析到 thread.started 则更新）。
  String _consumeChunk(
    String chunk,
    StringBuffer lineBuffer,
    CodexEventListener listener,
    {required String currentThreadId}
  ) {
    var threadId = currentThreadId;
    lineBuffer.write(chunk);
    var text = lineBuffer.toString();
    var newlineIndex = text.indexOf('\n');
    while (newlineIndex >= 0) {
      final line = text.substring(0, newlineIndex).trim();
      if (line.isNotEmpty) {
        final parsed = _parseLine(line);
        if (parsed is CodexThreadStarted) {
          threadId = parsed.threadId;
        }
        listener.onCodexEvent(parsed);
      }
      text = text.substring(newlineIndex + 1);
      newlineIndex = text.indexOf('\n');
    }
    // 剩余未换行部分保留在缓冲
    lineBuffer.clear();
    lineBuffer.write(text);
    return threadId;
  }

  void _flushLineBuffer(StringBuffer lineBuffer, CodexEventListener listener) {
    final rest = lineBuffer.toString().trim();
    if (rest.isNotEmpty) {
      listener.onCodexEvent(_parseLine(rest));
    }
  }

  /// 解析一行 JSONL 为强类型事件
  CodexEvent _parseLine(String line) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        return CodexErrorEvent(message: '非对象 JSON 行: $line');
      }
      json = decoded;
    } catch (e) {
      return CodexErrorEvent(message: 'JSON 解析失败: $e');
    }

    final type = json['type'] as String? ?? '';
    switch (type) {
      case 'thread.started':
        return CodexThreadStarted(
          threadId: (json['thread_id'] as String?) ?? '',
        );
      case 'turn.started':
        return const CodexTurnStarted();
      case 'turn.completed':
        final usage = json['usage'] as Map<String, dynamic>? ?? const {};
        return CodexTurnCompleted(
          inputTokens: usage['input_tokens'] as int?,
          outputTokens: usage['output_tokens'] as int?,
        );
      case 'item.started':
        final item = json['item'] as Map<String, dynamic>? ?? const {};
        if (item['type'] == 'command_execution') {
          return CodexCommandStarted(
            id: (item['id'] as String?) ?? '',
            command: (item['command'] as String?) ?? '',
          );
        }
        return CodexErrorEvent(
          message: '未知 item.started 类型: ${item['type']}',
        );
      case 'item.completed':
        final item = json['item'] as Map<String, dynamic>? ?? const {};
        switch (item['type']) {
          case 'agent_message':
            return CodexAgentMessage(
              text: (item['text'] as String?) ?? '',
            );
          case 'command_execution':
            return CodexCommandCompleted(
              id: (item['id'] as String?) ?? '',
              command: (item['command'] as String?) ?? '',
              exitCode: item['exit_code'] as int?,
              output: (item['aggregated_output'] as String?) ?? '',
            );
          case 'error':
            return CodexErrorEvent(
              message: (item['message'] as String?) ?? '',
            );
          default:
            return CodexErrorEvent(
              message: '未知 item 类型: ${item['type']}',
            );
        }
      default:
        return CodexErrorEvent(message: '未知事件类型: $type');
    }
  }

  // ─── 辅助 ───────────────────────────────────────────────────

  /// 读取 rootfs 内 DeepSeek API key（DS_API_KEY=）
  static String? _readDeepSeekKey(LinuxRuntimePaths paths) {
    try {
      final envFile = File('${paths.rootfsDir}/root/.mimo2codex/.env');
      if (!envFile.existsSync()) return null;
      final content = envFile.readAsStringSync();
      for (final line in content.split('\n')) {
        if (line.startsWith('DS_API_KEY=')) {
          final key = line.substring('DS_API_KEY='.length).trim();
          if (key.isNotEmpty) return key;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 将 rootfs 绝对路径转换为 guest 内路径
  static String _toRootfsPath(String rootfsDir, String executable) {
    if (executable.startsWith(rootfsDir)) {
      final rel = executable.substring(rootfsDir.length);
      if (rel.isEmpty) return executable;
      return rel.startsWith('/') ? rel : '/$rel';
    }
    return executable;
  }
}
