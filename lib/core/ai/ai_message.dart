/// 对话角色
enum ChatRole {
  system,
  user,
  assistant,

  /// 工具调用（预留）
  tool;

  String get apiValue {
    switch (this) {
      case ChatRole.system:
        return 'system';
      case ChatRole.user:
        return 'user';
      case ChatRole.assistant:
        return 'assistant';
      case ChatRole.tool:
        return 'tool';
    }
  }

  static ChatRole fromApi(String value) {
    switch (value) {
      case 'system':
        return ChatRole.system;
      case 'user':
        return ChatRole.user;
      case 'assistant':
        return ChatRole.assistant;
      case 'tool':
        return ChatRole.tool;
      default:
        return ChatRole.user;
    }
  }
}

/// 单条聊天消息
///
/// 用于 Provider 架构的消息模型。
/// [metadata] 用于携带文件引用、Selection、Token 信息等扩展属性。
class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final DateTime timestamp;
  final bool isStreaming;

  /// 扩展元数据
  ///
  /// 不参与 API 序列化，仅用于引擎层内部传递上下文。
  /// 支持：文件引用、Selection、Workspace Context、Token 信息、Provider 信息等。
  final Map<String, dynamic>? metadata;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isStreaming = false,
    this.metadata,
  });

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? content,
    DateTime? timestamp,
    bool? isStreaming,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      metadata: metadata ?? this.metadata,
    );
  }

  /// 转换为 API 请求格式
  ///
  /// 注意：[metadata] 不参与序列化，不影响现有调用方。
  Map<String, dynamic> toApiMap() {
    return {
      'role': role.apiValue,
      'content': content,
    };
  }
}

/// API 请求参数
class ChatCompletionRequest {
  final String model;
  final List<ChatMessage> messages;
  final bool stream;
  final double temperature;
  final int maxTokens;

  const ChatCompletionRequest({
    this.model = 'deepseek-chat',
    required this.messages,
    this.stream = true,
    this.temperature = 0.7,
    this.maxTokens = 4096,
  });

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'messages': messages.map((m) => m.toApiMap()).toList(),
      'stream': stream,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
  }
}

/// API 响应（非流式）
class ChatCompletionResponse {
  final String id;
  final String model;
  final List<ChatChoice> choices;
  final ChatUsage? usage;

  const ChatCompletionResponse({
    required this.id,
    required this.model,
    required this.choices,
    this.usage,
  });

  factory ChatCompletionResponse.fromJson(Map<String, dynamic> json) {
    return ChatCompletionResponse(
      id: json['id'] ?? '',
      model: json['model'] ?? '',
      choices: (json['choices'] as List<dynamic>?)
              ?.map((c) => ChatChoice.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      usage: json['usage'] != null ? ChatUsage.fromJson(json['usage'] as Map<String, dynamic>) : null,
    );
  }
}

/// API 选择
class ChatChoice {
  final int index;
  final ChatMessage message;
  final String? finishReason;

  const ChatChoice({
    required this.index,
    required this.message,
    this.finishReason,
  });

  factory ChatChoice.fromJson(Map<String, dynamic> json) {
    final msg = json['message'] as Map<String, dynamic>? ?? json['delta'] as Map<String, dynamic>? ?? {};
    final now = DateTime.now();
    return ChatChoice(
      index: json['index'] ?? 0,
      message: ChatMessage(
        id: now.microsecondsSinceEpoch.toString(),
        role: ChatRole.fromApi(msg['role'] ?? 'assistant'),
        content: msg['content'] ?? '',
        timestamp: now,
      ),
      finishReason: json['finish_reason'],
    );
  }
}

/// API 用量
class ChatUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const ChatUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  factory ChatUsage.fromJson(Map<String, dynamic> json) {
    return ChatUsage(
      promptTokens: json['prompt_tokens'] ?? 0,
      completionTokens: json['completion_tokens'] ?? 0,
      totalTokens: json['total_tokens'] ?? 0,
    );
  }
}
