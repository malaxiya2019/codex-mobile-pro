import 'syntax_highlighter.dart';
import '../models/editor_models.dart';

class TomlHighlighter extends BaseHighlighter {
  @override
  FileLanguage get language => FileLanguage.toml;

  @override
  Set<String> get keywords => {'true', 'false', 'inf', 'nan'};

  @override
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false}) {
    final tokens = <SyntaxToken>[];
    if (text.isEmpty) return tokens;

    int i = 0;

    // 注释 #
    if (text.contains('#')) {
      final idx = text.indexOf('#');
      tokens.add(SyntaxToken(type: TokenType.comment, start: idx, end: text.length));
      text = text.substring(0, idx);
    }

    // 表头 [section] 或 [table.key]
    final tableMatch = RegExp(r'^\[{1,2}.+\]{1,2}').matchAsPrefix(text);
    if (tableMatch != null) {
      tokens.add(SyntaxToken(type: TokenType.type, start: tableMatch.start, end: tableMatch.end));
      return tokens;
    }

    // Key = Value
    final eqIdx = text.indexOf('=');
    if (eqIdx > 0) {
      tokens.add(SyntaxToken(type: TokenType.property, start: 0, end: eqIdx));

      i = eqIdx + 1;
      while (i < text.length) {
        if (text[i] == '"' || text[i] == "'") {
          final quote = text[i];
          final start = i; i++;
          while (i < text.length) {
            if (text[i] == '\\') { i += 2; continue; }
            if (text[i] == quote) { i++; break; }
            i++;
          }
          tokens.add(SyntaxToken(type: TokenType.string, start: start, end: i));
          continue;
        }
        if (isDigit(text[i]) || text[i] == '-') {
          final start = i; i++;
          while (i < text.length && (isDigit(text[i]) || text[i] == '.' || text[i] == 'e' || text[i] == 'E' || text[i] == '+' || text[i] == '-')) i++;
          tokens.add(SyntaxToken(type: TokenType.number, start: start, end: i));
          continue;
        }
        if (isIdentChar(text[i])) {
          final start = i; while (i < text.length && isIdentChar(text[i])) i++;
          final word = text.substring(start, i);
          if (keywords.contains(word)) {
            tokens.add(SyntaxToken(type: TokenType.builtin, start: start, end: i));
          }
          continue;
        }
        i++;
      }
    }

    return tokens;
  }
}
