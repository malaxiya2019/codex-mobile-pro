/// 路由名称常量
abstract class RouteNames {
  static const home = '/';
  static const termuxTest = '/termux-test';
  static const deploy = '/deploy';
  static const aiChat = '/ai-chat';
  static const themeSettings = '/theme-settings';
  static const localeSettings = '/locale-settings';
  static const appSettings = '/settings';

  // ── 工作区 ──
  static const workspaceList = '/workspaces';
  static const workspaceCreate = '/workspaces/create';
  static const workspaceDetail = '/workspaces/:id';

  // ── 终端 ──
  static const terminal = '/terminal';

  // ── Git ──
  static const gitHubLogin = '/github-login';
  static const repoList = '/repos';
  static const repoDetail = '/repos/:owner/:name';
}
