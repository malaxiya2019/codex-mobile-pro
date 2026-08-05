import 'dart:convert';

import 'package:codex_mobile_pro/core/ai/ai_client.dart';
import 'package:codex_mobile_pro/core/ai/ai_provider.dart';
import 'package:codex_mobile_pro/core/ai/ai_service.dart';
import 'package:codex_mobile_pro/core/ai/providers/deepseek_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  late _MockHttpClient mockClient;
  late DeepSeekProvider provider;

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://fallback.invalid'));
    registerFallbackValue(
      http.Request('GET', Uri.parse('http://fallback.invalid')),
    );
  });

  setUp(() {
    mockClient = _MockHttpClient();
    provider = DeepSeekProvider(
      config: const AiConfig(
        baseUrl: 'http://fake:8788/v1',
        apiKey: 'test-key',
        maxRetries: 0, // 关闭重试：失败路径只走一轮，测试快速收敛
        initialRetryDelay: Duration(milliseconds: 1),
      ),
      httpClient: mockClient,
    );
  });

  Future<void> initializeReady() async {
    when(() => mockClient.get(any<Uri>())).thenAnswer(
      (_) async => http.Response('OK', 200),
    );
    await provider.initialize();
    expect(provider.status, AiProviderStatus.ready);
  }

  test('未就绪时 streamChat 返回空流（不发起请求）', () async {
    final chunks = <String>[];
    await for (final c in provider.streamChat(messages: const [
      ChatMessageInput(role: 'user', content: 'hi'),
    ])) {
      chunks.add(c);
    }
    expect(chunks, isEmpty);
    verifyNever(() => mockClient.send(any()));
  });

  test('ready 后流式返回 chunks', () async {
    await initializeReady();
    const sseData =
        'data: {"choices":[{"delta":{"content":"Hel"},"index":0}]}\n\n'
        'data: {"choices":[{"delta":{"content":"lo"},"index":0}]}\n\n'
        'data: [DONE]\n\n';
    when(() => mockClient.send(any<http.BaseRequest>())).thenAnswer((_) async {
      return http.StreamedResponse(
        http.ByteStream.fromBytes(utf8.encode(sseData)),
        200,
      );
    });

    final chunks = <String>[];
    await for (final c in provider.streamChat(messages: const [
      ChatMessageInput(role: 'user', content: 'hi'),
    ])) {
      chunks.add(c);
    }
    expect(chunks, ['Hel', 'lo']);
  });

  test('HTTP 错误（401）时 streamChat 抛出 AiClientException 而不是空流', () async {
    // 回归测试：历史上 chatStream 的 Future 未 await/未 catch，
    // onError 只 complete() 不传错误 → 错误被吞 → 上层显示「未收到有效回复」。
    await initializeReady();
    when(() => mockClient.send(any<http.BaseRequest>())).thenAnswer((_) async {
      return http.StreamedResponse(
        http.ByteStream.fromBytes(utf8.encode('Unauthorized')),
        401,
      );
    });

    expect(
      () => provider.streamChat(messages: const [
        ChatMessageInput(role: 'user', content: 'hi'),
      ]).toList(),
      throwsA(isA<AiClientException>()),
    );
  });

  test('SSE error 事件时 streamChat 抛出错误而不是空流', () async {
    await initializeReady();
    const sseData = 'event: error\n'
        'data: {"error":{"message":"bad request"}}\n\n'
        'data: [DONE]\n\n';
    when(() => mockClient.send(any<http.BaseRequest>())).thenAnswer((_) async {
      return http.StreamedResponse(
        http.ByteStream.fromBytes(utf8.encode(sseData)),
        200,
      );
    });

    expect(
      () => provider.streamChat(messages: const [
        ChatMessageInput(role: 'user', content: 'hi'),
      ]).toList(),
      throwsA(isA<AiClientException>()),
    );
  });
}
