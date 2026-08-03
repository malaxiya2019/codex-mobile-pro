/// 日志行解析与过滤（纯函数，便于单元测试）
///
/// 日志格式（LogService 输出）：
/// ```
/// [ISO8601时间戳][级别][标签] 消息
/// ```
/// 崩溃日志 tag 固定为 `CRASH`：
/// ```
/// [2026-08-03T12:00:00.000][ERROR][CRASH][FlutterError] 异常消息
/// ```
library;

/// 日志级别（与 LogService 对应）
enum LogEntryLevel { debug, info, warning, error }

extension LogEntryLevelX on LogEntryLevel {
  String get label => switch (this) {
        LogEntryLevel.debug => 'DEBUG',
        LogEntryLevel.info => 'INFO',
        LogEntryLevel.warning => 'WARN',
        LogEntryLevel.error => 'ERROR',
      };

  int get priority => switch (this) {
        LogEntryLevel.debug => 0,
        LogEntryLevel.info => 1,
        LogEntryLevel.warning => 2,
        LogEntryLevel.error => 3,
      };
}

/// 单条日志记录
class LogEntry {
  final DateTime? timestamp;
  final LogEntryLevel level;
  final String tag;
  final String message;

  /// 是否为崩溃日志（tag 固定为 CRASH）
  final bool isCrash;

  const LogEntry({
    this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  }) : isCrash = tag == 'CRASH';
}

final _logLinePattern = RegExp(
  r'^\[([^\]]+)\]\[(DEBUG|INFO|WARN|ERROR)\]\[([^\]]*)\]\s?(.*)$',
);

/// 解析单行日志；格式不匹配返回 null
LogEntry? parseLogLine(String line) {
  final m = _logLinePattern.firstMatch(line);
  if (m == null) return null;

  final timestamp = DateTime.tryParse(m.group(1)!);
  final level = switch (m.group(2)) {
    'DEBUG' => LogEntryLevel.debug,
    'INFO' => LogEntryLevel.info,
    'WARN' => LogEntryLevel.warning,
    'ERROR' => LogEntryLevel.error,
    _ => LogEntryLevel.info,
  };

  return LogEntry(
    timestamp: timestamp,
    level: level,
    tag: m.group(3)!,
    message: m.group(4) ?? '',
  );
}

/// 解析多行日志文本，跳过无法解析的行
List<LogEntry> parseLogText(String text) {
  final entries = <LogEntry>[];
  for (final line in text.split('\n')) {
    final entry = parseLogLine(line);
    if (entry != null) entries.add(entry);
  }
  return entries;
}

/// 过滤日志列表
///
/// - [minLevel]：低于该级别的日志被过滤
/// - [onlyCrash]：仅保留崩溃日志（tag == CRASH）
List<LogEntry> filterLogEntries(
  List<LogEntry> entries, {
  LogEntryLevel minLevel = LogEntryLevel.debug,
  bool onlyCrash = false,
}) {
  return entries.where((entry) {
    if (entry.level.priority < minLevel.priority) return false;
    if (onlyCrash && !entry.isCrash) return false;
    return true;
  }).toList();
}
