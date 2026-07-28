import 'dart:async';
import '../ai_provider.dart';
import '../ai_service.dart';
import '../ai_message.dart';

/// DeepSeek AI Provider 实现
///
/// 包装现有 [AiService]，实现 [AiProvider] 接口。
/// 支持内联补全、流式聊天、非流式聊天。
class DeepSeekProvider implements AiProvider {
  AiService? _service;
  AiProviderStatus _status = AiProviderStatus.uninitialized;
  final AiConfig _config;

  DeepSeekProvider({AiConfig? config})
      : _config = config ?? const AiConfig();

  @override
  String get name => 'DeepSeek';

  @override
  AiProviderStatus get status => _status;

  @override
  Future<void> initialize() async {
    _status = AiProviderStatus.initializing;
    try {
      _service = AiService(config: _config);
      final health = await _service!.checkStatus();
      if (health == AiServiceStatus.ready) {
        _status = AiProviderStatus.ready;
      } else if (health == AiServiceStatus.invalidKey) {
        _status = AiProviderStatus.invalidConfig;
      } else {
        _status = AiProviderStatus.error;
      }
    } catch (e) {
      _status = AiProviderStatus.error;
    }
  }

  @override
  Future<List<InlineCompletion>> getInlineCompletions({
    required InlineCompletionRequest request,
    CompletionTriggerKind triggerKind = CompletionTriggerKind.automatic,
    CancelToken? cancelToken,
  }) async {
    if (_service == null || _status != AiProviderStatus.ready) {
      return [];
    }

    if (cancelToken?.isCancelled == true) return [];

    // 构建补全 prompt
    final systemPrompt = _buildInlineCompletionPrompt(request.language);
    final userPrompt = _buildUserPrompt(request);

    try {
      final response = await _service!.chat(
        messages: [
          ChatMessage(
            id: 'system',
            role: ChatRole.system,
            content: systemPrompt,
            timestamp: DateTime.now(),
          ),
          ChatMessage(
            id: 'user',
            role: ChatRole.user,
            content: userPrompt,
            timestamp: DateTime.now(),
          ),
        ],
        temperature: 0.2,
        maxTokens: 256,
      );

      if (cancelToken?.isCancelled == true) return [];

      // 解析响应
      final text = response.content.trim();

      // 清理可能的 markdown 代码块包裹
      String cleaned = text;
      if (cleaned.startsWith('```')) {
        final firstNewline = cleaned.indexOf('\n');
        if (firstNewline != -1) {
          cleaned = cleaned.substring(firstNewline + 1);
        }
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();

      if (cleaned.isEmpty) return [];

      // 分解为多行,只返回第一段完整补全
      final lines = cleaned.split('\n');
      final suggestion = lines.take(5).join('\n').trim();

      if (suggestion.isEmpty) return [];

      return [
        InlineCompletion(
          text: suggestion,
          score: 0.9,
          label: 'DeepSeek',
        ),
      ];
    } catch (e) {
      return [];
    }
  }

  @override
  Stream<String> streamChat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
  }) async* {
    if (_service == null || _status != AiProviderStatus.ready) return;

    final completer = Completer<void>();
    final streamController = StreamController<String>();

    final chatMessages = messages
        .map((m) => ChatMessage(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              role: _toChatRole(m.role),
              content: m.content,
              timestamp: DateTime.now(),
            ))
        .toList();

    _service!.chatStream(
      messages: chatMessages,
      temperature: temperature,
      maxTokens: maxTokens,
      onChunk: (chunk) {
        if (cancelToken?.isCancelled == true) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        streamController.add(chunk);
      },
      onDone: (full) {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (error) {
        if (!completer.isCompleted) completer.complete();
      },
    );

    // 取消监听
    cancelToken?.reset();

    await for (final chunk in streamController.stream) {
      if (cancelToken?.isCancelled == true) break;
      yield chunk;
    }

    if (!completer.isCompleted) completer.complete();
    await completer.future;
  }

  @override
  Future<String> chat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
  }) async {
    if (_service == null || _status != AiProviderStatus.ready) {
      return '';
    }

    final chatMessages = messages
        .map((m) => ChatMessage(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              role: _toChatRole(m.role),
              content: m.content,
              timestamp: DateTime.now(),
            ))
        .toList();

    try {
      final response = await _service!.chat(
        messages: chatMessages,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      return response.content;
    } catch (e) {
      return '';
    }
  }

  @override
  Future<bool> healthCheck() async {
    if (_service == null) return false;
    try {
      final status = await _service!.checkStatus();
      return status == AiServiceStatus.ready;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _service?.dispose();
    _service = null;
    _status = AiProviderStatus.uninitialized;
  }

  // ── 内部方法 ──

  String _buildInlineCompletionPrompt(String language) {
    return '''You are a code completion engine. Your task is to predict the most likely code continuation at the cursor position.
Rules:
- Only output the completion text, no explanation.
- Match the existing code style and indentation.
- Complete logically: complete the current expression, statement, or block.
- Keep completions reasonable length (1-5 lines).
- Do NOT repeat what's already on the current line before cursor.
- Output ONLY the text that should appear after the cursor position.
Language: $language''';
  }

  String _buildUserPrompt(InlineCompletionRequest request) {
    final beforeCursor = request.textBeforeCursor;
    final afterCursor = request.textAfterCursor;

    return '''Complete the code at the cursor position (marked by <CURSOR>):

\`\`\`
${beforeCursor}<CURSOR>${afterCursor}
\`\`\`

Output ONLY the completion text, nothing else.''';
  }

  ChatRole _toChatRole(String role) {
    switch (role) {
      case 'system':
        return ChatRole.system;
      case 'assistant':
        return ChatRole.assistant;
      default:
        return ChatRole.user;
    }
  }
}
