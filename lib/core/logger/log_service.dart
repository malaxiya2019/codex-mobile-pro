import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'log_export_channel.dart';
import 'log_file_writer.dart';

/// 日志级别
enum LogLevel {
  debug(0, 'DEBUG'),
  info(1, 'INFO'),
  warning(2, 'WARN'),
  error(3, 'ERROR');

  final int priority;
  final String label;
  const LogLevel(this.priority, this.label);
}

/// 日志服务
///
/// 统一日志系统，支持：
/// - 控制台输出（debugPrint）
/// - 文件落盘（自动轮转）
/// - 日志级别过滤
/// - 高频写入缓冲
class LogService {
  LogService._();

  static LogLevel _level = LogLevel.debug;
  static LogFileWriter? _fileWriter;
  static bool _initialized = false;

  /// 初始化日志系统
  static Future<void> init({
    LogLevel level = LogLevel.debug,
    String? logDir,
    bool enableFile = true,
  }) async {
    if (_initialized) return;
    _level = level;

    if (enableFile) {
      final dir = logDir ?? _defaultLogDir();
      _fileWriter = LogFileWriter(baseDir: dir);
      try {
        await _fileWriter!.init();
      } catch (e) {
        _fileWriter = null;
        debugPrint('[LogService] 日志文件初始化失败: $e');
      }
    }

    _initialized = true;
    info('LogService', '日志系统初始化完成 (level=${level.label})');
  }

  /// 默认日志目录
  static String _defaultLogDir() {
    // 优先使用应用文档目录，回退到临时目录
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Android/data/com.codexmobile.app/files/.codex-mobile-pro/logs';
    }
    return '${Platform.environment['HOME'] ?? '/tmp'}/.codex-mobile-pro/logs';
  }

  /// 设置日志级别
  static void setLevel(LogLevel level) {
    _level = level;
  }

  /// DEBUG
  static void debug(String tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  /// INFO
  static void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// WARNING
  static void warning(String tag, String message) {
    _log(LogLevel.warning, tag, message);
  }

  /// ERROR — 带可选堆栈
  static void error(String tag, Object error, [StackTrace? stack]) {
    final message = error.toString();
    _log(LogLevel.error, tag, message);
    if (stack != null) {
      final stackStr = stack.toString();
      _log(LogLevel.error, tag, 'StackTrace: ${_truncateStack(stackStr)}');
    }
  }

  /// 异常快捷记录
  static void exception(String tag, dynamic exception, [StackTrace? stack]) {
    error(tag, exception is Object ? exception : exception.toString(), stack);
  }

  /// 核心日志方法
  static void _log(LogLevel level, String tag, String message) {
    if (level.priority < _level.priority) return;

    final timestamp = DateTime.now().toIso8601String();
    final output = '[$timestamp][${level.label}][$tag] $message';

    // 控制台输出
    debugPrint(output);

    // 文件写入（异步，不阻塞）
    if (_fileWriter != null) {
      unawaited(_fileWriter!.write(output));
    }
  }

  /// 截断过长的堆栈（避免写盘过大）
  static String _truncateStack(String stack, {int maxLines = 20}) {
    final lines = stack.split('\n');
    if (lines.length <= maxLines) return stack;
    return '${lines.sublist(0, maxLines).join('\n')}\n  ... (${lines.length - maxLines} more lines)';
  }

  /// 立即刷入日志缓冲区
  static Future<void> flush() async {
    await _fileWriter?.flush();
  }

  /// 导出全部日志到 Download 目录
  ///
  /// - Android：通过 MediaStore 写入公共 Download（无需运行时权限）。
  /// - 其他平台（测试/桌面）：写入系统临时目录便于验证。
  /// 成功返回导出文件路径；无日志或失败返回 null。
  static Future<String?> exportLogsToDownload({String? fileName}) async {
    await flush();
    if (_fileWriter == null) return null;

    final content = await _fileWriter!.readAll();
    if (content.trim().isEmpty) return null;

    final name = fileName ?? _exportFileName();

    if (Platform.isAndroid) {
      try {
        final written = await LogExportChannel.writeToDownload(
          fileName: name,
          content: content,
        );
        return '/storage/emulated/0/Download/$written';
      } on PlatformException catch (e) {
        debugPrint('[LogService] 导出日志到 Download 失败: ${e.message}');
        return null;
      } on MissingPluginException {
        debugPrint('[LogService] 日志导出插件未注册');
        return null;
      } catch (e) {
        debugPrint('[LogService] 导出日志到 Download 异常: $e');
        return null;
      }
    }

    // 非 Android：写入系统临时目录（便于测试/桌面调试）
    try {
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsString(content);
      return file.path;
    } catch (e) {
      debugPrint('[LogService] 导出日志（本地）失败: $e');
      return null;
    }
  }

  /// 生成带时间戳的导出文件名
  static String _exportFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'app_log_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}.log';
  }

  /// 获取最近日志
  static Future<String> getRecentLogs({int maxLines = 100}) async {
    if (_fileWriter == null) return '（文件日志未启用）';
    return _fileWriter!.readRecent(maxLines: maxLines);
  }

  /// 清理所有日志
  static Future<void> clearLogs() async {
    await _fileWriter?.clearAll();
    info('LogService', '日志已清理');
  }

  /// 获取日志总大小
  static Future<int> getTotalLogSize() async {
    if (_fileWriter == null) return 0;
    return _fileWriter!.totalSize();
  }

  /// 释放日志资源
  static Future<void> dispose() async {
    await _fileWriter?.dispose();
    _fileWriter = null;
    _initialized = false;
  }
}
