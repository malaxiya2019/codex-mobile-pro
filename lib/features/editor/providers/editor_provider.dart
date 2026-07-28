import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/editor_models.dart';
import '../services/editor_buffer.dart';
import '../extensions/inline_completion.dart';
import '../../../core/ai/ai_provider.dart';
import '../../../core/ai/providers/deepseek_provider.dart';
import '../../../core/ai/ai_service.dart';

/// 编辑器状态
class EditorState {
  final List<EditorTab> tabs;
  final String? activeTabId;
  final Map<String, EditorBuffer> buffers;
  final EditorSettings settings;
  final bool showFindPanel;
  final FindReplaceState findState;
  final List<String> recentFiles;
  final Set<String> pinnedFiles;
  final Set<String> favoriteFiles;

  /// 内联补全引擎
  final InlineCompletionEngine inlineCompletion;

  EditorState({
    this.tabs = const [],
    this.activeTabId,
    this.buffers = const {},
    EditorSettings? settings,
    this.showFindPanel = false,
    FindReplaceState? findState,
    this.recentFiles = const [],
    this.pinnedFiles = const {},
    this.favoriteFiles = const {},
    InlineCompletionEngine? inlineCompletion,
  }) : settings = settings ?? EditorSettings(),
      findState = findState ?? FindReplaceState(),
      inlineCompletion = inlineCompletion ?? _createDefaultInlineCompletion();

  EditorState copyWith({
    List<EditorTab>? tabs,
    String? activeTabId,
    Map<String, EditorBuffer>? buffers,
    EditorSettings? settings,
    bool? showFindPanel,
    FindReplaceState? findState,
    List<String>? recentFiles,
    Set<String>? pinnedFiles,
    Set<String>? favoriteFiles,
    InlineCompletionEngine? inlineCompletion,
    bool clearActiveTab = false,
  }) {
    return EditorState(
      tabs: tabs ?? this.tabs,
      activeTabId: clearActiveTab ? null : (activeTabId ?? this.activeTabId),
      buffers: buffers ?? this.buffers,
      settings: settings ?? this.settings,
      showFindPanel: showFindPanel ?? this.showFindPanel,
      findState: findState ?? this.findState,
      recentFiles: recentFiles ?? this.recentFiles,
      pinnedFiles: pinnedFiles ?? this.pinnedFiles,
      favoriteFiles: favoriteFiles ?? this.favoriteFiles,
      inlineCompletion: inlineCompletion ?? this.inlineCompletion,
    );
  }

  EditorTab? get activeTab {
    if (activeTabId == null) return null;
    try {
      return tabs.firstWhere((t) => t.id == activeTabId);
    } catch (_) {
      return null;
    }
  }

  EditorBuffer? get activeBuffer {
    if (activeTabId == null) return null;
    return buffers[activeTabId];
  }
}

/// 默认内联补全引擎（空实现）
InlineCompletionEngine _createDefaultInlineCompletion() {
  return InlineCompletionEngine();
}
/// 编辑器 Provider
final editorProvider = StateNotifierProvider<EditorNotifier, EditorState>((ref) {
  return EditorNotifier();
});

class EditorNotifier extends StateNotifier<EditorState> {
  Timer? _autoSaveTimer;
  AiProvider? _aiProvider;

  AiProvider? get aiProvider => _aiProvider;
  EditorNotifier() : super(EditorState());

  // ── AI Provider 管理 ──

  /// 初始化 AI Provider（DeepSeek）
  Future<void> initAiProvider({AiConfig? config}) async {
    final provider = DeepSeekProvider(config: config);
    await provider.initialize();
    _aiProvider = provider;
    state.inlineCompletion.setProvider(provider);
  }

  /// 设置自定义 AI Provider
  void setAiProvider(AiProvider provider) {
    _aiProvider = provider;
    state.inlineCompletion.setProvider(provider);
  }

  // ── 内联补全 ──

  /// 接受内联补全建议
  void acceptInlineCompletion() {
    final text = state.inlineCompletion.acceptSuggestion();
    if (text != null) {
      final buffer = state.activeBuffer;
      if (buffer != null) {
        buffer.insertText(text);
        _markDirty();
        state = state.copyWith();
      }
    }
  }

  /// 取消内联补全
  void cancelInlineCompletion() {
    state.inlineCompletion.cancelSuggestion();
    state = state.copyWith();
  }

  // ── Tab 管理 ──

  Future<void> openFile(String filePath) async {
    final existing = state.tabs.where((t) => t.filePath == filePath);
    if (existing.isNotEmpty) {
      state = state.copyWith(activeTabId: existing.first.id);
      return;
    }

    final tabId = DateTime.now().microsecondsSinceEpoch.toString();
    final tab = EditorTab(id: tabId, filePath: filePath);

    final buffer = EditorBuffer(filePath: filePath, settings: state.settings);
    await buffer.load();

    final newBuffers = Map<String, EditorBuffer>.from(state.buffers);
    newBuffers[tabId] = buffer;

    final recent = List<String>.from(state.recentFiles);
    recent.remove(filePath);
    recent.insert(0, filePath);
    if (recent.length > 50) recent.removeLast();

    state = state.copyWith(
      tabs: [...state.tabs, tab],
      activeTabId: tabId,
      buffers: newBuffers,
      recentFiles: recent,
    );

    _startAutoSave();
  }

  void closeTab(String tabId) {
    if (state.tabs.length <= 1) {
      final buffers = Map<String, EditorBuffer>.from(state.buffers);
      buffers.remove(tabId);
      state = state.copyWith(
        tabs: [],
        buffers: buffers,
        clearActiveTab: true,
      );
      return;
    }

    final tabIndex = state.tabs.indexWhere((t) => t.id == tabId);
    final newTabs = state.tabs.where((t) => t.id != tabId).toList();
    final buffers = Map<String, EditorBuffer>.from(state.buffers);
    buffers.remove(tabId);

    String? newActiveId;
    if (tabId == state.activeTabId) {
      if (tabIndex > 0) {
        newActiveId = newTabs[tabIndex - 1].id;
      } else if (newTabs.isNotEmpty) {
        newActiveId = newTabs[0].id;
      }
    } else {
      newActiveId = state.activeTabId;
    }

    state = state.copyWith(
      tabs: newTabs,
      activeTabId: newActiveId,
      buffers: buffers,
    );
  }

  void switchTab(String tabId) {
    state = state.copyWith(activeTabId: tabId);
  }

  void closeAllTabs() {
    final ids = state.tabs.map((t) => t.id).toList();
    final buffers = Map<String, EditorBuffer>.from(state.buffers);
    for (final id in ids) {
      buffers.remove(id);
    }
    state = state.copyWith(
      tabs: [],
      buffers: buffers,
      clearActiveTab: true,
    );
  }

  void closeOtherTabs(String tabId) {
    final keepTab = state.tabs.firstWhere((t) => t.id == tabId);
    final buffers = Map<String, EditorBuffer>.from(state.buffers);
    for (final tab in state.tabs) {
      if (tab.id != tabId) {
        buffers.remove(tab.id);
      }
    }
    state = state.copyWith(
      tabs: [keepTab],
      activeTabId: tabId,
      buffers: buffers,
    );
  }

  void togglePinTab(String tabId) {
    final newTabs = state.tabs.map((t) {
      if (t.id == tabId) {
        return EditorTab(
          id: t.id,
          filePath: t.filePath,
          isDirty: t.isDirty,
          isPinned: !t.isPinned,
          lastOpened: t.lastOpened,
        );
      }
      return t;
    }).toList();

    state = state.copyWith(tabs: newTabs);
  }

  // ── 编辑操作 ──

  void insertChar(String ch) {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    buffer.insertChar(ch);
    _markDirty();
  }

  void insertText(String text) {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    buffer.insertText(text);
    _markDirty();
  }

  void insertNewline() {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    buffer.insertNewline();
    _markDirty();
  }

  void insertTab() {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    buffer.insertTab();
    _markDirty();
  }

  void deleteLeft() {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    buffer.deleteLeft();
    _markDirty();
  }

  void deleteRight() {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    buffer.deleteRight();
    _markDirty();
  }

  void undo() {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    buffer.undo();
    _markDirty();
  }

  void redo() {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    buffer.redo();
    _markDirty();
  }

  // ── 光标 ──

  void moveCursor(CursorPosition pos) {
    state.activeBuffer?.moveCursor(pos);
    _notify();
  }

  void moveCursorUp() {
    state.activeBuffer?.moveCursorUp();
    _notify();
  }

  void moveCursorDown() {
    state.activeBuffer?.moveCursorDown();
    _notify();
  }

  void moveCursorLeft() {
    state.activeBuffer?.moveCursorLeft();
    _notify();
  }

  void moveCursorRight() {
    state.activeBuffer?.moveCursorRight();
    _notify();
  }

  void moveToLineStart() {
    state.activeBuffer?.moveToLineStart();
    _notify();
  }

  void moveToLineEnd() {
    state.activeBuffer?.moveToLineEnd();
    _notify();
  }

  void moveToFileStart() {
    state.activeBuffer?.moveToFileStart();
    _notify();
  }

  void moveToFileEnd() {
    state.activeBuffer?.moveToFileEnd();
    _notify();
  }

  // ── 选择 ──

  void selectAll() {
    state.activeBuffer?.selectAll();
    _notify();
  }

  void clearSelection() {
    state.activeBuffer?.clearSelection();
    _notify();
  }

  // ── 查找/替换 ──

  void toggleFindPanel() {
    state = state.copyWith(showFindPanel: !state.showFindPanel);
  }

  void updateFindQuery(String query) {
    final findState = state.findState;
    final buffer = state.activeBuffer;
    List<SearchMatch> matches = [];
    if (query.isNotEmpty && buffer != null) {
      matches = buffer.findAll(query, caseSensitive: findState.caseSensitive);
    }

    state = state.copyWith(
      showFindPanel: true,
      findState: FindReplaceState(
        query: query,
        replaceText: findState.replaceText,
        caseSensitive: findState.caseSensitive,
        useRegex: findState.useRegex,
        currentMatch: matches.isEmpty ? 0 : 1,
        totalMatches: matches.length,
        matches: matches,
      ),
    );
  }

  void updateReplaceText(String text) {
    state = state.copyWith(
      findState: FindReplaceState(
        query: state.findState.query,
        replaceText: text,
        caseSensitive: state.findState.caseSensitive,
        useRegex: state.findState.useRegex,
        currentMatch: state.findState.currentMatch,
        totalMatches: state.findState.totalMatches,
        matches: state.findState.matches,
      ),
    );
  }

  void toggleCaseSensitive() {
    updateFindQuery(state.findState.query);
    state = state.copyWith(
      findState: FindReplaceState(
        query: state.findState.query,
        replaceText: state.findState.replaceText,
        caseSensitive: !state.findState.caseSensitive,
        useRegex: state.findState.useRegex,
        currentMatch: state.findState.currentMatch,
        totalMatches: state.findState.totalMatches,
        matches: state.findState.matches,
      ),
    );
  }

  void toggleRegex() {
    updateFindQuery(state.findState.query);
    state = state.copyWith(
      findState: FindReplaceState(
        query: state.findState.query,
        replaceText: state.findState.replaceText,
        caseSensitive: state.findState.caseSensitive,
        useRegex: !state.findState.useRegex,
        currentMatch: state.findState.currentMatch,
        totalMatches: state.findState.totalMatches,
        matches: state.findState.matches,
      ),
    );
  }

  void nextMatch() {
    final total = state.findState.totalMatches;
    if (total == 0) return;
    final current = state.findState.currentMatch;
    final next = current >= total ? 1 : current + 1;
    state = state.copyWith(
      findState: FindReplaceState(
        query: state.findState.query,
        replaceText: state.findState.replaceText,
        caseSensitive: state.findState.caseSensitive,
        useRegex: state.findState.useRegex,
        currentMatch: next,
        totalMatches: total,
        matches: state.findState.matches,
      ),
    );
  }

  void prevMatch() {
    final total = state.findState.totalMatches;
    if (total == 0) return;
    final current = state.findState.currentMatch;
    final prev = current <= 1 ? total : current - 1;
    state = state.copyWith(
      findState: FindReplaceState(
        query: state.findState.query,
        replaceText: state.findState.replaceText,
        caseSensitive: state.findState.caseSensitive,
        useRegex: state.findState.useRegex,
        currentMatch: prev,
        totalMatches: total,
        matches: state.findState.matches,
      ),
    );
  }

  void replaceCurrent() {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    final findState = state.findState;
    if (findState.query.isEmpty || findState.matches.isEmpty) return;

    final match = findState.matches[findState.currentMatch - 1];
    buffer.moveCursor(CursorPosition(line: match.line, column: match.column));
    for (int i = 0; i < match.length; i++) {
      buffer.deleteRight();
    }
    buffer.insertText(findState.replaceText);

    updateFindQuery(findState.query);
    _markDirty();
  }

  void replaceAll() {
    final buffer = state.activeBuffer;
    if (buffer == null) return;
    final findState = state.findState;
    if (findState.query.isEmpty) return;

    buffer.replaceAll(findState.query, findState.replaceText,
        caseSensitive: findState.caseSensitive);
    updateFindQuery(findState.query);
    _markDirty();
  }

  // ── 文件操作 ──

  Future<bool> saveCurrentFile() async {
    final buffer = state.activeBuffer;
    if (buffer == null) return false;
    final result = await buffer.save();
    if (result) {
      _markClean();
    }
    return result;
  }

  Future<bool> saveFileAs(String newPath) async {
    final buffer = state.activeBuffer;
    if (buffer == null) return false;
    try {
      final file = File(newPath);
      await file.writeAsString(buffer.text);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── 设置 ──

  void updateSettings(EditorSettings Function(EditorSettings) updater) {
    final newSettings = updater(state.settings);
    state = state.copyWith(settings: newSettings);
  }

  void setFontSize(int size) {
    updateSettings((s) => EditorSettings(
      fontSize: size.clamp(8, 48),
      fontFamily: s.fontFamily,
      showLineNumbers: s.showLineNumbers,
      highlightCurrentLine: s.highlightCurrentLine,
      autoIndent: s.autoIndent,
      bracketMatching: s.bracketMatching,
      wordWrap: s.wordWrap,
      tabSize: s.tabSize,
      insertSpaces: s.insertSpaces,
      autoSaveDelayMs: s.autoSaveDelayMs,
    ));
  }

  void setFontFamily(String family) {
    updateSettings((s) => EditorSettings(
      fontSize: s.fontSize,
      fontFamily: family,
      showLineNumbers: s.showLineNumbers,
      highlightCurrentLine: s.highlightCurrentLine,
      autoIndent: s.autoIndent,
      bracketMatching: s.bracketMatching,
      wordWrap: s.wordWrap,
      tabSize: s.tabSize,
      insertSpaces: s.insertSpaces,
      autoSaveDelayMs: s.autoSaveDelayMs,
    ));
  }

  void toggleWordWrap() {
    updateSettings((s) => EditorSettings(
      fontSize: s.fontSize,
      fontFamily: s.fontFamily,
      showLineNumbers: s.showLineNumbers,
      highlightCurrentLine: s.highlightCurrentLine,
      autoIndent: s.autoIndent,
      bracketMatching: s.bracketMatching,
      wordWrap: !s.wordWrap,
      tabSize: s.tabSize,
      insertSpaces: s.insertSpaces,
      autoSaveDelayMs: s.autoSaveDelayMs,
    ));
  }

  // ── 文件收藏/固定 ──

  void toggleFavorite(String filePath) {
    final favorites = Set<String>.from(state.favoriteFiles);
    if (favorites.contains(filePath)) {
      favorites.remove(filePath);
    } else {
      favorites.add(filePath);
    }
    state = state.copyWith(favoriteFiles: favorites);
  }

  void togglePinned(String filePath) {
    final pinned = Set<String>.from(state.pinnedFiles);
    if (pinned.contains(filePath)) {
      pinned.remove(filePath);
    } else {
      pinned.add(filePath);
    }
    state = state.copyWith(pinnedFiles: pinned);
  }

  void removeFromRecent(String filePath) {
    final recent = List<String>.from(state.recentFiles);
    recent.remove(filePath);
    state = state.copyWith(recentFiles: recent);
  }

  // ── 内部 ──

  void _markDirty() {
    if (state.activeTabId == null) return;
    final newTabs = state.tabs.map((t) {
      if (t.id == state.activeTabId) {
        return EditorTab(
          id: t.id,
          filePath: t.filePath,
          isDirty: true,
          isPinned: t.isPinned,
          lastOpened: t.lastOpened,
        );
      }
      return t;
    }).toList();
    state = state.copyWith(tabs: newTabs);
  }

  void _markClean() {
    if (state.activeTabId == null) return;
    final newTabs = state.tabs.map((t) {
      if (t.id == state.activeTabId) {
        return EditorTab(
          id: t.id,
          filePath: t.filePath,
          isDirty: false,
          isPinned: t.isPinned,
          lastOpened: t.lastOpened,
        );
      }
      return t;
    }).toList();
    state = state.copyWith(tabs: newTabs);
  }

  void _startAutoSave() {
    final delay = state.settings.autoSaveDelayMs;
    if (delay <= 0) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(Duration(milliseconds: delay), (_) {
      for (final tab in state.tabs) {
        if (tab.isDirty) {
          final buffer = state.buffers[tab.id];
          buffer?.save();
        }
      }
    });
  }

  void _notify() {
    state = state.copyWith();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _aiProvider?.dispose();
    state.inlineCompletion.dispose();
    super.dispose();
  }
}
