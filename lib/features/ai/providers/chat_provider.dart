import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/ai/ai_message.dart';
import '../../../core/ai/ai_provider_manager.dart';
import '../../../core/ai/chat_engine.dart';
import '../../../core/ai/chat_session.dart';
import '../../../core/ai/codex_chat_engine.dart';
import '../../../core/ai/providers/deepseek_provider.dart';

// ══════════════════════════════════════════════
// Provider 注入（Sprint 9 可移至独立文件）
// ══════════════════════════════════════════════

/// IAIProviderManager Riverpod Provider
///
/// 保留的旧方案（本地 mimo :8788 直连）后备 Provider；主聊天引擎已切换为
/// [CodexChatEngine]（Codex CLI 驱动），本 Provider 仅供回退/扩展使用。
final aiProviderManagerProvider = Provider<IAIProviderManager>((ref) {
  final manager = AIProviderManager();
  // 默认 DeepSeek Provider：AiConfig 默认指向本地 mimo :8788（zero-auth 模式）
  final deepSeek = DeepSeekProvider();
  manager.register(deepSeek, priority: ProviderPriority.primary);
  unawaited(deepSeek.initialize());
  ref.onDispose(manager.dispose);
  return manager;
});

/// IChatEngine Riverpod Provider
///
/// 使用 [CodexChatEngine]：把「AI 对话」桥接到 rootfs 内的 Codex CLI，
/// AI 可以真实读写选定的项目目录、执行命令并迭代完成任务。
/// 默认工作目录 = App 文档目录（无项目被选中时的兜底）。
final chatEngineProvider = Provider<IChatEngine>((ref) {
  return CodexChatEngine(
    workspaceDirResolver: () async {
      try {
        final dir = await getApplicationDocumentsDirectory();
        return dir.path;
      } catch (_) {
        // 非 Android 环境或目录不可用时回退
        return '/workspace';
      }
    },
  );
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

  /// 当前选中的工作目录（Codex 引擎的 hostWorkingDir）
  final String? workspaceDir;

  const ChatState({
    this.currentSessionId,
    this.sessions = const [],
    this.messages = const [],
    this.loadingState = ChatLoadingState.idle,
    this.errorMessage,
    this.generationStatus = GenerationStatus.idle,
    this.workspaceDir,
  });

  ChatState copyWith({
    String? currentSessionId,
    List<ChatSession>? sessions,
    List<ChatMessage>? messages,
    ChatLoadingState? loadingState,
    String? errorMessage,
    GenerationStatus? generationStatus,
    String? workspaceDir,
  }) {
    return ChatState(
      currentSessionId: currentSessionId ?? this.currentSessionId,
      sessions: sessions ?? this.sessions,
      messages: messages ?? this.messages,
      loadingState: loadingState ?? this.loadingState,
      errorMessage: errorMessage ?? this.errorMessage,
      generationStatus: generationStatus ?? this.generationStatus,
      workspaceDir: workspaceDir ?? this.workspaceDir,
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

  /// 当前选中的工作目录（null = 使用引擎默认）
  String? _workspaceDir;

  ChatNotifier({required IChatEngine engine})
      : _engine = engine,
        super(const ChatState()) {
    _initDefaultSession();
  }

  /// 设置当前工作目录（Codex 引擎的 hostWorkingDir）
  void setWorkspaceDir(String? dir) {
    _workspaceDir = (dir == null || dir.isEmpty) ? null : dir;
    state = state.copyWith(workspaceDir: _workspaceDir);
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
      loadingState: ChatLoadingState.streaming,
    );

    try {
      await for (final _ in _engine.streamMessage(
        sessionId: sessionId,
        content: content.trim(),
        metadata: _workspaceDir != null
            ? {'workspaceDir': _workspaceDir}
            : null,
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
