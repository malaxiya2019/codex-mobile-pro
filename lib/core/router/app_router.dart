import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/views/home_page.dart';
import '../../features/termux/views/termux_test_page.dart';
import '../../features/deploy/views/deploy_page.dart';
import '../../features/ai/views/ai_chat_page.dart';
import '../../features/settings/views/theme_settings_page.dart';
import '../../features/settings/views/locale_settings_page.dart';
import '../../features/workspace/views/workspace_list_page.dart';
import '../../features/terminal/views/terminal_page.dart';
import '../../features/git/views/repo_list_page.dart';
import '../../features/git/views/github_login_page.dart';
import '../../features/git/views/pr_list_page.dart';
import '../../features/git/views/issue_list_page.dart';
import '../../features/editor/views/editor_page.dart';
import '../../features/file/views/file_browser_page.dart';
import 'route_guard.dart';
import 'route_names.dart';

/// GoRouter 路由配置
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: RouteNames.home,

    // ── 路由守卫 ──
    redirect: (context, state) {
      final path = state.uri.path;
      final redirectPath = RoutePermissions.getRedirectPath(path, auth);
      if (redirectPath != null) {
        return redirectPath;
      }
      return null;
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
      GoRoute(
        path: RouteNames.workspaceList,
        name: 'workspaceList',
        builder: (context, state) => const WorkspaceListPage(),
      ),
      GoRoute(
        path: RouteNames.terminal,
        name: 'terminal',
        builder: (context, state) => const TerminalPage(),
      ),
      // ── 编辑器 ──
      GoRoute(
        path: RouteNames.editor,
        name: 'editor',
        builder: (context, state) => const EditorPage(),
      ),
      GoRoute(
        path: '/editor/:path',
        name: 'editorFile',
        builder: (context, state) {
          final path = state.pathParameters['path'] ?? '';
          return EditorPage(initialPath: Uri.decodeComponent(path));
        },
      ),
      // ── 文件浏览器 ──
      GoRoute(
        path: RouteNames.fileBrowser,
        name: 'fileBrowser',
        builder: (context, state) => const FileBrowserPage(),
      ),
      // ── GitHub ──
      GoRoute(
        path: RouteNames.gitHubLogin,
        name: 'gitHubLogin',
        builder: (context, state) => const GitHubLoginPage(),
      ),
      GoRoute(
        path: RouteNames.repoList,
        name: 'repoList',
        builder: (context, state) => const RepoListPage(),
      ),
      GoRoute(
        path: '/repos/:owner/:name',
        name: 'repoDetail',
        builder: (context, state) {
          // final owner = state.pathParameters['owner'] ?? '';
          // final name = state.pathParameters['name'] ?? '';
          return RepoListPage(); // 重用仓库列表
        },
      ),
      GoRoute(
        path: '/repos/:owner/:name/prs',
        name: 'repoPrList',
        builder: (context, state) {
          // final owner = state.pathParameters['owner'] ?? '';
          final owner = state.pathParameters["owner"] ?? "";
          final name = state.pathParameters["name"] ?? "";
          return PrListPage(repoFullName: '$owner/$name');
        },
      ),
      GoRoute(
        path: '/repos/:owner/:name/issues',
        name: 'repoIssueList',
        builder: (context, state) {
          // final owner = state.pathParameters['owner'] ?? '';
          final owner = state.pathParameters["owner"] ?? "";
          final name = state.pathParameters["name"] ?? "";
          return IssueListPage(repoFullName: '$owner/$name');
        },
      ),
    ],
  );
});
