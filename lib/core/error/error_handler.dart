import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../logger/log_service.dart';

/// 全局错误处理状态
enum ErrorHandlerState {
  /// 调试模式 — 显示详细错误信息
  debug,

  /// 生产模式 — 显示用户友好提示
  production,
}

/// 全局异常处理配置
class ErrorHandlerConfig {
  final ErrorHandlerState state;
  final bool enableLogging;
  final bool enableCrashUi;

  const ErrorHandlerConfig({
    this.state = ErrorHandlerState.debug,
    this.enableLogging = true,
    this.enableCrashUi = true,
  });
}

/// 全局错误处理
///
/// 捕获所有未处理的 Flutter/Dart 异常，并：
/// 1. 自动记录日志
/// 2. 调试模式显示详细错误
/// 3. 生产模式显示用户友好界面
/// 4. 保留错误回调供外部处理
class GlobalErrorHandler {
  GlobalErrorHandler._();

  static ErrorHandlerConfig _config = const ErrorHandlerConfig();
  static bool _initialized = false;

  /// 错误发生回调（外部可监听）
  static void Function(FlutterErrorDetails details)? onError;

  /// 重置全局错误处理状态（仅用于测试）
  static void reset() {
    _initialized = false;
    onError = null;
  }

  /// 初始化全局错误处理
  ///
  /// 应在 main() 中尽早调用，在 WidgetsFlutterBinding.ensureInitialized() 之后。
  static void init({
    ErrorHandlerConfig? config,
    void Function(FlutterErrorDetails details)? onErrorCallback,
  }) {
    if (_initialized) return;

    _config = config ?? const ErrorHandlerConfig();
    onError = onErrorCallback;

    // 1. 捕获 Flutter 框架错误
    FlutterError.onError = (FlutterErrorDetails details) {
      _handleFlutterError(details);
    };

    // 2. 捕获 Dart 异步错误（PlatformDispatcher）
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _handleDartError(error, stack);
      return true; // 已处理，防止应用退出
    };

    _initialized = true;
    LogService.info('ErrorHandler', '全局异常处理已初始化 (mode=${_config.state.name})');
  }

  /// 处理 Flutter 框架错误
  static void _handleFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    final stack = details.stack;
    final context = details.context?.toString() ?? '未知上下文';

    // 记录日志
    if (_config.enableLogging) {
      LogService.error(
        'FlutterError',
        '[$context] $exception',
        stack,
      );
    }

    // 外部回调
    onError?.call(details);

    // 调试模式：打印到控制台
    if (_config.state == ErrorHandlerState.debug) {
      FlutterError.dumpErrorToConsole(details);
    }
  }

  /// 处理 Dart 顶层错误
  static bool _handleDartError(Object error, StackTrace stack) {
    // 记录日志
    if (_config.enableLogging) {
      LogService.error('DartError', '$error', stack);
    }

    // 调试模式：打印到控制台
    if (_config.state == ErrorHandlerState.debug) {
      debugPrint('═══════════════════════════════════');
      debugPrint('未处理的 Dart 异常: $error');
      debugPrint('堆栈: $stack');
      debugPrint('═══════════════════════════════════');
    }

    return true;
  }

  /// 使用 Zone 封装应用入口（推荐）
  ///
  /// 捕获所有异步未处理异常。
  ///
  /// 用法:
  /// ```dart
  /// runZonedGuarded(
  ///   () => runApp(const MyApp()),
  ///   GlobalErrorHandler.zoneErrorHandler,
  /// );
  /// ```
  static void zoneErrorHandler(Object error, StackTrace stack) {
    if (_config.enableLogging) {
      LogService.error('ZoneError', '$error', stack);
    }

    if (_config.state == ErrorHandlerState.debug) {
      debugPrint('═══════════════════════════════════');
      debugPrint('Zone 捕获未处理异常: $error');
      debugPrint('堆栈: $stack');
      debugPrint('═══════════════════════════════════');
    }
  }

  /// 获取错误摘要（用于用户显示）
  static String getErrorSummary(Object error) {
    final str = error.toString();

    // FlutterError 通常包含详细信息
    if (error is FlutterError) {
      return error.message.split('\n').first;
    }

    // 常见异常类型
    if (error is FormatException) {
      return '数据格式错误';
    }
    if (error is TypeError) {
      return '类型转换错误';
    }
    if (error is ArgumentError) {
      return '参数错误';
    }

    // 返回前 100 字符
    return str.length > 100 ? '${str.substring(0, 100)}...' : str;
  }

  /// 检查是否已初始化
  static bool get isInitialized => _initialized;
}
