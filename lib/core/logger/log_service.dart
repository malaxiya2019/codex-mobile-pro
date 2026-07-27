/// Codex Mobile Pro — 统一日志服务
///
/// 封装日志记录功能，支持级别过滤和文件落盘。
/// 后续可扩展为异步写入日志文件。
library log_service;

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

  /// 初始化日志系统
  static void init({LogLevel level = LogLevel.debug}) {
    _level = level;
    info('LogService', '日志系统初始化完成');
  }

  /// 设置日志级别
  static void setLevel(LogLevel level) {
    _level = level;
  }

  /// 调试日志
  static void debug(String tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  /// 信息日志
  static void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// 警告日志
  static void warning(String tag, String message) {
    _log(LogLevel.warning, tag, message);
  }

  /// 错误日志
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
