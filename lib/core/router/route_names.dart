/// 路由名称常量
abstract class RouteNames {
  static const home = '/';
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

  // ── 编辑器 ──
  static const editor = '/editor';
  static const editorFile = '/editor/:path';

  // ── 文件浏览 ──
  static const fileBrowser = '/files';

  // ── Git ──
  static const gitHubLogin = '/github-login';
  static const repoList = '/repos';
  static const repoDetail = '/repos/:owner/:name';
  static const repoPrList = '/repos/:owner/:name/prs';
  static const repoPrDetail = '/repos/:owner/:name/prs/:number';
  static const repoIssueList = '/repos/:owner/:name/issues';
  static const repoIssueDetail = '/repos/:owner/:name/issues/:number';
}
