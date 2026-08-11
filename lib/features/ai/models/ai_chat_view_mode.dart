/// AI 对话界面模式。
///
/// 两种 UI 共享同一套数据（ChatEngine / ChatNotifier / AI Stream /
/// ChatMessage / Tool Event / CodexRunner），切换模式只是换渲染层，
/// 绝不重新请求 AI、不重复执行命令、不创建第二个 Codex 进程。
enum AiChatViewMode {
  /// 聊天气泡模式（默认）：用户右侧气泡、AI 左侧气泡。
  bubble,

  /// 流式终端模式：Codex CLI 风格日志（Ran / Read / Working / 增量输出）。
  stream;

  static AiChatViewMode fromName(String? name) {
    return AiChatViewMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => AiChatViewMode.bubble,
    );
  }
}
