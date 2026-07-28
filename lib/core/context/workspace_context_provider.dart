import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/editor/models/editor_models.dart';
import '../../features/editor/providers/editor_provider.dart';
import '../../features/git/models/git_repository.dart';
import '../../features/git/providers/git_provider.dart';
import '../../features/workspace/workspace_provider.dart';
import '../ai/chat_engine.dart';
import 'workspace_context.dart';

// ══════════════════════════════════════════════
// IWorkspaceContextProvider 接口
// ══════════════════════════════════════════════

/// 工作区上下文提供者接口
///
/// 继承 [ContextManager] 以保证与 [ChatEngine] 的兼容性。
///
/// 在 [ContextManager] 的基础上，新增结构化上下文获取方法，
/// 供后续 AI Agent、Diff Apply、Refactor 使用。
abstract class IWorkspaceContextProvider implements ContextManager {
  /// 获取当前文件上下文
  FileContext? getCurrentFileContext();

  /// 获取选中代码上下文
  SelectionContext? getSelectionContext();

  /// 获取工作区结构
  WorkspaceStructure? getWorkspaceStructure();

  /// 获取 Git 上下文
  GitContext? getCurrentGitContext();
}

// ══════════════════════════════════════════════
// Riverpod Provider
// ══════════════════════════════════════════════

/// 工作区上下文 Provider
final Provider<IWorkspaceContextProvider> workspaceContextProvider =
    Provider<IWorkspaceContextProvider>((Ref ref) {
  return WorkspaceContextProvider(ref: ref);
});

// ══════════════════════════════════════════════
// WorkspaceContextProvider 实现
// ══════════════════════════════════════════════

/// 工作区上下文提供者实现
///
/// 通过 Riverpod [Ref] 读取已有 Provider，收集编辑器、工作区、Git 等上下文信息。
/// 不直接访问文件系统，完全通过 Provider 架构获取数据。
class WorkspaceContextProvider implements IWorkspaceContextProvider {
  final Ref _ref;

  /// 自定义上下文片段（通过 addContext 手动添加）
  final Map<String, String> _customContexts = <String, String>{};

  WorkspaceContextProvider({required Ref ref}) : _ref = ref;

  // ══════════════════════════════════════════════
  // ContextManager 接口实现
  // ══════════════════════════════════════════════

  @override
  String? get currentFile {
    final fileCtx = getCurrentFileContext();
    return fileCtx?.content;
  }

  @override
  String? get selection {
    final selCtx = getSelectionContext();
    return selCtx?.selectedText;
  }

  @override
  String? get workspaceContext {
    final ws = getWorkspaceStructure();
    if (ws == null) return null;

    final buf = StringBuffer();
    if (ws.workspacePath != null) {
      buf.writeln('项目路径: ${ws.workspacePath}');
    }
    if (ws.files.isNotEmpty) {
      buf.writeln('文件列表: ${ws.files.length} 个文件');
      for (final f in ws.files) {
        buf.writeln('  - $f');
      }
    }
    if (ws.projectInfo.isNotEmpty) {
      buf.writeln('项目信息:');
      ws.projectInfo.forEach((String k, String v) {
        buf.writeln('  $k: $v');
      });
    }
    return buf.toString();
  }

  @override
  void addContext(String key, String value) {
    _customContexts[key] = value;
  }

  @override
  void removeContext(String key) {
    _customContexts.remove(key);
  }

  @override
  void clearContext() {
    _customContexts.clear();
  }

  @override
  String buildContextPrompt() {
    final buf = StringBuffer();
    buf.writeln('\n## 上下文信息\n');

    // 1. 当前文件
    final fileCtx = getCurrentFileContext();
    if (fileCtx != null) {
      buf.writeln('### 当前文件: ${fileCtx.path}');
      buf.writeln('语言: ${fileCtx.language}');
      buf.writeln('```${fileCtx.language}');
      buf.writeln(_truncateContent(fileCtx.content, maxLines: 80));
      buf.writeln('```');
      buf.writeln();
    }

    // 2. 选中代码
    final selCtx = getSelectionContext();
    if (selCtx != null && selCtx.selectedText.isNotEmpty) {
      buf.writeln('### 选中代码');
      buf.writeln('位置: 第${selCtx.startLine + 1}行-第${selCtx.endLine + 1}行');
      buf.writeln('```');
      buf.writeln(selCtx.selectedText);
      buf.writeln('```');
      buf.writeln();
    }

    // 3. 打开的文件
    final openTabs = _getOpenTabsContext();
    if (openTabs.isNotEmpty) {
      buf.writeln('### 已打开文件');
      for (final tab in openTabs) {
        buf.writeln('- $tab');
      }
      buf.writeln();
    }

    // 4. Git 上下文
    final gitCtx = getCurrentGitContext();
    if (gitCtx != null && !gitCtx.isClean) {
      buf.writeln('### Git 状态');
      buf.writeln('分支: ${gitCtx.branch ?? "未知"}');
      if (gitCtx.ahead > 0 || gitCtx.behind > 0) {
        buf.writeln('同步: ahead ${gitCtx.ahead} / behind ${gitCtx.behind}');
      }
      if (gitCtx.modifiedFiles.isNotEmpty) {
        buf.writeln('变更文件:');
        for (final f in gitCtx.modifiedFiles) {
          buf.writeln('  - $f');
        }
      }
      if (gitCtx.diff != null && gitCtx.diff!.isNotEmpty) {
        buf.writeln('### Git Diff');
        buf.writeln('```diff');
        buf.writeln(_truncateContent(gitCtx.diff!, maxLines: 60));
        buf.writeln('```');
      }
      buf.writeln();
    }

    // 5. 自定义上下文
    if (_customContexts.isNotEmpty) {
      buf.writeln('### 附加上下文');
      for (final entry in _customContexts.entries) {
        buf.writeln('${entry.key}: ${entry.value}');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  // ══════════════════════════════════════════════
  // IWorkspaceContextProvider 结构化接口
  // ══════════════════════════════════════════════

  @override
  FileContext? getCurrentFileContext() {
    final editor = _ref.read(editorProvider);
    final buffer = editor.activeBuffer;
    final tab = editor.activeTab;

    if (tab == null || buffer == null) return null;

    return FileContext(
      path: tab.filePath,
      language: _languageName(buffer.language),
      content: buffer.text,
      lineCount: buffer.lineCount,
    );
  }

  @override
  SelectionContext? getSelectionContext() {
    final editor = _ref.read(editorProvider);
    final buffer = editor.activeBuffer;
    final tab = editor.activeTab;

    if (tab == null || buffer == null) return null;
    if (!buffer.hasSelection || buffer.selectedText.isEmpty) return null;

    final start = buffer.selectionStart;
    final end = buffer.selectionEnd;

    return SelectionContext(
      filePath: tab.filePath,
      startLine: start.line,
      startColumn: start.column,
      endLine: end.line,
      endColumn: end.column,
      selectedText: buffer.selectedText,
    );
  }

  @override
  WorkspaceStructure? getWorkspaceStructure() {
    final ws = _ref.read(workspaceProvider).currentWorkspace;
    if (ws == null) return null;

    // 获取工作区路径（取第一个项目的路径作为根路径）
    String? rootPath;
    if (ws.projects.isNotEmpty) {
      rootPath = ws.projects.first.path;
    }

    // 收集项目信息
    final info = <String, String>{};
    info['name'] = ws.name;
    info['template'] = ws.template.name;
    info['projects'] = ws.projects.length.toString();
    for (final p in ws.projects) {
      info['project_${p.name}'] = p.path;
    }

    return WorkspaceStructure(
      workspacePath: rootPath,
      files: const [],
      projectInfo: info,
    );
  }

  @override
  GitContext? getCurrentGitContext() {
    final ws = _ref.read(workspaceProvider).currentWorkspace;
    if (ws?.projects.isEmpty ?? true) return null;


    try {
      // 同步获取 git 状态（非阻塞读取已缓存状态）
      final GitStatus? _ = null; // 占位，异步版本在 getCurrentGitContextAsync
      return GitContext(
        isClean: true,
        modifiedFiles: const [],
      );
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════
  // 内部辅助方法
  // ══════════════════════════════════════════════

  /// 异步获取 Git 上下文（由 ChatEngine 调用）
  Future<GitContext> getCurrentGitContextAsync() async {
    final ws = _ref.read(workspaceProvider).currentWorkspace;
    if (ws?.projects.isEmpty ?? true) {
      return const GitContext();
    }

    final gitService = _ref.read(gitServiceProvider);
    final path = ws!.projects.first.path;

    try {
      final status = await gitService.status(path);
      final diff = await gitService.diff(path);

      return GitContext(
        branch: status.currentBranch,
        modifiedFiles: status.changes.map((GitFileChange c) => c.path).toList(),
        diff: diff,
        isClean: status.isClean,
        ahead: status.ahead,
        behind: status.behind,
      );
    } catch (_) {
      return const GitContext();
    }
  }

  /// 获取已打开文件列表
  List<String> _getOpenTabsContext() {
    final editor = _ref.read(editorProvider);
    return editor.tabs.map((EditorTab t) => t.filePath).toList();
  }

  /// 截断内容
  String _truncateContent(String content, {int maxLines = 80}) {
    final lines = content.split('\n');
    if (lines.length <= maxLines) return content;

    final headLines = maxLines ~/ 2;
    final tailLines = maxLines ~/ 2;

    final head = lines.take(headLines).join('\n');
    final tail = lines.skip(lines.length - tailLines).join('\n');

    return '$head\n\n// ... 中间 ${lines.length - maxLines} 行已省略 ...\n\n$tail';
  }

  /// 文件语言枚举转字符串
  String _languageName(FileLanguage lang) {
    switch (lang) {
      case FileLanguage.dart:
        return 'dart';
      case FileLanguage.rust:
        return 'rust';
      case FileLanguage.python:
        return 'python';
      case FileLanguage.json:
        return 'json';
      case FileLanguage.yaml:
        return 'yaml';
      case FileLanguage.markdown:
        return 'markdown';
      case FileLanguage.toml:
        return 'toml';
      case FileLanguage.shell:
        return 'bash';
      case FileLanguage.typescript:
        return 'typescript';
      case FileLanguage.javascript:
        return 'javascript';
      case FileLanguage.html:
        return 'html';
      case FileLanguage.css:
        return 'css';
      case FileLanguage.java:
        return 'java';
      case FileLanguage.cpp:
        return 'cpp';
      case FileLanguage.unknown:
        return 'text';
    }
  }
}
