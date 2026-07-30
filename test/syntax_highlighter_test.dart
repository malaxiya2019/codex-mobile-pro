import 'package:codex_mobile_pro/features/editor/models/editor_models.dart';
import 'package:codex_mobile_pro/features/editor/syntax/syntax_highlighter.dart';
import 'package:codex_mobile_pro/features/editor/syntax/syntax_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyntaxRegistry', () {
    test('支持所有语言', () {
      expect(SyntaxRegistry.getHighlighter(FileLanguage.dart), isNotNull);
      expect(SyntaxRegistry.getHighlighter(FileLanguage.rust), isNotNull);
      expect(SyntaxRegistry.getHighlighter(FileLanguage.python), isNotNull);
      expect(SyntaxRegistry.getHighlighter(FileLanguage.json), isNotNull);
      expect(SyntaxRegistry.getHighlighter(FileLanguage.yaml), isNotNull);
      expect(SyntaxRegistry.getHighlighter(FileLanguage.markdown), isNotNull);
      expect(SyntaxRegistry.getHighlighter(FileLanguage.toml), isNotNull);
      expect(SyntaxRegistry.getHighlighter(FileLanguage.shell), isNotNull);
    });

    test('通过文件名获取高亮器', () {
      expect(SyntaxRegistry.forFileName('main.dart'), isNotNull);
      expect(SyntaxRegistry.forFileName('main.rs'), isNotNull);
      expect(SyntaxRegistry.forFileName('main.py'), isNotNull);
      expect(SyntaxRegistry.forFileName('unknown.txt'), isNull);
    });

    test('已注册语言集合', () {
      final langs = SyntaxRegistry.supportedLanguages;
      expect(langs.length, greaterThanOrEqualTo(8));
    });
  });

  group('BaseHighlighter', () {
    test('空文本返回空列表', () {
      final highlighter = SyntaxRegistry.getHighlighter(FileLanguage.dart)!;
      final tokens = highlighter.highlightLine('');
      expect(tokens, isEmpty);
    });

    test('高亮关键字', () {
      final highlighter = SyntaxRegistry.getHighlighter(FileLanguage.dart)!;
      final tokens = highlighter.highlightLine('class Foo {');
      final keywordTokens =
          tokens.where((t) => t.type == TokenType.keyword).toList();
      expect(keywordTokens, isNotEmpty);
      expect(keywordTokens.any((t) =>
          'class Foo {'.substring(t.start, t.end) == 'class'),
          isTrue);
    });

    test('高亮字符串', () {
      final highlighter = SyntaxRegistry.getHighlighter(FileLanguage.dart)!;
      final tokens = highlighter.highlightLine('var s = "hello";');
      final stringTokens =
          tokens.where((t) => t.type == TokenType.string).toList();
      expect(stringTokens, isNotEmpty);
    });

    test('高亮注释', () {
      final highlighter = SyntaxRegistry.getHighlighter(FileLanguage.dart)!;
      final tokens = highlighter.highlightLine('// this is a comment');
      final commentTokens =
          tokens.where((t) => t.type == TokenType.comment).toList();
      expect(commentTokens, isNotEmpty);
    });

    test('获取 Token 颜色', () {
      final highlighter = SyntaxRegistry.getHighlighter(FileLanguage.dart)!;
      final color =
          highlighter.getColorForToken(TokenType.keyword);
      expect(color, isNotNull);

      final lightColor =
          highlighter.getColorForToken(TokenType.keyword, isDark: false);
      expect(lightColor, isNotNull);
    });
  });

  group('DartHighlighter', () {
    test('高亮 Dart 关键字', () {
      final highlighter = SyntaxRegistry.getHighlighter(FileLanguage.dart)!;
      expect(highlighter.keywords.contains('class'), isTrue);
      expect(highlighter.keywords.contains('void'), isTrue);
      expect(highlighter.typeKeywords.contains('Future'), isTrue);
    });
  });

  group('RustHighlighter', () {
    test('高亮 Rust 关键字', () {
      final highlighter = SyntaxRegistry.getHighlighter(FileLanguage.rust)!;
      expect(highlighter.keywords.contains('fn'), isTrue);
      expect(highlighter.keywords.contains('let'), isTrue);
      expect(highlighter.keywords.contains('mut'), isTrue);
    });
  });

  group('PythonHighlighter', () {
    test('高亮 Python 关键字', () {
      final highlighter = SyntaxRegistry.getHighlighter(FileLanguage.python)!;
      expect(highlighter.keywords.contains('def'), isTrue);
      expect(highlighter.keywords.contains('class'), isTrue);
      expect(highlighter.keywords.contains('import'), isTrue);
    });
  });

  group('FileLanguage', () {
    test('从文件名正确推断语言', () {
      expect(FileLanguage.fromFileName('main.dart'), FileLanguage.dart);
      expect(FileLanguage.fromFileName('lib.rs'), FileLanguage.rust);
      expect(FileLanguage.fromFileName('script.py'), FileLanguage.python);
      expect(FileLanguage.fromFileName('data.json'), FileLanguage.json);
      expect(FileLanguage.fromFileName('config.yaml'), FileLanguage.yaml);
      expect(FileLanguage.fromFileName('config.yml'), FileLanguage.yaml);
      expect(FileLanguage.fromFileName('README.md'), FileLanguage.markdown);
      expect(FileLanguage.fromFileName('Cargo.toml'), FileLanguage.toml);
      expect(FileLanguage.fromFileName('build.sh'), FileLanguage.shell);
      expect(FileLanguage.fromFileName('style.css'), FileLanguage.css);
      expect(FileLanguage.fromFileName('index.html'), FileLanguage.html);
      expect(FileLanguage.fromFileName('App.java'), FileLanguage.java);
      expect(FileLanguage.fromFileName('main.cpp'), FileLanguage.cpp);
      expect(FileLanguage.fromFileName('app.ts'), FileLanguage.typescript);
      expect(FileLanguage.fromFileName('app.js'), FileLanguage.javascript);
      expect(FileLanguage.fromFileName('unknown.xyz'), FileLanguage.unknown);
    });
  });
}
