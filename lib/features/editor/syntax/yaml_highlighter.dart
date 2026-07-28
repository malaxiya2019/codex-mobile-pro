import 'syntax_highlighter.dart';
import '../models/editor_models.dart';

class YamlHighlighter extends BaseHighlighter {
  @override
  FileLanguage get language => FileLanguage.yaml;

  @override
  Set<String> get keywords => {'true', 'false', 'yes', 'no', 'on', 'off', 'null', '~'};

  @override
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false}) {
    final tokens = <SyntaxToken>[];
    if (text.isEmpty) return tokens;

    int i = 0;
    // 注释 #
    final commentIdx = text.indexOf(' #');
    if (commentIdx >= 0) {
      tokens.add(SyntaxToken(type: TokenType.comment, start: commentIdx + 1, end: text.length));
      text = text.substring(0, commentIdx + 1);
    }
    if (text[0] == '#') {
      tokens.add(SyntaxToken(type: TokenType.comment, start: 0, end: text.length));
      return tokens;
    }

    // Key: value 模式 — 高亮 key
    final colonIdx = text.indexOf(':');
    if (colonIdx > 0) {
      // key 部分
      final keyEnd = colonIdx;
      tokens.add(SyntaxToken(type: TokenType.property, start: 0, end: keyEnd));
      i = colonIdx + 1;

      // 值部分
      while (i < text.length) {
        if (text[i] == '"' || text[i] == "'") {
          final quote = text[i];
          final start = i;
          i++;
          while (i < text.length) {
            if (text[i] == '\\') { i += 2; continue; }
            if (text[i] == quote) { i++; break; }
            i++;
          }
          tokens.add(SyntaxToken(type: TokenType.string, start: start, end: i));
          continue;
        }

        if (isDigit(text[i]) || text[i] == '-') {
          final start = i;
          i++;
          while (i < text.length && (isDigit(text[i]) || text[i] == '.')) i++;
          tokens.add(SyntaxToken(type: TokenType.number, start: start, end: i));
          continue;
        }

        if (isIdentChar(text[i])) {
          final start = i;
          while (i < text.length && isIdentChar(text[i])) i++;
          final word = text.substring(start, i);
          if (keywords.contains(word.toLowerCase())) {
            tokens.add(SyntaxToken(type: TokenType.builtin, start: start, end: i));
          }
          continue;
        }
        i++;
      }
    } else {
      // 列表项或纯文本
      i = 0;
      while (i < text.length) {
        if (text[i] == '"' || text[i] == "'") {
          final start = i; i++;
          while (i < text.length) { if (text[i] == text[start]) { i++; break; } i++; }
          tokens.add(SyntaxToken(type: TokenType.string, start: start, end: i));
          continue;
        }
        i++;
      }
    }

    return tokens;
  }
}
