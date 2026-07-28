import 'package:flutter/material.dart';
import '../models/editor_models.dart';

/// 语法高亮 Token 类型
enum TokenType {
  keyword, string, comment, number,
  type, function, className, punctuation,
  operator, builtin, constant, annotation,
  variable, property, plain,
}

/// 语法 Token
class SyntaxToken {
  final TokenType type;
  final int start;
  final int end;

  const SyntaxToken({required this.type, required this.start, required this.end});
  int get length => end - start;
}

/// 语法高亮器接口
abstract class SyntaxHighlighter {
  FileLanguage get language;

  /// 对一行文本进行语法高亮分析
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false});

  /// 获取 Token 对应的颜色
  Color getColorForToken(TokenType type, {bool isDark = true});

  /// 获取关键字列表
  Set<String> get keywords => {};

  /// 获取类型关键字
  Set<String> get typeKeywords => {};

  /// 获取内置函数/对象
  Set<String> get builtins => {};

  /// 获取注释前缀
  String get commentPrefix => '//';

  /// 是否支持多行注释
  bool get supportsMultiLineComment => false;

  /// 多行注释开始
  String get multiLineCommentStart => '/*';

  /// 多行注释结束
  String get multiLineCommentEnd => '*/';
}

/// 基础高亮器 — 通用颜色方案
abstract class BaseHighlighter extends SyntaxHighlighter {
  @override
  Color getColorForToken(TokenType type, {bool isDark = true}) {
    switch (type) {
      case TokenType.keyword:
        return isDark ? const Color(0xFFCC7832) : const Color(0xFF7F0055);
      case TokenType.string:
        return isDark ? const Color(0xFF6A8759) : const Color(0xFF2A00FF);
      case TokenType.comment:
        return isDark ? const Color(0xFF808080) : const Color(0xFF3F7F5F);
      case TokenType.number:
        return isDark ? const Color(0xFF6897BB) : const Color(0xFF0000FF);
      case TokenType.type:
        return isDark ? const Color(0xFFFFC66D) : const Color(0xFF000080);
      case TokenType.function:
        return isDark ? const Color(0xFFFFC66D) : const Color(0xFF795E26);
      case TokenType.className:
        return isDark ? const Color(0xFFFFC66D) : const Color(0xFF267F99);
      case TokenType.punctuation:
        return isDark ? const Color(0xFFA9B7C6) : const Color(0xFF000000);
      case TokenType.operator:
        return isDark ? const Color(0xFFA9B7C6) : const Color(0xFF000000);
      case TokenType.builtin:
        return isDark ? const Color(0xFF9876AA) : const Color(0xFF0000FF);
      case TokenType.constant:
        return isDark ? const Color(0xFF9876AA) : const Color(0xFF0000FF);
      case TokenType.annotation:
        return isDark ? const Color(0xFFBBB529) : const Color(0xFF808080);
      case TokenType.variable:
        return isDark ? const Color(0xFFA9B7C6) : const Color(0xFF000000);
      case TokenType.property:
        return isDark ? const Color(0xFF6C9EF8) : const Color(0xFF0000FF);
      case TokenType.plain:
        return isDark ? const Color(0xFFA9B7C6) : const Color(0xFF000000);
    }
  }

  /// 辅助：解析标识符
  List<SyntaxToken> tokenizeIdentifier(
    String text, int start,
    Set<String> keywords,
    Set<String> types,
    Set<String> builtins,
  ) {
    final tokens = <SyntaxToken>[];
    int i = start;
    while (i < text.length && (isIdentChar(text[i]))) {
      i++;
    }

    if (i > start) {
      final word = text.substring(start, i);
      TokenType type;
      if (keywords.contains(word)) {
        type = TokenType.keyword;
      } else if (types.contains(word)) {
        type = TokenType.type;
      } else if (builtins.contains(word)) {
        type = TokenType.builtin;
      } else if (start > 0 && text[start - 1] == '.') {
        type = TokenType.property;
      } else {
        // 检查是否可能是函数调用
        if (i < text.length && text[i] == '(') {
          type = TokenType.function;
        } else if (word.isNotEmpty &&
            word[0] == word[0].toUpperCase() &&
            word[0] != word[0].toLowerCase()) {
          type = TokenType.className;
        } else {
          type = TokenType.plain;
        }
      }
      tokens.add(SyntaxToken(type: type, start: start, end: i));
    }
    return tokens;
  }

  bool isIdentChar(String ch) {
    return RegExp(r'[a-zA-Z0-9_]').hasMatch(ch);
  }

  bool isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  @override
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false}) {
    final tokens = <SyntaxToken>[];
    if (text.isEmpty) return tokens;

    int i = 0;
    while (i < text.length) {
      // 字符串
      if (text[i] == '"' || text[i] == "'" || text[i] == '`') {
        final quote = text[i];
        final start = i;
        i++;
        while (i < text.length) {
          if (text[i] == '\\') {
            i += 2;
            continue;
          }
          if (text[i] == quote) {
            i++;
            break;
          }
          i++;
        }
        tokens.add(SyntaxToken(type: TokenType.string, start: start, end: i));
        continue;
      }

      // 注释 //
      if (i + 1 < text.length && text[i] == '/' && text[i + 1] == '/') {
        tokens.add(SyntaxToken(
          type: TokenType.comment,
          start: i,
          end: text.length,
        ));
        break;
      }

      // 多行注释 /* */
      if (i + 1 < text.length && text[i] == '/' && text[i + 1] == '*') {
        final start = i;
        i += 2;
        while (i + 1 < text.length) {
          if (text[i] == '*' && text[i + 1] == '/') {
            i += 2;
            break;
          }
          i++;
        }
        tokens.add(SyntaxToken(
          type: TokenType.comment,
          start: start,
          end: i,
        ));
        continue;
      }

      // 数字
      if (isDigit(text[i]) || (text[i] == '.' && i + 1 < text.length && isDigit(text[i + 1]))) {
        final start = i;
        i++;
        while (i < text.length && (isDigit(text[i]) || text[i] == '.' || text[i] == 'x' || text[i] == 'X' ||
            (text[i].compareTo('a') >= 0 && text[i].compareTo('f') <= 0) || (text[i].compareTo('A') >= 0 && text[i].compareTo('F') <= 0))) {
          i++;
        }
        tokens.add(SyntaxToken(type: TokenType.number, start: start, end: i));
        continue;
      }

      // 标识符
      if (isIdentChar(text[i])) {
        tokens.addAll(tokenizeIdentifier(text, i, keywords, typeKeywords, builtins));
        final last = tokens.last;
        i = last.end;
        continue;
      }

      i++;
    }

    return tokens;
  }
}
