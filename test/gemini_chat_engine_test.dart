import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codex_mobile_pro/core/ai/ai_message.dart';
import 'package:codex_mobile_pro/core/ai/attachment.dart';
import 'package:codex_mobile_pro/core/ai/chat_engine.dart';
import 'package:codex_mobile_pro/core/ai/gemini_chat_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 假 Gemini HTTP 客户端：捕获请求体，返回预置 SSE/错误响应
class _FakeGeminiClient extends http.BaseClient {
  _FakeGeminiClient(this.statusCode, this.body);

  final int statusCode;
  final String body;
  http.Request? lastRequest;
  String? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request as http.Request;
    final bytes = await request.finalize().toBytes();
    lastBody = utf8.decode(bytes);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// 挂起客户端：send 返回 200 + 永不发事件的流（直到 close 才结束），
/// 用于模拟「流式输出进行中」的稳定挂起点。
class _HangingClient extends http.BaseClient {
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      _controller.stream,
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  @override
  void close() {
    closed = true;
    if (!_controller.isClosed) _controller.close();
  }
}

/// 真实临时图片文件（PNG 头 + 少量字节）
Future<File> _tempPng(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('gemini_test');
  final f = File('${dir.path}/test.png');
  await f.writeAsBytes(bytes);
  return f;
}

Attachment _imageAttachment(File f, {String mime = 'image/png'}) {
  return Attachment(
    id: 'att-1',
    type: AttachmentType.image,
    name: 'test.png',
    mimeType: mime,
    size: f.lengthSync(),
    path: f.path,
  );
}

void main() {
  group('GeminiChatEngine 会话管理', () {
    test('createSession / getSession / deleteSession', () {
      final engine = GeminiChatEngine();
      final s = engine.createSession(title: 't');
      expect(engine.getSession(s.sessionId), same(s));
      expect(s.title, 't');
      engine.deleteSession(s.sessionId);
      expect(engine.getSession(s.sessionId), isNull);
    });
  });

  group('GeminiChatEngine 未配置 Key', () {
    test('apiKey 为空 → providerUnavailable 异常（不发起请求）', () async {
      final engine = GeminiChatEngine(apiKeyResolver: () async => '');
      final s = engine.createSession();
      await expectLater(
        engine
            .streamMessage(sessionId: s.sessionId, content: '你好')
            .toList(),
        throwsA(isA<ChatEngineException>()
            .having((e) => e.type, 'type', ChatEngineErrorType.providerUnavailable)
            .having((e) => e.message, 'message', contains('Gemini API Key'))),
      );
    });
  });

  group('GeminiChatEngine 请求构造', () {
    test('图片附件 → inline_data base64（内容=文件字节，非路径）', () async {
      const pngBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03];
      final f = await _tempPng(pngBytes);
      addTearDown(() => f.parent.deleteSync(recursive: true));

      final client = _FakeGeminiClient(
        200,
        'data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n\n'
        'data: [DONE]\n\n',
      );
      final engine = GeminiChatEngine(
        httpClient: client,
        apiKeyResolver: () async => 'test-key',
        modelResolver: () async => 'gemini-2.5-flash',
      );
      final s = engine.createSession();
      final att = _imageAttachment(f);
      final chunks = <String>[];
      await for (final c in engine.streamMessage(
        sessionId: s.sessionId,
        content: '请描述这张图片',
        metadata: {'attachments': [att.toJson()]},
      )) {
        chunks.add(c);
      }

      // 1. 请求头带 key
      expect(client.lastRequest!.headers['x-goog-api-key'], 'test-key');
      // 2. URL 指向 streamGenerateContent
      expect(client.lastRequest!.url.path, contains('gemini-2.5-flash:streamGenerateContent'));

      // 3. 请求体解析
      final body = jsonDecode(client.lastBody!) as Map<String, dynamic>;
      final contents = body['contents'] as List<dynamic>;
      final userContent = contents.firstWhere(
        (c) => (c as Map<String, dynamic>)['role'] == 'user',
      ) as Map<String, dynamic>;
      final parts = userContent['parts'] as List<dynamic>;

      // 文本 part
      expect(parts.any((p) => (p as Map<String, dynamic>)['text'] == '请描述这张图片'), isTrue);

      // inline_data part：base64 解码 == 文件字节（证明发的是图片内容而非路径）
      final inline = parts
          .map((p) => p as Map<String, dynamic>)
          .firstWhere((p) => p.containsKey('inline_data'));
      final inlineData = inline['inline_data'] as Map<String, dynamic>;
      expect(inlineData['mime_type'], 'image/png');
      final decoded = base64Decode(inlineData['data'] as String);
      expect(decoded, pngBytes);
      // 路径字符串绝不能出现在请求体
      expect(client.lastBody, isNot(contains(f.path)));

      // 4. 流式输出
      expect(chunks.join(), 'ok');
      // 5. 会话最终 assistant 消息
      final msgs = await engine.getMessages(s.sessionId);
      expect(msgs.last.role, ChatRole.assistant);
      expect(msgs.last.content, 'ok');
      expect(msgs.first.attachments.single.isImage, isTrue);
    });

    test('纯文本（无附件）请求体只有 text part，不含 inline_data', () async {
      final client = _FakeGeminiClient(
        200,
        'data: {"candidates":[{"content":{"parts":[{"text":"hi"}]}}]}\n\n'
        'data: [DONE]\n\n',
      );
      final engine = GeminiChatEngine(
        httpClient: client,
        apiKeyResolver: () async => 'test-key',
      );
      final s = engine.createSession();
      await for (final _ in engine.streamMessage(
        sessionId: s.sessionId,
        content: '你好',
      )) {}
      final body = jsonDecode(client.lastBody!) as Map<String, dynamic>;
      final contents = body['contents'] as List<dynamic>;
      final parts = (contents.last as Map<String, dynamic>)['parts'] as List<dynamic>;
      expect(parts.every((p) => !(p as Map<String, dynamic>).containsKey('inline_data')), isTrue);
    });
  });

  group('GeminiChatEngine 错误处理', () {
    test('HTTP 401 → providerUnavailable', () async {
      final client = _FakeGeminiClient(
        401,
        '{"error":{"message":"API key not valid. Please pass a valid API key."}}',
      );
      final engine = GeminiChatEngine(
        httpClient: client,
        apiKeyResolver: () async => 'bad-key',
      );
      final s = engine.createSession();
      await expectLater(
        engine.streamMessage(sessionId: s.sessionId, content: 'hi').toList(),
        throwsA(isA<ChatEngineException>()
            .having((e) => e.type, 'type', ChatEngineErrorType.providerUnavailable)),
      );
      // 错误消息已写入会话
      final msgs = await engine.getMessages(s.sessionId);
      expect(msgs.last.content, contains('❌'));
    });

    test('HTTP 400（模型不支持图片）→ unsupported 并带出 API message', () async {
      final client = _FakeGeminiClient(
        400,
        '{"error":{"message":"Request contains an invalid argument."}}',
      );
      final engine = GeminiChatEngine(
        httpClient: client,
        apiKeyResolver: () async => 'test-key',
      );
      final s = engine.createSession();
      await expectLater(
        engine.streamMessage(sessionId: s.sessionId, content: 'hi').toList(),
        throwsA(isA<ChatEngineException>()
            .having((e) => e.type, 'type', ChatEngineErrorType.unsupported)
            .having((e) => e.message, 'message', contains('400'))),
      );
    });

    test('多块 SSE 增量文本正确拼接（流式）', () async {
      final client = _FakeGeminiClient(
        200,
        'data: {"candidates":[{"content":{"parts":[{"text":"这是一"}]}}]}\n\n'
        'data: {"candidates":[{"content":{"parts":[{"text":"张图片"}]}}]}\n\n'
        'data: {"candidates":[{"content":{"parts":[{"text":"，里面有一只猫。"}]}}]}\n\n'
        'data: [DONE]\n\n',
      );
      final engine = GeminiChatEngine(
        httpClient: client,
        apiKeyResolver: () async => 'test-key',
      );
      final s = engine.createSession();
      final chunks = <String>[];
      await for (final c in engine.streamMessage(
        sessionId: s.sessionId,
        content: '看下',
      )) {
        chunks.add(c);
      }
      expect(chunks.join(), '这是一张图片，里面有一只猫。');
      expect(engine.getGenerationStatus(s.sessionId), GenerationStatus.completed);
    });
  });

  group('GeminiChatEngine 停止', () {
    test('stopGeneration 将占位替换为已停止', () async {
      final hanging = _HangingClient();
      final engine = GeminiChatEngine(
        httpClient: hanging,
        apiKeyResolver: () async => 'k',
      );
      final s = engine.createSession();
      final sub = engine
          .streamMessage(sessionId: s.sessionId, content: 'hi')
          .listen((_) {});
      // 等待流挂起（占位已创建、请求已发出）
      await Future<void>.delayed(const Duration(milliseconds: 50));
      engine.stopGeneration(s.sessionId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.isGenerating(s.sessionId), isFalse);
      expect(hanging.closed, isTrue);
      // 会话内最后一条为停止占位（⚠️ 已停止生成 或 停止标记）
      final msgs = await engine.getMessages(s.sessionId);
      expect(msgs.last.metadata?['stopped'], isTrue);
      expect(msgs.last.content, contains('已停止'));
      await sub.cancel();
    });
  });
}
