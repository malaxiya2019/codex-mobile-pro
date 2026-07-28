import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/views/home_page.dart';
import '../../features/termux/views/termux_test_page.dart';
import '../../features/deploy/views/deploy_page.dart';
import '../../features/ai/views/ai_chat_page.dart';
import '../../features/settings/views/theme_settings_page.dart';
import '../../features/settings/views/locale_settings_page.dart';
import 'route_guard.dart';
import 'route_names.dart';

/// GoRouter 路由配置
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: RouteNames.home,

    // ── 路由守卫 ──
    // 每次导航前检查权限
    redirect: (context, state) {
      final path = state.uri.path;
      final redirectPath = RoutePermissions.getRedirectPath(path, auth);
      if (redirectPath != null) {
        return redirectPath;
      }
      return null; // 允许访问
    },

    routes: [
      GoRoute(
        path: RouteNames.home,
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: RouteNames.termuxTest,
        name: 'termuxTest',
        builder: (context, state) => const TermuxTestPage(),
      ),
      GoRoute(
        path: RouteNames.deploy,
        name: 'deploy',
        builder: (context, state) => const DeployPage(),
      ),
      GoRoute(
        path: RouteNames.aiChat,
        name: 'aiChat',
        builder: (context, state) => const AiChatPage(),
      ),
      GoRoute(
        path: RouteNames.themeSettings,
        name: 'themeSettings',
        builder: (context, state) => const ThemeSettingsPage(),
      ),
      GoRoute(
        path: RouteNames.localeSettings,
        name: 'localeSettings',
        builder: (context, state) => const LocaleSettingsPage(),
      ),
    ],
  );
});
