import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/error/error_handler.dart';
import 'package:codex_mobile_pro/core/logger/log_service.dart';

void main() {
  group('GlobalErrorHandler', () {
    setUp(() {
      LogService.dispose();
    });

    test('init 不抛异常', () {
      GlobalErrorHandler.init();
      expect(GlobalErrorHandler.isInitialized, true);
    });

    test('重复 init 安全', () {
      GlobalErrorHandler.init();
      GlobalErrorHandler.init(); // 第二次调用应安全
      expect(GlobalErrorHandler.isInitialized, true);
    });

    test('getErrorSummary 返回摘要', () {
      final summary = GlobalErrorHandler.getErrorSummary(
        Exception('连接超时: 10001'),
      );
      expect(summary, isNotEmpty);
    });

    test('getErrorSummary 处理 FlutterError', () {
      final error = FlutterError('布局溢出: 1073741824 pixels');
      final summary = GlobalErrorHandler.getErrorSummary(error);
      expect(summary, contains('布局溢出'));
    });

    test('getErrorSummary 处理长错误截断', () {
      final longError = 'x' * 200;
      final summary = GlobalErrorHandler.getErrorSummary(longError);
      expect(summary.length, lessThanOrEqualTo(103)); // 100 + '...'
    });

    test('getErrorSummary 处理 FormatException', () {
      final summary = GlobalErrorHandler.getErrorSummary(
        FormatException('Invalid number', 'abc'),
      );
      expect(summary, '数据格式错误');
    });

    test('getErrorSummary 处理 TypeError', () {
      final summary = GlobalErrorHandler.getErrorSummary(
        TypeError(),
      );
      expect(summary, '类型转换错误');
    });

    test('zoneErrorHandler 不抛异常', () {
      GlobalErrorHandler.init();
      GlobalErrorHandler.zoneErrorHandler(
        Exception('zone error'),
        StackTrace.current,
      );
      // 没有异常即通过
    });

    test('onError 回调被触发', () {
      FlutterErrorDetails? captured;
      GlobalErrorHandler.init(
        onErrorCallback: (details) {
          captured = details;
        },
      );

      FlutterError.reportError(FlutterErrorDetails(
        exception: Exception('test error'),
        context: ErrorDescription('test context'),
      ));

      expect(captured, isNotNull);
      expect(captured!.exception.toString(), contains('test error'));
    });
  });

  group('ErrorHandlerConfig', () {
    test('默认配置为 debug 模式', () {
      const config = ErrorHandlerConfig();
      expect(config.state, ErrorHandlerState.debug);
      expect(config.enableLogging, true);
      expect(config.enableCrashUi, true);
    });

    test('可以配置生产模式', () {
      const config = ErrorHandlerConfig(state: ErrorHandlerState.production);
      expect(config.state, ErrorHandlerState.production);
    });
  });
}
