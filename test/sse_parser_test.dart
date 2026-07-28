import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/ai/sse_parser.dart';

void main() {
  group('SseParser.parseLine', () {
    test('解析有效的 data 行', () {
      final event = SseParser.parseLine('data: {"choices":[{"delta":{"content":"你好"},"index":0}]}');
      expect(event, isNotNull);
      expect(event!.type, SseEventType.data);
      expect(event.content, '你好');
    });

    test('解析 [DONE] 标记', () {
      final event = SseParser.parseLine('data: [DONE]');
      expect(event, isNotNull);
      expect(event!.type, SseEventType.done);
      expect(event.isDone, true);
    });

    test('空行返回 null', () {
      final event = SseParser.parseLine('');
      expect(event, isNull);
    });

    test('注释行（: 开头）返回 null', () {
      final event = SseParser.parseLine(': this is a comment');
      expect(event, isNull);
    });

    test('非 data 行返回 null', () {
      final event = SseParser.parseLine('event: message');
      expect(event, isNull);
    });

    test('无效 JSON 返回 error 事件', () {
      final event = SseParser.parseLine('data: {invalid json}');
      expect(event, isNotNull);
      expect(event!.type, SseEventType.error);
      expect(event.errorMessage, contains('SSE 解析失败'));
    });
  });

  group('SseParser.extractContent', () {
    test('从有效 JSON 中提取内容', () {
      final json = {
        'choices': [
          {
            'delta': {'content': 'Hello'},
            'index': 0,
          }
        ]
      };
      expect(SseParser.extractContent(json), 'Hello');
    });

    test('choices 为空返回空字符串', () {
      final json = {'choices': <dynamic>[]};
      expect(SseParser.extractContent(json), '');
    });

    test('缺少 choices 返回空字符串', () {
      final json = <String, dynamic>{};
      expect(SseParser.extractContent(json), '');
    });

    test('delta 中缺少 content 返回空字符串', () {
      final json = {
        'choices': [
          {
            'delta': {'role': 'assistant'},
            'index': 0,
          }
        ]
      };
      expect(SseParser.extractContent(json), '');
    });
  });

  group('SseParser.byteTransformer', () {
    test('转换完整 SSE 流', () async {
      final parser = SseParser();
      final input = utf8.encode(
        'data: {"choices":[{"delta":{"content":"您好"},"index":0}]}\n\n'
        'data: {"choices":[{"delta":{"content":"世界"},"index":0}]}\n\n'
        'data: [DONE]\n\n',
      );

      final events = <SseEvent>[];
      final controller = StreamController<List<int>>();
      controller.stream
          .transform(parser.byteTransformer)
          .listen((event) => events.add(event));

      controller.add(input);
      await controller.close();

      expect(events.length, 3);
      expect(events[0].type, SseEventType.data);
      expect(events[0].content, '您好');
      expect(events[1].content, '世界');
      expect(events[2].type, SseEventType.done);
      expect(events[2].isDone, true);
    });
  });

  group('SseEvent', () {
    test('SseEvent.data 正确创建', () {
      final json = {'choices': [{'delta': {'content': 'test'}, 'index': 0}]};
      final event = SseEvent.data(json);
      expect(event.type, SseEventType.data);
      expect(event.isDone, false);
      expect(event.errorMessage, isNull);
    });

    test('SseEvent.done 正确创建', () {
      final event = SseEvent.done();
      expect(event.type, SseEventType.done);
      expect(event.isDone, true);
    });

    test('SseEvent.error 正确创建', () {
      final event = SseEvent.error('测试错误');
      expect(event.type, SseEventType.error);
      expect(event.errorMessage, '测试错误');
    });
  });

  group('ChatRole', () {
    test('apiValue 正确映射', () {
      expect(ChatRole.system.apiValue, 'system');
      expect(ChatRole.user.apiValue, 'user');
      expect(ChatRole.assistant.apiValue, 'assistant');
      expect(ChatRole.tool.apiValue, 'tool');
    });

    test('fromApi 正确反映射', () {
      expect(ChatRole.fromApi('system'), ChatRole.system);
      expect(ChatRole.fromApi('user'), ChatRole.user);
      expect(ChatRole.fromApi('assistant'), ChatRole.assistant);
      expect(ChatRole.fromApi('tool'), ChatRole.tool);
      expect(ChatRole.fromApi('unknown'), ChatRole.user);
    });
  });

  group('ChatMessage', () {
    test('copyWith 正确复制', () {
      final msg = ChatMessage(
        id: '1',
        role: ChatRole.user,
        content: '你好',
        timestamp: DateTime(2026),
      );
      final copy = msg.copyWith(content: '世界');
      expect(copy.id, '1');
      expect(copy.content, '世界');
      expect(copy.role, ChatRole.user);
    });

    test('toApiMap 正确转换', () {
      final msg = ChatMessage(
        id: '1',
        role: ChatRole.user,
        content: '你好',
        timestamp: DateTime(2026),
      );
      final map = msg.toApiMap();
      expect(map['role'], 'user');
      expect(map['content'], '你好');
    });
  });

  group('ChatCompletionResponse', () {
    test('fromJson 正确解析', () {
      final json = {
        'id': 'chat-123',
        'model': 'deepseek-chat',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': '你好！'
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
      final response = ChatCompletionResponse.fromJson(json);
      expect(response.id, 'chat-123');
      expect(response.model, 'deepseek-chat');
      expect(response.choices.length, 1);
      expect(response.choices[0].message.content, '你好！');
      expect(response.usage!.totalTokens, 30);
    });
  });
}
