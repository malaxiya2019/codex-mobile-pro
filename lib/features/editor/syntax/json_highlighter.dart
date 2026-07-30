import '../models/editor_models.dart';
import 'syntax_highlighter.dart';

class JsonHighlighter extends BaseHighlighter {
  @override
  FileLanguage get language => FileLanguage.json;

  @override
  Set<String> get keywords => {'true', 'false', 'null'};

  @override
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false}) {
    final tokens = <SyntaxToken>[];
    if (text.isEmpty) return tokens;

    int i = 0;
    while (i < text.length) {
      // 字符串键或值
      if (text[i] == '"') {
        final start = i;
        i++;
        while (i < text.length) {
          if (text[i] == '\\') { i += 2; continue; }
          if (text[i] == '"') { i++; break; }
          i++;
        }
        tokens.add(SyntaxToken(type: TokenType.string, start: start, end: i));
        continue;
      }

      // 数字
      if (isDigit(text[i]) || text[i] == '-') {
        final start = i;
        i++;
        while (i < text.length && (isDigit(text[i]) || text[i] == '.' || text[i] == 'e' || text[i] == 'E' || text[i] == '+' || text[i] == '-')) {
          i++;
        }
        tokens.add(SyntaxToken(type: TokenType.number, start: start, end: i));
        continue;
      }

      // 关键字 true/false/null
      if (isIdentChar(text[i])) {
        final start = i;
        while (i < text.length && isIdentChar(text[i])) {
          i++;
        }
        final word = text.substring(start, i);
        if (keywords.contains(word)) {
          tokens.add(SyntaxToken(type: TokenType.builtin, start: start, end: i));
        }
        continue;
      }

      i++;
    }
    return tokens;
  }
}
