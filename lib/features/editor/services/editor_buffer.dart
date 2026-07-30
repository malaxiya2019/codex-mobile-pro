import 'dart:io';
import '../models/editor_models.dart';
import '../syntax/syntax_highlighter.dart';
import '../syntax/syntax_registry.dart';

/// 编辑器缓冲区
///
/// 管理单个文件的文本内容、撤销/重做历史、查找/替换。
class EditorBuffer {
  final String filePath;
  List<String> _lines;
  final List<EditAction> _undoStack = [];
  final List<EditAction> _redoStack = [];
  static const int _maxUndoStack = 500;
  CursorPosition _cursor;
  CursorPosition _selectionStart;
  bool _hasSelection;
  bool _isDirty;
  final EditorSettings _settings;
  SyntaxHighlighter? _highlighter;

  EditorBuffer({
    required this.filePath,
    List<String>? initialContent,
    EditorSettings? settings,
  }) : _lines = initialContent ?? [''],
       _cursor = const CursorPosition(),
       _selectionStart = const CursorPosition(),
       _hasSelection = false,
       _isDirty = false,
       _settings = settings ?? EditorSettings() {
    _initHighlighter();
  }

  // ── 属性 ──

  List<String> get lines => List.unmodifiable(_lines);
  int get lineCount => _lines.length;
  CursorPosition get cursor => _cursor;
  bool get hasSelection => _hasSelection;
  bool get isDirty => _isDirty;
  EditorSettings get settings => _settings;
  SyntaxHighlighter? get highlighter => _highlighter;

  String get text => _lines.join('\n');

  String get currentLine =>
      _cursor.line < _lines.length ? _lines[_cursor.line] : '';

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// 文件语言
  FileLanguage get language => FileLanguage.fromFileName(filePath);

  void _initHighlighter() {
    _highlighter = SyntaxRegistry.forFileName(filePath);
  }

  // ── 光标操作 ──

  void moveCursor(CursorPosition pos) {
    final line = pos.line.clamp(0, _lines.length - 1);
    final col = pos.column.clamp(0, _lines[line].length);
    _cursor = CursorPosition(line: line, column: col);
    _hasSelection = false;
  }

  void moveCursorUp() {
    if (_cursor.line > 0) {
      final newLine = _cursor.line - 1;
      final col = _cursor.column.clamp(0, _lines[newLine].length);
      _cursor = CursorPosition(line: newLine, column: col);
    }
  }

  void moveCursorDown() {
    if (_cursor.line < _lines.length - 1) {
      final newLine = _cursor.line + 1;
      final col = _cursor.column.clamp(0, _lines[newLine].length);
      _cursor = CursorPosition(line: newLine, column: col);
    }
  }

  void moveCursorLeft() {
    if (_cursor.column > 0) {
      _cursor = CursorPosition(line: _cursor.line, column: _cursor.column - 1);
    } else if (_cursor.line > 0) {
      final newLine = _cursor.line - 1;
      _cursor = CursorPosition(line: newLine, column: _lines[newLine].length);
    }
  }

  void moveCursorRight() {
    final lineLen = _lines[_cursor.line].length;
    if (_cursor.column < lineLen) {
      _cursor = CursorPosition(line: _cursor.line, column: _cursor.column + 1);
    } else if (_cursor.line < _lines.length - 1) {
      _cursor = CursorPosition(line: _cursor.line + 1);
    }
  }

  void moveToLineStart() {
    _cursor = CursorPosition(line: _cursor.line);
  }

  void moveToLineEnd() {
    _cursor = CursorPosition(
      line: _cursor.line,
      column: _lines[_cursor.line].length,
    );
  }

  void moveToFileStart() {
    _cursor = const CursorPosition();
  }

  void moveToFileEnd() {
    _cursor = CursorPosition(
      line: _lines.length - 1,
      column: _lines.last.length,
    );
  }

  // ── 文本编辑 ──

  void insertChar(String ch) {
    if (ch.isEmpty) return;

    final line = _cursor.line;
    final col = _cursor.column;

    // 删除选中文本
    if (_hasSelection) {
      _deleteSelection();
    }

    final oldText = _lines[line];
    final newText = oldText.substring(0, col) + ch + oldText.substring(col);
    _lines[line] = newText;
    _cursor = CursorPosition(line: line, column: col + ch.length);

    _pushUndo(EditAction(
      type: 'insert',
      line: line,
      column: col,
      text: ch,
    ));
    _redoStack.clear();
    _isDirty = true;

    // 自动缩进
    if (ch == '\n') {
      _autoIndent();
    }

    // 括号匹配
    if (_settings.bracketMatching && _isOpeningBracket(ch)) {
      _insertClosingBracket(ch);
    }
  }

  void insertText(String text) {
    if (text.isEmpty) return;

    if (_hasSelection) {
      _deleteSelection();
    }

    final line = _cursor.line;
    final col = _cursor.column;
    final oldText = _lines[line];
    final newText = oldText.substring(0, col) + text + oldText.substring(col);
    _lines[line] = newText;
    _cursor = CursorPosition(line: line, column: col + text.length);

    _pushUndo(EditAction(
      type: 'insert',
      line: line,
      column: col,
      text: text,
    ));
    _redoStack.clear();
    _isDirty = true;
  }

  void insertNewline() {
    final line = _cursor.line;
    final col = _cursor.column;
    final oldText = _lines[line];

    final firstPart = oldText.substring(0, col);
    final secondPart = oldText.substring(col);

    // 计算缩进
    String indent = '';
    final indentMatch = RegExp(r'^(\s*)').firstMatch(firstPart);
    if (indentMatch != null) {
      indent = indentMatch.group(1) ?? '';
      // 如果上一行以 { 结尾，增加缩进
      if (firstPart.trimRight().endsWith('{') ||
          firstPart.trimRight().endsWith('(') ||
          firstPart.trimRight().endsWith('[')) {
        indent += _settings.insertSpaces
            ? ' ' * _settings.tabSize
            : '\t';
      }
    }

    _lines[line] = firstPart;
    _lines.insert(line + 1, indent + secondPart);
    _cursor = CursorPosition(line: line + 1, column: indent.length);

    _pushUndo(EditAction(
      type: 'insert',
      line: line,
      column: col,
      text: '\n$indent',
    ));
    _redoStack.clear();
    _isDirty = true;
  }

  void deleteLeft() {
    if (_hasSelection) {
      _deleteSelection();
      return;
    }

    final line = _cursor.line;
    final col = _cursor.column;

    if (col > 0) {
      final oldText = _lines[line];
      final deleted = oldText[col - 1];
      _lines[line] = oldText.substring(0, col - 1) + oldText.substring(col);
      _cursor = CursorPosition(line: line, column: col - 1);

      _pushUndo(EditAction(
        type: 'delete',
        line: line,
        column: col - 1,
        text: '',
        oldText: deleted,
      ));
    } else if (line > 0) {
      final prevLine = _lines[line - 1];
      const deleted = '\n';
      _lines[line - 1] = prevLine + _lines[line];
      _lines.removeAt(line);
      _cursor = CursorPosition(line: line - 1, column: prevLine.length);

      _pushUndo(EditAction(
        type: 'delete',
        line: line - 1,
        column: prevLine.length,
        text: '',
        oldText: deleted,
      ));
    }

    _redoStack.clear();
    _isDirty = true;
  }

  void deleteRight() {
    if (_hasSelection) {
      _deleteSelection();
      return;
    }

    final line = _cursor.line;
    final col = _cursor.column;

    if (col < _lines[line].length) {
      final oldText = _lines[line];
      final deleted = oldText[col];
      _lines[line] = oldText.substring(0, col) + oldText.substring(col + 1);

      _pushUndo(EditAction(
        type: 'delete',
        line: line,
        column: col,
        text: '',
        oldText: deleted,
      ));
    } else if (line < _lines.length - 1) {
      const deleted = '\n';
      _lines[line] = _lines[line] + _lines[line + 1];
      _lines.removeAt(line + 1);

      _pushUndo(EditAction(
        type: 'delete',
        line: line,
        column: col,
        text: '',
        oldText: deleted,
      ));
    }

    _redoStack.clear();
    _isDirty = true;
  }

  /// 插入 Tab
  void insertTab() {
    if (_settings.insertSpaces) {
      insertText(' ' * _settings.tabSize);
    } else {
      insertText('\t');
    }
  }

  // ── 撤销/重做 ──

  void undo() {
    if (_undoStack.isEmpty) return;

    final action = _undoStack.removeLast();
    _redoStack.add(action);

    if (action.type == 'insert') {
      _undoInsert(action);
    } else if (action.type == 'delete') {
      _undoDelete(action);
    }

    _isDirty = _undoStack.isNotEmpty;
  }

  void redo() {
    if (_redoStack.isEmpty) return;

    final action = _redoStack.removeLast();
    _undoStack.add(action);

    if (action.type == 'insert') {
      _redoInsert(action);
    } else if (action.type == 'delete') {
      _redoDelete(action);
    }

    _isDirty = true;
  }

  void _pushUndo(EditAction action) {
    _undoStack.add(action);
    if (_undoStack.length > _maxUndoStack) {
      _undoStack.removeAt(0);
    }
  }

  void _undoInsert(EditAction action) {
    final line = _lines[action.line];
    final len = action.text.length;
    final newText = line.substring(0, action.column) + line.substring(action.column + len);
    _lines[action.line] = newText;
    _cursor = CursorPosition(line: action.line, column: action.column);
  }

  void _undoDelete(EditAction action) {
    final line = _lines[action.line];
    final newText = line.substring(0, action.column) +
        (action.oldText ?? '') +
        line.substring(action.column);
    _lines[action.line] = newText;
    _cursor = CursorPosition(line: action.line, column: action.column + (action.oldText?.length ?? 0));
  }

  void _redoInsert(EditAction action) {
    final line = _lines[action.line];
    final newText = line.substring(0, action.column) +
        action.text +
        line.substring(action.column);
    _lines[action.line] = newText;
    _cursor = CursorPosition(line: action.line, column: action.column + action.text.length);
  }

  void _redoDelete(EditAction action) {
    final line = _lines[action.line];
    final len = action.oldText?.length ?? 0;
    final newText = line.substring(0, action.column) + line.substring(action.column + len);
    _lines[action.line] = newText;
    _cursor = CursorPosition(line: action.line, column: action.column);
  }

  // ── 选择 ──

  void selectAll() {
    _selectionStart = const CursorPosition();
    _cursor = CursorPosition(
      line: _lines.length - 1,
      column: _lines.last.length,
    );
    _hasSelection = true;
  }

  void clearSelection() {
    _hasSelection = false;
  }

  CursorPosition get selectionStart => _selectionStart;
  CursorPosition get selectionEnd => _cursor;

  String get selectedText {
    if (!_hasSelection) return '';
    final start = _selectionStart;
    final end = _cursor;

    if (start.line == end.line) {
      return _lines[start.line].substring(
        start.column < end.column ? start.column : end.column,
        start.column < end.column ? end.column : start.column,
      );
    }

    final firstLine = start.line < end.line ? start : end;
    final lastLine = start.line < end.line ? end : start;

    final parts = <String>[];
    parts.add(_lines[firstLine.line].substring(firstLine.column));
    for (int i = firstLine.line + 1; i < lastLine.line; i++) {
      parts.add(_lines[i]);
    }
    parts.add(_lines[lastLine.line].substring(0, lastLine.column));
    return parts.join('\n');
  }

  void _deleteSelection() {
    if (!_hasSelection) return;
    final text = selectedText;
    final start = _selectionStart;
    final end = _cursor;

    if (start.line == end.line) {
      final minCol = start.column < end.column ? start.column : end.column;
      final maxCol = start.column < end.column ? end.column : start.column;
      _lines[start.line] = _lines[start.line].substring(0, minCol) +
          _lines[start.line].substring(maxCol);
      _cursor = CursorPosition(line: start.line, column: minCol);
    } else {
      final firstLine = start.line < end.line ? start : end;
      final lastLine = start.line < end.line ? end : start;

      _lines[firstLine.line] = _lines[firstLine.line].substring(0, firstLine.column) +
          _lines[lastLine.line].substring(lastLine.column);
      _lines.removeRange(firstLine.line + 1, lastLine.line + 1);
      _cursor = CursorPosition(line: firstLine.line, column: firstLine.column);
    }

    _hasSelection = false;
    _pushUndo(EditAction(type: 'delete', line: -1, column: -1, text: '', oldText: text));
  }

  // ── 自动缩进 ──

  void _autoIndent() {
    if (!_settings.autoIndent) return;

    final line = _cursor.line;
    if (line > 0) {
      final prevLine = _lines[line - 1];
      final indentMatch = RegExp(r'^(\s*)').firstMatch(prevLine);
      if (indentMatch != null) {
        final prevIndent = indentMatch.group(1) ?? '';

        // 检查是否需要额外缩进
        String extraIndent = '';
        if (prevLine.trimRight().endsWith('{') ||
            prevLine.trimRight().endsWith('(') ||
            prevLine.trimRight().endsWith('[') ||
            prevLine.trimRight().endsWith(':')) {
          extraIndent = _settings.insertSpaces
              ? ' ' * _settings.tabSize
              : '\t';
        }

        final totalIndent = prevIndent + extraIndent;
        _lines[line] = totalIndent + _lines[line].trimLeft();
        _cursor = CursorPosition(line: line, column: totalIndent.length);
      }
    }
  }

  // ── 括号匹配 ──

  bool _isOpeningBracket(String ch) {
    return ch == '{' || ch == '(' || ch == '[' || ch == '"' || ch == "'";
  }

  String _getClosingBracket(String open) {
    switch (open) {
      case '{': return '}';
      case '(': return ')';
      case '[': return ']';
      case '"': return '"';
      case "'": return "'";
      default: return '';
    }
  }

  void _insertClosingBracket(String open) {
    final close = _getClosingBracket(open);
    if (close.isEmpty) return;

    final line = _cursor.line;
    final col = _cursor.column;
    final oldText = _lines[line];
    _lines[line] = oldText.substring(0, col) + close + oldText.substring(col);
  }

  /// 查找匹配的括号位置
  CursorPosition? findMatchingBracket(CursorPosition pos) {
    final line = _lines[pos.line];
    if (pos.column >= line.length) return null;

    final ch = line[pos.column];
    String open, close;
    int direction;

    if (ch == '{' || ch == '(' || ch == '[') {
      open = ch;
      close = _getClosingBracket(ch);
      direction = 1;
    } else if (ch == '}' || ch == ')' || ch == ']') {
      open = _getClosingBracket(ch);
      close = ch;
      direction = -1;
    } else {
      return null;
    }

    int depth = 1;
    int l = pos.line;
    int c = pos.column + direction;

    while (l >= 0 && l < _lines.length) {
      final currentLine = _lines[l];
      while (c >= 0 && c < currentLine.length) {
        if (currentLine[c] == open) depth++;
        if (currentLine[c] == close) depth--;
        if (depth == 0) return CursorPosition(line: l, column: c);
        c += direction;
      }
      l += direction;
      c = direction > 0 ? 0 : (_lines[l].length - 1);
    }

    return null;
  }

  // ── 查找/替换 ──

  List<SearchMatch> findAll(String query, {bool caseSensitive = false}) {
    if (query.isEmpty) return [];

    final matches = <SearchMatch>[];
    for (int i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      String searchText = line;
      String searchQuery = query;
      if (!caseSensitive) {
        searchText = searchText.toLowerCase();
        searchQuery = searchQuery.toLowerCase();
      }

      int idx = 0;
      while (true) {
        final found = searchText.indexOf(searchQuery, idx);
        if (found == -1) break;
        matches.add(SearchMatch(line: i, column: found, length: query.length));
        idx = found + 1;
      }
    }
    return matches;
  }

  int replaceAll(String query, String replacement, {bool caseSensitive = false}) {
    if (query.isEmpty) return 0;

    int count = 0;
    for (int i = 0; i < _lines.length; i++) {
      final String line = _lines[i];
      final String searchText = caseSensitive ? line : line.toLowerCase();
      final String searchQuery = caseSensitive ? query : query.toLowerCase();

      if (searchText.contains(searchQuery)) {
        final newLine = line.replaceAll(searchQuery, replacement);
        if (newLine != line) {
          _lines[i] = newLine;
          count++;
        }
      }
    }
    if (count > 0) _isDirty = true;
    return count;
  }

  // ── 文件 I/O ──

  Future<bool> load() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      final content = await file.readAsString();
      _lines = content.isEmpty ? [''] : content.split('\n');
      _cursor = const CursorPosition();
      _undoStack.clear();
      _redoStack.clear();
      _isDirty = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> save() async {
    try {
      final file = File(filePath);
      await file.writeAsString(text);
      _isDirty = false;
      return true;
    } catch (_) {
      return false;
    }
  }
}
