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

  group('Codex TUI (ratatui alt-screen 光栅重绘)', () {
    late AnsiParser parser;
    setUp(() {
      parser = AnsiParser();
    });

    test('全屏重绘：绝对定位各行内容正确分布（不再压成一行）', () {
      // Codex TUI 每次事件：进 alt screen → 清屏 → 用 \x1b[{r};{c}H 逐行绘制
      final input = [
        '\x1b[?1049h', // 进入 alt screen
        '\x1b[2J', // 清屏
        '\x1b[1;1H介绍一下自己吧',
        '\x1b[2;1H> 怎么回事',
        '\x1b[3;1Hdeepseek-chat default · ~',
      ].join();
      final segments = parser.parse(input);
      expect(segments.length, 1);
      expect(
        segments[0].text,
        '介绍一下自己吧\n> 怎么回事\ndeepseek-chat default · ~',
      );
    });

    test('重复重绘后只保留最后一帧（2J 清屏 + 定位覆盖）', () {
      final input = [
        '\x1b[?1049h',
        '\x1b[2J\x1b[1;1Hframe1-line1',
        '\x1b[2;1Hframe1-line2',
        '\x1b[2J\x1b[1;1Hframe2-only', // 第二次全量重绘
      ].join();
      final segments = parser.parse(input);
      expect(segments[0].text, 'frame2-only');
    });

    test('离开 alt screen 后恢复主屏内容', () {
      final input = [
        'bash-prompt: ', // 主屏内容
        '\x1b[?1049h', // 进入 TUI
        '\x1b[2J\x1b[1;1Htui-line',
        '\x1b[?1049l', // 退出 TUI
        'after-exit',
      ].join();
      final segments = parser.parse(input);
      expect(segments[0].text, 'bash-prompt: after-exit');
    });

    test('绝对定位到较远行会自动补空行', () {
      const input = '\x1b[1;1Ha\x1b[3;1Hc';
      final segments = parser.parse(input);
      expect(segments[0].text, 'a\n\nc');
    });

    test('光标移动 C/D 后继续写入', () {
      const input = '\x1b[1;1HABCD\x1b[1;1H\x1b[2CXY';
      // 定位行首 → 右移 2 列 → 写 XY → 覆盖 C、D
      final segments = parser.parse(input);
      expect(segments[0].text, 'ABXY');
    });

    test('底部状态栏与输入行共存（典型 Codex 屏）', () {
      final input = [
        '\x1b[?1049h',
        '\x1b[2J',
        '\x1b[1;1H你：介绍一下自己吧',
        '\x1b[2;1H我是 Codex，很高兴认识你！',
        '\x1b[3;1H─────────────────────────────',
        '\x1b[4;1H> ',
        '\x1b[4;3Hdeepseek-chat default · ~',
      ].join();
      final segments = parser.parse(input, cols: 30);
      expect(segments[0].text.split('\n').length, 4);
      expect(segments[0].text, contains('你：介绍一下自己吧'));
      expect(segments[0].text, contains('deepseek-chat default · ~'));
      expect(segments[0].text.split('\n').last, '> deepseek-chat default · ~');
    });

    test('cols 限制：超宽行被截断', () {
      const input = '\x1b[1;1H123456789';
      final segments = parser.parse(input, cols: 5);
      expect(segments[0].text, '12345');
    });
    test('回归: TUI 先定位后清行(1;2H + 1K) 空行不抛 RangeError', () {
      // Codex TUI 重绘典型序列：进 alt-screen -> 定位 1;2 -> 清光标前
      const input = '\x1b[?1049h\x1b[1;2H\x1b[1K';
      final segments = parser.parse(input, cols: 80);
      // 空行清除后画布仍可用，后续写入正常
      final after = parser.parse('\x1b[?1049h\x1b[1;2H\x1b[1KOK', cols: 80);
      expect(after[0].text, contains('OK'));
      expect(segments, isNotNull);
    });

    test('回归: 空行定位非 0 列后 clearScreen mode 1(1J) 不抛 RangeError', () {
      const input = '\x1b[?1049h\x1b[1;2H\x1b[1J';
      final segments = parser.parse(input, cols: 80);
      final after = parser.parse('\x1b[?1049h\x1b[1;2H\x1b[1JReady', cols: 80);
      expect(after[0].text, contains('Ready'));
      expect(segments, isNotNull);
    });

    test('回归: 已有文本时 clearLine mode 1 清除光标前字符(语义保持)', () {
      // 行首写 ABCDEF，光标定位到 4 列后 1K -> 清掉 ABC，保留 D
      const input = 'ABCDEF\x1b[1;4H\x1b[1K';
      final segments = parser.parse(input, cols: 80);
      expect(segments[0].text, 'DEF');
    });

    test('回归: 已有文本时 clearScreen mode 1 清光标前及之前所有行', () {
      // 两行内容，光标在 2;4(第4列)，1J -> 删当前行前3字符并丢弃之前所有行
      const input = 'line1\nline2XY\x1b[2;4H\x1b[1J';
      final segments = parser.parse(input, cols: 80);
      expect(segments[0].text, 'e2XY');
    });

    test('回归: 纯文本命令回显不触发(echo hello / printf / cyo --zh)', () {
      final e1 = parser.parse('echo hello\n', cols: 80);
      final e2 = parser.parse("printf 'hello\\n'\n", cols: 80);
      final e3 = parser.parse('cyo --zh\r\n', cols: 80);
      expect(e1[0].text, contains('echo hello'));
      expect(e2, isNotEmpty);
      expect(e3, isNotEmpty);
    });
  });
}
