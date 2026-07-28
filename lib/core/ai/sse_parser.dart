import 'dart:async';
import 'dart:convert';

/// SSE (Server-Sent Events) 流式解析器
///
/// 将 HTTP 响应体中的 SSE 数据逐行解析为结构化事件。
/// 支持标准 SSE 格式：
///   data: {"choices":[{"delta":{"content":"你好"},"index":0}]}
///   data: [DONE]
class SseParser {
  /// 转换原始字节流为 SSE 事件流
  StreamTransformer<List<int>, SseEvent> get byteTransformer {
    // 缓冲所有字节块，在流关闭时统一处理
    final chunks = <int>[];
    return StreamTransformer<List<int>, SseEvent>.fromHandlers(
      handleData: (data, sink) {
        chunks.addAll(data);
      },
      handleDone: (sink) {
        if (chunks.isEmpty) {
          sink.close();
          return;
        }
        final text = utf8.decode(chunks, allowMalformed: true);
        for (final line in const LineSplitter().convert(text)) {
          if (line.isEmpty || line.startsWith(':')) continue;
          if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6).trim();
            if (jsonStr == '[DONE]') {
              sink.add(SseEvent.done());
              return;
            }
            try {
              final json = jsonDecode(jsonStr) as Map<String, dynamic>;
              sink.add(SseEvent.data(json));
            } catch (e) {
              sink.add(SseEvent.error('SSE 解析失败: $e'));
            }
          }
        }
        sink.close();
      },
    );
  }

  /// 解析单行文本为 SSE 事件（用于测试）
  static SseEvent? parseLine(String line) {
    if (line.isEmpty || line.startsWith(':')) return null;

    if (line.startsWith('data: ')) {
      final jsonStr = line.substring(6).trim();
      if (jsonStr == '[DONE]') {
        return SseEvent.done();
      }
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return SseEvent.data(json);
      } catch (e) {
        return SseEvent.error('SSE 解析失败: $e');
      }
    }
    return null;
  }

  /// 从 JSON chunk 中提取内容增量
  static String extractContent(Map<String, dynamic> json) {
    try {
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return '';
      final delta = choices[0] as Map<String, dynamic>?;
      if (delta == null) return '';
      final content = delta['delta'] as Map<String, dynamic>?;
      if (content == null) return '';
      return content['content'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }
}

/// SSE 事件
class SseEvent {
  final SseEventType type;
  final Map<String, dynamic>? data;
  final String? errorMessage;
  final bool isDone;

  const SseEvent._({
    required this.type,
    this.data,
    this.errorMessage,
    this.isDone = false,
  });

  factory SseEvent.data(Map<String, dynamic> json) {
    return SseEvent._(type: SseEventType.data, data: json);
  }

  factory SseEvent.done() {
    return SseEvent._(type: SseEventType.done, isDone: true);
  }

  factory SseEvent.error(String message) {
    return SseEvent._(type: SseEventType.error, errorMessage: message);
  }

  /// 从事件数据中提取增量文本
  String get content => data != null ? SseParser.extractContent(data!) : '';
}

/// SSE 事件类型
enum SseEventType {
  data,
  done,
  error,
}
