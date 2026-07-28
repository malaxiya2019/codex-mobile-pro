// ══════════════════════════════════════════════
// Workspace Context — 数据模型
// ══════════════════════════════════════════════

/// 文件上下文
///
/// 当前编辑文件的完整上下文。
class FileContext {
  /// 文件路径
  final String path;

  /// 文件语言（如 dart, rust, python, json 等）
  final String language;

  /// 文件内容
  final String content;

  /// 总行数
  final int lineCount;

  const FileContext({
    required this.path,
    required this.language,
    required this.content,
    this.lineCount = 0,
  });
}

/// 选中代码上下文
///
/// 当前编辑器中的选中内容。
class SelectionContext {
  /// 文件路径
  final String filePath;

  /// 选中起始行
  final int startLine;

  /// 选中起始列
  final int startColumn;

  /// 选中结束行
  final int endLine;

  /// 选中结束列
  final int endColumn;

  /// 选中的文本内容
  final String selectedText;

  const SelectionContext({
    required this.filePath,
    this.startLine = 0,
    this.startColumn = 0,
    this.endLine = 0,
    this.endColumn = 0,
    required this.selectedText,
  });
}

/// 工作区结构
///
/// 项目级别的上下文信息。
class WorkspaceStructure {
  /// 工作区根路径
  final String? workspacePath;

  /// 文件列表（相对路径）
  final List<String> files;

  /// 项目信息（如 pubspec.yaml 内容概览）
  final Map<String, String> projectInfo;

  const WorkspaceStructure({
    this.workspacePath,
    this.files = const [],
    this.projectInfo = const {},
  });
}

/// Git 上下文
///
/// 当前仓库的 Git 状态信息。
class GitContext {
  /// 当前分支名
  final String? branch;

  /// 已修改文件列表
  final List<String> modifiedFiles;

  /// Git Diff 内容（未暂存变更）
  final String? diff;

  /// 是否干净工作区
  final bool isClean;

  /// ahead/behind 数量
  final int ahead;
  final int behind;

  const GitContext({
    this.branch,
    this.modifiedFiles = const [],
    this.diff,
    this.isClean = true,
    this.ahead = 0,
    this.behind = 0,
  });
}
