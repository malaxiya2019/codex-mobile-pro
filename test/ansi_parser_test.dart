import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/terminal/services/ansi_parser.dart';

void main() {
  group('AnsiParser', () {
    late AnsiParser parser;

    setUp(() {
      parser = AnsiParser();
    });

    test('解析纯文本（无 ANSI 序列）', () {
      final segments = parser.parse('Hello World');
      expect(segments.length, 1);
      expect(segments[0].text, 'Hello World');
      expect(segments[0].foreground, isNull);
      expect(segments[0].bold, false);
    });

    test('解析空字符串', () {
      final segments = parser.parse('');
      expect(segments, isEmpty);
    });

    test('解析绿色文本 \\x1b[32m', () {
      final segments = parser.parse('\x1b[32mGreen Text\x1b[0m');
      expect(segments.length, 2);

      expect(segments[0].text, 'Green Text');
      expect(segments[0].foreground, isNotNull);
      expect(segments[0].bold, false);

      expect(segments[1].text, '');
      // Reset 后应该是默认色
    });

    test('解析粗体 + 红色', () {
      final segments = parser.parse('\x1b[1;31mBold Red\x1b[0m');
      expect(segments.length, 2);
      expect(segments[0].text, 'Bold Red');
      expect(segments[0].bold, true);
    });

    test('解析多段 ANSI', () {
      final segments = parser.parse(
        '\x1b[32mGreen\x1b[0m Normal \x1b[31mRed\x1b[0m',
      );
      // segments: [Green, , Normal , , Red, ]
      expect(segments.length, greaterThanOrEqualTo(4));
      expect(segments[0].text, 'Green');
      expect(segments[2].text, ' Normal ');
      expect(segments[4].text, 'Red');
    });

    test('解析黄色背景', () {
      final segments = parser.parse('\x1b[43mYellow BG\x1b[0m');
      expect(segments[0].background, isNotNull);
    });

    test('解析亮色前景', () {
      final segments = parser.parse('\x1b[91mBright Red\x1b[0m');
      expect(segments[0].foreground, isNotNull);
    });

    test('忽略光标移动序列', () {
      // CSI 光标移动不应产生额外段
      final segments = parser.parse('Hello\x1b[2JWorld');
      expect(segments.length, 1);
      expect(segments[0].text, 'HelloWorld');
    });

    test('处理下划线样式', () {
      final segments = parser.parse('\x1b[4mUnderline\x1b[0m');
      expect(segments[0].underline, true);
    });

    test('处理反色样式', () {
      final segments = parser.parse('\x1b[7mReversed\x1b[0m');
      expect(segments[0].reversed, true);
    });

    test('处理删除线样式', () {
      final segments = parser.parse('\x1b[9mStrikethrough\x1b[0m');
      expect(segments[0].strikethrough, true);
    });

    test('处理连续 SGR 参数', () {
      final segments = parser.parse('\x1b[1;3;4;31mBold Italic Underline Red\x1b[0m');
      expect(segments[0].bold, true);
      expect(segments[0].italic, true);
      expect(segments[0].underline, true);
    });

    test('处理 \\r 回车符', () {
      final segments = parser.parse('Line1\rLine2');
      // \r 应被忽略
      expect(segments.length, 1);
    });

    test('处理 \\b 退格符', () {
      final segments = parser.parse('Hell\bo');
      expect(segments.length, 1);
      expect(segments[0].text, 'Hello');
    });

    test('处理 OSC 序列（如设置标题）', () {
      // OSC: ESC ] 0; title \x07
      final segments = parser.parse('\x1b]0;My Terminal Title\x07Hello');
      expect(segments.length, 1);
      expect(segments[0].text, 'Hello');
    });

    test('256 色前景 (38;5;N)', () {
      final segments = parser.parse('\x1b[38;5;82m256 Color\x1b[0m');
      expect(segments[0].foreground, isNotNull);
    });

    test('AnsiSegment.toTextStyle 返回有效的 TextStyle', () {
      final segment = const AnsiSegment(
        text: 'Test',
        foreground: Color(0xFF00FF00),
        bold: true,
      );
      final style = segment.toTextStyle();
      expect(style.fontWeight, FontWeight.bold);
      expect(style.color, const Color(0xFF00FF00));
      expect(style.fontFamily, 'monospace');
    });

    test('处理设置/重置下划线 (24)', () {
      final segments = parser.parse('\x1b[4mUnderline\x1b[24mNo Underline');
      expect(segments[0].underline, true);
      expect(segments[1].underline, false);
    });
  });
}
