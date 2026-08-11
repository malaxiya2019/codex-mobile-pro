import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/app_locale.dart';
import 'core/performance/performance_tracker.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/git/providers/git_provider.dart';

class CodexMobileApp extends ConsumerStatefulWidget {
  const CodexMobileApp({super.key});

  @override
  ConsumerState<CodexMobileApp> createState() => _CodexMobileAppState();
}

class _CodexMobileAppState extends ConsumerState<CodexMobileApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerformanceTracker.instance.recordEvent('app_ready');
      // App 启动时预加载 GitHub 登录态（从 secure storage 恢复 token）。
      // 触发 StateNotifier 创建 → 异步恢复 isLoggedIn；后续页面无需重新输入。
      ref.read(gitHubAuthProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeState = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final fontFamily = themeState.fontConfig.family;

    return MaterialApp.router(
      title: 'Codex Mobile Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(fontFamily: fontFamily),
      darkTheme: AppTheme.dark(fontFamily: fontFamily),
      themeMode: themeState.materialMode,
      locale: locale.locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: AppLanguage.values.map((l) => l.locale).toList(),
      routerConfig: router,
    );
  }
}
