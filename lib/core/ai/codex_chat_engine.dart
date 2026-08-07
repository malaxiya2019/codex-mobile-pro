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

import 'ai_message.dart';
import 'chat_engine.dart';
import 'chat_session.dart';
import 'codex_runner.dart';

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

    // 创建用户消息
    final userMessage = ChatMessage(
      id: _generateId(),
      role: ChatRole.user,
      content: content.trim(),
      timestamp: DateTime.now(),
      metadata: metadata,
    );
    session.addMessage(userMessage);

    // 自动更新标题（首条用户消息）
    if (session.title.startsWith('对话 ') &&
        session.messagesByRole(ChatRole.user).length == 1) {
      session.title = _generateTitle(content.trim());
    }

    // 确定目标目录
    final workspaceDir = await _resolveWorkspaceDir(metadata, session);

    // 占位消息（实时承载文本 + 工具调用状态）
    final placeholderId = 'streaming-${_generateId()}';
    session.addMessage(ChatMessage(
      id: placeholderId,
      role: ChatRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
      metadata: {
        'workspaceDir': workspaceDir,
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
          hostWorkingDir: workspaceDir,
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
                workspaceDir: workspaceDir,
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
              workspaceDir: workspaceDir,
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
              workspaceDir: workspaceDir,
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
          'workspaceDir': workspaceDir,
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
          'workspaceDir': workspaceDir,
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
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: '⚠️ 未收到有效回复',
        timestamp: DateTime.now(),
        metadata: {
          'workspaceDir': workspaceDir,
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
          'workspaceDir': workspaceDir,
          'codex_tool_calls': toolCalls.map((t) => t.toJson()).toList(),
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

  Future<String> _resolveWorkspaceDir(
    Map<String, dynamic>? messageMetadata,
    ChatSession session,
  ) async {
    final fromMessage = messageMetadata?['workspaceDir'] as String?;
    if (fromMessage != null && fromMessage.isNotEmpty) return fromMessage;

    final fromSession = session.metadata?['workspaceDir'] as String?;
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;

    if (defaultWorkspaceDir != null && defaultWorkspaceDir!.isNotEmpty) {
      return defaultWorkspaceDir!;
    }

    if (workspaceDirResolver != null) {
      try {
        final dir = await workspaceDirResolver!();
        if (dir.isNotEmpty) return dir;
      } catch (_) {}
    }
    return '/workspace';
  }

  void _updatePlaceholder(
    ChatSession session,
    String placeholderId,
    {required String content, required String workspaceDir, required List<CodexToolCall> toolCalls}) {
    final idx = session.messages.indexWhere((m) => m.id == placeholderId);
    if (idx < 0) return;
    session.messages[idx] = ChatMessage(
      id: placeholderId,
      role: ChatRole.assistant,
      content: content,
      timestamp: DateTime.now(),
      isStreaming: true,
      metadata: {
        'workspaceDir': workspaceDir,
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
