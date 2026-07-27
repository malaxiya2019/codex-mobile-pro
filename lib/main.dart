/// Codex Mobile Pro — 手机上的 AI IDE
///
/// 将 Codex CLI、DeepSeek、GitHub、Termux 深度整合，
/// 实现真正的移动端软件开发。
library codex_mobile_pro;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/logger/log_service.dart';

void main() {
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

  runApp(const ProviderScope(child: CodexMobileApp()));
}
