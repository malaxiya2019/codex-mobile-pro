import 'app_locale.dart';

/// 应用字符串资源
///
/// 所有用户可见文本集中管理，禁止硬编码。
///
/// 使用方式：
/// ```dart
/// Strings.of(context).appName
/// // 或直接通过 Provider：
/// Strings.get(ref.watch(localeProvider))
/// ```
class Strings {
  final AppLanguage lang;

  const Strings(this.lang);

  /// 获取当前语言的字符串
  static Strings of(BuildContext context) {
    // 从 Provider 读取
    // 实际使用时应通过 ref.watch(localeProvider) 获取语言
    return Strings(AppLanguage.zhCN);
  }

  /// 根据语言获取字符串
  static Strings get(AppLanguage lang) => Strings(lang);

  // ══════════════════════════════════════
  //  通用
  // ══════════════════════════════════════

  String get appName => _t('Codex Mobile Pro', 'Codex Mobile Pro');

  String get ok => _t('确定', 'OK');
  String get cancel => _t('取消', 'Cancel');
  String get confirm => _t('确认', 'Confirm');
  String get retry => _t('重试', 'Retry');
  String get back => _t('返回', 'Back');
  String get save => _t('保存', 'Save');
  String get delete => _t('删除', 'Delete');
  String get search => _t('搜索', 'Search');
  String get loading => _t('加载中...', 'Loading...');
  String get error => _t('错误', 'Error');
  String get warning => _t('警告', 'Warning');
  String get success => _t('成功', 'Success');
  String get done => _t('完成', 'Done');
  String get close => _t('关闭', 'Close');
  String get settings => _t('设置', 'Settings');
  String get about => _t('关于', 'About');

  // ══════════════════════════════════════
  //  首页
  // ══════════════════════════════════════

  String get homeTitle => _t('Codex Mobile Pro', 'Codex Mobile Pro');
  String get systemStatus => _t('系统状态', 'System Status');
  String get envInfo => _t('环境信息', 'Environment Info');

  // ══════════════════════════════════════
  //  导航
  // ══════════════════════════════════════

  String get navHome => _t('首页', 'Home');
  String get navDeploy => _t('部署', 'Deploy');
  String get navTermux => _t('Termux', 'Termux');
  String get navAi => _t('AI', 'AI');

  // ══════════════════════════════════════
  //  AI 对话
  // ══════════════════════════════════════

  String get aiChatTitle => _t('AI 对话', 'AI Chat');
  String get aiInputHint => _t('输入问题...', 'Ask a question...');
  String get aiClearConfirm => _t('确定要清空当前对话吗？', 'Clear current conversation?');
  String get aiClearTitle => _t('清空对话', 'Clear Chat');
  String get aiEmptyTitle => _t('AI 编程助手', 'AI Coding Assistant');
  String get aiEmptyDesc => _t(
    '输入问题开始对话\n支持代码生成、解释、调试',
    'Start a conversation\nCode generation, explanation, debugging',
  );
  String get aiProxyNotRunning =>
      _t('mimo2codex 代理未运行', 'mimo2codex proxy is not running');
  String get aiServiceReady => _t('AI 服务就绪', 'AI Service Ready');
  String get aiServiceConnecting => _t('正在连接...', 'Connecting...');
  String get aiServiceError => _t('服务异常', 'Service Error');

  // ══════════════════════════════════════
  //  主题设置
  // ══════════════════════════════════════

  String get themeSettingsTitle => _t('主题设置', 'Theme Settings');
  String get themeMode => _t('主题模式', 'Theme Mode');
  String get themeLight => _t('浅色模式', 'Light Mode');
  String get themeDark => _t('深色模式', 'Dark Mode');
  String get themeSystem => _t('跟随系统', 'System');
  String get fontSettings => _t('字体设置', 'Font Settings');
  String get fontFamily => _t('字体', 'Font');
  String get fontSize => _t('字体大小', 'Font Size');
  String get fontPreview => _t('预览文本', 'Preview');

  // ══════════════════════════════════════
  //  Termux 测试页
  // ══════════════════════════════════════

  String get termuxTestTitle => _t('Termux 通信验证', 'Termux Comm Test');
  String get termuxEnvCheck => _t('环境检查', 'Environment Check');
  String get termuxCmdTest => _t('命令测试', 'Command Test');
  String get termuxBatchTest => _t('批量测试', 'Batch Test');

  // ══════════════════════════════════════
  //  部署中心
  // ══════════════════════════════════════

  String get deployTitle => _t('部署中心', 'Deploy Center');
  String get deployDetect => _t('检测环境', 'Detect Env');
  String get deployInstall => _t('一键安装', 'Quick Install');
  String get deployStatus => _t('部署状态', 'Deploy Status');

  // ══════════════════════════════════════
  //  错误页面
  // ══════════════════════════════════════

  String get errorAppTitle => _t('应用出现错误', 'App Error');
  String get errorOpTitle => _t('操作遇到问题', 'Something Went Wrong');
  String get errorFatalMsg => _t(
    '应用遇到意外错误，请尝试重新启动。如果问题持续，请联系支持。',
    'An unexpected error occurred. Please restart the app. Contact support if the issue persists.',
  );
  String get errorRetryMsg =>
      _t('请稍后重试，或返回上一页。', 'Please try again later or go back.');
  String get errorDebugInfo => _t('调试信息', 'Debug Info');
  String get errorCopy => _t('复制错误信息', 'Copy Error Info');

  // ══════════════════════════════════════
  //  工作区
  // ══════════════════════════════════════

  String get workspaceListTitle => _t('工作区管理', 'Workspaces');
  String get workspaceCreateTitle => _t('新建工作区', 'New Workspace');
  String get workspaceNameHint => _t('工作区名称', 'Workspace Name');
  String get workspaceTemplateLabel => _t('选择模板', 'Choose Template');
  String get workspaceEmpty => _t('还没有工作区', 'No Workspaces Yet');
  String get workspaceEmptyDesc =>
      _t('创建工作区来管理项目', 'Create a workspace to manage your projects');
  String get workspaceCurrent => _t('当前', 'Current');
  String get workspaceSelect => _t('切换到此工作区', 'Select');
  String get workspaceSwitch => _t('切换工作区', 'Switch');
  String get workspaceDeleteConfirm => _t('确定要删除工作区', 'Delete workspace');
  String get workspaceCreated => _t('工作区已创建', 'Workspace Created');
  String get workspaceProjects => _t('个项目', ' projects');
  String get workspaceInfo => _t('当前工作区', 'Current Workspace');
  String get workspaceQuickNew => _t('新建项目', 'New Project');
  String get workspaceQuickOpen => _t('打开项目', 'Open Project');
  String get workspaceQuickAi => _t('AI 编程', 'AI Code');
  String get workspaceQuickTerminal => _t('终端', 'Terminal');

  // ══════════════════════════════════════
  //  文件浏览
  // ══════════════════════════════════════

  String get fileBrowserTitle => _t('文件浏览器', 'File Browser');
  String get fileBrowserEmpty => _t('此目录为空', 'This directory is empty');
  String get fileBrowserError => _t('无法读取目录', 'Cannot read directory');
  String get fileSearchNoResults => _t('未找到匹配的文件', 'No matching files');
  String get fileSizeBytes => _t('B', ' B');
  String get fileSizeKB => _t('KB', ' KB');
  String get fileSizeMB => _t('MB', ' MB');
  String get fileLoading => _t('加载中...', 'Loading...');
  String get fileTooLarge =>
      _t('文件过大，仅显示预览', 'File too large, showing preview');

  // ══════════════════════════════════════
  //  项目创建
  // ══════════════════════════════════════

  String get projectCreateTitle => _t('创建项目', 'Create Project');
  String get projectNameHint => _t('项目名称', 'Project Name');
  String get projectTemplateLabel => _t('选择模板', 'Select Template');
  String get projectCreating => _t('正在创建...', 'Creating...');
  String get projectCreated => _t('项目创建成功', 'Project Created');
  String get projectFailed => _t('项目创建失败', 'Project Creation Failed');
  String get projectSelectPath => _t('选择路径', 'Select Path');
  String get projectPathHint => _t('项目存放路径', 'Project Path');
  String get projectTemplateFlutter => _t('Flutter', 'Flutter');
  String get projectTemplateRust => _t('Rust', 'Rust');
  String get projectTemplatePython => _t('Python', 'Python');

  // ══════════════════════════════════════
  //  终端
  // ══════════════════════════════════════

  String get terminalTitle => _t('终端', 'Terminal');
  String get terminalNew => _t('新建终端', 'New Terminal');
  String get terminalClose => _t('关闭终端', 'Close Terminal');
  String get terminalClear => _t('清除所有', 'Clear All');
  String get terminalInputHint => _t('输入命令...', 'Type a command...');
  String get terminalNoSession => _t('点击 + 新建终端', 'Tap + to create a terminal');
  String get terminalExit => _t('进程退出', 'Process exited');
  String get terminalCwd => _t('当前目录', 'Current directory');

  // ══════════════════════════════════════
  //  快捷命令
  // ══════════════════════════════════════

  String get quickCommands => _t('快捷命令', 'Quick Commands');
  String get quickCommandsFavorites => _t('收藏', 'Favorites');
  String get quickCommandsAll => _t('全部', 'All');
  String get quickCommandsExecute => _t('执行', 'Execute');
  String get quickCommandsEmpty => _t('暂无命令', 'No commands');

  // ── 内部辅助 ──

  String _t(String zh, String en) {
    switch (lang) {
      case AppLanguage.zhCN:
        return zh;
      case AppLanguage.enUS:
        return en;
    }
  }
}
