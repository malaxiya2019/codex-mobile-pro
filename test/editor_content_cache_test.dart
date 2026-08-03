import 'package:codex_mobile_pro/features/editor/models/editor_models.dart';
import 'package:codex_mobile_pro/features/editor/services/editor_buffer.dart';
import 'package:codex_mobile_pro/features/editor/syntax/syntax_highlighter.dart';
import 'package:codex_mobile_pro/features/editor/syntax/syntax_registry.dart';
import 'package:codex_mobile_pro/features/editor/widgets/editor_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 计数高亮器：统计 highlightLine 调用次数并记录 isFirstLine 参数
class _CountingHighlighter extends SyntaxHighlighter {
  int highlightCalls = 0;
  final List<bool> isFirstLineSeen = [];

  @override
  FileLanguage get language => FileLanguage.dart;

  @override
  List<SyntaxToken> highlightLine(String text, {bool isFirstLine = false}) {
    highlightCalls++;
    isFirstLineSeen.add(isFirstLine);
    // 返回一个简单的 plain token（覆盖整行），保证调用方逻辑与真实高亮器一致
    return [SyntaxToken(type: TokenType.plain, start: 0, end: text.length)];
  }

  @override
  Color getColorForToken(TokenType type, {bool isDark = true}) =>
      const Color(0xFF000000);
}

void main() {
  group('EditorContent 语法高亮缓存', () {
    late _CountingHighlighter counter;
    late SyntaxHighlighter? original;

    setUp(() {
      counter = _CountingHighlighter();
      original = SyntaxRegistry.getHighlighter(FileLanguage.dart);
      SyntaxRegistry.register(FileLanguage.dart, counter);
    });

    tearDown(() {
      if (original != null) {
        SyntaxRegistry.register(FileLanguage.dart, original!);
      }
    });

    Widget buildEditor({required List<String> lines}) {
      return MaterialApp(
        home: Scaffold(
          body: EditorContent(
            buffer: EditorBuffer(
              filePath: '/tmp/cache_test.dart',
              initialContent: lines,
            ),
            settings: EditorSettings(),
          ),
        ),
      );
    }

    testWidgets('同一行文本重复 build 只 tokenize 一次（缓存命中）', (tester) async {
      const lines = ['void main() {', '  print("hi");', '}'];
      await tester.pumpWidget(buildEditor(lines: lines));
      final firstCalls = counter.highlightCalls;
      expect(firstCalls, lines.length, reason: '初始 build 每行各 tokenize 一次');

      // 重新 pump 相同内容的 EditorContent → state 保留 → build 重跑 → 全部命中缓存
      await tester.pumpWidget(buildEditor(lines: lines));
      expect(counter.highlightCalls, firstCalls,
          reason: '相同行文本再次 build 应命中缓存，不再重复 tokenize');
    });

    testWidgets('首行与后续行文本相同仍分别 tokenize（isFirstLine 参与缓存 key）',
        (tester) async {
      // 第 0 行与第 1 行文本相同：isFirstLine 不同 → 缓存 key 不同 → 各 tokenize 一次
      const lines = ['def foo():', 'def foo():', '    return 1'];
      await tester.pumpWidget(buildEditor(lines: lines));
      expect(counter.highlightCalls, lines.length);

      // 第一行应标记 isFirstLine=true，其余行 false
      expect(counter.isFirstLineSeen[0], isTrue);
      expect(counter.isFirstLineSeen[1], isFalse);

      // 再 pump：两处相同文本因 isFirstLine 不同各自命中缓存，计数不增长
      await tester.pumpWidget(buildEditor(lines: lines));
      expect(counter.highlightCalls, lines.length);
    });

    testWidgets('文本变更后重新 tokenize（缓存失效）', (tester) async {
      await tester.pumpWidget(buildEditor(lines: ['var a = 1;']));
      expect(counter.highlightCalls, 1);

      // 行内容变化 → key 不同 → 重新 tokenize
      await tester.pumpWidget(buildEditor(lines: ['var b = 2;']));
      expect(counter.highlightCalls, 2);
    });
  });
}
