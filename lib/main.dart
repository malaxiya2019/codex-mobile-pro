import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/error/error_handler.dart';
import 'core/logger/log_service.dart';
import 'core/navigation/global_navigator_key.dart';
import 'core/performance/performance_tracker.dart';

void main() {
  // 标记启动开始
  PerformanceTracker.instance.markAppStart();

  WidgetsFlutterBinding.ensureInitialized();

  // 初始化全局异常处理（必须在 runApp 之前）
  GlobalErrorHandler.init(
    config: const ErrorHandlerConfig(),
    navigatorKey: globalNavigatorKey,
  );

  // 初始化日志系统（含文件落盘）
  LogService.init(
    
  );

  // 锁定竖屏
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 设置状态栏样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // 使用 Zone 包裹应用，捕获所有异步异常
  runZonedGuarded(
    () {
      runApp(
        const ProviderScope(
          child: CodexMobileApp(),
        ),
      );
    },
    (Object error, StackTrace stack) {
      GlobalErrorHandler.zoneErrorHandler(error, stack);
    },
  );
}
