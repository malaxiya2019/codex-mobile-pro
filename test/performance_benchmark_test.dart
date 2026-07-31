// ──────────────────────────────────────────────────────────────
// 性能基准测试
// 模拟各种操作并记录性能数据
// 在真机上运行时，结果写入 build/benchmark/ 目录
// ──────────────────────────────────────────────────────────────

import 'package:codex_mobile_pro/core/performance/performance_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PerformanceTracker tracker;

  setUp(() {
    tracker = PerformanceTracker.instance;
    tracker.reset();
    tracker.markAppStart();
  });

  group('性能基线测试套件', () {
    test('B-001: 性能打点基础设施 — 事件记录延迟 < 1ms', () {
      final start = DateTime.now();
      tracker.recordEvent('test_latency');
      final elapsed = DateTime.now().difference(start).inMicroseconds;
      expect(elapsed, lessThan(1000), reason: 'recordEvent 耗时应 < 1ms');
    });

    test('B-002: 页面加载记录延迟 < 5ms', () {
      final start = DateTime.now();
      tracker.recordPageLoad('test_page', 100);
      final elapsed = DateTime.now().difference(start).inMicroseconds;
      expect(elapsed, lessThan(5000), reason: 'recordPageLoad 耗时应 < 5ms');
    });

    test('B-003: 模拟 10 次页面加载 — 平均耗时 < 500ms', () {
      final durations = <int>[];
      for (int i = 0; i < 10; i++) {
        final start = DateTime.now();
        // 模拟页面加载（实际应用中的页面构建）
        List.generate(100, (i) => i * 2); // simulatedWork
        final elapsed = DateTime.now().difference(start).inMilliseconds;
        durations.add(elapsed);
        tracker.recordPageLoad('page_$i', elapsed);
      }
      final avg = durations.reduce((a, b) => a + b) ~/ durations.length;
      expect(avg, lessThan(500), reason: '模拟页面加载平均应 < 500ms');
    });

    test('B-004: 模拟 20 次 AI Token — 每次 < 200ms 处理', () {
      final times = <int>[];

      for (int i = 0; i < 20; i++) {
        final start = DateTime.now();
        // 模拟处理一个 token chunk
        final token = 'token_$i';
        // 模拟字符串操作（类似 AI 响应渲染）
        final result = token.split('_').join(' ');
        expect(result, isNotEmpty);
        final elapsed = DateTime.now().difference(start).inMicroseconds;
        times.add(elapsed);
      }

      final maxTime = times.reduce((a, b) => a > b ? a : b);
      expect(maxTime, lessThan(10000), reason: '单 token 处理应 < 10ms（CI runner 抖动容忍）');
    });

    test('B-005: 模拟消息列表重建 — 100 条消息 < 50ms', () {
      // 模拟消息列表数据
      final messages = List.generate(100, (i) => MapEntry(
        'msg_$i',
        '这是第 $i 条测试消息的内容，包含一些文本用于模拟真实对话。',
      ));

      final start = DateTime.now();

      // 模拟列表重建
      final rendered = messages.map((entry) {
        return '${entry.key}: ${entry.value}';
      }).toList();

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      expect(elapsed, lessThan(50), reason: '100 条消息列表重建应 < 50ms');
      expect(rendered.length, 100);
    });

    test('B-006: 模拟大文本渲染 — 10KB Markdown < 100ms', () {
      // 生成 10KB 模拟 Markdown
      final buffer = StringBuffer();
      buffer.writeln('# 测试文档\n');
      for (int i = 0; i < 50; i++) {
        buffer.writeln('## 章节 $i\n');
        buffer.writeln('这是一段普通的文本内容，用来模拟 Markdown 渲染的性能。\n');
        buffer.writeln('- 列表项 ${i}a');
        buffer.writeln('- 列表项 ${i}b');
        buffer.writeln();
        buffer.writeln('```dart');
        buffer.writeln('void main() {');
        buffer.writeln('  print("Hello, World!");');
        buffer.writeln('}');
        buffer.writeln('```\n');
      }
      final markdown = buffer.toString();

      final start = DateTime.now();

      // 模拟 Markdown 解析（简易的分段处理）
      final lines = markdown.split('\n');
      final codeBlocks = <String>[];
      bool inCode = false;
      String currentCode = '';

      for (final line in lines) {
        if (line.startsWith('```')) {
          if (inCode) {
            codeBlocks.add(currentCode);
            currentCode = '';
          }
          inCode = !inCode;
          continue;
        }
        if (inCode) {
          currentCode += '$line\n';
        }
      }

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      expect(elapsed, lessThan(100), reason: '10KB Markdown 解析应 < 100ms');
      expect(codeBlocks.length, 50);
    });

    test('B-007: 模拟状态更新 — 100 次 setState < 200ms', () {
      final start = DateTime.now();

      // 模拟 ChatState.copyWith 操作
      var state = {
        'messages': <String>[],
        'loadingState': 'idle',
        'errorMessage': null as String?,
      };

      for (int i = 0; i < 100; i++) {
        state = {
          ...state,
          'messages': [...state['messages'] as List, 'msg_$i'],
          'loadingState': i < 99 ? 'streaming' : 'idle',
        };
      }

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      expect(elapsed, lessThan(200), reason: '100 次状态更新应 < 200ms');
      expect((state['messages'] as List).length, 100);
    });

    test('B-008: 模拟 SSE 解析 — 50 个 chunk < 50ms', () {
      final start = DateTime.now();

      // 模拟 SSE 数据解析
      final chunks = <String>[];
      for (int i = 0; i < 50; i++) {
        final jsonStr = 'data: {"choices":[{"delta":{"content":"token_$i"},"index":0}]}';
        if (jsonStr.startsWith('data: ')) {
          final content = jsonStr.substring(6);
          if (content != '[DONE]') {
            chunks.add(content);
          }
        }
      }

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      expect(elapsed, lessThan(50), reason: '50 个 SSE chunk 解析应 < 50ms');
      expect(chunks.length, 50);
    });

    test('B-009: 内存压力 — 10MB 数据处理 < 500ms', () {
      final start = DateTime.now();

      // 模拟 10MB 数据
      const chunkSize = 1024 * 1024; // 1MB
      final dataChunks = <List<int>>[];
      for (int i = 0; i < 10; i++) {
        dataChunks.add(List.generate(chunkSize, (i) => i % 256));
      }

      // 处理数据
      int total = 0;
      for (final chunk in dataChunks) {
        total += chunk.length;
      }

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      expect(elapsed, lessThan(500), reason: '10MB 数据处理应 < 500ms');
      expect(total, 10 * chunkSize);
    });

    test('B-010: 性能摘要一致性', () {
      // 模拟完整的性能和加载数据
      tracker.recordEvent('app_ready');
      tracker.recordPageLoad('home', 350);
      tracker.recordPageLoad('ai', 520);
      tracker.recordPageLoad('deploy', 280);
      tracker.recordAiLatency(requestType: 'first_token', durationMs: 1500, success: true);
      tracker.recordAiLatency(requestType: 'first_token', durationMs: 2800, success: true);
      tracker.recordAiLatency(requestType: 'full_response', durationMs: 6000, success: true);
      tracker.recordAiLatency(requestType: 'first_token', durationMs: 30000, success: false, errorType: 'timeout');

      final summary = tracker.getSummary();

      // 验证关键字段
      expect(summary['total_events'], 2); // app_ready + markAppStart from setUp
      expect(summary['total_page_loads'], 3);
      expect(summary['total_ai_requests'], 4);
      expect(summary['cold_start_ms'], isNotNull);
      expect(summary['page_load_avg_ms'], greaterThan(0));
      expect(summary['ai_success_rate'], '75.0');
    });
  });
}
