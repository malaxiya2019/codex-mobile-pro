import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/performance/performance_tracker.dart';

void main() {
  group('PerformanceTracker', () {
    setUp(() {
      PerformanceTracker.instance.reset();
    });

    test('初始状态为空', () {
      final tracker = PerformanceTracker.instance;
      expect(tracker.events, isEmpty);
      expect(tracker.pageLoads, isEmpty);
      expect(tracker.aiLatencies, isEmpty);
      expect(tracker.coldStartMs, isNull);
    });

    test('markAppStart 记录 app_start 事件', () {
      final tracker = PerformanceTracker.instance;
      tracker.markAppStart();
      expect(tracker.events.length, 1);
      expect(tracker.events[0].name, 'app_start');
    });

    test('recordEvent 记录事件带时间戳', () {
      final tracker = PerformanceTracker.instance;
      tracker.markAppStart();
      tracker.recordEvent('test_event');
      expect(tracker.events.length, 2);
      expect(tracker.events[1].name, 'test_event');
      expect(tracker.events[1].timestamp, isNotNull);
    });

    test('coldStartMs 计算正确', () {
      final tracker = PerformanceTracker.instance;
      tracker.markAppStart();
      tracker.recordEvent('app_ready');
      final coldMs = tracker.coldStartMs;
      expect(coldMs, isNotNull);
      expect(coldMs!, greaterThanOrEqualTo(0));
    });

    test('recordPageLoad 正确记录', () {
      final tracker = PerformanceTracker.instance;
      tracker.recordPageLoad('home_page', 350);
      tracker.recordPageLoad('ai_chat', 420);

      expect(tracker.pageLoads.length, 2);
      expect(tracker.pageLoads[0].pageName, 'home_page');
      expect(tracker.pageLoads[0].durationMs, 350);
      expect(tracker.pageLoads[1].pageName, 'ai_chat');
    });

    test('recordAiLatency 正确记录', () {
      final tracker = PerformanceTracker.instance;
      tracker.recordAiLatency(requestType: 'first_token', durationMs: 1200, success: true);
      tracker.recordAiLatency(requestType: 'full_response', durationMs: 5000, success: true);
      tracker.recordAiLatency(requestType: 'first_token', durationMs: 30000, success: false, errorType: 'timeout');

      expect(tracker.aiLatencies.length, 3);
      expect(tracker.aiLatencies[0].success, true);
      expect(tracker.aiLatencies[2].success, false);
    });

    test('getSummary 返回正确统计', () {
      final tracker = PerformanceTracker.instance;
      tracker.markAppStart();
      tracker.recordEvent('app_ready');
      tracker.recordPageLoad('home', 300);
      tracker.recordPageLoad('ai', 500);
      tracker.recordAiLatency(requestType: 'first_token', durationMs: 1000, success: true);
      tracker.recordAiLatency(requestType: 'first_token', durationMs: 2000, success: true);

      final summary = tracker.getSummary();
      expect(summary['total_events'], 2);
      expect(summary['total_page_loads'], 2);
      expect(summary['total_ai_requests'], 2);
      expect(summary['page_load_avg_ms'], 400);
      expect(summary['ai_first_token_avg_ms'], 1500);
      expect(summary['ai_success_rate'], '100.0');
    });

    test('reset 清除所有数据', () {
      final tracker = PerformanceTracker.instance;
      tracker.markAppStart();
      tracker.recordPageLoad('test', 100);
      tracker.recordAiLatency(requestType: 'test', durationMs: 500, success: true);

      tracker.reset();
      expect(tracker.events, isEmpty);
      expect(tracker.pageLoads, isEmpty);
      expect(tracker.aiLatencies, isEmpty);
    });

    test('toMarkdown 输出有效格式', () {
      final tracker = PerformanceTracker.instance;
      tracker.markAppStart();
      tracker.recordEvent('app_ready');
      tracker.recordPageLoad('home', 300);

      final md = tracker.toMarkdown();
      expect(md, contains('性能基线摘要'));
      expect(md, contains('page_load_avg_ms'));
    });
  });
}
