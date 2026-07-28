/// Codex Mobile Pro — 性能打点跟踪器
///
/// 记录关键性能事件的时间戳、内存快照、页面渲染耗时等数据。
/// 作为 Sprint 0 性能基线的基础测量工具。
///
/// 使用方式：
/// ```dart
/// PerformanceTracker.instance.recordEvent('app_start');
/// PerformanceTracker.instance.recordPageLoad('home_page', duration);
/// ```
library;

import 'dart:io';

/// 性能事件记录
class PerformanceEvent {
  final String name;
  final DateTime timestamp;
  final int? elapsedMs;    /// 相对应用启动的耗时（毫秒）
  final int? memoryKb;     /// 当前内存占用（KB）
  final double? cpuPct;    /// 当前 CPU 占用（百分比）

  const PerformanceEvent({
    required this.name,
    required this.timestamp,
    this.elapsedMs,
    this.memoryKb,
    this.cpuPct,
  });
}

/// 页面加载记录
class PageLoadRecord {
  final String pageName;
  final int durationMs;
  final DateTime timestamp;

  const PageLoadRecord({
    required this.pageName,
    required this.durationMs,
    required this.timestamp,
  });
}

/// AI 请求延迟记录
class AiLatencyRecord {
  final String requestType;    /// 'first_token' | 'full_response'
  final int durationMs;
  final bool success;
  final String? errorType;

  const AiLatencyRecord({
    required this.requestType,
    required this.durationMs,
    required this.success,
    this.errorType,
  });
}

/// 性能跟踪器（单例）
class PerformanceTracker {
  static final PerformanceTracker _instance = PerformanceTracker._();
  static PerformanceTracker get instance => _instance;
  PerformanceTracker._();

  /// 应用启动时间戳
  DateTime? _appStartTime;

  /// 事件历史
  final List<PerformanceEvent> _events = [];
  final List<PageLoadRecord> _pageLoads = [];
  final List<AiLatencyRecord> _aiLatencies = [];

  // ─── 事件记录 ───

  /// 记录性能事件
  void recordEvent(String name, {int? memoryKb, double? cpuPct}) {
    final now = DateTime.now();
    final elapsedMs = _appStartTime != null
        ? now.difference(_appStartTime!).inMilliseconds
        : null;
    _events.add(PerformanceEvent(
      name: name,
      timestamp: now,
      elapsedMs: elapsedMs,
      memoryKb: memoryKb,
      cpuPct: cpuPct,
    ));
  }

  /// 标记应用启动完成
  void markAppStart() {
    _appStartTime ??= DateTime.now();
    recordEvent('app_start');
  }

  /// 记录页面加载耗时
  void recordPageLoad(String pageName, int durationMs) {
    _pageLoads.add(PageLoadRecord(
      pageName: pageName,
      durationMs: durationMs,
      timestamp: DateTime.now(),
    ));
  }

  /// 记录 AI 请求延迟
  void recordAiLatency({
    required String requestType,
    required int durationMs,
    required bool success,
    String? errorType,
  }) {
    _aiLatencies.add(AiLatencyRecord(
      requestType: requestType,
      durationMs: durationMs,
      success: success,
      errorType: errorType,
    ));
  }

  // ─── 数据获取 ───

  /// 获取冷启动耗时（ms）
  int? get coldStartMs {
    final start = _events.where((e) => e.name == 'app_start').firstOrNull;
    final ready = _events.where((e) => e.name == 'app_ready').firstOrNull;
    if (start == null || ready == null) return null;
    return ready.timestamp.difference(start.timestamp).inMilliseconds;
  }

  /// 获取所有已记录事件
  List<PerformanceEvent> get events => List.unmodifiable(_events);

  /// 获取页面加载记录
  List<PageLoadRecord> get pageLoads => List.unmodifiable(_pageLoads);

  /// 获取 AI 延迟记录
  List<AiLatencyRecord> get aiLatencies => List.unmodifiable(_aiLatencies);

  /// 获取事件统计摘要
  Map<String, dynamic> getSummary() {
    final loadTimes = _pageLoads.map((r) => r.durationMs);
    final aiTimes = _aiLatencies
        .where((r) => r.success && r.requestType == 'first_token')
        .map((r) => r.durationMs);

    return {
      'total_events': _events.length,
      'total_page_loads': _pageLoads.length,
      'total_ai_requests': _aiLatencies.length,
      'cold_start_ms': coldStartMs,
      'page_load_avg_ms': loadTimes.isEmpty ? null : loadTimes.reduce((a, b) => a + b) ~/ loadTimes.length,
      'page_load_max_ms': loadTimes.isEmpty ? null : loadTimes.reduce((a, b) => a > b ? a : b),
      'ai_first_token_avg_ms': aiTimes.isEmpty ? null : aiTimes.reduce((a, b) => a + b) ~/ aiTimes.length,
      'ai_success_rate': _aiLatencies.isEmpty
          ? null
          : (_aiLatencies.where((r) => r.success).length / _aiLatencies.length * 100).toStringAsFixed(1),
    };
  }

  // ─── 导出 ───

  /// 导出为 Markdown 报告片段
  String toMarkdown() {
    final summary = getSummary();
    final buf = StringBuffer();

    buf.writeln('## 性能基线摘要（运行时采集）\n');
    buf.writeln('| 指标 | 值 |');
    buf.writeln('|------|-----|');

    buf.writeln('| 冷启动耗时 | ${summary['cold_start_ms'] ?? "未采集"} ms |');
    buf.writeln('| 页面平均加载 | ${summary['page_load_avg_ms'] ?? "未采集"} ms |');
    buf.writeln('| 页面最大加载 | ${summary['page_load_max_ms'] ?? "未采集"} ms |');
    buf.writeln('| AI 首 Token 平均 | ${summary['ai_first_token_avg_ms'] ?? "未采集"} ms |');
    buf.writeln('| AI 请求成功率 | ${summary['ai_success_rate'] ?? "未采集"}% |');
    buf.writeln('| 总事件数 | ${summary['total_events']} |');
    buf.writeln('| 总页面加载 | ${summary['total_page_loads']} |');
    buf.writeln('| 总 AI 请求 | ${summary['total_ai_requests']} |');

    return buf.toString();
  }

  /// 重置所有数据（测试用）
  void reset() {
    _appStartTime = null;
    _events.clear();
    _pageLoads.clear();
    _aiLatencies.clear();
  }
}
