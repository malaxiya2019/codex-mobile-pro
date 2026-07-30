import '../models/editor_models.dart';
import 'syntax_highlighter.dart';

class MarkdownHighlighter extends BaseHighlighter {
  @override
  FileLanguage get language => FileLanguage.markdown;

  @override
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false}) {
    final tokens = <SyntaxToken>[];
    if (text.isEmpty) return tokens;

    // 标题
    final headerMatch = RegExp(r'^(#{1,6})\s').matchAsPrefix(text);
    if (headerMatch != null) {
      tokens.add(SyntaxToken(type: TokenType.keyword, start: headerMatch.start, end: headerMatch.end));
    }

    // 粗体 **text**
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(text)) {
      tokens.add(SyntaxToken(type: TokenType.builtin, start: m.start, end: m.end));
    }
    // 斜体 *text*
    for (final m in RegExp(r'\*(.+?)\*').allMatches(text)) {
      tokens.add(SyntaxToken(type: TokenType.constant, start: m.start, end: m.end));
    }
    // 行内代码 `code`
    for (final m in RegExp(r'`([^`]+)`').allMatches(text)) {
      tokens.add(SyntaxToken(type: TokenType.string, start: m.start, end: m.end));
    }
    // 链接 [text](url)
    for (final m in RegExp(r'\[([^\]]+)\]\(([^)]+)\)').allMatches(text)) {
      tokens.add(SyntaxToken(type: TokenType.function, start: m.start, end: m.end));
    }
    // 列表项 - / *
    final listMatch = RegExp(r'^(\s*)[-*+]\s').matchAsPrefix(text);
    if (listMatch != null) {
      tokens.add(SyntaxToken(type: TokenType.punctuation, start: listMatch.start, end: listMatch.end));
    }
    // 数字列表
    final numListMatch = RegExp(r'^(\s*)\d+\.\s').matchAsPrefix(text);
    if (numListMatch != null) {
      tokens.add(SyntaxToken(type: TokenType.number, start: numListMatch.start, end: numListMatch.end));
    }
    // 引用 >
    final quoteMatch = RegExp(r'^(>\s?)').matchAsPrefix(text);
    if (quoteMatch != null) {
      tokens.add(SyntaxToken(type: TokenType.comment, start: quoteMatch.start, end: quoteMatch.end));
    }

    return tokens;
  }
}
