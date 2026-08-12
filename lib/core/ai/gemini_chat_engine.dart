/// ====================================================================
/// GeminiChatEngine — 直连 Google Gemini API 的多模态聊天引擎
///
/// 实现 [IChatEngine]，与 [CodexChatEngine]（Codex CLI / DeepSeek 文本）
/// 平级。用于「AI 对话带图片附件」的场景：
///   - 不走 Codex CLI / Linux Runtime，Flutter 层直接 HTTPS 调
///     `generativelanguage.googleapis.com/v1beta/models/<model>:streamGenerateContent`
///   - 图片附件 → `attachment.toDataUrl()` → `inline_data` base64
///   - 文本消息保持普通 Gemini 文本对话（纯文本聊天仍由 CodexChatEngine 接管）
///
/// 会话/占位/停止/错误处理骨架与 CodexChatEngine 保持一致，保证
/// ChatNotifier 上层无感知切换。
/// ====================================================================
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/logger/log_service.dart';
import 'ai_message.dart';
import 'attachment.dart';
import 'chat_engine.dart';
import 'chat_session.dart';
import 'gemini_config.dart';

/// Gemini REST 基础 URL
const String kGeminiApiBaseUrl =
    'https://generativelanguage.googleapis.com/v1beta';

/// GeminiChatEngine
class GeminiChatEngine implements IChatEngine {
  /// 可注入 http.Client（测试用；null 时每次请求新建）
  final http.Client? httpClient;

  /// API Key 解析器（测试注入；默认 [GeminiConfig.loadApiKey]）
  final Future<String> Function()? apiKeyResolver;

  /// 模型名解析器（测试注入；默认 [GeminiConfig.loadModel]）
  final Future<String> Function()? modelResolver;

  /// 会话内系统提示词
  @override
  String systemPrompt;

  final Map<String, ChatSession> _sessions = {};
  final Map<String, GenerationStatus> _generationStatuses = {};

  /// sessionId → 正在进行的请求客户端（stopGeneration 时 close 中断流）
  final Map<String, http.Client> _activeClients = {};

  /// sessionId → 已请求停止标记（区分「停止」与「真实错误」）
  final Set<String> _stopRequests = {};

  GeminiChatEngine({
    this.httpClient,
    this.apiKeyResolver,
    this.modelResolver,
    this.systemPrompt = '你是一个乐于助人的 AI 助手。'
        '可以描述图片内容、回答与图片相关的问题。请用简体中文回答。',
  });

  // ── Session 管理 ────────────────────────────────────────────

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
    _stopRequests.remove(sessionId);
  }

  @override
  ChatSession? getSession(String sessionId) => _sessions[sessionId];

  @override
  List<ChatSession> listSessions() {
    final list = _sessions.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  // ── 消息操作 ─────────────────────────────────────────────────

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
    final buffer = StringBuffer();
    await for (final chunk in streamMessage(
      sessionId: sessionId,
      content: content,
      metadata: metadata,
    )) {
      buffer.write(chunk);
    }
    final session = _getSessionOrThrow(sessionId);
    return session.messages.last;
  }

  @override
  Stream<String> streamMessage({
    required String sessionId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async* {
    final session = _getSessionOrThrow(sessionId);

    if (isGenerating(sessionId)) {
      throw const ChatEngineException(
        type: ChatEngineErrorType.sessionBusy,
        message: '该会话正在生成中，请等待完成或停止当前生成',
      );
    }

    final attachments = _attachmentsFromMetadata(metadata);
    if (content.trim().isEmpty && attachments.isEmpty) {
      throw const ChatEngineException(
        type: ChatEngineErrorType.internal,
        message: '消息内容不能为空',
      );
    }

    // 读取 Gemini 配置（每次请求实时读，设置页改 key 后无需重建引擎）
    final apiKey = await (apiKeyResolver ?? GeminiConfig.loadApiKey)();
    if (apiKey.isEmpty) {
      throw const ChatEngineException(
        type: ChatEngineErrorType.providerUnavailable,
        message: '未配置 Gemini API Key。请在「AI 对话 → Gemini 设置」中填写',
      );
    }
    final model = await (modelResolver ?? GeminiConfig.loadModel)();

    // 创建用户消息（含附件，供 UI 展示）
    final userMessage = ChatMessage(
      id: _generateId(),
      role: ChatRole.user,
      content: content.trim(),
      timestamp: DateTime.now(),
      metadata: metadata,
      attachments: attachments,
    );
    session.addMessage(userMessage);

    // 自动更新标题（首条用户消息）
    if (session.title.startsWith('对话 ') &&
        session.messagesByRole(ChatRole.user).length == 1) {
      session.title = content.trim().isEmpty
          ? '图片消息'
          : _generateTitle(content.trim());
    }

    // 占位消息（实时承载文本）
    final placeholderId = 'streaming-${_generateId()}';
    session.addMessage(ChatMessage(
      id: placeholderId,
      role: ChatRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
      metadata: {'gemini': true, 'model': model},
    ));

    _generationStatuses[sessionId] = GenerationStatus.streaming;
    _stopRequests.remove(sessionId);

    final textBuffer = StringBuffer();
    http.Client? ownedClient;
    try {
      final client = httpClient ?? http.Client();
      ownedClient = client;
      _activeClients[sessionId] = client;

      // 构造 Gemini 请求体（历史消息 + 当前用户消息 + 图片 inline_data）
      final body = await _buildRequestBody(session, model, systemPrompt);

      final url =
          '$kGeminiApiBaseUrl/models/$model:streamGenerateContent?alt=sse';
      final request = http.Request('POST', Uri.parse(url))
        ..headers['x-goog-api-key'] = apiKey
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(body);

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errBody = await response.stream.bytesToString();
        throw _buildHttpException(response.statusCode, errBody);
      }

      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (_stopRequests.contains(sessionId)) break;
        final trimmed = line.trim();
        if (!trimmed.startsWith('data: ')) continue;
        final jsonStr = trimmed.substring(6).trim();
        if (jsonStr == '[DONE]') break;
        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final text = _extractText(json);
          if (text.isNotEmpty) {
            textBuffer.write(text);
            _updatePlaceholder(session, placeholderId,
                content: textBuffer.toString(), model: model);
            yield text;
          }
        } catch (_) {
          // 单条 SSE 解析失败不中断（可能为中间事件）
        }
      }
    } catch (e) {
      final wasStop = _stopRequests.contains(sessionId);
      _generationStatuses[sessionId] = GenerationStatus.error;
      if (wasStop) {
        // 主动停止：占位替换为已停止
        session.replaceLastMessage(ChatMessage(
          id: _generateId(),
          role: ChatRole.assistant,
          content: textBuffer.toString().isNotEmpty
              ? textBuffer.toString()
              : '⚠️ 已停止生成',
          timestamp: DateTime.now(),
          metadata: {'stopped': true, 'gemini': true, 'model': model},
        ));
        return;
      }
      final message = e is ChatEngineException
          ? e.message
          : 'Gemini 请求失败: $e';
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: '❌ $message',
        timestamp: DateTime.now(),
        metadata: {'error': message, 'gemini': true, 'model': model},
      ));
      throw ChatEngineException(
        type: e is ChatEngineException
            ? e.type
            : ChatEngineErrorType.internal,
        message: message,
      );
    } finally {
      _activeClients.remove(sessionId);
      if (ownedClient != null && httpClient == null) {
        ownedClient.close();
      }
    }

    // 正常结束
    if (_stopRequests.contains(sessionId)) {
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: textBuffer.toString().isNotEmpty
            ? textBuffer.toString()
            : '⚠️ 已停止生成',
        timestamp: DateTime.now(),
        metadata: {'stopped': true, 'gemini': true, 'model': model},
      ));
    } else {
      _generationStatuses[sessionId] = GenerationStatus.completed;
      final fullContent = textBuffer.toString();
      final finalContent = fullContent.isEmpty
          ? '⚠️ 未收到有效回复'
          : fullContent;
      session.replaceLastMessage(ChatMessage(
        id: _generateId(),
        role: ChatRole.assistant,
        content: finalContent,
        timestamp: DateTime.now(),
        metadata: {'gemini': true, 'model': model},
      ));
      LogService.info('GeminiChatEngine', '回复完成 model=$model');
    }
  }

  @override
  Future<ChatMessage> retryLastMessage(String sessionId) async {
    final session = _getSessionOrThrow(sessionId);
    final userMessages = session.messagesByRole(ChatRole.user);
    if (userMessages.isEmpty) {
      throw const ChatEngineException(
        type: ChatEngineErrorType.internal,
        message: '没有可重试的消息',
      );
    }
    if (session.messages.isNotEmpty &&
        session.messages.last.role == ChatRole.assistant) {
      session.messages.removeLast();
    }
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
    _stopRequests.add(sessionId);
    _activeClients.remove(sessionId)?.close();
    _generationStatuses[sessionId] = GenerationStatus.completed;

    final session = _sessions[sessionId];
    if (session != null && session.messages.isNotEmpty) {
      final last = session.messages.last;
      if (last.isStreaming) {
        session.replaceLastMessage(ChatMessage(
          id: _generateId(),
          role: ChatRole.assistant,
          content: last.content.isNotEmpty ? last.content : '⚠️ 已停止生成',
          timestamp: DateTime.now(),
          metadata: {...?last.metadata, 'stopped': true},
        ));
      }
    }
  }

  // ── 上下文管理（无本地上下文） ───────────────────────────────

  @override
  void addContext(String key, String value) {}

  @override
  void removeContext(String key) {}

  @override
  void clearContext() {}

  // ── 状态 ─────────────────────────────────────────────────────

  @override
  bool isGenerating(String sessionId) {
    return _generationStatuses[sessionId] == GenerationStatus.streaming;
  }

  @override
  GenerationStatus getGenerationStatus(String sessionId) {
    return _generationStatuses[sessionId] ?? GenerationStatus.idle;
  }

  // ── 生命周期 ─────────────────────────────────────────────────

  @override
  void dispose() {
    for (final sessionId in _sessions.keys.toList()) {
      stopGeneration(sessionId);
    }
    _sessions.clear();
    _generationStatuses.clear();
    _stopRequests.clear();
  }

  // ── 请求体构造 ───────────────────────────────────────────────

  /// 把会话消息构造成 Gemini `contents` + `systemInstruction`。
  ///
  /// Gemini role 映射：user → user，assistant → model，system → 系统指令。
  /// 当前用户消息的图片附件 → `inline_data`（base64），**绝不把路径当内容**。
  Future<Map<String, dynamic>> _buildRequestBody(
    ChatSession session,
    String model,
    String systemPrompt,
  ) async {
    final systemTexts = <String>[if (systemPrompt.trim().isNotEmpty) systemPrompt.trim()];
    final contents = <Map<String, dynamic>>[];

    for (final msg in session.messages) {
      // 跳过占位 / 错误 / 停止消息
      if (msg.isStreaming) continue;
      if (msg.content.startsWith('❌') || msg.content.startsWith('⚠️')) continue;

      switch (msg.role) {
        case ChatRole.system:
          if (msg.content.trim().isNotEmpty) systemTexts.add(msg.content.trim());
        case ChatRole.user:
          final parts = <Map<String, dynamic>>[
            if (msg.content.trim().isNotEmpty) {'text': msg.content.trim()},
          ];
          // 图片附件 → inline_data
          for (final a in msg.attachments.where((a) => a.isImage)) {
            final inline = await _inlineDataPart(a);
            if (inline != null) parts.add(inline);
          }
          if (parts.isNotEmpty) {
            contents.add({'role': 'user', 'parts': parts});
          }
        case ChatRole.assistant:
          if (msg.content.trim().isNotEmpty) {
            contents.add({
              'role': 'model',
              'parts': [
                {'text': msg.content.trim()},
              ],
            });
          }
        case ChatRole.tool:
          // Gemini 无 tool 消息，忽略
          break;
      }
    }

    final body = <String, dynamic>{'contents': contents};
    if (systemTexts.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          for (final t in systemTexts) {'text': t},
        ],
      };
    }
    return body;
  }

  /// 图片附件 → `inline_data` part（base64 无 data: 前缀）。
  Future<Map<String, dynamic>?> _inlineDataPart(Attachment a) async {
    final dataUrl = await a.toDataUrl();
    if (dataUrl == null || dataUrl.isEmpty) return null;
    final comma = dataUrl.indexOf(',');
    if (comma < 0 || comma + 1 >= dataUrl.length) return null;
    final base64Data = dataUrl.substring(comma + 1);
    final mime = a.mimeType.trim().isNotEmpty
        ? a.mimeType.trim()
        : 'image/jpeg';
    return {
      'inline_data': {
        'mime_type': mime,
        'data': base64Data,
      },
    };
  }

  // ── 响应解析 ─────────────────────────────────────────────────

  /// 从 Gemini SSE chunk 提取增量文本
  /// 结构：candidates[0].content.parts[*].text
  static String _extractText(Map<String, dynamic> json) {
    try {
      final candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return '';
      final content = candidates[0]?['content'] as Map<String, dynamic>?;
      if (content == null) return '';
      final parts = content['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return '';
      final buffer = StringBuffer();
      for (final part in parts) {
        final text = (part as Map<String, dynamic>?)?['text'] as String?;
        if (text != null && text.isNotEmpty) buffer.write(text);
      }
      return buffer.toString();
    } catch (_) {
      return '';
    }
  }

  ChatEngineException _buildHttpException(int statusCode, String body) {
    // 提取 Gemini error.message
    String message = '';
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final err = json['error'];
        if (err is Map<String, dynamic> && err['message'] is String) {
          message = err['message'] as String;
        }
      }
    } catch (_) {}

    switch (statusCode) {
      case 400:
        return ChatEngineException(
          type: ChatEngineErrorType.unsupported,
          message: message.isNotEmpty
              ? 'Gemini 请求被拒绝（400）：$message'
              : 'Gemini 请求被拒绝（400），可能是图片格式不支持或模型不支持图片输入',
        );
      case 401:
      case 403:
        return ChatEngineException(
          type: ChatEngineErrorType.providerUnavailable,
          message: 'Gemini API Key 无效或已过期（$statusCode），请在设置中重新填写',
        );
      case 429:
        return const ChatEngineException(
          type: ChatEngineErrorType.timeout,
          message: 'Gemini 请求过于频繁（429），请稍后重试',
        );
      case 500:
      case 502:
      case 503:
        return ChatEngineException(
          type: ChatEngineErrorType.internal,
          message: 'Gemini 服务暂时不可用（$statusCode），请稍后重试',
        );
      default:
        return ChatEngineException(
          type: ChatEngineErrorType.internal,
          message: message.isNotEmpty
              ? 'Gemini 请求失败（$statusCode）：$message'
              : 'Gemini 请求失败（HTTP $statusCode）',
        );
    }
  }

  // ── 内部工具 ─────────────────────────────────────────────────

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

  /// 从 metadata['attachments'] 解析附件列表
  List<Attachment> _attachmentsFromMetadata(Map<String, dynamic>? metadata) {
    final raw = metadata?['attachments'];
    if (raw is! List || raw.isEmpty) return const [];
    return raw
        .map((e) => Attachment.fromJson((e as Map).cast<String, dynamic>()))
        .whereType<Attachment>()
        .toList();
  }

  void _updatePlaceholder(
    ChatSession session,
    String placeholderId, {
    required String content,
    required String model,
  }) {
    final idx = session.messages.indexWhere((m) => m.id == placeholderId);
    if (idx < 0) return;
    session.messages[idx] = ChatMessage(
      id: placeholderId,
      role: ChatRole.assistant,
      content: content,
      timestamp: DateTime.now(),
      isStreaming: true,
      metadata: {'gemini': true, 'model': model},
    );
    session.updatedAt = DateTime.now();
  }

  String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  String _generateTitle(String content) {
    final cleaned = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 30) return cleaned;
    return '${cleaned.substring(0, 30)}...';
  }
}
