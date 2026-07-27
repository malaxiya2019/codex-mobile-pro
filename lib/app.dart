import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Codex Mobile Pro 应用入口 Widget
///
/// 配置 Material 3 主题、GoRouter 路由。
class CodexMobileApp extends ConsumerWidget {
  const CodexMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Codex Mobile Pro',
      debugShowCheckedModeBanner: false,

      // Material 3 主题（亮/暗自适应）
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,

      // GoRouter 路由
      routerConfig: router,
    );
  }
}
