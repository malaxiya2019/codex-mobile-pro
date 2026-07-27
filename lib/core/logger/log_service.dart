import 'package:flutter/foundation.dart';

enum LogLevel {
  debug(0, 'DEBUG'),
  info(1, 'INFO'),
  warning(2, 'WARN'),
  error(3, 'ERROR');

  final int priority;
  final String label;
  const LogLevel(this.priority, this.label);
}

class LogService {
  LogService._();

  static LogLevel _level = LogLevel.debug;

  static void init({LogLevel level = LogLevel.debug}) {
    _level = level;
    info('LogService', '日志系统初始化完成');
  }

  static void setLevel(LogLevel level) {
    _level = level;
  }

  static void debug(String tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  static void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  static void warning(String tag, String message) {
    _log(LogLevel.warning, tag, message);
  }

  static void error(String tag, Object error, [StackTrace? stack]) {
    final message = error.toString();
    _log(LogLevel.error, tag, message);
    if (stack != null) {
      debugPrint('└─ StackTrace: ${stack.toString()}');
    }
  }

  static void _log(LogLevel level, String tag, String message) {
    if (level.priority < _level.priority) return;
    final timestamp = DateTime.now().toIso8601String();
    final output = '[$timestamp][${level.label}][$tag] $message';
    debugPrint(output);
  }
}
