import 'syntax_highlighter.dart';
import '../models/editor_models.dart';

class PythonHighlighter extends BaseHighlighter {
  @override
  FileLanguage get language => FileLanguage.python;

  @override
  Set<String> get keywords => {
    'False', 'None', 'True', 'and', 'as', 'assert', 'async',
    'await', 'break', 'class', 'continue', 'def', 'del', 'elif',
    'else', 'except', 'finally', 'for', 'from', 'global', 'if',
    'import', 'in', 'is', 'lambda', 'nonlocal', 'not', 'or',
    'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
  };

  @override
  Set<String> get typeKeywords => {
    'int', 'float', 'bool', 'str', 'bytes', 'list', 'dict',
    'tuple', 'set', 'frozenset', 'NoneType', 'Any', 'Optional',
    'Union', 'List', 'Dict', 'Tuple', 'Set', 'Callable',
    'Iterator', 'Iterable', 'Generator', 'Type',
  };

  @override
  Set<String> get builtins => {
    'print', 'len', 'range', 'map', 'filter', 'zip', 'enumerate',
    'sorted', 'reversed', 'type', 'isinstance', 'issubclass',
    'hasattr', 'getattr', 'setattr', 'open', 'super', 'classmethod',
    'staticmethod', 'property', 'abstractmethod',
    'self', 'cls',
  };

  @override
  String get commentPrefix => '#';

  @override
  bool get supportsMultiLineComment => false;

  @override
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false}) {
    final tokens = <SyntaxToken>[];
    if (text.isEmpty) return tokens;

    int i = 0;
    while (i < text.length) {
      // 字符串
      if (text[i] == '"' || text[i] == "'") {
        final quote = text[i];
        // 检查三引号
        final isTriple = i + 2 < text.length &&
            text[i] == text[i + 1] && text[i] == text[i + 2];
        final start = i;
        if (isTriple) {
          i += 3;
          while (i + 2 < text.length) {
            if (text[i] == quote && text[i + 1] == quote && text[i + 2] == quote) {
              i += 3;
              break;
            }
            if (text[i] == '\\') i += 2;
            else i++;
          }
          if (i + 2 >= text.length) i = text.length;
        } else {
          i++;
          while (i < text.length) {
            if (text[i] == '\\') { i += 2; continue; }
            if (text[i] == quote) { i++; break; }
            i++;
          }
        }
        tokens.add(SyntaxToken(type: TokenType.string, start: start, end: i));
        continue;
      }

      // f-string 前缀
      if ((text[i] == 'f' || text[i] == 'F' || text[i] == 'r' || text[i] == 'b' || text[i] == 'u') &&
          i + 1 < text.length && (text[i + 1] == '"' || text[i + 1] == "'")) {
        // final start = i; // kept for clarity
        i++;
        continue;
      }

      // 注释 #
      if (text[i] == '#') {
        tokens.add(SyntaxToken(type: TokenType.comment, start: i, end: text.length));
        break;
      }

      // 数字
      if (isDigit(text[i]) || (text[i] == '.' && i + 1 < text.length && isDigit(text[i + 1]))) {
        final start = i;
        i++;
        while (i < text.length && (
            isDigit(text[i]) || text[i] == '.' || text[i] == 'x' || text[i] == 'X' ||
            text[i] == 'o' || text[i] == 'O' || text[i] == 'b' || text[i] == 'B' ||
            text[i] == 'e' || text[i] == 'E' || text[i] == '_' ||
            (text[i].compareTo('a') >= 0 && text[i].compareTo('f') <= 0) || (text[i].compareTo('A') >= 0 && text[i].compareTo('F') <= 0))) {
          i++;
        }
        tokens.add(SyntaxToken(type: TokenType.number, start: start, end: i));
        continue;
      }

      // 标识符
      if (isIdentChar(text[i])) {
        final idTokens = tokenizeIdentifier(text, i, keywords, typeKeywords, builtins);
        tokens.addAll(idTokens);
        i = tokens.last.end;
        continue;
      }

      i++;
    }

    return tokens;
  }
}
