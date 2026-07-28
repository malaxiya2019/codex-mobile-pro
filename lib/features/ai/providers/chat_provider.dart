import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/ai_message.dart';
import '../../../core/ai/ai_service.dart';

/// 对话加载状态
enum ChatLoadingState {
  idle,
  loading,
  streaming,
  error,
}

/// 对话状态
class ChatState {
  final List<ChatMessage> messages;
  final ChatLoadingState loadingState;
  final String? errorMessage;
  final int totalTokens;
  final AiServiceStatus serviceStatus;

  const ChatState({
    this.messages = const [],
    this.loadingState = ChatLoadingState.idle,
    this.errorMessage,
    this.totalTokens = 0,
    this.serviceStatus = AiServiceStatus.proxyDown,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    ChatLoadingState? loadingState,
    String? errorMessage,
    int? totalTokens,
    AiServiceStatus? serviceStatus,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      loadingState: loadingState ?? this.loadingState,
      errorMessage: errorMessage ?? this.errorMessage,
      totalTokens: totalTokens ?? this.totalTokens,
      serviceStatus: serviceStatus ?? this.serviceStatus,
    );
  }

  /// 清空对话
  ChatState cleared() {
    return ChatState(
      serviceStatus: serviceStatus,
    );
  }
}

/// 系统提示词
const kSystemPrompt = ChatMessage(
  id: 'system-0',
  role: ChatRole.system,
  content: '你是一个 AI 编程助手，精通 Flutter、Dart、Rust、Python 等技术栈。'
      '请用简体中文回答用户的问题。回答时优先给出可直接运行的代码示例。',
  timestamp: DateTime(2026),
);

/// 对话 Provider
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});

class ChatNotifier extends StateNotifier<ChatState> {
  AiService? _service;

  ChatNotifier() : super(const ChatState());

  /// 设置 AI 服务（测试用）
  void setService(AiService service) {
    _service = service;
  }

  /// 获取 AI 服务
  AiService _getService() {
    _service ??= AiService();
    return _service!;
  }

  /// 检查代理状态
  Future<AiServiceStatus> checkService() async {
    final status = await _getService().checkStatus();
    state = state.copyWith(serviceStatus: status);
    return status;
  }

  /// 发送消息（流式）
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    final userMessage = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: ChatRole.user,
      content: content.trim(),
      timestamp: DateTime.now(),
    );

    // 添加用户消息 + 占位 AI 消息
    final newMessages = [
      kSystemPrompt,
      ...state.messages.where((m) => m.id != 'system-0'),
      userMessage,
    ];

    // AI 占位（不包含 system 消息在显示中）
    final displayMessages = [...state.messages, userMessage];
    final aiPlaceholder = ChatMessage(
      id: 'streaming-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    state = state.copyWith(
      messages: [...displayMessages, aiPlaceholder],
      loadingState: ChatLoadingState.streaming,
      errorMessage: null,
    );

    try {
      // 检查服务状态
      final status = await checkService();
      if (status != AiServiceStatus.ready) {
        String errMsg;
        switch (status) {
          case AiServiceStatus.proxyDown:
            errMsg = 'mimo2codex 代理未运行，请先启动代理';
            break;
          case AiServiceStatus.invalidKey:
            errMsg = 'DeepSeek API Key 无效，请检查配置';
            break;
          default:
            errMsg = 'AI 服务不可用 (${status.name})';
        }
        state = state.copyWith(
          messages: state.messages.map((m) {
            if (m.id == aiPlaceholder.id) {
              return m.copyWith(
                content: '⚠️ $errMsg',
                isStreaming: false,
              );
            }
            return m;
          }).toList(),
          loadingState: ChatLoadingState.error,
          errorMessage: errMsg,
        );
        return;
      }

      // 准备发送的消息列表（不含占位符）
      final sendMessages = [
        kSystemPrompt,
        ...state.messages
            .where((m) => m.id != 'system-0' && !m.id.startsWith('streaming-'))
            .map((m) => m),
        userMessage,
      ];

      String fullContent = '';

      await _getService().chatStream(
        messages: sendMessages,
        onChunk: (chunk) {
          fullContent += chunk;
          // 实时更新 AI 消息内容
          state = state.copyWith(
            messages: state.messages.map((m) {
              if (m.id == aiPlaceholder.id) {
                return m.copyWith(content: fullContent);
              }
              return m;
            }).toList(),
          );
        },
        onDone: (content) {
          // 流结束，标记为非流式
          state = state.copyWith(
            messages: state.messages.map((m) {
              if (m.id == aiPlaceholder.id) {
                return ChatMessage(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  role: ChatRole.assistant,
                  content: content,
                  timestamp: DateTime.now(),
                );
              }
              return m;
            }).toList(),
            loadingState: ChatLoadingState.idle,
          );
        },
        onError: (error) {
          state = state.copyWith(
            messages: state.messages.map((m) {
              if (m.id == aiPlaceholder.id) {
                return m.copyWith(
                  content: '❌ ${error.message}\n\n请检查网络连接和 API 配置。',
                  isStreaming: false,
                );
              }
              return m;
            }).toList(),
            loadingState: ChatLoadingState.error,
            errorMessage: error.message,
          );
        },
      );
    } catch (e) {
      final errMsg = e.toString();
      state = state.copyWith(
        messages: state.messages.map((m) {
          if (m.id == aiPlaceholder.id) {
            return m.copyWith(
              content: '❌ 发送失败: $errMsg',
              isStreaming: false,
            );
          }
          return m;
        }).toList(),
        loadingState: ChatLoadingState.error,
        errorMessage: errMsg,
      );
    }
  }

  /// 清空对话
  void clearChat() {
    state = state.cleared();
  }

  /// 释放资源
  void dispose() {
    _service?.dispose();
    super.dispose();
  }
}
