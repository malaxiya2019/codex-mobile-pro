import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'performance_tracker.dart';

/// 性能摘要 Provider
final performanceSummaryProvider = Provider<Map<String, dynamic>>((ref) {
  return PerformanceTracker.instance.getSummary();
});

/// 页面加载耗时记录 Provider
final pageLoadProvider = StateNotifierProvider<PageLoadNotifier, List<PageLoadRecord>>((ref) {
  return PageLoadNotifier();
});

class PageLoadNotifier extends StateNotifier<List<PageLoadRecord>> {
  PageLoadNotifier() : super([]);

  /// 记录页面加载并回传耗时
  int startTimer(String pageName) {
    final start = DateTime.now();
    // 返回 startMs 用于外部计算
    return start.millisecondsSinceEpoch;
  }

  /// 结束计时
  void endTimer(String pageName, int startMs) {
    final duration = DateTime.now().millisecondsSinceEpoch - startMs;
    final record = PageLoadRecord(
      pageName: pageName,
      durationMs: duration,
      timestamp: DateTime.now(),
    );
    state = [...state, record];
    PerformanceTracker.instance.recordPageLoad(pageName, duration);
  }
}
