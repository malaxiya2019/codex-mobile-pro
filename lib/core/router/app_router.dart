import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/views/home_page.dart';
import '../../features/termux/views/termux_test_page.dart';
import '../../features/deploy/views/deploy_page.dart';
import '../../features/ai/views/ai_chat_page.dart';
import 'route_names.dart';

/// GoRouter 路由配置
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RouteNames.home,
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
    ],
  );
});
