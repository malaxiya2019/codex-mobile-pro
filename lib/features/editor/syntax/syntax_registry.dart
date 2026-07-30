import '../models/editor_models.dart';
import 'dart_highlighter.dart';
import 'json_highlighter.dart';
import 'markdown_highlighter.dart';
import 'python_highlighter.dart';
import 'rust_highlighter.dart';
import 'shell_highlighter.dart';
import 'syntax_highlighter.dart';
import 'toml_highlighter.dart';
import 'yaml_highlighter.dart';

/// 语法高亮器注册表
///
/// 集中管理所有语言的语法高亮器。
/// 可扩展：添加新语言只需实现 SyntaxHighlighter 并在此注册。
class SyntaxRegistry {
  static final Map<FileLanguage, SyntaxHighlighter> _highlighters = {
    FileLanguage.dart: DartHighlighter(),
    FileLanguage.rust: RustHighlighter(),
    FileLanguage.python: PythonHighlighter(),
    FileLanguage.json: JsonHighlighter(),
    FileLanguage.yaml: YamlHighlighter(),
    FileLanguage.markdown: MarkdownHighlighter(),
    FileLanguage.toml: TomlHighlighter(),
    FileLanguage.shell: ShellHighlighter(),
  };

  /// 获取指定语言的高亮器
  static SyntaxHighlighter? getHighlighter(FileLanguage language) {
    return _highlighters[language];
  }

  /// 根据文件名获取高亮器
  static SyntaxHighlighter? forFileName(String fileName) {
    final lang = FileLanguage.fromFileName(fileName);
    return _highlighters[lang];
  }

  /// 获取所有已注册的语言
  static Set<FileLanguage> get supportedLanguages =>
      _highlighters.keys.toSet();

  /// 注册自定义高亮器
  static void register(FileLanguage language, SyntaxHighlighter highlighter) {
    _highlighters[language] = highlighter;
  }
}
