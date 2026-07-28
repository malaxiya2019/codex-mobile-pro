import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/performance/performance_tracker.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class CodexMobileApp extends ConsumerStatefulWidget {
  const CodexMobileApp({super.key});

  @override
  ConsumerState<CodexMobileApp> createState() => _CodexMobileAppState();
}

class _CodexMobileAppState extends ConsumerState<CodexMobileApp> {
  @override
  void initState() {
    super.initState();
    // 首帧渲染完成后记录 app_ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerformanceTracker.instance.recordEvent('app_ready');
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Codex Mobile Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
