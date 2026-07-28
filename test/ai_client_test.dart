import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:codex_mobile_pro/core/ai/ai_client.dart';
import 'package:codex_mobile_pro/core/ai/ai_message.dart';
import 'package:codex_mobile_pro/core/ai/sse_parser.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

void main() {
  late MockHttpClient mockClient;
  late AiClient aiClient;

  setUp(() {
    registerFallbackValue(FakeUri());
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
              'content': '你好！',
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
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode(responseJson), 200));

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: '你好', timestamp: DateTime(2026)),
      ];

      final response = await aiClient.chat(messages: messages);
      expect(response.choices.length, 1);
      expect(response.choices[0].message.content, '你好！');
    });

    test('401 返回 api 错误', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
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
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
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
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
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
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
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
      final sseData = 
        'data: {"choices":[{"delta":{"content":"您"},"index":0}]}\n\n'
        'data: {"choices":[{"delta":{"content":"好"},"index":0}]}\n\n'
        'data: [DONE]\n\n';

      final mockStream = http.ByteStream.fromBytes(utf8.encode(sseData));
      final mockResponse = http.StreamedResponse(mockStream, 200);

      when(() => mockClient.send(any())).thenAnswer((_) async => mockResponse);

      final messages = [
        ChatMessage(id: '1', role: ChatRole.user, content: '你好', timestamp: DateTime(2026)),
      ];

      final events = <SseEvent>[];
      await for (final event in aiClient.chatStream(messages: messages)) {
        events.add(event);
      }

      expect(events.length, 3);
      expect(events[0].content, '您');
      expect(events[1].content, '好');
      expect(events[2].isDone, true);
    });

    test('流式请求 401 返回错误', () async {
      final mockStream = http.ByteStream.fromBytes(utf8.encode('Unauthorized'));
      final mockResponse = http.StreamedResponse(mockStream, 401);

      when(() => mockClient.send(any())).thenAnswer((_) async => mockResponse);

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
    test('200 返回 true', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('OK', 200),
      );

      final result = await aiClient.healthCheck();
      expect(result, true);
    });

    test('非 200 返回 false', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Not Found', 404),
      );

      final result = await aiClient.healthCheck();
      expect(result, false);
    });

    test('网络异常返回 false', () async {
      when(() => mockClient.get(any())).thenThrow(Exception('Connection refused'));

      final result = await aiClient.healthCheck();
      expect(result, false);
    });
  });

  group('AiClientException', () {
    test('toString 正确格式化', () {
      final ex = AiClientException(
        type: AiClientErrorType.api,
        message: 'API Key 无效',
        statusCode: 401,
      );
      expect(ex.toString(), '[api] API Key 无效 (HTTP 401)');
    });
  });
}
