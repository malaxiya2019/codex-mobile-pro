import 'dart:async';

import 'ai_message.dart';
import 'ai_provider.dart';
import 'ai_provider_manager.dart';
import 'chat_session.dart';

// ══════════════════════════════════════════════
// 类型定义
// ══════════════════════════════════════════════

/// 引擎错误类型
enum ChatEngineErrorType {
  /// 会话不存在
  sessionNotFound,

  /// 会话正在生成中
  sessionBusy,

  /// Provider 不可用
  providerUnavailable,

  /// 请求超时
  timeout,

  /// 请求被取消
  cancelled,

  /// 内部错误
  internal,
}

/// 引擎异常
class ChatEngineException implements Exception {
  final ChatEngineErrorType type;
  final String message;

  const ChatEngineException({
    required this.type,
    required this.message,
  });

  @override
  String toString() => '[$type] $message';
}

/// 生成状态
enum GenerationStatus {
  /// 空闲
  idle,

  /// 正在流式生成
  streaming,

  /// 生成完成
  completed,

  /// 生成出错
  error,
}

// ══════════════════════════════════════════════
// ContextManager（预留接口）
// ══════════════════════════════════════════════

/// 上下文管理器接口
///
/// 负责收集当前编辑器上下文：
/// - 当前文件引用
/// - Selection 引用
/// - Workspace Context
///
/// 当前为预留接口，提供默认空实现。
abstract class ContextManager {
  /// 获取当前文件路径
  String? get currentFile;

  /// 获取当前选中的文本
  String? get selection;

  /// 获取工作区上下文描述
  String? get workspaceContext;

  /// 添加上下文片段
  void addContext(String key, String value);

  /// 移除上下文片段
  void removeContext(String key);

  /// 清空所有上下文
  void clearContext();

  /// 构建上下文消息块
  ///
  /// 返回适合注入到 system prompt 的文本片段。
  String buildContextPrompt();
}

/// 默认上下文管理器（空实现）
class DefaultContextManager implements ContextManager {
  final Map<String, String> _contexts = {};

  @override
  String? get currentFile => null;

  @override
  String? get selection => null;

  @override
  String? get workspaceContext => null;

  @override
  void addContext(String key, String value) {
    _contexts[key] = value;
  }

  @override
  void removeContext(String key) {
    _contexts.remove(key);
  }

  @override
  void clearContext() {
    _contexts.clear();
  }

  @override
  String buildContextPrompt() {
    if (_contexts.isEmpty) return '';
    final buffer = StringBuffer('\n\n## 上下文信息\n');
    for (final entry in _contexts.entries) {
      buffer.writeln('### ${entry.key}');
      buffer.writeln(entry.value);
      buffer.writeln();
    }
    return buffer.toString();
  }
}

// ══════════════════════════════════════════════
// TokenContextManager
// ══════════════════════════════════════════════

/// Token 上下文管理器
///
/// 根据 Token 限制自动裁剪消息历史：
/// - 保留 system message
/// - 保留最近消息（N 条）
/// - 从旧到新裁剪中间消息
class TokenContextManager {
  /// 最大 Token 数（默认 8K）
  final int maxTokens;

  /// 保留的最近消息数（裁剪后至少保留这些）
  final int minRecentMessages;

  /// 单条消息的估算 Token 系数（每字符约 0.25 token）
  static const double _tokenPerChar = 0.25;

  const TokenContextManager({
    this.maxTokens = 8192,
    this.minRecentMessages = 4,
  });

  /// 估算文本的 Token 数
  int estimateTokens(String text) {
    return (text.length * _tokenPerChar).ceil();
  }

  /// 估算消息列表的总 Token 数
  int estimateMessagesTokens(List<ChatMessage> messages) {
    int total = 0;
    for (final msg in messages) {
      total += estimateTokens(msg.content);
      // 角色和格式开销
      total += 4;
    }
    return total;
  }

  /// 裁剪消息上下文
  ///
  /// 策略：
  /// 1. 分离 system message
  /// 2. 保留最近 N 条消息
  /// 3. 如果仍超出限制，从最旧的非 system 消息开始裁剪
  /// 4. 如果裁剪后依然超限，缩小最近消息保留数
  List<ChatMessage> trimContext({
    required List<ChatMessage> messages,
    ChatMessage? systemMessage,
  }) {
    if (messages.isEmpty) return [];

    // 分离 system message
    final List<ChatMessage> nonSystem;
    if (systemMessage != null) {
      nonSystem = messages
          .where((m) => m.id != systemMessage.id)
          .toList();
    } else {
      nonSystem = List.from(messages);
    }

    if (nonSystem.isEmpty) {
      return systemMessage != null ? [systemMessage] : [];
    }

    // 计算 system 的 Token
    final systemTokens = systemMessage != null
        ? estimateTokens(systemMessage.content) + 4
        : 0;

    final availableTokens = maxTokens - systemTokens;

    // 如果全部在限制内，直接返回
    if (estimateMessagesTokens(nonSystem) <= availableTokens) {
      return systemMessage != null ? [systemMessage, ...nonSystem] : nonSystem;
    }

    // 逐步裁剪：从最早的消息开始移除
    int recentCount = nonSystem.length;
    while (recentCount > minRecentMessages) {
      final candidate = nonSystem.sublist(nonSystem.length - recentCount);
      if (estimateMessagesTokens(candidate) <= availableTokens) {
        final result = systemMessage != null
            ? [systemMessage, ...candidate]
            : candidate;
        return result;
      }
      recentCount--;
    }

    // 最少保留 recentCount 条
    final minimal = nonSystem.sublist(nonSystem.length - recentCount);
    final result = systemMessage != null
        ? [systemMessage, ...minimal]
        : minimal;

    return result;
  }
}

// ══════════════════════════════════════════════
// IChatEngine 接口
// ══════════════════════════════════════════════

/// 统一聊天引擎接口
///
/// UI 层通过此接口与 AI 交互，不直接调用 Provider。
///
/// 架构：
/// ```
/// UI → IChatEngine → IAIProviderManager → AIProvider
/// ```
abstract class IChatEngine {
  // ── Session 管理 ──

  /// 创建新会话
  ChatSession createSession({String? title, Map<String, dynamic>? metadata});

  /// 删除会话
  void deleteSession(String sessionId);

  /// 获取会话
  ChatSession? getSession(String sessionId);

  /// 获取所有会话
  List<ChatSession> listSessions();

  // ── 消息操作 ──

  /// 获取会话消息历史
  Future<List<ChatMessage>> getMessages(String sessionId);

  /// 发送消息（非流式）
  Future<ChatMessage> sendMessage({
    required String sessionId,
    required String content,
    Map<String, dynamic>? metadata,
  });

  /// 发送消息（流式）
  ///
  /// 返回流式 chunk，流结束后通过返回的 Future 获取完整消息。
  Stream<String> streamMessage({
    required String sessionId,
    required String content,
    Map<String, dynamic>? metadata,
  });

  /// 重试最后一条消息
  Future<ChatMessage> retryLastMessage(String sessionId);

  /// 停止生成
  void stopGeneration(String sessionId);

  // ── 上下文管理 ──

  /// 添加上下文片段
  void addContext(String key, String value);

  /// 移除上下文片段
  void removeContext(String key);

  /// 清空上下文
  void clearContext();

  // ── 状态 ──

  /// 是否有正在进行的生成
  bool isGenerating(String sessionId);

  /// 获取生成状态
  GenerationStatus getGenerationStatus(String sessionId);

  // ── 生命周期 ──

  /// 释放资源
  void dispose();
}

// ══════════════════════════════════════════════
// ChatEngine 实现
// ══════════════════════════════════════════════

/// 统一聊天引擎实现
///
/// 在 [IAIProviderManager] 之上提供 Session 管理、上下文组装、Chat 流程控制。
class ChatEngine implements IChatEngine {
  final IAIProviderManager _providerManager;
  final TokenContextManager _tokenManager;
  final ContextManager _contextManager;
  final Map<String, CancelToken> _activeCancelTokens = {};

  final Map<String, ChatSession> _sessions = {};
  final Map<String, GenerationStatus> _generationStatuses = {};

  /// 默认系统提示词
  String systemPrompt;

  ChatEngine({
    required IAIProviderManager providerManager,
    TokenContextManager? tokenManager,
    ContextManager? contextManager,
    this.systemPrompt = '你是一个 AI 编程助手，精通 Flutter、Dart、Rust、Python 等技术栈。'
        '请用简体中文回答用户的问题。回答时优先给出可直接运行的代码示例。',
  }) : _providerManager = providerManager,
       _tokenManager = tokenManager ?? const TokenContextManager(),
       _contextManager = contextManager ?? DefaultContextManager();

  // ── Session 管理 ──

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
    _activeCancelTokens.remove(sessionId);
  }

  @override
  ChatSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  @override
  List<ChatSession> listSessions() {
    final list = _sessions.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  // ── 消息操作 ──

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
    final session = _getSessionOrThrow(sessionId);

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
    if (session.title.startsWith('对话 ') && session.messagesByRole(ChatRole.user).length == 1) {
      session.title = _generateTitle(content.trim());
    }

    // 构建上下文
    final messages = _buildChatContext(session);

    _generationStatuses[sessionId] = GenerationStatus.streaming;

    try {
      // 调用 Provider
      final result = await _providerManager.chat(
        messages: messages,
        temperature: 0.7,
        maxTokens: 4096,
      );

      final assistantMessage = ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: result,
        timestamp: DateTime.now(),
        metadata: {
          'provider': _providerManager.activeProviderName,
          ...?metadata,
        },
      );
      session.addMessage(assistantMessage);
      _generationStatuses[sessionId] = GenerationStatus.completed;

      return assistantMessage;
    } catch (e) {
      _generationStatuses[sessionId] = GenerationStatus.error;
      rethrow;
    }
  }

  @override
  Stream<String> streamMessage({
    required String sessionId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async* {
    final session = _getSessionOrThrow(sessionId);

    // 检查是否已在生成
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
    if (session.title.startsWith('对话 ') && session.messagesByRole(ChatRole.user).length == 1) {
      session.title = _generateTitle(content.trim());
    }

    final buffer = StringBuffer();
    final cancelToken = CancelToken();
    _activeCancelTokens[sessionId] = cancelToken;

    // 构建 streaming 占位消息
    final placeholderId = 'streaming-${_generateId()}';
    session.addMessage(ChatMessage(
      id: placeholderId,
      role: ChatRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
    ));

    _generationStatuses[sessionId] = GenerationStatus.streaming;

    // 构建上下文（不包含占位消息）
    final messages = _buildChatContext(session, excludePlaceholder: true);

    try {
      final stream = _providerManager.streamChat(
        messages: messages,
        temperature: 0.7,
        maxTokens: 4096,
        cancelToken: cancelToken,
      );

      await for (final chunk in stream) {
        if (cancelToken.isCancelled) break;

        buffer.write(chunk);
        yield chunk;

        // 实时更新占位消息
        session.replaceLastMessage(ChatMessage(
          id: placeholderId,
          role: ChatRole.assistant,
          content: buffer.toString(),
          timestamp: DateTime.now(),
          isStreaming: true,
        ));
      }

      // 流正常结束
      if (!cancelToken.isCancelled) {
        final fullContent = buffer.toString();
        if (fullContent.isEmpty) {
          _generationStatuses[sessionId] = GenerationStatus.error;
          session.replaceLastMessage(ChatMessage(
            id: _generateId(),
            role: ChatRole.assistant,
            content: '⚠️ 未收到有效回复',
            timestamp: DateTime.now(),
          ));
        } else {
          _generationStatuses[sessionId] = GenerationStatus.completed;
          session.replaceLastMessage(ChatMessage(
            id: _generateId(),
            role: ChatRole.assistant,
            content: fullContent,
            timestamp: DateTime.now(),
            metadata: {
              'provider': _providerManager.activeProviderName,
              ...?metadata,
            },
          ));
        }
      }
    } catch (e) {
      _generationStatuses[sessionId] = GenerationStatus.error;

      final errorMsg = e.toString();
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: '❌ $errorMsg',
        timestamp: DateTime.now(),
        metadata: {'error': errorMsg},
      ));

      if (e is ChatEngineException) rethrow;
      throw ChatEngineException(
        type: ChatEngineErrorType.internal,
        message: '流式聊天失败: $e',
      );
    } finally {
      _activeCancelTokens.remove(sessionId);
    }
  }

  @override
  Future<ChatMessage> retryLastMessage(String sessionId) async {
    final session = _getSessionOrThrow(sessionId);

    // 找到最后一条用户消息
    final userMessages = session.messagesByRole(ChatRole.user);
    if (userMessages.isEmpty) {
      throw const ChatEngineException(
        type: ChatEngineErrorType.internal,
        message: '没有可重试的消息',
      );
    }

    // 移除最后一条 assistant 消息（如果有）
    if (session.messages.isNotEmpty &&
        session.messages.last.role == ChatRole.assistant) {
      session.messages.removeLast();
    }

    // 移除最后一条 user 消息（sendMessage 会重新添加）
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
    _generationStatuses[sessionId] = GenerationStatus.completed;

    final cancelToken = _activeCancelTokens.remove(sessionId);
    cancelToken?.cancel();

    // 更新会话中的 streaming 占位消息
    final session = _sessions[sessionId];
    if (session != null && session.messages.isNotEmpty) {
      final last = session.messages.last;
      if (last.isStreaming) {
        session.replaceLastMessage(ChatMessage(
          id: _generateId(),
          role: ChatRole.assistant,
          content: last.content.isNotEmpty ? last.content : '⚠️ 已停止生成',
          timestamp: DateTime.now(),
          metadata: {'stopped': true},
        ));
      }
    }
  }

  // ── 上下文管理 ──

  @override
  void addContext(String key, String value) {
    _contextManager.addContext(key, value);
  }

  @override
  void removeContext(String key) {
    _contextManager.removeContext(key);
  }

  @override
  void clearContext() {
    _contextManager.clearContext();
  }

  // ── 状态 ──

  @override
  bool isGenerating(String sessionId) {
    return _generationStatuses[sessionId] == GenerationStatus.streaming;
  }

  @override
  GenerationStatus getGenerationStatus(String sessionId) {
    return _generationStatuses[sessionId] ?? GenerationStatus.idle;
  }

  // ── 生命周期 ──

  @override
  void dispose() {
    // 停止所有活动生成
    for (final sessionId in _sessions.keys.toList()) {
      stopGeneration(sessionId);
    }
    _sessions.clear();
    _generationStatuses.clear();
    _activeCancelTokens.clear();
  }

  // ── 内部方法 ──

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

  /// 构建发送给 Provider 的消息列表
  ///
  /// 组装：system message + 上下文提示 + 历史消息（经 Token 裁剪）
  List<ChatMessageInput> _buildChatContext(
    ChatSession session, {
    bool excludePlaceholder = false,
  }) {
    // 构建 system message（含上下文）
    final contextPrompt = _contextManager.buildContextPrompt();
    final systemContent = contextPrompt.isNotEmpty
        ? '$systemPrompt$contextPrompt'
        : systemPrompt;

    final systemMessage = ChatMessage(
      id: 'system',
      role: ChatRole.system,
      content: systemContent,
      timestamp: DateTime.now(),
    );

    // 准备消息列表（排除占位符）
    List<ChatMessage> historyMessages;
    if (excludePlaceholder) {
      historyMessages = session.messages
          .where((m) => !m.id.startsWith('streaming-'))
          .toList();
    } else {
      historyMessages = List.from(session.messages);
    }

    // Token 裁剪
    final trimmed = _tokenManager.trimContext(
      messages: historyMessages,
      systemMessage: systemMessage,
    );

    // 转换为 ChatMessageInput
    return trimmed
        .where((m) => m.content.isNotEmpty)
        .map((m) => ChatMessageInput(
              role: m.role.apiValue,
              content: m.content,
            ))
        .toList();
  }

  String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  String _generateTitle(String content) {
    // 取用户消息的前 30 个字符作为标题
    final cleaned = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 30) return cleaned;
    return '${cleaned.substring(0, 30)}...';
  }
}
