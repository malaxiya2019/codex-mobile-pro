import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../extensions/diagnostics_provider.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../models/editor_models.dart';
import '../providers/editor_provider.dart';
import '../widgets/editor_content.dart';
import '../widgets/editor_find_panel.dart';
import '../extensions/inline_completion.dart';
import '../extensions/code_explain.dart';
import '../extensions/code_review.dart';
import '../extensions/refactor_code.dart';
import '../extensions/generate_test.dart';
import '../extensions/fix_error.dart';
import '../widgets/code_review_sheet.dart';

/// 编辑器页面 — 多标签代码编辑器（带 AI 内联补全 + 代码解释）
class EditorPage extends ConsumerStatefulWidget {
  final String? initialPath;

  const EditorPage({super.key, this.initialPath});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  CodeExplainer? _explainer;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(editorProvider.notifier).openFile(widget.initialPath!);
      });
    }
  }

  /// 获取或创建 CodeExplainer
  CodeExplainer _getExplainer() {
    if (_explainer == null) {
      final aiProvider = ref.read(editorProvider.notifier).aiProvider;
      if (aiProvider != null) {
        _explainer = CodeExplainer(aiProvider);
      }
    }
    return _explainer!;
  }

  /// 解释选中的代码
  Future<void> _explainSelectedCode() async {
    final editorState = ref.read(editorProvider);
    final buffer = editorState.activeBuffer;
    if (buffer == null) return;

    // 获取 AI Provider
    final aiProvider = ref.read(editorProvider.notifier).aiProvider;
    if (aiProvider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 服务未初始化')),
      );
      return;
    }

    // 如果无选中内容，尝试使用当前行
    String code;
    if (buffer.hasSelection) {
      code = buffer.selectedText;
    } else {
      code = buffer.currentLine;
    }

    if (code.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择要解释的代码')),
      );
      return;
    }

    // 创建解释器并请求解释
    final explainer = CodeExplainer(aiProvider);
    final result = await explainer.explain(
      code: code,
      language: buffer.language.name,
    );

    if (!mounted) return;

    if (result.isValid) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ExplainCodeSheet(
          result: result,
          onClose: () => Navigator.of(context).pop(),
        ),
      );
    } else if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('解释失败: ${result.errorMessage}')),
      );
    }
  }

  /// 审查选中的代码
  Future<void> _reviewCode() async {
    final editorState = ref.read(editorProvider);
    final buffer = editorState.activeBuffer;
    if (buffer == null) return;

    final aiProvider = ref.read(editorProvider.notifier).aiProvider;
    if (aiProvider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 服务未初始化')),
      );
      return;
    }

    String code;
    if (buffer.hasSelection) {
      code = buffer.selectedText;
    } else {
      code = buffer.text;
    }

    if (code.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择要审查的代码')),
      );
      return;
    }

    final engine = CodeReviewEngine(aiProvider);
    final result = await engine.reviewSelection(
      code: code,
      language: buffer.language.name,
    );

    if (!mounted) return;

    if (result.isValid || result.hasError) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CodeReviewSheet(
          result: result,
          onClose: () => Navigator.of(context).pop(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('审查未返回结果')),
      );
    }
  }

  /// 重构选中的代码
  Future<void> _refactorCode() async {
    final editorState = ref.read(editorProvider);
    final buffer = editorState.activeBuffer;
    if (buffer == null) return;

    final aiProvider = ref.read(editorProvider.notifier).aiProvider;
    if (aiProvider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 服务未初始化')),
      );
      return;
    }

    String code;
    if (buffer.hasSelection) {
      code = buffer.selectedText;
    } else {
      code = buffer.text;
    }

    if (code.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择要重构的代码')),
      );
      return;
    }

    final engine = RefactorEngine(aiProvider);
    final result = await engine.refactor(
      code: code,
      language: buffer.language.name,
    );

    if (!mounted) return;

    if (result.isValid) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _RefactorCodeSheet(
          result: result,
          onClose: () => Navigator.of(context).pop(),
        ),
      );
    } else if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重构失败: ${result.errorMessage}')),
      );
    }
  }

  /// 生成测试
  Future<void> _generateTest() async {
    final editorState = ref.read(editorProvider);
    final buffer = editorState.activeBuffer;
    if (buffer == null) return;

    final aiProvider = ref.read(editorProvider.notifier).aiProvider;
    if (aiProvider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 服务未初始化')),
      );
      return;
    }

    final code = buffer.text;
    final fileName = buffer.filePath.split('/').last;
    final className = fileName.replaceAll('.dart', '');

    if (code.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件内容为空')),
      );
      return;
    }

    final generator = TestGenerator(aiProvider);
    final result = await generator.generateTest(
      sourceCode: code,
      className: className,
      language: buffer.language.name,
    );

    if (!mounted) return;

    if (result.isValid) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _TestGenSheet(
          result: result,
          onClose: () => Navigator.of(context).pop(),
        ),
      );
    } else if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成测试失败: ${result.errorMessage}')),
      );
    }
  }

  /// AI 修 Bug
  Future<void> _fixBug() async {
    final editorState = ref.read(editorProvider);
    final buffer = editorState.activeBuffer;
    if (buffer == null) return;

    // 如果有选中文本，优先使用选中内容
    String code;
    if (buffer.hasSelection) {
      code = buffer.selectedText;
    } else {
      code = buffer.text;
    }

    if (code.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择要修复的代码')),
      );
      return;
    }

    // 显示输入对话框，让用户粘贴错误日志
    final errorLog = await showDialog<String>(
      context: context,
      builder: (ctx) => _BugErrorDialog(),
    );
    if (errorLog == null || errorLog.trim().isEmpty) return;

    final aiProvider = ref.read(editorProvider.notifier).aiProvider;
    if (aiProvider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 服务未初始化')),
      );
      return;
    }

    // 使用 FixEngine 分析
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final engine = FixEngine(aiProvider);
      final fakeDiagnostic = Diagnostic(
        message: errorLog,
        line: 0,
        column: 0,
        length: code.length,
        severity: DiagnosticSeverity.error,
        source: code,
      );

      final result = await engine.fixDiagnostic(
        diagnostic: fakeDiagnostic,
        filePath: buffer.filePath,
        code: code,
        language: buffer.language.name,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading

      if (result.hasSuggestions) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _FixBugSheet(
            result: result,
            language: buffer.language.name,
            onClose: () => Navigator.of(context).pop(),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未生成修复建议')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('修复分析失败: $e')),
      );
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
    final buffer = editorState.activeBuffer;

    return Scaffold(
      appBar: _buildAppBar(editorState, colorScheme, s, editorState.activeTab),
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

          // 编辑器内容（带 AI 内联补全）
          Expanded(
            child: editorState.activeBuffer != null
                ? EditorContent(
                    buffer: editorState.activeBuffer!,
                    settings: editorState.settings,
                    isDark: isDark,
                    inlineCompletion: editorState.inlineCompletion,
                    onAcceptCompletion: () {
                      ref.read(editorProvider.notifier).acceptInlineCompletion();
                    },
                    onCursorChanged: (_) => setState(() {}),
                  )
                : _buildEmptyState(theme, colorScheme, s),
          ),

          // 状态栏
          if (buffer != null)
            _buildStatusBar(editorState, colorScheme, theme),
        ],
      ),
      // Explain Code 浮动按钮
      floatingActionButton: buffer != null
          ? FloatingActionButton.small(
              onPressed: _explainSelectedCode,
              tooltip: 'AI 辅助',
              child: const Icon(Icons.auto_awesome),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(
    EditorState editorState,
    ColorScheme colorScheme,
    Strings s,
    EditorTab? activeTab,
  ) {
    // 从 editorState 获取 activeTab
    final tab = editorState.activeTab;

    return AppBar(
      title: Text(
        tab?.fileName ?? '编辑器',
        style: const TextStyle(fontSize: 16),
      ),
      centerTitle: false,
      backgroundColor: colorScheme.surfaceContainer,
      actions: [
        // Explain Code
        if (editorState.activeBuffer != null)
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined, size: 20),
            tooltip: '解释选中代码',
            onPressed: _explainSelectedCode,
          ),
        // AI Refactor
        if (editorState.activeBuffer != null)
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'AI 重构代码',
            onPressed: _refactorCode,
          ),
        // 撤销
        IconButton(
          icon: const Icon(Icons.undo, size: 20),
          tooltip: '撤销 (Ctrl+Z)',
          onPressed: () => ref.read(editorProvider.notifier).undo(),
        ),
        // Code Review
        if (editorState.activeBuffer != null)
          IconButton(
            icon: const Icon(Icons.rate_review_outlined, size: 20),
            tooltip: '审查代码',
            onPressed: _reviewCode,
          ),
        // Generate Test
        if (editorState.activeBuffer != null)
          IconButton(
            icon: const Icon(Icons.science_outlined, size: 20),
            tooltip: 'AI 生成测试',
            onPressed: _generateTest,
          ),
        // Fix Bug
        if (editorState.activeBuffer != null)
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            tooltip: 'AI 修 Bug',
            onPressed: _fixBug,
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
                  if (tab.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.push_pin,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
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
          Text(
            '行 ${cursor.line + 1}，列 ${cursor.column + 1}',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Text(
            _languageDisplayName(lang),
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (editorState.inlineCompletion.state == InlineCompletionState.loading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 10, height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: colorScheme.primary,
                ),
              ),
            ),
          if (editorState.inlineCompletion.hasSuggestion)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.auto_awesome, size: 12, color: colorScheme.primary),
            ),
          Text('UTF-8', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          Text('Tab: ${editorState.settings.tabSize}', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
          if (buffer.isDirty) ...[
            const SizedBox(width: 12),
            Icon(Icons.circle, size: 6, color: colorScheme.primary),
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
          Icon(Icons.code, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('打开文件开始编辑', style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('在文件浏览器中选择文件\n或在终端中打开', textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
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

/// 代码解释结果 BottomSheet
class ExplainCodeSheet extends StatelessWidget {
  final CodeExplanation result;
  final VoidCallback? onClose;

  const ExplainCodeSheet({
    super.key,
    required this.result,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // 标题和关闭按钮
              Row(
                children: [
                  Icon(Icons.smart_toy, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('代码解释', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),

              // 功能解释
              if (result.explanation.isNotEmpty) ...[
                _sectionHeader('📖 功能解释', colorScheme),
                const SizedBox(height: 4),
                Text(result.explanation, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
              ],

              // 时间复杂度
              if (result.timeComplexity != null) ...[
                _sectionHeader('⏱ 时间复杂度', colorScheme),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.timeComplexity!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 空间复杂度
              if (result.spaceComplexity != null) ...[
                _sectionHeader('💾 空间复杂度', colorScheme),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.spaceComplexity!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 优化建议
              if (result.suggestions.isNotEmpty) ...[
                _sectionHeader('💡 优化建议', colorScheme),
                const SizedBox(height: 4),
                ...result.suggestions.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${entry.key + 1}. ', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Text(entry.value, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // 错误
              if (result.hasError && result.errorMessage != null) ...[
                _sectionHeader('❌ 错误', colorScheme),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(result.errorMessage!, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.error)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colorScheme.primary,
      ),
    );
  }
}

/// AI 修正 Bug — 错误日志输入对话框
class _BugErrorDialog extends StatefulWidget {
  @override
  State<_BugErrorDialog> createState() => _BugErrorDialogState();
}

class _BugErrorDialogState extends State<_BugErrorDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('粘贴错误日志'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _controller,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: '请粘贴编译错误、运行时异常或报错日志...',
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('分析修复'),
        ),
      ],
    );
  }
}

/// 重构代码结果 BottomSheet
class _RefactorCodeSheet extends StatelessWidget {
  final RefactorResult result;
  final VoidCallback? onClose;

  const _RefactorCodeSheet({
    required this.result,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon(Icons.refresh, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('AI 重构建议', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),

              // 重构说明
              if (result.explanation.isNotEmpty) ...[
                Text('重构说明',
                  style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
                const SizedBox(height: 4),
                Text(result.explanation, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
              ],

              // 变更列表
              if (result.changes.isNotEmpty) ...[
                Text('变更清单',
                  style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
                const SizedBox(height: 4),
                ...result.changes.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.key + 1}. ', style: theme.textTheme.bodySmall),
                      Expanded(
                        child: Text(e.value, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 16),
              ],

              // 重构后的代码
              if (result.refactoredCode.isNotEmpty) ...[
                Text('重构后代码',
                  style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    result.refactoredCode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ],

              if (result.hasError && result.errorMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(result.errorMessage!,
                    style: TextStyle(color: colorScheme.error)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 测试生成结果 BottomSheet
class _TestGenSheet extends StatelessWidget {
  final TestGenResult result;
  final VoidCallback? onClose;

  const _TestGenSheet({
    required this.result,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon(Icons.science_outlined, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('AI 生成测试', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (result.testFileName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(result.testFileName,
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),

              if (result.isValid) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    result.testCode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ],

              if (result.hasError && result.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(result.errorMessage!,
                    style: TextStyle(color: colorScheme.error)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// AI 修 Bug 结果 BottomSheet
class _FixBugSheet extends StatelessWidget {
  final FixResult result;
  final String language;
  final VoidCallback? onClose;

  const _FixBugSheet({
    required this.result,
    required this.language,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon(Icons.bug_report_outlined, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('AI 修复建议', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),

              if (result.hasError && result.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(result.error!,
                    style: TextStyle(color: colorScheme.error)),
                ),
              ],

              if (result.hasSuggestions)
                ...result.suggestions.map((s) => _buildSuggestionCard(s, colorScheme, theme)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuggestionCard(FixSuggestion s, ColorScheme colorScheme, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: colorScheme.error),
                const SizedBox(width: 6),
                Text('错误原因', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(s.reason, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(Icons.build_outlined, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text('修复方案', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(s.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),

            if (s.hasValidPatch) ...[
              Row(
                children: [
                  Icon(Icons.code, size: 16, color: colorScheme.tertiary),
                  const SizedBox(width: 6),
                  Text('修复代码', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  s.patch,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
