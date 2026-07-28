import 'ai_message.dart';

/// 聊天会话状态
enum SessionStatus {
  /// 活跃
  active,

  /// 正在生成
  generating,

  /// 已归档
  archived,
}

/// 聊天会话
///
/// 包含会话元数据和消息历史。
/// [metadata] 用于扩展属性（模型选择、Provider 信息等）。
class ChatSession {
  final String sessionId;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessage> messages;
  SessionStatus status;
  final Map<String, dynamic>? metadata;

  ChatSession({
    required this.sessionId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
    this.status = SessionStatus.active,
    this.metadata,
  }) : title = title ?? _defaultTitle(createdAt ?? DateTime.now()),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       messages = messages ?? [];

  /// 添加消息到会话
  void addMessage(ChatMessage message) {
    messages.add(message);
    updatedAt = DateTime.now();
  }

  /// 替换最后一条消息（用于 streaming 结束更新）
  void replaceLastMessage(ChatMessage message) {
    if (messages.isNotEmpty) {
      messages.removeLast();
    }
    messages.add(message);
    updatedAt = DateTime.now();
  }

  /// 获取指定角色的消息
  List<ChatMessage> messagesByRole(ChatRole role) {
    return messages.where((m) => m.role == role).toList();
  }

  /// 获取最后 N 条消息
  List<ChatMessage> lastMessages(int count) {
    if (messages.length <= count) return List.from(messages);
    return messages.sublist(messages.length - count);
  }

  /// 创建默认标题（基于首条用户消息）
  static String _defaultTitle(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '对话 $month-$day $hour:$minute';
  }
}
