/// ====================================================================
/// CodexChatEngine — 基于 Codex CLI 的聊天引擎
///
/// 实现 [IChatEngine]，把 UI 的消息流桥接到 rootfs 内的
/// `codex exec --json`（见 [CodexRunner]）：
///   - `agent_message` 事件 → 流式文本 chunk
///   - `command_execution` 事件 → 实时更新会话占位消息的
///     `codex_tool_calls` metadata（UI 据此显示工具调用状态）
///   - `thread.started` → 记录 thread_id（供将来 resume）
///   - `turn.completed` / 进程退出 → 结束流
///
/// 目标目录（[CodexRunner] 的 hostWorkingDir）来源优先级：
///   1. `streamMessage.metadata['workspaceDir']`
///   2. `createSession(metadata: {'workspaceDir': ...})`
///   3. 构造注入的 [defaultWorkspaceDir]
///   4. 运行时解析 App 文档目录
/// ====================================================================
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/logger/log_service.dart';
import 'ai_message.dart';
import 'attachment.dart';
import 'chat_engine.dart';
import 'chat_session.dart';
import 'codex_runner.dart';
import 'workspace_dir_resolver.dart';

/// 工具调用状态（用于 UI 展示）
class CodexToolCall {
  final String id;
  final String command;

  /// in_progress / completed / error
  final String status;
  final int? exitCode;
  final String output;

  const CodexToolCall({
    required this.id,
    required this.command,
    required this.status,
    this.exitCode,
    this.output = '',
  });

  CodexToolCall copyWith({
    String? status,
    int? exitCode,
    String? output,
  }) {
    return CodexToolCall(
      id: id,
      command: command,
      status: status ?? this.status,
      exitCode: exitCode ?? this.exitCode,
      output: output ?? this.output,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'status': status,
    'exitCode': exitCode,
    'output': output,
  };

  static CodexToolCall fromJson(Map<String, dynamic> json) => CodexToolCall(
    id: (json['id'] as String?) ?? '',
    command: (json['command'] as String?) ?? '',
    status: (json['status'] as String?) ?? 'in_progress',
    exitCode: json['exitCode'] as int?,
    output: (json['output'] as String?) ?? '',
  );
}

/// CodexChatEngine
class CodexChatEngine implements IChatEngine {
  final CodexRunner _runner;

  /// 默认工作目录（测试注入；null 时运行时解析 App 文档目录）
  final String? defaultWorkspaceDir;

  /// 运行时解析默认工作目录（App 文档目录等）
  final Future<String> Function()? workspaceDirResolver;

  final Map<String, ChatSession> _sessions = {};
  final Map<String, GenerationStatus> _generationStatuses = {};
  final Map<String, String> _threadIds = {};

  /// sessionId → 工作目录解析结果缓存。
  /// 会话内缓存：同一请求解析一次后不再每轮重新猜测；用户显式切换工作
  /// 目录或解析目录失效时重新解析（见 [_resolveWorkspaceDir]）。
  ///   - requested:    用户/会话请求的目录（host 或 /workspace 兜底）
  ///   - host:         CodexRunner 的 bind 根（= requested）
  ///   - guest:        解析出的项目 guest 路径（Codex cwd，如 `/workspace/git/<repo>`）
  ///   - resolvedHost: 解析出的 host 项目路径
  ///   - isGit:        resolvedHost 是否为 Git 仓库
  final Map<
    String,
    ({
      String requested,
      String host,
      String guest,
      String resolvedHost,
      bool isGit,
    })
  >
      _resolvedWorkspaceDirs = {};

  /// 每会话正在运行的 run（供 stopGeneration）
  final Map<String, CodexRunner> _activeRunners = {};

  @override
  String systemPrompt;

  CodexChatEngine({
    CodexRunner? runner,
    this.defaultWorkspaceDir,
    this.workspaceDirResolver,
    this.systemPrompt = '你是一个 AI 编程助手。你可以读取和修改用户项目目录里的文件、'
        '运行命令、迭代完成任务。当前工作目录是你的目标项目目录，可以直接操作其中的文件。'
        '请用简体中文回答。',
  }) : _runner = runner ?? CodexRunner();

  // ── Session 管理 ────────────────────────────────────────────

  @override
  ChatSession createSession({String? title, Map<String, dynamic>? metadata}) {
    final session = ChatSession(
      sessionId: _generateId(),
      title: title,
      metadata: metadata,
    );
    _sessions[session.sessionId] = session;
    _generationStatuses[session.sessionId] = GenerationStatus.idle;
    return session;
  }

  @override
  void deleteSession(String sessionId) {
    stopGeneration(sessionId);
    _sessions.remove(sessionId);
    _generationStatuses.remove(sessionId);
    _threadIds.remove(sessionId);
    _resolvedWorkspaceDirs.remove(sessionId);
    _activeRunners.remove(sessionId);
  }

  @override
  ChatSession? getSession(String sessionId) => _sessions[sessionId];

  @override
  List<ChatSession> listSessions() {
    final list = _sessions.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  // ── 消息操作 ─────────────────────────────────────────────────

  @override
  Future<List<ChatMessage>> getMessages(String sessionId) async {
    final session = _getSessionOrThrow(sessionId);
    return List.from(session.messages);
  }

  @override
  Future<ChatMessage> sendMessage({
    required String sessionId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in streamMessage(
      sessionId: sessionId,
      content: content,
      metadata: metadata,
    )) {
      buffer.write(chunk);
    }
    final session = _getSessionOrThrow(sessionId);
    return session.messages.last;
  }

  @override
  Stream<String> streamMessage({
    required String sessionId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async* {
    final session = _getSessionOrThrow(sessionId);

    if (isGenerating(sessionId)) {
      throw const ChatEngineException(
        type: ChatEngineErrorType.sessionBusy,
        message: '该会话正在生成中，请等待完成或停止当前生成',
      );
    }
    if (content.trim().isEmpty) {
      throw const ChatEngineException(
        type: ChatEngineErrorType.internal,
        message: '消息内容不能为空',
      );
    }

    // 创建用户消息（attachments 来自 metadata，仅本地绑定，不参与 AI 请求）
    final userMessage = ChatMessage(
      id: _generateId(),
      role: ChatRole.user,
      content: content.trim(),
      timestamp: DateTime.now(),
      metadata: metadata,
      attachments: _attachmentsFromMetadata(metadata),
    );
    session.addMessage(userMessage);

    // 自动更新标题（首条用户消息）
    if (session.title.startsWith('对话 ') &&
        session.messagesByRole(ChatRole.user).length == 1) {
      session.title = _generateTitle(content.trim());
    }

    // 确定目标目录
    final workspace = await _resolveWorkspaceDir(metadata, session);

    // 占位消息（实时承载文本 + 工具调用状态）
    final placeholderId = 'streaming-${_generateId()}';
    session.addMessage(ChatMessage(
      id: placeholderId,
      role: ChatRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
      metadata: {
        'workspaceDir': workspace.host,
        'workspaceDirGuest': workspace.guest,
        'codex_tool_calls': <Map<String, dynamic>>[],
      },
    ));

    _generationStatuses[sessionId] = GenerationStatus.streaming;
    _activeRunners[sessionId] = _runner;

    // 事件桥接：CodexRunner 回调式 → 此处 StreamController
    final controller = StreamController<CodexEvent>();
    final done = Completer<CodexRunResult>();
    final toolCalls = <CodexToolCall>[];
    final textBuffer = StringBuffer();
    var runError = '';

    // run 结束（无论正常/取消/错误）都要 close controller，
    // 否则下方 `await for` 永不结束（死锁）
    void finishStream() {
      if (!controller.isClosed) {
        controller.close();
      }
    }

    unawaited(_runner
        .run(
          prompt: content.trim(),
          // bind 根保持 requested；Codex cwd 用解析出的项目 guest 路径，
          // 避免 /workspace 空壳被当作 Git 项目目录。
          hostWorkingDir: workspace.host,
          guestWorkingDir: workspace.guest,
          resolveWorkspace: false,
          systemPrompt: systemPrompt,
          listener: _CodexEventListener(
            onEvent: (event) {
              if (!controller.isClosed) {
                controller.add(event);
              }
            },
            onExit: (_) {},
          ),
        )
        .then((result) {
          if (!done.isCompleted) {
            done.complete(result);
            if (result.error != null && result.error!.isNotEmpty) {
              runError = result.error!;
            }
          }
          finishStream();
        })
        .catchError((Object e) {
          if (!done.isCompleted) {
            done.complete(
              CodexRunResult(exitCode: -1, error: 'codex 执行异常: $e'),
            );
            runError = 'codex 执行异常: $e';
          }
          finishStream();
        }));

    bool cancelled = false;
    bool timedOut = false;

    try {
      await for (final event in controller.stream) {
        switch (event) {
          case CodexThreadStarted(:final threadId):
            _threadIds[sessionId] = threadId;
          case CodexTurnStarted():
            break;
          case CodexAgentMessage(:final text):
            if (text.isNotEmpty) {
              textBuffer.write(text);
              _updatePlaceholder(
                session,
                placeholderId,
                content: textBuffer.toString(),

                workspaceHost: workspace.host,

                workspaceGuest: workspace.guest,
                toolCalls: toolCalls,
              );
              yield text;
            }
          case CodexCommandStarted(:final id, :final command):
            _upsertToolCall(
              toolCalls,
              CodexToolCall(id: id, command: command, status: 'in_progress'),
            );
            _updatePlaceholder(
              session,
              placeholderId,
              content: textBuffer.toString(),

              workspaceHost: workspace.host,

              workspaceGuest: workspace.guest,
              toolCalls: toolCalls,
            );
          case CodexCommandCompleted(
            :final id,
            :final command,
            :final exitCode,
            :final output,
          ):
            _upsertToolCall(
              toolCalls,
              CodexToolCall(
                id: id,
                command: command,
                status: exitCode == 0 ? 'completed' : 'error',
                exitCode: exitCode,
                output: output,
              ),
            );
            _updatePlaceholder(
              session,
              placeholderId,
              content: textBuffer.toString(),

              workspaceHost: workspace.host,

              workspaceGuest: workspace.guest,
              toolCalls: toolCalls,
            );
          case CodexTurnCompleted():
            break;
          case CodexErrorEvent():
            // 无害 fallback 警告静默；真实错误由 exit 结果承载
            break;
        }
      }
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }

    // 等待进程真正结束（含超时/取消/错误信息）
    final result = await done.future;
    cancelled = result.cancelled;
    timedOut = result.timedOut;

    if (result.error != null && result.error!.isNotEmpty) {
      runError = result.error!;
    }

    if (cancelled) {
      _generationStatuses[sessionId] = GenerationStatus.completed;
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: textBuffer.toString().isNotEmpty
            ? textBuffer.toString()
            : '⚠️ 已停止生成',
        timestamp: DateTime.now(),
        metadata: {
          'stopped': true,
          'workspaceDir': workspace.host,
          'workspaceDirGuest': workspace.guest,
          'codex_tool_calls': toolCalls.map((t) => t.toJson()).toList(),
        },
      ));
      return;
    }

    if (timedOut || runError.isNotEmpty) {
      _generationStatuses[sessionId] = GenerationStatus.error;
      final errorMsg = runError.isNotEmpty
          ? runError
          : '执行超时（exitCode=${result.exitCode}）';
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: '❌ $errorMsg',
        timestamp: DateTime.now(),
        metadata: {
          'error': errorMsg,
          'workspaceDir': workspace.host,
          'workspaceDirGuest': workspace.guest,
          'codex_tool_calls': toolCalls.map((t) => t.toJson()).toList(),
        },
      ));
      throw ChatEngineException(
        type: timedOut
            ? ChatEngineErrorType.timeout
            : ChatEngineErrorType.internal,
        message: errorMsg,
      );
    }

    // 正常结束
    final fullContent = textBuffer.toString();
    if (fullContent.isEmpty) {
      _generationStatuses[sessionId] = GenerationStatus.error;
      final diag = _buildNoReplyDiagnostic(result);
      // [AI-DEBUG] 取证期：只要 runner 积累了 debugLog（真实命令/exitCode/
      // stdout/stderr/事件），一律贴出；否则回退到原有轻量诊断
      final content = result.debugLog.isNotEmpty
          ? '⚠️ 未收到有效回复\n\n[AI-DEBUG]\n${result.debugLog}'
          : diag == null
              ? '⚠️ 未收到有效回复'
              : '⚠️ 未收到有效回复\n\n[诊断] 未解析到 agent_message\n$diag';
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: content,
        timestamp: DateTime.now(),
        metadata: {
          'exitCode': result.exitCode.toString(),
          'workspaceDir': workspace.host,
          'workspaceDirGuest': workspace.guest,
          'codex_tool_calls': toolCalls.map((t) => t.toJson()).toList(),
        },
      ));
    } else {
      _generationStatuses[sessionId] = GenerationStatus.completed;
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: fullContent,
        timestamp: DateTime.now(),
        metadata: {
          'threadId': _threadIds[sessionId],
          'exitCode': result.exitCode.toString(),
          'workspaceDir': workspace.host,
          'workspaceDirGuest': workspace.guest,
          'codex_tool_calls': toolCalls.map((t) => t.toJson()).toList(),
          // [AI-DEBUG] 取证期：正常回复也把诊断挂到 metadata（UI 可查）
          'debugLog': result.debugLog,
        },
      ));
    }
  }

  @override
  Future<ChatMessage> retryLastMessage(String sessionId) async {
    final session = _getSessionOrThrow(sessionId);

    final userMessages = session.messagesByRole(ChatRole.user);
    if (userMessages.isEmpty) {
      throw const ChatEngineException(
        type: ChatEngineErrorType.internal,
        message: '没有可重试的消息',
      );
    }

    if (session.messages.isNotEmpty &&
        session.messages.last.role == ChatRole.assistant) {
      session.messages.removeLast();
    }
    if (session.messages.isNotEmpty &&
        session.messages.last.role == ChatRole.user) {
      session.messages.removeLast();
    }

    final lastUserMessage = userMessages.last;
    return sendMessage(
      sessionId: sessionId,
      content: lastUserMessage.content,
      metadata: lastUserMessage.metadata,
    );
  }

  @override
  void stopGeneration(String sessionId) {
    final runner = _activeRunners.remove(sessionId);
    runner?.stop();
    _generationStatuses[sessionId] = GenerationStatus.completed;

    final session = _sessions[sessionId];
    if (session != null && session.messages.isNotEmpty) {
      final last = session.messages.last;
      if (last.isStreaming) {
        session.replaceLastMessage(ChatMessage(
          id: _generateId(),
          role: ChatRole.assistant,
          content: last.content.isNotEmpty ? last.content : '⚠️ 已停止生成',
          timestamp: DateTime.now(),
          metadata: {...?last.metadata, 'stopped': true},
        ));
      }
    }
  }

  // ── 上下文管理 ───────────────────────────────────────────────

  @override
  void addContext(String key, String value) {}

  @override
  void removeContext(String key) {}

  @override
  void clearContext() {}

  // ── 状态 ─────────────────────────────────────────────────────

  @override
  bool isGenerating(String sessionId) {
    return _generationStatuses[sessionId] == GenerationStatus.streaming;
  }

  @override
  GenerationStatus getGenerationStatus(String sessionId) {
    return _generationStatuses[sessionId] ?? GenerationStatus.idle;
  }

  // ── 生命周期 ─────────────────────────────────────────────────

  @override
  void dispose() {
    for (final sessionId in _sessions.keys.toList()) {
      stopGeneration(sessionId);
    }
    _sessions.clear();
    _generationStatuses.clear();
    _threadIds.clear();
    _activeRunners.clear();
  }

  // ── 内部 ─────────────────────────────────────────────────────

  ChatSession _getSessionOrThrow(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw ChatEngineException(
        type: ChatEngineErrorType.sessionNotFound,
        message: '会话不存在: $sessionId',
      );
    }
    return session;
  }

  Future<({String host, String guest, String resolvedHost, bool isGit})>
      _resolveWorkspaceDir(
    Map<String, dynamic>? messageMetadata,
    ChatSession session,
  ) async {
    // 确定「请求的工作目录」：用户/消息显式指定 > 会话 metadata >
    // 构造注入的默认 > 运行时解析 App 文档目录 > 兜底 /workspace
    String? requested;
    final fromMessage = messageMetadata?['workspaceDir'] as String?;
    if (fromMessage != null && fromMessage.isNotEmpty) {
      requested = fromMessage;
    } else {
      final fromSession = session.metadata?['workspaceDir'] as String?;
      if (fromSession != null && fromSession.isNotEmpty) {
        requested = fromSession;
      } else if (defaultWorkspaceDir != null && defaultWorkspaceDir!.isNotEmpty) {
        requested = defaultWorkspaceDir;
      } else if (workspaceDirResolver != null) {
        try {
          final dir = await workspaceDirResolver!();
          if (dir.isNotEmpty) requested = dir;
        } catch (_) {}
      }
    }
    requested = (requested == null || requested.isEmpty)
        ? CodexRunner.guestWorkspaceDir
        : requested;

    // 会话内缓存：同一请求目录且解析目录仍有效 → 直接复用，避免每轮重新
    // 扫描文件系统（除非用户主动切换工作目录，或目录已失效）。
    final cached = _resolvedWorkspaceDirs[session.sessionId];
    if (cached != null && cached.requested == requested) {
      final bindRootValid = cached.host == CodexRunner.guestWorkspaceDir ||
          Directory(cached.host).existsSync();
      final resolvedValid = cached.resolvedHost.isEmpty ||
          Directory(cached.resolvedHost).existsSync();
      if (bindRootValid && resolvedValid) {
        return (
          host: cached.host,
          guest: cached.guest,
          resolvedHost: cached.resolvedHost,
          isGit: cached.isGit,
        );
      }
    }

    // Codex 启动前统一工作目录解析：
    //   1) 判断目录是否存在；2) 判断是否为 Git 仓库；3) 不是 Git 仓库时
    //   检查已知项目根目录（requested/git/ 下的 git clone 仓库）。
    final resolved = resolveCodexWorkspaceDir(requested);
    // bind 根 = requested（CodexRunner 把 host 根 bind 到 guest /workspace）
    final host = requested;
    // Codex cwd = 项目 guest 路径（如 /workspace/git/codex-mobile-pro）
    final guest = _hostPathToGuestCwd(requested, resolved.path);
    _resolvedWorkspaceDirs[session.sessionId] = (
      requested: requested,
      host: host,
      guest: guest,
      resolvedHost: resolved.path,
      isGit: resolved.isGitRepository,
    );
    LogService.info('CodexChatEngine', 'requestedWorkingDirectory = $requested');
    LogService.info('CodexChatEngine',
        'resolvedWorkingDirectory = ${resolved.path}');
    LogService.info('CodexChatEngine',
        'isGitRepository = ${resolved.isGitRepository}');
    LogService.info('CodexChatEngine', 'codex cwd = $guest');
    return (
      host: host,
      guest: guest,
      resolvedHost: resolved.path,
      isGit: resolved.isGitRepository,
    );
  }

  /// 把解析出的 host 项目路径映射为 PRoot guest cwd。
  ///
  /// host 根（requested）被 bind 到 guest /workspace，因此：
  ///   requested=/data/.../app_flutter，resolved=/data/.../app_flutter/git/repo
  ///   → guest=/workspace/git/repo
  /// 若 requested 本身就是 /workspace（兜底）→ guest 保持 resolved。
  /// 若 resolved 不在 requested 下（异常）→ 退回 /workspace（bind 根）。
  String _hostPathToGuestCwd(String requested, String resolvedHost) {
    if (requested == CodexRunner.guestWorkspaceDir) return resolvedHost;
    if (resolvedHost == requested) return CodexRunner.guestWorkspaceDir;
    if (resolvedHost.startsWith(requested)) {
      return '${CodexRunner.guestWorkspaceDir}${resolvedHost.substring(requested.length)}';
    }
    return CodexRunner.guestWorkspaceDir;
  }


  /// 从 metadata['attachments'] 解析附件列表（本地绑定，不参与 AI 请求）。
  List<Attachment> _attachmentsFromMetadata(Map<String, dynamic>? metadata) {
    final raw = metadata?['attachments'];
    if (raw is! List || raw.isEmpty) return const [];
    return raw
        .map((e) =>
            Attachment.fromJson((e as Map).cast<String, dynamic>()))
        .whereType<Attachment>()
        .toList();
  }

  void _updatePlaceholder(
    ChatSession session,
    String placeholderId,
    {required String content,
     required String workspaceHost,
     required String workspaceGuest,
     required List<CodexToolCall> toolCalls}) {
    final idx = session.messages.indexWhere((m) => m.id == placeholderId);
    if (idx < 0) return;
    session.messages[idx] = ChatMessage(
      id: placeholderId,
      role: ChatRole.assistant,
      content: content,
      timestamp: DateTime.now(),
      isStreaming: true,
      metadata: {
        'workspaceDir': workspaceHost,
        'workspaceDirGuest': workspaceGuest,
        'codex_tool_calls': toolCalls.map((t) => t.toJson()).toList(),
      },
    );
    session.updatedAt = DateTime.now();
  }

  void _upsertToolCall(List<CodexToolCall> toolCalls, CodexToolCall call) {
    final idx = toolCalls.indexWhere((t) => t.id == call.id);
    if (idx >= 0) {
      toolCalls[idx] = toolCalls[idx].copyWith(
        status: call.status,
        exitCode: call.exitCode,
        output: call.output,
      );
    } else {
      toolCalls.add(call);
    }
  }

  String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  String _generateTitle(String content) {
    final cleaned = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 30) return cleaned;
    return '${cleaned.substring(0, 30)}...';
  }

  /// 空回复时构造真实诊断（仅当存在真实失败信号时返回非 null）。
  ///
  /// 触发条件（满足其一）：
  ///  1. exitCode != 0 —— codex 崩溃/退出非 0（ENOENT、API 401 等真实失败）
  ///  2. stderr 非空且非无害提示（如 codex 的 stdin 提示行）
  ///  3. stdout 含真实错误事件（type=error / turn.failed，排除无害 config 警告）
  ///
  /// 排除的无害噪音：
  ///  - "Ignored unsupported project-local config keys ..."（config 键忽略警告）
  ///  - "Defaulting to fallback metadata ..."（模型元数据降级警告）
  ///  - "Reading additional input from stdin..."（stdin 非 TTY 提示）
  String? _buildNoReplyDiagnostic(CodexRunResult result) {
    final lines = <String>[];

    if (result.exitCode != 0) {
      lines.add('exitCode=${result.exitCode}');
    }

    final stderr = result.stderr.trim();
    if (stderr.isNotEmpty &&
        !stderr.contains('Reading additional input from stdin')) {
      lines.add('stderr: $stderr');
    }

    // stdout JSONL：提取真实错误事件，去重、排除无害警告
    final errorMessages = <String>{};
    for (final raw in const LineSplitter().convert(result.stdout)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(line);
      } catch (_) {
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;
      String? message;
      if (decoded['type'] == 'error' && decoded['message'] is String) {
        message = decoded['message'] as String;
      } else if (decoded['type'] == 'turn.failed') {
        final err = decoded['error'];
        if (err is Map && err['message'] is String) {
          message = err['message'] as String;
        }
      }
      if (message == null || message.isEmpty) continue;
      if (_isBenignCodexMessage(message)) continue;
      errorMessages.add(message);
    }
    for (final m in errorMessages.take(3)) {
      lines.add('codex: $m');
    }

    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  /// codex 输出中的无害警告（不影响对话回复，不纳入诊断）
  bool _isBenignCodexMessage(String message) {
    if (message.contains('Ignored unsupported project-local config keys')) {
      return true;
    }
    if (message.contains('Defaulting to fallback metadata')) {
      return true;
    }
    return false;
  }
}

/// CodexRunner 事件监听器适配（把事件转发给回调）
class _CodexEventListener implements CodexEventListener {
  final void Function(CodexEvent event) onEvent;
  final void Function(int exitCode) onExit;

  _CodexEventListener({required this.onEvent, required this.onExit});

  @override
  void onCodexEvent(CodexEvent event) => onEvent(event);

  @override
  void onCodexExit(int exitCode) => onExit(exitCode);
}
