import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../models/editor_models.dart';
import '../providers/editor_provider.dart';
import '../widgets/editor_content.dart';
import '../widgets/editor_find_panel.dart';

/// 编辑器页面 — 多标签代码编辑器
class EditorPage extends ConsumerStatefulWidget {
  final String? initialPath;

  const EditorPage({super.key, this.initialPath});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(editorProvider.notifier).openFile(widget.initialPath!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final editorState = ref.watch(editorProvider);
    final isDark = theme.brightness == Brightness.dark;
    final locale = ref.watch(localeProvider);
    final s = Strings.get(locale);

    return Scaffold(
      appBar: _buildAppBar(editorState, colorScheme, s),
      body: Column(
        children: [
          // Tab 栏
          if (editorState.tabs.isNotEmpty)
            _buildTabBar(editorState, colorScheme),

          // 查找替换面板
          if (editorState.showFindPanel)
            EditorFindPanel(
              state: editorState.findState,
              onQueryChanged: (q) =>
                  ref.read(editorProvider.notifier).updateFindQuery(q),
              onReplaceChanged: (r) =>
                  ref.read(editorProvider.notifier).updateReplaceText(r),
              onNext: () => ref.read(editorProvider.notifier).nextMatch(),
              onPrev: () => ref.read(editorProvider.notifier).prevMatch(),
              onReplace: () =>
                  ref.read(editorProvider.notifier).replaceCurrent(),
              onReplaceAll: () =>
                  ref.read(editorProvider.notifier).replaceAll(),
              onToggleCase: () =>
                  ref.read(editorProvider.notifier).toggleCaseSensitive(),
              onToggleRegex: () =>
                  ref.read(editorProvider.notifier).toggleRegex(),
              onClose: () =>
                  ref.read(editorProvider.notifier).toggleFindPanel(),
            ),

          // 编辑器内容
          Expanded(
            child: editorState.activeBuffer != null
                ? EditorContent(
                    buffer: editorState.activeBuffer!,
                    settings: editorState.settings,
                    isDark: isDark,
                    onCursorChanged: (_) => setState(() {}),
                  )
                : _buildEmptyState(theme, colorScheme, s),
          ),

          // 状态栏
          if (editorState.activeBuffer != null)
            _buildStatusBar(editorState, colorScheme, theme),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    EditorState editorState,
    ColorScheme colorScheme,
    Strings s,
  ) {
    final activeTab = editorState.activeTab;

    return AppBar(
      title: Text(
        activeTab?.fileName ?? '编辑器',
        style: const TextStyle(fontSize: 16),
      ),
      centerTitle: false,
      backgroundColor: colorScheme.surfaceContainer,
      actions: [
        // 撤销
        IconButton(
          icon: const Icon(Icons.undo, size: 20),
          tooltip: '撤销 (Ctrl+Z)',
          onPressed: () => ref.read(editorProvider.notifier).undo(),
        ),
        // 重做
        IconButton(
          icon: const Icon(Icons.redo, size: 20),
          tooltip: '重做 (Ctrl+Shift+Z)',
          onPressed: () => ref.read(editorProvider.notifier).redo(),
        ),
        // 查找
        IconButton(
          icon: const Icon(Icons.search, size: 20),
          tooltip: '查找 (Ctrl+F)',
          onPressed: () =>
              ref.read(editorProvider.notifier).toggleFindPanel(),
        ),
        // 保存
        IconButton(
          icon: const Icon(Icons.save_outlined, size: 20),
          tooltip: '保存 (Ctrl+S)',
          onPressed: () =>
              ref.read(editorProvider.notifier).saveCurrentFile(),
        ),
        // 换行切换
        IconButton(
          icon: Icon(
            editorState.settings.wordWrap
                ? Icons.wrap_text
                : Icons.wrap_text_outlined,
            size: 20,
          ),
          tooltip: editorState.settings.wordWrap ? '取消换行' : '自动换行',
          onPressed: () =>
              ref.read(editorProvider.notifier).toggleWordWrap(),
        ),
      ],
    );
  }

  Widget _buildTabBar(EditorState editorState, ColorScheme colorScheme) {
    return Container(
      height: 36,
      color: colorScheme.surfaceContainerHighest,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: editorState.tabs.length,
        itemBuilder: (context, index) {
          final tab = editorState.tabs[index];
          final isActive = tab.id == editorState.activeTabId;

          return GestureDetector(
            onTap: () =>
                ref.read(editorProvider.notifier).switchTab(tab.id),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? (colorScheme.brightness == Brightness.dark
                        ? const Color(0xFF1E1E1E)
                        : Colors.white)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive
                        ? colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 修改标记
                  if (tab.isDirty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  // 固定图标
                  if (tab.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.push_pin,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  // 文件名
                  Flexible(
                    child: Text(
                      tab.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isActive
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 关闭按钮
                  InkWell(
                    onTap: () =>
                        ref.read(editorProvider.notifier).closeTab(tab.id),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(
    EditorState editorState,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final buffer = editorState.activeBuffer;
    if (buffer == null) return const SizedBox.shrink();

    final cursor = buffer.cursor;
    final lang = buffer.language;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          // 行:列
          Text(
            '行 ${cursor.line + 1}，列 ${cursor.column + 1}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          // 语言
          Text(
            _languageDisplayName(lang),
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // 编码
          Text(
            'UTF-8',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          // Tab 大小
          Text(
            'Tab: ${editorState.settings.tabSize}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (buffer.isDirty) ...[
            const SizedBox(width: 12),
            Icon(
              Icons.circle,
              size: 6,
              color: colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme, Strings s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.code,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '打开文件开始编辑',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在文件浏览器中选择文件\n或在终端中打开',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  String _languageDisplayName(FileLanguage lang) {
    switch (lang) {
      case FileLanguage.dart: return 'Dart';
      case FileLanguage.rust: return 'Rust';
      case FileLanguage.python: return 'Python';
      case FileLanguage.json: return 'JSON';
      case FileLanguage.yaml: return 'YAML';
      case FileLanguage.markdown: return 'Markdown';
      case FileLanguage.toml: return 'TOML';
      case FileLanguage.shell: return 'Shell';
      case FileLanguage.typescript: return 'TypeScript';
      case FileLanguage.javascript: return 'JavaScript';
      case FileLanguage.html: return 'HTML';
      case FileLanguage.css: return 'CSS';
      case FileLanguage.java: return 'Java';
      case FileLanguage.cpp: return 'C++';
      case FileLanguage.unknown: return 'Plain Text';
    }
  }
}

// 需要 WidgetsBinding
