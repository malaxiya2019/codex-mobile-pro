import 'dart:convert';

import 'package:codex_mobile_pro/core/ai/ai_client.dart';
import 'package:codex_mobile_pro/core/ai/ai_message.dart';
import 'package:codex_mobile_pro/core/ai/sse_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  late MockHttpClient mockClient;
  late AiClient aiClient;

  setUp(() {
    registerFallbackValue(FakeUri());
    registerFallbackValue(FakeBaseRequest());
    mockClient = MockHttpClient();
    aiClient = AiClient(
      config: const AiClientConfig(
        baseUrl: 'http://test.local/v1',
        apiKey: 'test-key',
        model: 'test-model',
        timeout: Duration(seconds: 5),
        maxRetries: 0,
      ),
      httpClient: mockClient,
    );
  });

  group('AiClient.chat', () {
    test('非流式请求成功返回响应', () async {
      final responseJson = {
        'id': 'chat-123',
        'model': 'test-model',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'Hello!',
            },
            'finish_reason': 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 20,
          'total_tokens': 30,
        },
      };

      when(() => mockClient.post(
            any<Uri>(),
            headers: any<Map<String, String>>(named: 'headers'),
            body: any<String>(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode(responseJson), 200));

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'hello', timestamp: DateTime(2026)),
      ];

      final response = await aiClient.chat(messages: messages);
      expect(response.choices.length, 1);
      expect(response.choices[0].message.content, 'Hello!');
    });

    test('401 返回 api 错误', () async {
      when(() => mockClient.post(
            any<Uri>(),
            headers: any<Map<String, String>>(named: 'headers'),
            body: any<String>(named: 'body'),
          )).thenAnswer((_) async => http.Response('{"error":"unauthorized"}', 401));

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'test', timestamp: DateTime(2026)),
      ];

      expect(
        () => aiClient.chat(messages: messages),
        throwsA(isA<AiClientException>().having(
          (e) => e.type,
          'type',
          AiClientErrorType.api,
        )),
      );
    });

    test('429 返回 rateLimit 错误', () async {
      when(() => mockClient.post(
            any<Uri>(),
            headers: any<Map<String, String>>(named: 'headers'),
            body: any<String>(named: 'body'),
          )).thenAnswer((_) async => http.Response('{"error":"rate limited"}', 429));

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'test', timestamp: DateTime(2026)),
      ];

      expect(
        () => aiClient.chat(messages: messages),
        throwsA(isA<AiClientException>().having(
          (e) => e.type,
          'type',
          AiClientErrorType.rateLimit,
        )),
      );
    });

    test('502/503 返回 proxyDown 错误', () async {
      when(() => mockClient.post(
            any<Uri>(),
            headers: any<Map<String, String>>(named: 'headers'),
            body: any<String>(named: 'body'),
          )).thenAnswer((_) async => http.Response('Bad Gateway', 502));

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'test', timestamp: DateTime(2026)),
      ];

      expect(
        () => aiClient.chat(messages: messages),
        throwsA(isA<AiClientException>().having(
          (e) => e.type,
          'type',
          AiClientErrorType.proxyDown,
        )),
      );
    });

    test('5xx 返回 server 错误', () async {
      when(() => mockClient.post(
            any<Uri>(),
            headers: any<Map<String, String>>(named: 'headers'),
            body: any<String>(named: 'body'),
          )).thenAnswer((_) async => http.Response('Server Error', 500));

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'test', timestamp: DateTime(2026)),
      ];

      expect(
        () => aiClient.chat(messages: messages),
        throwsA(isA<AiClientException>().having(
          (e) => e.type,
          'type',
          AiClientErrorType.server,
        )),
      );
    });
  });

  group('AiClient.chatStream', () {
    test('流式请求返回 SSE 事件流', () async {
      const sseData = 
        'data: {"choices":[{"delta":{"content":"Hel"},"index":0}]}\n\n'
        'data: {"choices":[{"delta":{"content":"lo"},"index":0}]}\n\n'
        'data: [DONE]\n\n';

      when(() => mockClient.send(any<http.BaseRequest>())).thenAnswer((_) async {
        // 确保 stream 可以被多次监听
        final bytes = utf8.encode(sseData);
        final controller = http.ByteStream.fromBytes(bytes);
        return http.StreamedResponse(controller, 200);
      });

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'hello', timestamp: DateTime(2026)),
      ];

      final events = <SseEvent>[];
      await aiClient
          .chatStream(messages: messages)
          .timeout(const Duration(seconds: 5))
          .forEach((event) => events.add(event));

      expect(events.length, 3);
      expect(events[0].content, 'Hel');
      expect(events[1].content, 'lo');
      expect(events[2].isDone, true);
    });

    test('流式请求 401 返回错误', () async {
      final mockStream = http.ByteStream.fromBytes(utf8.encode('Unauthorized'));
      final mockResponse = http.StreamedResponse(mockStream, 401);

      when(() => mockClient.send(any<http.BaseRequest>())).thenAnswer((_) async => mockResponse);

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'test', timestamp: DateTime(2026)),
      ];

      expect(
        () async {
          await for (final _ in aiClient.chatStream(messages: messages)) {
            // should not reach here
          }
        },
        throwsA(isA<AiClientException>()),
      );
    });
  });

  group('AiClient.healthCheck', () {
    test('200 返回 true（探测 /models 端点而非 /health）', () async {
      when(() => mockClient.get(any<Uri>())).thenAnswer(
        (_) async => http.Response('OK', 200),
      );

      final result = await aiClient.healthCheck();
      expect(result, true);

      // 回归：必须探测 OpenAI 兼容的 /v1/models（mimo2codex 无 /health 路由，
      // 若探测 /health 会 404 → provider 永不 ready → 「未收到有效回复」）
      final captured = verify(() => mockClient.get(captureAny())).captured;
      expect(captured.single, isA<Uri>());
      expect((captured.single as Uri).path, '/v1/models');
    });

    test('非 200 返回 false', () async {
      when(() => mockClient.get(any<Uri>())).thenAnswer(
        (_) async => http.Response('Not Found', 404),
      );

      final result = await aiClient.healthCheck();
      expect(result, false);
    });

    test('网络异常返回 false', () async {
      when(() => mockClient.get(any<Uri>())).thenThrow(Exception('Connection refused'));

      final result = await aiClient.healthCheck();
      expect(result, false);
    });
  });

  group('AiClientException', () {
    test('toString 正确格式化', () {
      const ex = AiClientException(
        type: AiClientErrorType.api,
        message: 'API Key 无效',
        statusCode: 401,
      );
      expect(ex.toString(), '[api] API Key 无效 (HTTP 401)');
    });
  });
}
