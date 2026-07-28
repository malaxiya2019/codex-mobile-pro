import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/logger/log_service.dart';
import 'core/performance/performance_tracker.dart';

void main() {
  // 标记启动开始
  PerformanceTracker.instance.markAppStart();

  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志系统
  LogService.init();

  // 锁定竖屏（手机使用习惯）
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

  runApp(
    const ProviderScope(
      child: CodexMobileApp(),
    ),
  );
}
