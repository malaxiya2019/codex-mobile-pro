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

import '../../core/logger/log_service.dart';
import '../../runtime/process/linux_execution.dart';
import '../../runtime/process/process_runner.dart';
import '../../runtime/process/runner_models.dart';
import '../../runtime/provider/linux_runtime_provider.dart';
import '../../runtime/runtime_manager.dart';

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

  /// codex 进程 stdout（JSONL 事件原始文本；诊断用，正常回复不依赖它）
  final String stdout;

  /// codex 进程 stderr（codex 启动/运行错误常写在此；诊断用）
  final String stderr;

  /// [AI-DEBUG] 全链路诊断文本（多行）：命令/路径/exitCode/stdout 全文/
  /// stderr 全文/解析事件统计/agent_message 提取。供 ChatEngine 在失败或
  /// 空回复时展示、正常回复时写入 metadata。临时取证用，取证完成后移除。
  final String debugLog;

  const CodexRunResult({
    required this.exitCode,
    this.timedOut = false,
    this.cancelled = false,
    this.cleanupTimedOut = false,
    this.error,
    this.threadId,
    this.stdout = '',
    this.stderr = '',
    this.debugLog = '',
  });

  bool get isSuccess => exitCode == 0 && !cancelled && !timedOut;

  CodexRunResult copyWith({
    String? debugLog,
  }) => CodexRunResult(
        exitCode: exitCode,
        timedOut: timedOut,
        cancelled: cancelled,
        cleanupTimedOut: cleanupTimedOut,
        error: error,
        threadId: threadId,
        stdout: stdout,
        stderr: stderr,
        debugLog: debugLog ?? this.debugLog,
      );
}

/// 在 rootfs 内执行 codex 的 Runner
///
/// 统一入口（与部署中心 / Terminal / Git 共用同一 Linux Runtime 执行链）：
///   Android App
///     → CodexRunner
///     → RuntimeProcessRunner（runtimeId='linux'）
///     → LinuxExecutionAdapter（PRoot 参数唯一生成点，即 ProotExecutor）
///     → LocalProcessExecution
///     → PRoot（Ubuntu 24.04 rootfs）
///     → /bin/bash -lc 'exec /usr/local/bin/codex exec --json ...'
///
/// [provider] 默认复用 [RuntimeManager] 的共享 [LinuxRuntimeProvider] 实例
/// （与部署中心一致，nativeLibraryDir 路径缓存全局一致；启动失败自愈会
/// 同步刷新部署中心使用的同一缓存）。[processExecution] 可注入（测试用
/// Fake，重写 execute 输出假 JSONL）。
class CodexRunner {
  final LinuxRuntimeProvider _provider;

  /// 实际执行器（RuntimeProcessRunner + LinuxExecutionAdapter 统一链路）
  late final RuntimeProcessRunner _runner;

  /// 底层进程执行器（CodexRunner 私有实例，stop() 只取消 codex 运行，
  /// 不影响共享 runner 上其他组件如 git / 部署中心的在途任务）
  final LocalProcessExecution _process;

  /// guest（rootfs 内）工作目录挂载点
  static const String guestWorkspaceDir = '/workspace';

  /// Android 宿主绝对路径特征（在 Ubuntu rootfs 内不存在 → codex 读取必 ENOENT）
  static final RegExp _hostPathPattern =
      RegExp(r'''["']\s*/(?:data|storage|sdcard)/''');

  /// 检测工作区 `.codex/config.toml` 是否被 Android 宿主绝对路径污染。
  ///
  /// codex 0.147 会把 cwd 的 `.codex/config.toml` 作为 project config
  /// 加载（见 codex-rs config loader `load_project_layers`）。若其中
  /// `model_catalog_json` / `log_dir` / `sqlite_home` 等指向 Android
  /// 宿主路径（`/data/...`、`/storage/...`、`/sdcard/...`），PRoot 内
  /// codex 读取该文件必然 ENOENT，进程直接退出且无 stdout → UI 显示
  /// 「未收到有效回复」。
  static bool isWorkspaceCodexHostPathPolluted(String hostWorkingDir) {
    try {
      final config = File('$hostWorkingDir/.codex/config.toml');
      if (!config.existsSync()) return false;
      final text = config.readAsStringSync();
      return _hostPathPattern.hasMatch(text);
    } catch (_) {
      return false;
    }
  }

  /// 为被污染的 workspace `.codex` 生成「干净阴影目录」bind。
  ///
  /// 原理：PRoot `-b <shadowDir>:/workspace/.codex` 把 workspace 内含
  /// 宿主绝对路径的 `.codex` 整体遮蔽为空目录（无 config.toml → 空
  /// project layer），codex 改读 rootfs 用户级 `/root/.codex/config.toml`
  /// （DeepSeek 直连、干净）。不改用户文件、不伪造 git、不重复实现
  /// PRoot——只是往统一 LinuxExecutionAdapter 的 extraBinds 加一条。
  ///
  /// 返回 null 表示无需遮蔽（.codex 干净或不存在）。
  static String? buildCodexShadowBind({
    required String hostWorkingDir,
    required String rootfsDir,
  }) {
    if (!isWorkspaceCodexHostPathPolluted(hostWorkingDir)) return null;
    try {
      final shadowDir =
          '$rootfsDir/tmp/.codex-shadow-${DateTime.now().microsecondsSinceEpoch}';
      Directory(shadowDir).createSync(recursive: true);
      return '$shadowDir:$guestWorkspaceDir/.codex';
    } catch (e) {
      LogService.warning('CodexRunner', '创建 .codex 阴影目录失败: $e');
      return null;
    }
  }

  CodexRunner({
    LinuxRuntimeProvider? provider,
    LocalProcessExecution? processExecution,
  }) : _provider = provider ??
           RuntimeManager.instance.linuxProvider ??
           LinuxRuntimeProvider(),
       _process = processExecution ?? LocalProcessExecution() {
    final runner = RuntimeProcessRunner();
    // PRoot 参数统一由 LinuxExecutionAdapter 生成（禁止在此拼接）
    runner.registerAdapter(LinuxExecutionAdapter(_provider, inner: _process));
    _runner = runner;
  }

  /// 请求停止当前执行（kill 进程，仅作用于本 runner 的 codex 进程）
  void stop() => _process.requestCancel();

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
    // [AI-DEBUG] 全链路诊断累积（临时取证用）
    final debug = <String>[];
    void dbg(String s) => debug.add('[AI-DEBUG] $s');

    try {
      final paths = await _provider.resolvePaths();
      dbg('user input = ${_truncateForLog(prompt, 200)}');
      dbg('hostWorkingDir = $hostWorkingDir');
      dbg('rootfsDir = ${paths.rootfsDir}');
      dbg('workspace 存在 = ${Directory(hostWorkingDir).existsSync()}');

      // ─── 1. 校验 codex 已安装 ────────────────────────────────
      final codexExecutable = await _provider.resolveExecutable('codex');
      if (codexExecutable == null) {
        dbg('codexBin = (未找到)');
        return CodexRunResult(
          exitCode: -1,
          error: 'Codex CLI 未安装，请先在「部署中心」安装 Codex CLI',
          debugLog: debug.join('\n'),
        );
      }
      dbg('codex 宿主路径 = $codexExecutable');

      // ─── 2. 读取 DeepSeek API key（rootfs 内 codex 读取位置）──
      final apiKey = _readDeepSeekKey(paths);
      if (apiKey == null) {
        dbg('apiKey = (未配置)');
        return CodexRunResult(
          exitCode: -1,
          error: '未配置 DeepSeek API Key，请先在「部署中心」保存 API Key',
          debugLog: debug.join('\n'),
        );
      }
      dbg('apiKey = ${_maskKey(apiKey)}');
      dbg('workspace .codex 含宿主路径(需遮蔽) = '
          '${CodexRunner.isWorkspaceCodexHostPathPolluted(hostWorkingDir)}');

      // ─── 3. 确保宿主工作目录存在 ─────────────────────────────
      try {
        await Directory(hostWorkingDir).create(recursive: true);
      } catch (e) {
        dbg('创建/访问工作目录失败 = $e');
        return CodexRunResult(
          exitCode: -1,
          error: '无法创建/访问工作目录 $hostWorkingDir: $e',
          debugLog: debug.join('\n'),
        );
      }

      // ─── 4. 组装完整 prompt（system + user）─────────────────
      final fullPrompt = (systemPrompt != null && systemPrompt.trim().isNotEmpty)
          ? '$systemPrompt\n\n$prompt'
          : prompt;

      // ─── 5. 组装请求 + 执行（带失败自愈重试）────────────────
      final codexBin = _toRootfsPath(paths.rootfsDir, codexExecutable);
      dbg('codexBin (guest) = $codexBin');
      dbg('full command = exec $codexBin exec --json --skip-git-repo-check '
          '--dangerously-bypass-approvals-and-sandbox "\$CODEX_PROMPT" </dev/null');
      dbg('cwd (guest) = /workspace');
      dbg('env = DEEPSEEK_API_KEY=<掩码> CODEX_PROMPT=<prompt>');

      // 事件统计包装（转发给原 listener，同时累积类型与 agent_message）
      final eventTypes = <String>[];
      final agentMessages = <String>[];
      final debugListener = _DebugEventListener(
        inner: listener,
        onEvent: (e) {
          eventTypes.add(_eventTypeName(e));
          if (e is CodexAgentMessage) agentMessages.add(e.text);
        },
      );

      var outcome = await _runProotOnce(
        rootfsDir: paths.rootfsDir,
        codexBin: codexBin,
        hostWorkingDir: hostWorkingDir,
        fullPrompt: fullPrompt,
        apiKey: apiKey,
        timeout: timeout,
        listener: debugListener,
      );

      // ─── 6. 自愈重试：proot 可执行路径（nativeLibraryDir）───
      // 覆盖安装 / 系统清理后旧 session 路径（/data/app/~~<rand>==/
      // .../lib/arm64）会失效，`Process.start` → ENOENT（真机 AI
      // 对话「启动 codex 失败: 可执行文件不存在」即此场景）。
      // 刷新共享缓存、重新解析 nativeLibraryDir 后重试一次；
      // 仍失败则如实返回错误（已带完整诊断上下文）。
      if (outcome.failedToStart) {
        dbg('第一次启动失败（failedToStart），刷新 nativeLibraryDir 缓存后重试');
        LogService.warning(
          'CodexRunner',
          'proot 启动失败，刷新路径缓存后重试: ${outcome.result.error}',
        );
        _provider.invalidatePathCache();
        outcome = await _runProotOnce(
          rootfsDir: paths.rootfsDir,
          codexBin: codexBin,
          hostWorkingDir: hostWorkingDir,
          fullPrompt: fullPrompt,
          apiKey: apiKey,
          timeout: timeout,
          listener: debugListener,
        );
      }

      // ─── 7. 组装 [AI-DEBUG] 执行结果诊断 ────────────────────
      final result = outcome.result;
      dbg('process started = ${!outcome.failedToStart}');
      dbg('exitCode = ${result.exitCode}');
      dbg('timedOut = ${result.timedOut}');
      dbg('cancelled = ${result.cancelled}');
      dbg('cleanupTimedOut = ${result.cleanupTimedOut}');
      dbg('result.error = ${result.error ?? '(null)'}');
      dbg('threadId = ${result.threadId ?? '(null)'}');
      dbg('stdout length = ${result.stdout.length}');
      dbg('stderr length = ${result.stderr.length}');
      dbg('parsed events (${eventTypes.length}) = '
          '${eventTypes.isEmpty ? '(无)' : eventTypes.join(', ')}');
      if (agentMessages.isNotEmpty) {
        dbg('agent message = ${agentMessages.join(' | ')}');
      } else {
        dbg('agent message = (无 agent_message 事件)');
      }
      dbg('--- stdout 全文 begin ---');
      dbg(result.stdout.isEmpty ? '(空)' : result.stdout);
      dbg('--- stdout 全文 end ---');
      dbg('--- stderr 全文 begin ---');
      dbg(result.stderr.isEmpty ? '(空)' : result.stderr);
      dbg('--- stderr 全文 end ---');

      return result.copyWith(debugLog: debug.join('\n'));
    } catch (e) {
      dbg('codex 执行异常 = $e');
      return CodexRunResult(
        exitCode: -1,
        error: 'codex 执行异常: $e',
        debugLog: debug.join('\n'),
      );
    }
  }

  /// 组装 PRoot bind 列表：workspace → /workspace + （被污染时）.codex 阴影。
  List<String> _buildExtraBinds({
    required String hostWorkingDir,
    required String rootfsDir,
  }) {
    final binds = <String>['$hostWorkingDir:$guestWorkspaceDir'];
    final shadow = CodexRunner.buildCodexShadowBind(
      hostWorkingDir: hostWorkingDir,
      rootfsDir: rootfsDir,
    );
    if (shadow != null) {
      LogService.info('CodexRunner', 'workspace .codex 含宿主绝对路径，'
          '已遮蔽为干净阴影: $shadow');
      binds.add(shadow);
    }
    return binds;
  }

  /// 组装 codex 请求并通过统一 runner 执行一轮（供失败自愈重试复用）。
  ///
  /// PRoot 参数、bind（宿主工作目录 → /workspace）、环境由
  /// LinuxExecutionAdapter 统一生成。返回执行结果（CodexRunResult）、
  /// 解析到的 threadId，以及 failedToStart 标记（进程未能启动，
  /// 如 proot 路径 ENOENT）。
  Future<({CodexRunResult result, String threadId, bool failedToStart})>
  _runProotOnce({
    required String rootfsDir,
    required String codexBin,
    required String hostWorkingDir,
    required String fullPrompt,
    required String apiKey,
    required Duration? timeout,
    required CodexEventListener listener,
  }) async {
    // 内层 bash 命令：
    //   - `exec` 让 bash 进程替换为 codex，信号直接送达 codex
    //   - `"$CODEX_PROMPT"` 经环境变量传递（避免 shell 转义，可含引号/换行）
    //   - `</dev/null`：codex exec 检测到 stdin 是 pipe 时会等待追加
    //     <stdin> block 导致挂起
    final innerCommand =
        'exec $codexBin exec --json --skip-git-repo-check '
        '--dangerously-bypass-approvals-and-sandbox '
        '"\$CODEX_PROMPT" </dev/null';

    final lineBuffer = StringBuffer();
    var threadId = '';

    final request = RuntimeProcessRequest(
      // runtimeId='linux' → 路由到 LinuxExecutionAdapter（统一 PRoot 入口）
      runtimeId: 'linux',
      executable: codexBin,
      innerCommand: innerCommand,
      // 宿主工作目录 bind 进 guest /workspace（PRoot -b host:/workspace）；
      // 若 workspace 的 .codex 被宿主绝对路径污染，追加一条干净阴影
      // 目录 bind，遮蔽 /workspace/.codex，避免 codex 启动读宿主路径 ENOENT。
      extraBinds: _buildExtraBinds(hostWorkingDir: hostWorkingDir, rootfsDir: rootfsDir),
      workingDirectory: guestWorkspaceDir,
      // codex 专属环境：key + prompt（Linux 基础环境由适配器合并）
      environment: {
        'DEEPSEEK_API_KEY': apiKey,
        'CODEX_PROMPT': fullPrompt,
      },
      timeout: timeout,
      label: 'codex-exec',
      onStdoutChunk: (chunk) {
        threadId = _consumeChunk(
          chunk,
          lineBuffer,
          listener,
          currentThreadId: threadId,
        );
      },
    );

    final result = await _runner.run(request);

    // 解析尾随缓冲（最后一行可能无换行）
    _flushLineBuffer(lineBuffer, listener);

    if (result.failedToStart) {
      return (
        result: CodexRunResult(
          exitCode: result.exitCode,
          error: _startupErrorMessage(result.error),
          threadId: threadId.isEmpty ? null : threadId,
          stdout: result.stdout,
          stderr: result.stderr,
        ),
        threadId: threadId,
        failedToStart: true,
      );
    }

    return (
      result: CodexRunResult(
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        cancelled: result.cancelled,
        cleanupTimedOut: result.cleanupTimedOut,
        error: result.error,
        threadId: threadId.isEmpty ? null : threadId,
        stdout: result.stdout,
        stderr: result.stderr,
      ),
      threadId: threadId,
      failedToStart: false,
    );
  }

  /// 将 Runtime 启动失败转为用户可读错误。
  ///
  /// Runtime 未就绪（LinuxExecutionAdapter 返回「Linux Runtime 未初始化」）
  /// → 明确提示部署，替代 ENOENT 误导性报错；其他启动失败如实透传。
  static String _startupErrorMessage(String? error) {
    final err = error ?? '';
    if (err.contains('Linux Runtime 未初始化') || err.contains('Linux Runtime')) {
      return 'Coding Runtime 未就绪，请先部署 Linux Runtime。\n$err';
    }
    return '启动 codex 失败: $err';
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

  /// [AI-DEBUG] 掩码 API key（只显示首尾 4 位，不泄露）
  static String _maskKey(String key) {
    if (key.length <= 8) return '***';
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)} '
        '(len=${key.length})';
  }

  /// [AI-DEBUG] 截断超长文本（防 UI 爆炸；完整内容仍留在 debugLog 尾部）
  static String _truncateForLog(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}\n...[已截断，完整见 stdout 全文，len=${s.length}]';
  }

  /// [AI-DEBUG] 事件类型短名（CodexAgentMessage → agent_message）
  static String _eventTypeName(CodexEvent e) {
    final name = e.runtimeType.toString().replaceFirst('Codex', '');
    final buf = StringBuffer();
    for (final ch in name.split('')) {
      if (ch == ch.toUpperCase() && buf.isNotEmpty) {
        buf.write('_');
      }
      buf.write(ch.toLowerCase());
    }
    return buf.toString();
  }
}

/// [AI-DEBUG] 事件统计包装监听器：转发事件，同时累积类型与 agent_message 文本
class _DebugEventListener implements CodexEventListener {
  final CodexEventListener inner;
  final void Function(CodexEvent event) onEvent;

  _DebugEventListener({required this.inner, required this.onEvent});

  @override
  void onCodexEvent(CodexEvent event) {
    onEvent(event);
    inner.onCodexEvent(event);
  }

  @override
  void onCodexExit(int exitCode) => inner.onCodexExit(exitCode);
}
