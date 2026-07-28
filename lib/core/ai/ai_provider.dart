/// AI Provider 统一抽象接口
///
/// 所有 AI 能力通过此接口暴露。
/// UI 层不依赖具体实现（DeepSeek / OpenAI / Claude / Gemini 等）。
library;

/// AI 补全请求
class InlineCompletionRequest {
  final String filePath;
  final String language;
  final String prefix;       // 光标之前的文本
  final String suffix;       // 光标之后的文本
  final String textBeforeCursor;
  final String textAfterCursor;
  final int cursorLine;
  final int cursorColumn;

  const InlineCompletionRequest({
    required this.filePath,
    required this.language,
    required this.prefix,
    required this.suffix,
    required this.textBeforeCursor,
    required this.textAfterCursor,
    required this.cursorLine,
    required this.cursorColumn,
  });
}

/// AI 补全响应（单条建议）
class InlineCompletion {
  final String text;
  final double score;
  final String? label;

  const InlineCompletion({
    required this.text,
    this.score = 1.0,
    this.label,
  });
}

/// AI Provider 状态
enum AiProviderStatus {
  /// 未初始化
  uninitialized,

  /// 正在初始化
  initializing,

  /// 已就绪
  ready,

  /// 配置无效
  invalidConfig,

  /// 错误
  error,
}

/// 补全类型
enum CompletionTriggerKind {
  /// 手动触发
  invoked,

  /// 自动触发（输入时）
  automatic,
}

/// AI Provider 抽象接口
///
/// 实现此接口以接入不同的 AI 后端。
/// 所有方法均为异步，支持取消。
abstract class AiProvider {
  /// 提供者名称
  String get name;

  /// 当前状态
  AiProviderStatus get status;

  /// 初始化
  Future<void> initialize();

  /// 获取内联补全（Ghost Text）
  ///
  /// 返回补全建议列表，按 score 降序排列。
  /// 支持通过 [cancelToken] 取消进行中的请求。
  Future<List<InlineCompletion>> getInlineCompletions({
    required InlineCompletionRequest request,
    CompletionTriggerKind triggerKind = CompletionTriggerKind.automatic,
    CancelToken? cancelToken,
  });

  /// 流式聊天
  Stream<String> streamChat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
  });

  /// 非流式聊天
  Future<String> chat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
  });

  /// 检查健康状态
  Future<bool> healthCheck();

  /// 释放资源
  void dispose();
}

/// 聊天消息输入
class ChatMessageInput {
  final String role;     // 'system' | 'user' | 'assistant'
  final String content;

  const ChatMessageInput({
    required this.role,
    required this.content,
  });
}

/// 取消令牌
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  void reset() {
    _cancelled = false;
  }
}
