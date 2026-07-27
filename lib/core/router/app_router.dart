import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/views/home_page.dart';
import 'route_names.dart';

/// GoRouter 路由配置
///
/// 各模块路由由对应 Sprint 添加：
/// - Sprint 2：首页路由
/// - Sprint 4：AI 对话路由
/// - Sprint 5：终端路由
/// - Sprint 6：文件管理路由
/// - Sprint 7：Git 路由
/// - Sprint 3/9：部署/设置路由
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RouteNames.home,
    routes: [
      // 首页（Sprint 0 + Sprint 2）
      GoRoute(
        path: RouteNames.home,
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),

      // ── 以下路由由后续 Sprint 添加 ──
      // AI 对话 — Sprint 4
      // GoRoute(path: '/ai/chat', builder: (_, __) => const AiChatPage()),

      // 终端 — Sprint 5
      // GoRoute(path: '/terminal', builder: (_, __) => const TerminalPage()),

      // 文件管理 — Sprint 6
      // GoRoute(path: '/files', builder: (_, __) => const FileExplorerPage()),

      // Git — Sprint 7
      // GoRoute(path: '/git', builder: (_, __) => const GitPage()),

      // 部署中心 — Sprint 3
      // GoRoute(path: '/deploy', builder: (_, __) => const DeployPage()),

      // 设置 — Sprint 9
      // GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
    ],
  );
});
