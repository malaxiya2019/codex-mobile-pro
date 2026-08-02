import 'dart:ui' show Color, FontWeight;

import 'package:codex_mobile_pro/features/terminal/services/ansi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

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
      // \x1b[0m 重置后无文本，不产生空段
      expect(segments.length, 1);
      expect(segments[0].text, 'Green Text');
      expect(segments[0].foreground, isNotNull);
      expect(segments[0].bold, false);
    });

    test('解析粗体 + 红色', () {
      final segments = parser.parse('\x1b[1;31mBold Red\x1b[0m');
      // \x1b[0m 重置后无文本，不产生空段
      expect(segments.length, 1);
      expect(segments[0].text, 'Bold Red');
      expect(segments[0].bold, true);
    });

    test('解析多段 ANSI', () {
      final segments = parser.parse(
        '\x1b[32mGreen\x1b[0m Normal \x1b[31mRed\x1b[0m',
      );
      // segments: [Green,  Normal , Red]
      expect(segments.length, 3);
      expect(segments[0].text, 'Green');
      expect(segments[1].text, ' Normal ');
      expect(segments[2].text, 'Red');
    });

    test('解析黄色背景', () {
      final segments = parser.parse('\x1b[43mYellow BG\x1b[0m');
      expect(segments[0].background, isNotNull);
    });

    test('解析亮色前景', () {
      final segments = parser.parse('\x1b[91mBright Red\x1b[0m');
      expect(segments[0].foreground, isNotNull);
    });

    test('清屏序列 (2J) 清除已输出文本', () {
      final segments = parser.parse('Hello\x1b[2JWorld');
      expect(segments.length, 1);
      expect(segments[0].text, 'World');
    });

    test('清屏 + 光标回行首 (2J H) 重绘 prompt', () {
      final segments = parser.parse(
        'Hello\x1b[2J\x1b[Hroot@localhost:/# ',
      );
      expect(segments.length, 1);
      expect(segments[0].text, 'root@localhost:/# ');
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

    test('处理 \\r 回车符（覆盖当前行）', () {
      final segments = parser.parse('Line1\rLine2');
      // \r 回行首，Line2 覆盖 Line1
      expect(segments.length, 1);
      expect(segments[0].text, 'Line2');
    });

    test('\\r 覆盖当前行部分文本', () {
      final segments = parser.parse('abcdef\rXY');
      expect(segments[0].text, 'XYcdef');
    });

    test('进度条同位置刷新（\\r + 覆盖）', () {
      final segments = parser.parse('10%\r20%\r30%');
      expect(segments[0].text, '30%');
    });

    test('bash resize 重绘序列只保留一行 prompt（核心修复）', () {
      // bash 收到 SIGWINCH 后输出 \r\x1b[K\r<prompt> 重绘当前行，
      // 历史上被错误展开为多行堆叠的 root@localhost:/#
      const prompt = 'root@localhost:/# ';
      final segments = parser.parse(
        '$prompt\r\x1b[K\r$prompt\r\x1b[K\r$prompt',
      );
      expect(segments.length, 1);
      expect(segments[0].text, prompt);
    });

    test('命令执行后重绘（长行变短，\x1b[K 清除残留）', () {
      final segments = parser.parse(
        'root@localhost:/# ls -la\r\x1b[K\rroot@localhost:/# ',
      );
      expect(segments[0].text, 'root@localhost:/# ');
    });

    test('处理 \\r\\n 双行', () {
      final segments = parser.parse('a\r\nb');
      expect(segments.length, 1);
      expect(segments[0].text, 'a\nb');
    });

    test('处理多行文本（保留 \\n）', () {
      final segments = parser.parse('line1\nline2');
      expect(segments.length, 1);
      expect(segments[0].text, 'line1\nline2');
    });

    test('处理 2K 清除整行', () {
      final segments = parser.parse('abc\x1b[2Kdef');
      expect(segments[0].text, 'def');
    });

    test('覆盖时样式跟随新字符', () {
      final segments = parser.parse('\x1b[32mABCDE\x1b[0m\rXY');
      // X、Y 以普通样式覆盖 A、B；C、D、E 仍是绿色
      expect(segments.length, 2);
      expect(segments[0].text, 'XY');
      expect(segments[0].foreground, isNull);
      expect(segments[1].text, 'CDE');
      expect(segments[1].foreground, isNotNull);
    });

    test('处理 \\b 退格符', () {
      // Hell + \b(删掉最后一个l) + o = Helo
      final segments = parser.parse('Hell\bo');
      expect(segments.length, 1);
      expect(segments[0].text, 'Helo');
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
      const segment = AnsiSegment(
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
