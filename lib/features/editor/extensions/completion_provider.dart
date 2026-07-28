import '../models/editor_models.dart';
import '../../../core/ai/ai_provider.dart';

/// 自动补全条目
class CompletionItem {
  final String label;
  final String? detail;
  final String? documentation;
  final CompletionItemKind kind;
  final String insertText;

  const CompletionItem({
    required this.label,
    this.detail,
    this.documentation,
    this.kind = CompletionItemKind.text,
    this.insertText = '',
  });
}

enum CompletionItemKind {
  text,
  keyword,
  function,
  constructor,
  field,
  variable,
  klass,
  interface,
  module,
  property,
  method,
  snippet,
}

/// 自动补全提供者接口
///
/// 可扩展：实现此接口以添加自定义自动补全源。
/// 预留 AI 补全接口。
abstract class CompletionProvider {
  /// 提供者名称
  String get name;

  /// 是否为 AI 补全提供者
  bool get isAiProvider => false;

  /// 获取补全建议
  Future<List<CompletionItem>> getCompletions({
    required String filePath,
    required String text,
    required int offset,
    required CursorPosition position,
    required FileLanguage language,
  });

  /// 是否应为此语言激活
  bool supportsLanguage(FileLanguage language);
}

/// 基于关键字的自动补全提供者
class KeywordCompletionProvider extends CompletionProvider {
  @override
  String get name => 'Keywords';

  /// 语言关键字映射
  static final Map<FileLanguage, List<String>> _keywords = {
    FileLanguage.dart: [
      'abstract', 'as', 'assert', 'async', 'await', 'break', 'case',
      'catch', 'class', 'const', 'continue', 'covariant', 'default',
      'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends',
      'extension', 'external', 'factory', 'false', 'final', 'finally',
      'for', 'Function', 'get', 'hide', 'if', 'implements', 'import',
      'in', 'interface', 'is', 'late', 'library', 'mixin', 'new',
      'null', 'on', 'operator', 'part', 'required', 'rethrow',
      'return', 'set', 'show', 'static', 'super', 'switch', 'sync',
      'this', 'throw', 'true', 'try', 'typedef', 'var', 'void',
      'while', 'with', 'yield',
    ],
    FileLanguage.python: [
      'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await',
      'break', 'class', 'continue', 'def', 'del', 'elif', 'else',
      'except', 'finally', 'for', 'from', 'global', 'if', 'import',
      'in', 'is', 'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise',
      'return', 'try', 'while', 'with', 'yield',
    ],
    FileLanguage.rust: [
      'as', 'async', 'await', 'break', 'const', 'continue', 'crate',
      'dyn', 'else', 'enum', 'extern', 'false', 'fn', 'for', 'if',
      'impl', 'in', 'let', 'loop', 'match', 'mod', 'move', 'mut',
      'pub', 'ref', 'return', 'self', 'static', 'struct', 'super',
      'trait', 'true', 'type', 'unsafe', 'use', 'where', 'while',
    ],
  };

  @override
  bool supportsLanguage(FileLanguage language) {
    return _keywords.containsKey(language);
  }

  @override
  Future<List<CompletionItem>> getCompletions({
    required String filePath,
    required String text,
    required int offset,
    required CursorPosition position,
    required FileLanguage language,
  }) async {
    final keywords = _keywords[language] ?? [];
    return keywords.map((kw) => CompletionItem(
      label: kw,
      kind: CompletionItemKind.keyword,
      insertText: kw,
    )).toList();
  }
}

/// AI 自动补全提供者
///
/// 使用 [AiProvider] 接口获取 AI 补全建议。
/// 与新的 InlineCompletion 系统共享底层 AI Provider。
class AiCompletionProvider extends CompletionProvider {
  final AiProvider? _aiProvider;
  final CancelToken? _cancelToken;

  AiCompletionProvider({AiProvider? aiProvider, CancelToken? cancelToken})
      : _aiProvider = aiProvider,
        _cancelToken = cancelToken;

  @override
  String get name => 'AI';

  @override
  bool get isAiProvider => true;

  @override
  bool supportsLanguage(FileLanguage language) => true;

  @override
  Future<List<CompletionItem>> getCompletions({
    required String filePath,
    required String text,
    required int offset,
    required CursorPosition position,
    required FileLanguage language,
  }) async {
    if (_aiProvider == null) return [];

    try {
      final prefix = text.substring(0, offset);
      final suffix = text.substring(offset);

      final request = InlineCompletionRequest(
        filePath: filePath,
        language: language.name,
        prefix: prefix,
        suffix: suffix,
        textBeforeCursor: prefix,
        textAfterCursor: suffix,
        cursorLine: position.line,
        cursorColumn: position.column,
      );

      final completions = await _aiProvider.getInlineCompletions(
        request: request,
        triggerKind: CompletionTriggerKind.invoked,
        cancelToken: _cancelToken,
      );

      return completions.map((c) => CompletionItem(
        label: c.text.split('\n').first,
        detail: c.label,
        kind: CompletionItemKind.snippet,
        insertText: c.text,
      )).toList();
    } catch (_) {
      return [];
    }
  }
}

/// 补全管理器
class CompletionManager {
  final List<CompletionProvider> _providers = [];

  CompletionManager() {
    _providers.add(KeywordCompletionProvider());
    // AiCompletionProvider 可通过 register 添加
  }

  /// 注册自定义补全提供者
  void register(CompletionProvider provider) {
    _providers.add(provider);
  }

  /// 获取补全建议（合并所有提供者结果）
  Future<List<CompletionItem>> getCompletions({
    required String filePath,
    required String text,
    required int offset,
    required CursorPosition position,
    required FileLanguage language,
  }) async {
    final results = <CompletionItem>[];
    for (final provider in _providers) {
      if (provider.supportsLanguage(language)) {
        try {
          final items = await provider.getCompletions(
            filePath: filePath,
            text: text,
            offset: offset,
            position: position,
            language: language,
          );
          results.addAll(items);
        } catch (_) {
          // 忽略单个提供者的错误
        }
      }
    }
    return results;
  }
}
