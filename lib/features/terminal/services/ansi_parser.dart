/// ANSI 转义序列解析器（画布/网格模型）
///
/// 将终端输出的 ANSI 转义码转换为可渲染的文本段。
/// 支持标准 SGR (Select Graphic Rendition) 参数：
/// - 颜色：30-37（前景），40-47（背景），90-97（亮色前景），100-107（亮色背景）
/// - 样式：0（重置），1（粗体），3（斜体），4（下划线），7（反色），9（删除线）
/// - 256 色：38;5;N（前景），48;5;N（背景）
///
/// 使用「可增长的字符画布」模拟终端行为（不只是行缓冲）：
/// - `\n`：换行（光标下移，列归零）
/// - `\r`：光标回到当前行行首，后续文本按列覆盖
/// - `\x1b[{r};{c}H` / `\x1b[{r};{c}f`：**绝对光标定位**（行不足自动补空行）
/// - `\x1b[A/B/C/D`：光标上下左右移动
/// - `\x1b[K`：清除当前行（光标后 / 光标前 / 整行）
/// - `\x1b[J`：清除屏幕（光标后 / 光标前 / 全部）
/// - `\x1b[?1049h` / `\x1b[?1049l`：**进入 / 退出 alternate screen**（主屏内容保存并恢复）
/// - `\b`：光标左移；若在行尾则删除末尾字符
///
/// 这套语义覆盖两类渲染：
///   1. bash / 普通 shell 的「行式 + \r 行内覆盖 + prompt 重绘」：
///      `\r\x1b[K\r<prompt>` 只在当前行内重绘，不产生多行堆叠。
///   2. Codex TUI 等全屏光栅应用（ratatui/crossterm）的
///      「alt-screen + 绝对定位 + 全屏清屏」：进入 `\x1b[?1049h` 后，
///      每次事件用 `\x1b[H\x1b[2J` 清屏，再用 `\x1b[{r};{c}H` 逐行绘制。
///      画布模型按行列寻址后，一屏内容不再被压缩到单一行。
library;

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

/// 单个字符的样式快照（画布中样式跟随字符存储，
/// 以便 `\r` 覆盖旧字符时同步替换其样式）。
class _AnsiStyle {
  final Color? fg;
  final Color? bg;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool reversed;

  const _AnsiStyle({
    this.fg,
    this.bg,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.reversed = false,
  });

  static const normal = _AnsiStyle();

  _AnsiStyle copyWith({
    Color? fg,
    Color? bg,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? reversed,
    bool clearFg = false,
    bool clearBg = false,
  }) {
    return _AnsiStyle(
      fg: clearFg ? null : (fg ?? this.fg),
      bg: clearBg ? null : (bg ?? this.bg),
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      reversed: reversed ?? this.reversed,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _AnsiStyle &&
        other.fg == fg &&
        other.bg == bg &&
        other.bold == bold &&
        other.italic == italic &&
        other.underline == underline &&
        other.strikethrough == strikethrough &&
        other.reversed == reversed;
  }

  @override
  int get hashCode => Object.hash(
        fg, bg, bold, italic, underline, strikethrough, reversed,
      );
}

/// 画布中的字符单元
class _Cell {
  final String char;
  final _AnsiStyle style;

  _Cell(this.char, this.style);
}

/// 画布中的一行
class _Line {
  final List<_Cell> cells = [];
}

/// ANSI 解析器（画布模型）
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

  /// 解析 ANSI 转义序列，返回文本段列表。
  ///
  /// 输出为换行分隔的流式文本：`\n` 保留在 segment.text 内，
  /// `\r` / 光标移动 / 清屏只影响画布，不直接产生新行。
  ///
  /// [cols] 为可选列宽限制：>0 时每行最多写入 [cols] 列，
  /// 超出部分截断（Codex TUI 按 PTY 列宽排版，与之一致）；
  /// 传 0（默认）时不限制列宽，保持既有流式行为。
  List<AnsiSegment> parse(String input, {int cols = 0}) {
    if (input.isEmpty) return [];

    // ── 画布状态 ──
    final List<_Line> lines = <_Line>[_Line()];
    var cursorRow = 0;
    var cursorCol = 0;
    var style = _AnsiStyle.normal;

    // alternate screen：进入时保存主屏快照，退出时恢复
    List<_Line>? altSavedLines;
    var altSavedRow = 0;
    var altSavedCol = 0;

    _Line lineAt(int row) => lines[row];

    /// 在 [row] 行 [col] 列写入字符（超出画布自动补空行/空列）
    void writeAt(String ch, int row, int col) {
      while (lines.length <= row) {
        lines.add(_Line());
      }
      final line = lines[row];
      while (line.cells.length < col) {
        line.cells.add(_Cell(' ', style));
      }
      final cell = _Cell(ch, style);
      if (col < line.cells.length) {
        line.cells[col] = cell;
      } else {
        line.cells.add(cell);
      }
    }

    /// 写入字符到光标处并前进一列。
    void write(String ch) {
      if (cols > 0 && cursorCol >= cols) {
        // 超过列宽限制：截断（Codex 按 PTY 列宽排版，不会自然越界）
        return;
      }
      writeAt(ch, cursorRow, cursorCol);
      cursorCol++;
    }

    /// 换行：光标下移一行，列归零（画布无限增长，模拟滚动终端）。
    void newline() {
      cursorRow++;
      cursorCol = 0;
    }

    void carriageReturn() {
      cursorCol = 0;
    }

    void backspace() {
      final line = lineAt(cursorRow);
      if (cursorCol == line.cells.length && cursorCol > 0) {
        // 光标位于行尾：删除末尾字符（近似退格）
        line.cells.removeLast();
        cursorCol--;
      } else if (cursorCol > 0) {
        // 光标在行中：仅左移（真实终端语义，后续字符覆盖）
        cursorCol--;
      }
    }

    List<int> parseParams(StringBuffer buf) {
      final str = buf.toString();
      if (str.isEmpty) return const [];
      return str.split(';').map((p) {
        if (p.isEmpty) return 0;
        return int.tryParse(p) ?? 0;
      }).toList();
    }

    /// CSI K — 清除行
    void clearLine(List<int> codes) {
      final line = lineAt(cursorRow);
      final mode = codes.isEmpty ? 0 : codes.first;
      switch (mode) {
        case 1:
          // 清行首到光标（真实终端：光标前字符被空格替换；此处保留旧语义删除）
          if (cursorCol > 0) line.cells.removeRange(0, cursorCol);
          cursorCol = 0;
          break;
        case 2:
          // 清整行
          line.cells.clear();
          cursorCol = 0;
          break;
        default:
          // 0（默认）：清光标到行尾
          if (cursorCol < line.cells.length) {
            line.cells.removeRange(cursorCol, line.cells.length);
          }
      }
    }

    /// CSI J — 清除屏幕
    void clearScreen(List<int> codes) {
      final mode = codes.isEmpty ? 0 : codes.first;
      switch (mode) {
        case 2:
          // 全清：整张画布重置为一行
          lines
            ..clear()
            ..add(_Line());
          cursorRow = 0;
          cursorCol = 0;
          break;
        case 1:
          // 清光标前：保留当前行，清掉之前所有行 + 当前行光标前
          final cur = lineAt(cursorRow);
          if (cursorCol > 0) cur.cells.removeRange(0, cursorCol);
          lines
            ..clear()
            ..add(cur);
          cursorRow = 0;
          cursorCol = 0;
          break;
        default:
          // 0（默认）：清光标后（当前行光标后 + 之后所有行）
          final cur = lineAt(cursorRow);
          if (cursorCol < cur.cells.length) {
            cur.cells.removeRange(cursorCol, cur.cells.length);
          }
          if (cursorRow + 1 < lines.length) {
            lines.removeRange(cursorRow + 1, lines.length);
          }
          break;
      }
    }

    /// CSI H/f — 绝对光标定位（行不足自动补空行）
    void cursorPosition(List<int> codes) {
      final row = codes.isNotEmpty ? codes[0] : 1;
      final col = codes.length > 1 ? codes[1] : 1;
      while (lines.length < row) {
        lines.add(_Line());
      }
      cursorRow = row - 1;
      cursorCol = col - 1;
      if (cols > 0 && cursorCol >= cols) cursorCol = cols - 1;
    }

    /// CSI A/B/C/D — 光标移动
    void cursorMove(String finalChar, List<int> codes) {
      final n = codes.isNotEmpty ? codes[0] : 1;
      switch (finalChar) {
        case 'A':
          cursorRow = (cursorRow - n).clamp(0, lines.length - 1);
          break;
        case 'B':
          cursorRow = (cursorRow + n).clamp(0, lines.length - 1);
          break;
        case 'C':
          cursorCol += n;
          if (cols > 0 && cursorCol >= cols) cursorCol = cols - 1;
          break;
        case 'D':
          cursorCol = (cursorCol - n).clamp(0, cursorCol);
          break;
      }
    }

    /// ?1049h / ?1049l — 进入/退出 alternate screen
    void enterAltScreen() {
      altSavedLines = lines.map((l) => _Line()..cells.addAll(l.cells)).toList();
      altSavedRow = cursorRow;
      altSavedCol = cursorCol;
      lines
        ..clear()
        ..add(_Line());
      cursorRow = 0;
      cursorCol = 0;
    }

    void exitAltScreen() {
      if (altSavedLines == null) return;
      lines
        ..clear()
        ..addAll(altSavedLines!);
      cursorRow = altSavedRow;
      cursorCol = altSavedCol;
      altSavedLines = null;
    }

    void applySgr(List<int> codes) {
      if (codes.isEmpty) {
        codes = [0];
      }

      int i = 0;
      while (i < codes.length) {
        switch (codes[i]) {
          case 0:
            style = _AnsiStyle.normal;
            break;
          case 1:
            style = style.copyWith(bold: true);
            break;
          case 3:
            style = style.copyWith(italic: true);
            break;
          case 4:
            style = style.copyWith(underline: true);
            break;
          case 7:
            style = style.copyWith(reversed: true);
            break;
          case 9:
            style = style.copyWith(strikethrough: true);
            break;
          case 22:
            style = style.copyWith(bold: false);
            break;
          case 23:
            style = style.copyWith(italic: false);
            break;
          case 24:
            style = style.copyWith(underline: false);
            break;
          case 27:
            style = style.copyWith(reversed: false);
            break;
          case 29:
            style = style.copyWith(strikethrough: false);
            break;
          case 30:
          case 31:
          case 32:
          case 33:
          case 34:
          case 35:
          case 36:
          case 37:
            style = style.copyWith(fg: _ansiColors[codes[i]]);
            break;
          case 38:
            // 38;5;N — 256 色前景
            if (i + 2 < codes.length && codes[i + 1] == 5) {
              style = style.copyWith(fg: _get256Color(codes[i + 2]));
              i += 2;
            }
            // 38;2;R;G;B — TrueColor 前景
            else if (i + 4 < codes.length && codes[i + 1] == 2) {
              style = style.copyWith(
                fg: Color.fromARGB(255, codes[i + 2], codes[i + 3], codes[i + 4]),
              );
              i += 4;
            }
            break;
          case 39:
            style = style.copyWith(clearFg: true);
            break;
          case 40:
          case 41:
          case 42:
          case 43:
          case 44:
          case 45:
          case 46:
          case 47:
            style = style.copyWith(bg: _ansiColors[codes[i] - 10]);
            break;
          case 48:
            // 48;5;N — 256 色背景
            if (i + 2 < codes.length && codes[i + 1] == 5) {
              style = style.copyWith(bg: _get256Color(codes[i + 2]));
              i += 2;
            }
            // 48;2;R;G;B — TrueColor 背景
            else if (i + 4 < codes.length && codes[i + 1] == 2) {
              style = style.copyWith(
                bg: Color.fromARGB(255, codes[i + 2], codes[i + 3], codes[i + 4]),
              );
              i += 4;
            }
            break;
          case 49:
            style = style.copyWith(clearBg: true);
            break;
          case 90:
          case 91:
          case 92:
          case 93:
          case 94:
          case 95:
          case 96:
          case 97:
            style = style.copyWith(fg: _ansiColors[codes[i]]);
            break;
          case 100:
          case 101:
          case 102:
          case 103:
          case 104:
          case 105:
          case 106:
          case 107:
            style = style.copyWith(bg: _ansiColors[codes[i] - 60]);
            break;
        }
        i++;
      }
    }

    bool inEscape = false;
    bool inOsc = false; // Operating System Command
    final params = StringBuffer();

    for (int i = 0; i < input.length; i++) {
      final ch = input[i];

      if (inOsc) {
        // OSC 序列：ESC ] ... BEL(\x07) 或 ST(\x1b\\)
        if (ch == '\x07' ||
            (ch == '\x1b' && i + 1 < input.length && input[i + 1] == '\\')) {
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
            if ((c.compareTo('0') >= 0 && c.compareTo('9') <= 0) ||
                c == ';' ||
                c == ':') {
              params.write(c);
              j++;
            } else if (c == '?') {
              // DEC private sequence（如 ?25h、?1049h）
              params.write('?');
              j++;
              continue;
            } else if (c == 'm') {
              // SGR 结束
              applySgr(parseParams(params));
              i = j; // 跳过 'm'
              break;
            } else if (c == 'K') {
              // 清除行
              clearLine(parseParams(params));
              i = j;
              break;
            } else if (c == 'J') {
              // 清除屏幕
              clearScreen(parseParams(params));
              i = j;
              break;
            } else if (c == 'H' || c == 'f') {
              // 绝对光标定位
              cursorPosition(parseParams(params));
              i = j;
              break;
            } else if (c == 'A' || c == 'B' || c == 'C' || c == 'D') {
              // 光标移动
              cursorMove(c, parseParams(params));
              i = j;
              break;
            } else if (c == 'h' || c == 'l') {
              // 模式设置：?1049h（进入 alt screen）/ ?1049l（退出）
              final raw = params.toString();
              if (raw.contains('?') &&
                  (raw.contains('1049') || raw.contains('47'))) {
                if (c == 'h') {
                  enterAltScreen();
                } else {
                  exitAltScreen();
                }
              }
              i = j;
              break;
            } else if (c == 's' || c == 'u') {
              // 保存/恢复光标 — 忽略
              i = j;
              break;
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
        inEscape = true;
        continue;
      }

      if (ch == '\r') {
        // 回车 — 光标回行首，后续文本覆盖
        carriageReturn();
        continue;
      }

      if (ch == '\n') {
        // 换行 — 光标下移，列归零
        newline();
        continue;
      }

      if (ch == '\b') {
        // 退格
        backspace();
        continue;
      }

      if (ch == '\x07') {
        // BEL — 忽略
        continue;
      }

      write(ch);
    }

    // ── 画布 → 文本段（按样式连续性分组，\n 保留在文本内） ──
    // 去掉尾部空行（Codex 全屏重绘只画用到的行，尾部补的行保持空白，
    // 若保留会产生大段尾部空行；中间空行仍保留以对齐屏幕布局）。
    var lastNonEmpty = lines.length - 1;
    while (lastNonEmpty > 0 && lines[lastNonEmpty].cells.isEmpty) {
      lastNonEmpty--;
    }

    final segments = <AnsiSegment>[];
    final buffer = StringBuffer();
    _AnsiStyle? lastStyle;

    void flushSegment() {
      if (buffer.isEmpty) return;
      final s = lastStyle ?? _AnsiStyle.normal;
      segments.add(AnsiSegment(
        text: buffer.toString(),
        foreground: s.fg,
        background: s.bg,
        bold: s.bold,
        italic: s.italic,
        underline: s.underline,
        strikethrough: s.strikethrough,
        reversed: s.reversed,
      ));
      buffer.clear();
    }

    void emitCell(_Cell cell) {
      final s = cell.style;
      if (lastStyle != null && s != lastStyle) {
        flushSegment();
      }
      lastStyle = s;
      buffer.write(cell.char);
    }

    for (int li = 0; li <= lastNonEmpty; li++) {
      final line = lines[li];
      for (final cell in line.cells) {
        emitCell(cell);
      }
      if (li < lastNonEmpty) {
        // 行分隔：换行符归属当前样式 run
        lastStyle ??= _AnsiStyle.normal;
        buffer.write('\n');
      }
    }
    flushSegment();

    return segments;
  }
}
