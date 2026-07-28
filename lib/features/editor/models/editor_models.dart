import 'dart:io';

/// 编辑器 Tab 模型
class EditorTab {
  final String id;
  final String filePath;
  final String fileName;
  bool isDirty;
  bool isPinned;
  DateTime lastOpened;

  EditorTab({
    required this.id,
    required this.filePath,
    this.isDirty = false,
    this.isPinned = false,
    DateTime? lastOpened,
  }) : fileName = filePath.split('/').last,
       lastOpened = lastOpened ?? DateTime.now();
}

/// 编辑器光标位置
class CursorPosition {
  final int line;
  final int column;

  const CursorPosition({this.line = 0, this.column = 0});

  CursorPosition copyWith({int? line, int? column}) {
    return CursorPosition(
      line: line ?? this.line,
      column: column ?? this.column,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CursorPosition && line == other.line && column == other.column;

  @override
  int get hashCode => line.hashCode ^ column.hashCode;
}

/// 文本范围
class TextRange {
  final int start;
  final int end;

  const TextRange({required this.start, required this.end});
  int get length => end - start;
  bool get isEmpty => start == end;
}

/// 选择范围
class SelectionRange {
  final CursorPosition start;
  final CursorPosition end;

  const SelectionRange({required this.start, required this.end});

  CursorPosition get normalizedStart {
    if (start.line < end.line ||
        (start.line == end.line && start.column <= end.column)) {
      return start;
    }
    return end;
  }

  CursorPosition get normalizedEnd {
    if (start.line < end.line ||
        (start.line == end.line && start.column <= end.column)) {
      return end;
    }
    return start;
  }
}

/// 编辑操作（用于撤销/重做）
class EditAction {
  final String type; // 'insert' | 'delete' | 'replace'
  final int line;
  final int column;
  final String text;
  final String? oldText;

  const EditAction({
    required this.type,
    required this.line,
    required this.column,
    required this.text,
    this.oldText,
  });
}

/// 查找/替换状态
class FindReplaceState {
  String query;
  String replaceText;
  bool caseSensitive;
  bool useRegex;
  int currentMatch;
  int totalMatches;
  List<SearchMatch> matches;

  FindReplaceState({
    this.query = '',
    this.replaceText = '',
    this.caseSensitive = false,
    this.useRegex = false,
    this.currentMatch = 0,
    this.totalMatches = 0,
    this.matches = const [],
  });
}

/// 搜索结果
class SearchMatch {
  final int line;
  final int column;
  final int length;

  const SearchMatch({
    required this.line,
    required this.column,
    required this.length,
  });
}

/// 编辑器设置
class EditorSettings {
  int fontSize;
  String fontFamily;
  bool showLineNumbers;
  bool highlightCurrentLine;
  bool autoIndent;
  bool bracketMatching;
  bool wordWrap;
  int tabSize;
  bool insertSpaces;
  int autoSaveDelayMs;

  EditorSettings({
    this.fontSize = 14,
    this.fontFamily = 'monospace',
    this.showLineNumbers = true,
    this.highlightCurrentLine = true,
    this.autoIndent = true,
    this.bracketMatching = true,
    this.wordWrap = false,
    this.tabSize = 2,
    this.insertSpaces = true,
    this.autoSaveDelayMs = 3000,
  });
}

/// 文件语言类型
enum FileLanguage {
  dart, rust, python, json, yaml, markdown, toml, shell,
  typescript, javascript, html, css, java, cpp, unknown;

  static FileLanguage fromFileName(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return FileLanguage.dart;
      case 'rs': return FileLanguage.rust;
      case 'py': return FileLanguage.python;
      case 'json': return FileLanguage.json;
      case 'yaml': case 'yml': return FileLanguage.yaml;
      case 'md': case 'markdown': return FileLanguage.markdown;
      case 'toml': return FileLanguage.toml;
      case 'sh': case 'bash': case 'zsh': case 'fish': return FileLanguage.shell;
      case 'ts': case 'tsx': return FileLanguage.typescript;
      case 'js': case 'jsx': case 'mjs': return FileLanguage.javascript;
      case 'html': case 'htm': return FileLanguage.html;
      case 'css': case 'scss': case 'less': return FileLanguage.css;
      case 'java': return FileLanguage.java;
      case 'c': case 'cpp': case 'h': case 'hpp': case 'cc': return FileLanguage.cpp;
      default: return FileLanguage.unknown;
    }
  }
}

/// 行数据
class LineData {
  final int lineNumber;
  final String text;
  final bool isModified;
  final bool isSelected;

  const LineData({
    required this.lineNumber,
    required this.text,
    this.isModified = false,
    this.isSelected = false,
  });
}
