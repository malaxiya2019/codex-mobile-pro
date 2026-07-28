/// ANSI 转义序列解析器
///
/// 将终端输出的 ANSI 转义码转换为可渲染的文本段。
/// 支持标准 SGR (Select Graphic Rendition) 参数：
/// - 颜色：30-37（前景），40-47（背景），90-97（亮色前景），100-107（亮色背景）
/// - 样式：0（重置），1（粗体），3（斜体），4（下划线），7（反色），9（删除线）
/// - 256 色：38;5;N（前景），48;5;N（背景）
///
/// 使用方式：
/// ```dart
/// final parser = AnsiParser();
/// final segments = parser.parse('\x1b[32mHello\x1b[0m World');
/// // segments: [{text: 'Hello', fg: Colors.green}, {text: ' World', fg: default}]
/// ```

import 'package:flutter/material.dart';

/// ANSI 文本段
class AnsiSegment {
  final String text;
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool reversed;

  const AnsiSegment({
    required this.text,
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.reversed = false,
  });

  TextStyle toTextStyle() {
    return TextStyle(
      color: foreground ?? Colors.greenAccent,
      backgroundColor: background,
      fontWeight: bold ? FontWeight.bold : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: TextDecoration.combine([
        if (underline) TextDecoration.underline,
        if (strikethrough) TextDecoration.lineThrough,
      ]),
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.5,
    );
  }
}

/// ANSI 解析器
class AnsiParser {
  // ANSI 颜色映射 — 标准 16 色
  static const Map<int, Color> _ansiColors = {
    30: Color(0xFF000000), // Black
    31: Color(0xFFCC0000), // Red
    32: Color(0xFF00CC00), // Green
    33: Color(0xFFCCCC00), // Yellow
    34: Color(0xFF0000CC), // Blue
    35: Color(0xFFCC00CC), // Magenta
    36: Color(0xFF00CCCC), // Cyan
    37: Color(0xFFCCCCCC), // White
    90: Color(0xFF666666), // Bright Black (Gray)
    91: Color(0xFFFF0000), // Bright Red
    92: Color(0xFF00FF00), // Bright Green
    93: Color(0xFFFFFF00), // Bright Yellow
    94: Color(0xFF6666FF), // Bright Blue
    95: Color(0xFFFF00FF), // Bright Magenta
    96: Color(0xFF00FFFF), // Bright Cyan
    97: Color(0xFFFFFFFF), // Bright White
  };

  // 256 色面板（前 16 匹配标准色，216 色 6x6x6 立方体，24 阶灰度）
  static Color _get256Color(int code) {
    if (code < 16) {
      // 标准 16 色
      return _ansiColors[code + 30] ?? const Color(0xFFCCCCCC);
    } else if (code < 232) {
      // 216 色彩色立方体 (6x6x6)
      code -= 16;
      final r = (code ~/ 36) % 6;
      final g = (code ~/ 6) % 6;
      final b = code % 6;
      final ri = (r == 0) ? 0 : (r * 40 + 55);
      final gi = (g == 0) ? 0 : (g * 40 + 55);
      final bi = (b == 0) ? 0 : (b * 40 + 55);
      return Color.fromARGB(255, ri, gi, bi);
    } else {
      // 24 阶灰度
      final gray = (code - 232) * 10 + 8;
      return Color.fromARGB(255, gray, gray, gray);
    }
  }

  /// 解析 ANSI 转义序列，返回文本段列表
  List<AnsiSegment> parse(String input) {
    if (input.isEmpty) return [];

    final segments = <AnsiSegment>[];
    final buffer = StringBuffer();
    bool inEscape = false;
    bool inOsc = false; // Operating System Command
    final params = StringBuffer();

    Color? currentFg;
    Color? currentBg;
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strikethrough = false;
    bool reversed = false;

    void flushBuffer() {
      if (buffer.isNotEmpty) {
        segments.add(AnsiSegment(
          text: buffer.toString(),
          foreground: currentFg,
          background: currentBg,
          bold: bold,
          italic: italic,
          underline: underline,
          strikethrough: strikethrough,
          reversed: reversed,
        ));
        buffer.clear();
      }
    }

    void resetAttributes() {
      currentFg = null;
      currentBg = null;
      bold = false;
      italic = false;
      underline = false;
      strikethrough = false;
      reversed = false;
    }

    void applySgr(List<int> codes) {
      if (codes.isEmpty) {
        codes = [0];
      }

      int i = 0;
      while (i < codes.length) {
        switch (codes[i]) {
          case 0:
            resetAttributes();
            break;
          case 1:
            bold = true;
            break;
          case 3:
            italic = true;
            break;
          case 4:
            underline = true;
            break;
          case 7:
            reversed = true;
            break;
          case 9:
            strikethrough = true;
            break;
          case 22:
            bold = false;
            break;
          case 23:
            italic = false;
            break;
          case 24:
            underline = false;
            break;
          case 27:
            reversed = false;
            break;
          case 29:
            strikethrough = false;
            break;
          case 30:
          case 31:
          case 32:
          case 33:
          case 34:
          case 35:
          case 36:
          case 37:
            currentFg = _ansiColors[codes[i]];
            break;
          case 38:
            // 38;5;N — 256 色前景
            if (i + 2 < codes.length && codes[i + 1] == 5) {
              currentFg = _get256Color(codes[i + 2]);
              i += 2;
            }
            // 38;2;R;G;B — TrueColor 前景
            else if (i + 4 < codes.length && codes[i + 1] == 2) {
              currentFg = Color.fromARGB(255, codes[i + 2], codes[i + 3], codes[i + 4]);
              i += 4;
            }
            break;
          case 39:
            currentFg = null;
            break;
          case 40:
          case 41:
          case 42:
          case 43:
          case 44:
          case 45:
          case 46:
          case 47:
            currentBg = _ansiColors[codes[i] - 10];
            break;
          case 48:
            // 48;5;N — 256 色背景
            if (i + 2 < codes.length && codes[i + 1] == 5) {
              currentBg = _get256Color(codes[i + 2]);
              i += 2;
            }
            // 48;2;R;G;B — TrueColor 背景
            else if (i + 4 < codes.length && codes[i + 1] == 2) {
              currentBg = Color.fromARGB(255, codes[i + 2], codes[i + 3], codes[i + 4]);
              i += 4;
            }
            break;
          case 49:
            currentBg = null;
            break;
          case 90:
          case 91:
          case 92:
          case 93:
          case 94:
          case 95:
          case 96:
          case 97:
            currentFg = _ansiColors[codes[i]];
            break;
          case 100:
          case 101:
          case 102:
          case 103:
          case 104:
          case 105:
          case 106:
          case 107:
            currentBg = _ansiColors[codes[i] - 60];
            break;
        }
        i++;
      }
    }

    for (int i = 0; i < input.length; i++) {
      final ch = input[i];

      if (inOsc) {
        // OSC 序列：ESC ] ... BEL(\x07) 或 ST(\x1b\\)
        if (ch == '\x07' || (ch == '\x1b' && i + 1 < input.length && input[i + 1] == '\\')) {
          inOsc = false;
          if (ch == '\x1b') i++; // 跳过 '\\'
        }
        continue;
      }

      if (inEscape) {
        if (ch == '[') {
          // CSI (Control Sequence Introducer): ESC [
          params.clear();
          inEscape = false;
          // 读取参数
          int j = i + 1;
          while (j < input.length) {
            final c = input[j];
            if ((c >= '0' && c <= '9') || c == ';' || c == ':') {
              params.write(c);
              j++;
            } else if (c == 'm') {
              // SGR 结束
              if (params.isNotEmpty) {
                final codes = params.toString().split(';').map((p) {
                  final v = int.tryParse(p);
                  return v ?? 0;
                }).toList();
                applySgr(codes);
              } else {
                applySgr([0]);
              }
              i = j; // 跳过 'm'
              break;
            } else if (c == 'H' || c == 'f' || c == 'A' || c == 'B' ||
                       c == 'C' || c == 'D' || c == 'J' || c == 'K' ||
                       c == 's' || c == 'u' || c == 'h' || c == 'l') {
              // 其他 CSI 序列 — 忽略光标移动等
              i = j;
              break;
            } else if (c == '?') {
              // DEC private sequences (like ?25h)
              j++;
              continue;
            } else {
              // 未知结束符
              i = j;
              break;
            }
          }
        } else if (ch == ']') {
          // OSC 序列开始
          inOsc = true;
          inEscape = false;
        } else {
          // 单字符转义（如 \x1b=, \x1b> 等）
          inEscape = false;
        }
        continue;
      }

      if (ch == '\x1b') {
        flushBuffer();
        inEscape = true;
        continue;
      }

      if (ch == '\r') {
        // 回车符 — 忽略或重置
        continue;
      }

      if (ch == '\b') {
        // 退格 — 简单处理
        if (buffer.isNotEmpty) {
          final str = buffer.toString();
          buffer.clear();
          buffer.write(str.substring(0, str.length - 1));
        }
        continue;
      }

      buffer.write(ch);
    }

    flushBuffer();

    return segments;
  }
}
