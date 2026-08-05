import 'dart:async';

import 'package:http/http.dart' as http;

import '../ai_message.dart';
import '../ai_provider.dart';
import '../ai_service.dart';

/// DeepSeek AI Provider 实现
///
/// 包装现有 [AiService]，实现 [AiProvider] 接口。
/// 支持内联补全、流式聊天、非流式聊天。
class DeepSeekProvider implements AiProvider {
  AiService? _service;
  AiProviderStatus _status = AiProviderStatus.uninitialized;
  final AiConfig _config;
  final http.Client? _httpClient;

  DeepSeekProvider({AiConfig? config, http.Client? httpClient})
      : _config = config ?? const AiConfig(),
        _httpClient = httpClient;

  @override
  String get name => 'DeepSeek';

  @override
  AiProviderStatus get status => _status;

  @override
  Future<void> initialize() async {
    _status = AiProviderStatus.initializing;
    try {
      _service = AiService(config: _config, httpClient: _httpClient);
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

    final streamController = StreamController<String>();

    final chatMessages = messages
        .map((m) => ChatMessage(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              role: _toChatRole(m.role),
              content: m.content,
              timestamp: DateTime.now(),
            ))
        .toList();

    // 把 AiService.chatStream（Future 风格 + onChunk 回调）桥接为
    // 单订阅 Stream。历史 bug：chatStream 的 Future 既未 await 也未
    // catch，错误变成 unhandled async error 被运行时吞掉；onError 回调
    // 只 complete() 不传错误 → 上层收到空流 → ChatEngine 显示
    // 「⚠️ 未收到有效回复」。现在统一经 streamController 的 error 通道
    // 把真实错误抛给调用方（AIProviderManager 负责重试/failover）。
    final completion = _service!
        .chatStream(
      messages: chatMessages,
      temperature: temperature,
      maxTokens: maxTokens,
      onChunk: (chunk) {
        if (cancelToken?.isCancelled != true) {
          streamController.add(chunk);
        }
      },
      onDone: (_) {
        if (!streamController.isClosed) streamController.close();
      },
    )
        .then<void>((_) {}, onError: (Object error) {
      if (!streamController.isClosed) streamController.addError(error);
    });

    cancelToken?.reset();

    try {
      await for (final chunk in streamController.stream) {
        if (cancelToken?.isCancelled == true) break;
        yield chunk;
      }
      // 流正常结束时若 chatStream 自身还有未传播的错误，在此抛出
      //（正常情况下 completion 已消费，不会抛）。
      await completion;
    } finally {
      if (!streamController.isClosed) streamController.close();
    }
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

```
$beforeCursor<CURSOR>$afterCursor
```

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
