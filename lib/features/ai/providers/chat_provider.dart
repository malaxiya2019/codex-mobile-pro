import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/ai/ai_message.dart';
import '../../../core/ai/ai_provider_manager.dart';
import '../../../core/ai/attachment.dart';
import '../../../core/ai/chat_engine.dart';
import '../../../core/ai/chat_session.dart';
import '../../../core/ai/codex_chat_engine.dart';
import '../../../core/ai/gemini_chat_engine.dart';
import '../../../core/ai/providers/deepseek_provider.dart';
import '../models/ai_chat_view_mode.dart';

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

  /// AI 对话界面模式（气泡 / 流式）
  final AiChatViewMode viewMode;

  const ChatState({
    this.currentSessionId,
    this.sessions = const [],
    this.messages = const [],
    this.loadingState = ChatLoadingState.idle,
    this.errorMessage,
    this.generationStatus = GenerationStatus.idle,
    this.workspaceDir,
    this.viewMode = AiChatViewMode.bubble,
  });

  ChatState copyWith({
    String? currentSessionId,
    List<ChatSession>? sessions,
    List<ChatMessage>? messages,
    ChatLoadingState? loadingState,
    String? errorMessage,
    GenerationStatus? generationStatus,
    String? workspaceDir,
    AiChatViewMode? viewMode,
  }) {
    return ChatState(
      currentSessionId: currentSessionId ?? this.currentSessionId,
      sessions: sessions ?? this.sessions,
      messages: messages ?? this.messages,
      loadingState: loadingState ?? this.loadingState,
      errorMessage: errorMessage ?? this.errorMessage,
      generationStatus: generationStatus ?? this.generationStatus,
      workspaceDir: workspaceDir ?? this.workspaceDir,
      viewMode: viewMode ?? this.viewMode,
    );
  }
}

// ══════════════════════════════════════════════
// ChatNotifier
// ══════════════════════════════════════════════

/// Gemini 视觉引擎 Provider（带图片附件时由 ChatNotifier 接管）
///
/// 直连 Google Gemini API（不经 Codex CLI / Linux Runtime），仅承载
/// 「图片理解」场景；纯文本消息仍由 [chatEngineProvider]（Codex）处理。
final geminiChatEngineProvider = Provider<GeminiChatEngine>((ref) {
  final engine = GeminiChatEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// 对话 Provider（主聊天入口）
///
/// 纯文本走 [chatEngineProvider]（Codex / DeepSeek）；带图片附件自动
/// 切换到 [geminiChatEngineProvider]（Gemini 视觉）。
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final engine = ref.watch(chatEngineProvider);
  final visionEngine = ref.watch(geminiChatEngineProvider);
  return ChatNotifier(engine: engine, visionEngine: visionEngine);
});

class ChatNotifier extends StateNotifier<ChatState> {
  final IChatEngine _engine;

  /// Gemini 视觉引擎（带图片附件时接管；null = 禁用图片理解）
  final GeminiChatEngine? _visionEngine;

  /// 当前选中的工作目录（null = 使用引擎默认）
  String? _workspaceDir;

  /// 当前界面模式（气泡 / 流式）
  AiChatViewMode _viewMode = AiChatViewMode.bubble;

  /// 界面模式持久化 key（SharedPreferences）
  static const String _viewModePrefKey = 'ai_chat_view_mode';

  ChatNotifier({
    required IChatEngine engine,
    GeminiChatEngine? visionEngine,
  })  : _engine = engine,
        _visionEngine = visionEngine,
        super(const ChatState()) {
    _initDefaultSession();
    _loadViewMode();
  }

  /// 从 SharedPreferences 恢复界面模式（异步，不阻塞 UI）
  Future<void> _loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_viewModePrefKey);
      final mode = AiChatViewMode.fromName(saved);
      if (!mounted) return; // Provider 已销毁（如页面退出），不再更新 state
      _viewMode = mode;
      state = state.copyWith(viewMode: mode);
    } catch (_) {
      // 读取失败保持默认气泡模式
    }
  }

  /// 切换界面模式（只换渲染层，不重新请求 AI / 不重复执行命令）。
  /// 持久化选择；AI 正在生成时也允许切换。
  Future<void> setViewMode(AiChatViewMode mode) async {
    if (_viewMode == mode) return;
    _viewMode = mode;
    state = state.copyWith(viewMode: mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewModePrefKey, mode.name);
    } catch (_) {}
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
      workspaceDir: _workspaceDir,
      viewMode: _viewMode,
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

  /// 发送消息（流式）。
  ///
  /// [attachments] 为本地附件：随用户消息绑定（仅本地展示，不参与 AI 请求、
  /// 不上传、不塞进 AI Context）。
  Future<void> sendMessage(
    String content, {
    List<Attachment> attachments = const [],
  }) async {
    if (content.trim().isEmpty) return;

    final sessionId = state.currentSessionId;
    if (sessionId == null) return;

    state = state.copyWith(
      loadingState: ChatLoadingState.streaming,
    );

    try {
      final meta = <String, dynamic>{
        if (_workspaceDir != null) 'workspaceDir': _workspaceDir,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };
      // 图片附件 → Gemini 视觉引擎；否则 Codex 引擎（纯文本默认链路不变）
      final hasImage = attachments.any((a) => a.isImage);
      final engine = hasImage && _visionEngine != null
          ? _visionEngine
          : _engine;
      await for (final _ in engine.streamMessage(
        sessionId: sessionId,
        content: content.trim(),
        metadata: meta.isEmpty ? null : meta,
      )) {
        // 每收到一个 chunk 就同步状态（引擎会实时更新占位消息内容）
        _syncFromEngine(sessionId);
      }

      // 流结束，同步最终状态
      _syncFromEngine(sessionId);
    } catch (e) {
      // 发生错误时同步状态（引擎已将占位消息替换为错误消息）
      _syncFromEngine(sessionId);
      // ChatEngineException 展示其 message（不含 [type] 前缀），其余异常按原样
      final message = e is ChatEngineException ? e.message : e.toString();
      state = state.copyWith(
        errorMessage: message,
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
