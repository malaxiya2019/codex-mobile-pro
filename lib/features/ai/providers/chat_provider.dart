import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/ai_message.dart';
import '../../../core/ai/ai_provider_manager.dart';
import '../../../core/ai/chat_engine.dart';
import '../../../core/ai/chat_session.dart';

// ══════════════════════════════════════════════
// Provider 注入（Sprint 9 可移至独立文件）
// ══════════════════════════════════════════════

/// IAIProviderManager Riverpod Provider
final aiProviderManagerProvider = Provider<IAIProviderManager>((ref) {
  return AIProviderManager();
});

/// IChatEngine Riverpod Provider
final chatEngineProvider = Provider<IChatEngine>((ref) {
  final manager = ref.watch(aiProviderManagerProvider);
  return ChatEngine(providerManager: manager);
});

// ══════════════════════════════════════════════
// 状态定义
// ══════════════════════════════════════════════

/// 对话加载状态
enum ChatLoadingState {
  idle,
  loading,
  streaming,
  error,
}

/// 对话状态
class ChatState {
  /// 当前会话 ID
  final String? currentSessionId;

  /// 所有会话列表
  final List<ChatSession> sessions;

  /// 当前会话的消息列表
  final List<ChatMessage> messages;

  /// 加载状态
  final ChatLoadingState loadingState;

  /// 错误信息
  final String? errorMessage;

  /// 引擎生成状态
  final GenerationStatus generationStatus;

  const ChatState({
    this.currentSessionId,
    this.sessions = const [],
    this.messages = const [],
    this.loadingState = ChatLoadingState.idle,
    this.errorMessage,
    this.generationStatus = GenerationStatus.idle,
  });

  ChatState copyWith({
    String? currentSessionId,
    List<ChatSession>? sessions,
    List<ChatMessage>? messages,
    ChatLoadingState? loadingState,
    String? errorMessage,
    GenerationStatus? generationStatus,
  }) {
    return ChatState(
      currentSessionId: currentSessionId ?? this.currentSessionId,
      sessions: sessions ?? this.sessions,
      messages: messages ?? this.messages,
      loadingState: loadingState ?? this.loadingState,
      errorMessage: errorMessage ?? this.errorMessage,
      generationStatus: generationStatus ?? this.generationStatus,
    );
  }
}

// ══════════════════════════════════════════════
// ChatNotifier
// ══════════════════════════════════════════════

/// 对话 Provider
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final engine = ref.watch(chatEngineProvider);
  return ChatNotifier(engine: engine);
});

class ChatNotifier extends StateNotifier<ChatState> {
  final IChatEngine _engine;

  ChatNotifier({required IChatEngine engine})
      : _engine = engine,
        super(const ChatState()) {
    _initDefaultSession();
  }

  /// 初始化默认会话
  void _initDefaultSession() {
    final session = _engine.createSession();
    _syncFromEngine(session.sessionId);
  }

  /// 从引擎同步最新状态
  void _syncFromEngine(String sessionId) {
    final session = _engine.getSession(sessionId);
    final sessions = _engine.listSessions();
    state = ChatState(
      currentSessionId: sessionId,
      sessions: sessions,
      messages: session?.messages ?? [],
      loadingState: _deriveLoadingState(sessionId),
      generationStatus: _engine.getGenerationStatus(sessionId),
    );
  }

  /// 从引擎 GenerationStatus 推导 UI 加载状态
  ChatLoadingState _deriveLoadingState(String sessionId) {
    final status = _engine.getGenerationStatus(sessionId);
    switch (status) {
      case GenerationStatus.streaming:
        return ChatLoadingState.streaming;
      case GenerationStatus.error:
        return ChatLoadingState.error;
      case GenerationStatus.completed:
      case GenerationStatus.idle:
        return ChatLoadingState.idle;
    }
  }

  // ── Session 管理 ──

  /// 创建新会话
  void createSession({String? title}) {
    final session = _engine.createSession(title: title);
    _syncFromEngine(session.sessionId);
  }

  /// 切换会话
  void switchSession(String sessionId) {
    if (state.currentSessionId == sessionId) return;
    // 先停止当前会话的生成
    if (state.currentSessionId != null) {
      _engine.stopGeneration(state.currentSessionId!);
    }
    _syncFromEngine(sessionId);
  }

  /// 删除会话
  void deleteSession(String sessionId) {
    _engine.deleteSession(sessionId);
    final sessions = _engine.listSessions();
    if (sessions.isNotEmpty) {
      _syncFromEngine(sessions.first.sessionId);
    } else {
      _initDefaultSession();
    }
  }

  // ── 消息操作 ──

  /// 发送消息（流式）
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    final sessionId = state.currentSessionId;
    if (sessionId == null) return;

    state = state.copyWith(
      errorMessage: null,
      loadingState: ChatLoadingState.streaming,
    );

    try {
      await for (final _ in _engine.streamMessage(
        sessionId: sessionId,
        content: content.trim(),
      )) {
        // 每收到一个 chunk 就同步状态（引擎会实时更新占位消息内容）
        _syncFromEngine(sessionId);
      }

      // 流结束，同步最终状态
      _syncFromEngine(sessionId);
    } catch (e) {
      // 发生错误时同步状态（引擎已将占位消息替换为错误消息）
      _syncFromEngine(sessionId);
      state = state.copyWith(
        errorMessage: e.toString(),
        loadingState: ChatLoadingState.error,
      );
    }
  }

  /// 停止生成
  void stopGeneration() {
    final sessionId = state.currentSessionId;
    if (sessionId == null) return;
    _engine.stopGeneration(sessionId);
    _syncFromEngine(sessionId);
  }

  /// 重试最后一条消息
  Future<void> retryLastMessage() async {
    final sessionId = state.currentSessionId;
    if (sessionId == null) return;

    state = state.copyWith(
      errorMessage: null,
      loadingState: ChatLoadingState.streaming,
    );

    try {
      await _engine.retryLastMessage(sessionId);
      _syncFromEngine(sessionId);
    } catch (e) {
      _syncFromEngine(sessionId);
      state = state.copyWith(
        errorMessage: e.toString(),
        loadingState: ChatLoadingState.error,
      );
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(
      errorMessage: null,
      loadingState: ChatLoadingState.idle,
    );
  }

  // ── 生命周期 ──

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}
