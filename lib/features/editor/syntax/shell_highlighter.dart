import '../models/editor_models.dart';
import 'syntax_highlighter.dart';

class ShellHighlighter extends BaseHighlighter {
  @override
  FileLanguage get language => FileLanguage.shell;

  @override
  Set<String> get keywords => {
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until',
    'do', 'done', 'in', 'case', 'esac', 'select', 'function',
    'return', 'exit', 'break', 'continue', 'declare', 'local',
    'export', 'readonly', 'unset', 'shift', 'source', '.',
    'trap', 'exec', 'eval', 'set', 'unset',
  };

  @override
  Set<String> get builtins => {
    'echo', 'printf', 'read', 'cd', 'pwd', 'ls', 'cat', 'grep',
    'sed', 'awk', 'cut', 'sort', 'uniq', 'wc', 'head', 'tail',
    'find', 'xargs', 'tee', 'tr', 'diff', 'patch', 'chmod',
    'chown', 'cp', 'mv', 'rm', 'mkdir', 'rmdir', 'touch',
    'ln', 'mount', 'umount', 'df', 'du', 'ps', 'kill', 'jobs',
    'fg', 'bg', 'wait', 'sleep', 'test', '[', 'true', 'false',
    'type', 'which', 'command', 'hash', 'alias', 'unalias',
    'bind', 'help', 'let',
  };

  @override
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false}) {
    final tokens = <SyntaxToken>[];
    if (text.isEmpty) return tokens;

    int i = 0;

    // Shebang
    if (isFirstLine && text.startsWith('#!')) {
      tokens.add(SyntaxToken(type: TokenType.comment, start: 0, end: text.length));
      return tokens;
    }

    while (i < text.length) {
      // 注释 #
      if (text[i] == '#') {
        tokens.add(SyntaxToken(type: TokenType.comment, start: i, end: text.length));
        break;
      }

      // 字符串
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

      // 变量 $VAR 或 ${VAR}
      if (text[i] == '\$') {
        final start = i; i++;
        if (i < text.length && text[i] == '{') {
          while (i < text.length && text[i] != '}') {
            i++;
          }
          if (i < text.length) i++;
        } else {
          while (i < text.length && (isIdentChar(text[i]))) {
            i++;
          }
        }
        tokens.add(SyntaxToken(type: TokenType.variable, start: start, end: i));
        continue;
      }

      // 数字
      if (isDigit(text[i])) {
        final start = i; i++;
        while (i < text.length && isDigit(text[i])) {
          i++;
        }
        tokens.add(SyntaxToken(type: TokenType.number, start: start, end: i));
        continue;
      }

      // 标识符
      if (isIdentChar(text[i])) {
        final start = i;
        while (i < text.length && isIdentChar(text[i])) {
          i++;
        }
        final word = text.substring(start, i);

        // 检查是否是命令（行首或管道后）
        final isCommand = start == 0 || (start > 1 && text[start - 1] == '|');

        if (keywords.contains(word)) {
          tokens.add(SyntaxToken(type: TokenType.keyword, start: start, end: i));
        } else if (builtins.contains(word) || isCommand) {
          tokens.add(SyntaxToken(type: TokenType.function, start: start, end: i));
        }
        continue;
      }

      // 重定向操作符
      if (text[i] == '>' || text[i] == '<' || text[i] == '|' || text[i] == '&') {
        final start = i; i++;
        while (i < text.length && (text[i] == '>' || text[i] == '<' || text[i] == '|' || text[i] == '&')) {
          i++;
        }
        tokens.add(SyntaxToken(type: TokenType.operator, start: start, end: i));
        continue;
      }

      i++;
    }

    return tokens;
  }
}
