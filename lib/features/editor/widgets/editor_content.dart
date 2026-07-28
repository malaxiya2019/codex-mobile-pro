import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import '../services/editor_buffer.dart';
import '../syntax/syntax_highlighter.dart';

/// 编辑器内容区域 — 带语法高亮的代码编辑器
class EditorContent extends StatefulWidget {
  final EditorBuffer buffer;
  final EditorSettings settings;
  final bool isDark;
  final ValueChanged<CursorPosition>? onCursorChanged;

  const EditorContent({
    super.key,
    required this.buffer,
    required this.settings,
    this.isDark = true,
    this.onCursorChanged,
  });

  @override
  State<EditorContent> createState() => _EditorContentState();
}

class _EditorContentState extends State<EditorContent> {
  late ScrollController _verticalScrollController;
  late ScrollController _horizontalScrollController;
  final FocusNode _focusNode = FocusNode();
  double _fontSize = 14;

  @override
  void initState() {
    super.initState();
    _verticalScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    _fontSize = widget.settings.fontSize.toDouble();
  }

  @override
  void didUpdateWidget(EditorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.fontSize != widget.settings.fontSize) {
      _fontSize = widget.settings.fontSize.toDouble();
    }
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double get _lineHeight => _fontSize * 1.5;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lines = widget.buffer.lines;
    final cursor = widget.buffer.cursor;
    final highlighter = widget.buffer.highlighter;

    return Container(
      color: widget.isDark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFFFFFFF),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 行号栏 ──
          if (widget.settings.showLineNumbers)
            _buildGutter(lines.length, cursor.line, colorScheme),

          // ── 代码内容 ──
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              child: KeyboardListener(
                focusNode: _focusNode,
                onKeyEvent: _handleKeyEvent,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _computeContentWidth(lines, highlighter),
                    child: ListView.builder(
                      controller: _verticalScrollController,
                      padding: EdgeInsets.only(
                        top: 8,
                        left: 8,
                        right: 16,
                        bottom: 200,
                      ),
                      itemCount: lines.length,
                      itemExtent: _lineHeight,
                      itemBuilder: (context, index) {
                        return _buildLine(
                          index,
                          lines[index],
                          highlighter,
                          cursor,
                          colorScheme,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGutter(int lineCount, int currentLine, ColorScheme colorScheme) {
    return Container(
      width: 48,
      color: widget.isDark
          ? const Color(0xFF252526)
          : const Color(0xFFF3F3F3),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        itemCount: lineCount,
        itemExtent: _lineHeight,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final isCurrentLine = index == currentLine;
          return Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isCurrentLine
                  ? (widget.isDark
                      ? const Color(0xFF2A2D2E)
                      : const Color(0xFFE8E8E8))
                  : null,
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: isCurrentLine
                    ? (widget.isDark
                        ? const Color(0xFFC6C6C6)
                        : const Color(0xFF333333))
                    : (widget.isDark
                        ? const Color(0xFF858585)
                        : const Color(0xFFA0A0A0)),
                fontWeight: isCurrentLine ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLine(
    int index,
    String text,
    SyntaxHighlighter? highlighter,
    CursorPosition cursor,
    ColorScheme colorScheme,
  ) {
    final isCurrentLine = index == cursor.line;

    // 背景
    Color bgColor;
    if (isCurrentLine && widget.settings.highlightCurrentLine) {
      bgColor = widget.isDark
          ? const Color(0xFF2A2D2E)
          : const Color(0xFFE8E8E8);
    } else {
      bgColor = Colors.transparent;
    }

    // 语法高亮
    final spans = <TextSpan>[];
    if (highlighter != null && text.isNotEmpty) {
      final tokens = highlighter.highlightLine(text);
      if (tokens.isNotEmpty) {
        int lastEnd = 0;
        for (final token in tokens) {
          // 普通文本（Token 之间的部分）
          if (token.start > lastEnd) {
            spans.add(TextSpan(
              text: text.substring(lastEnd, token.start),
              style: TextStyle(
                color: widget.isDark
                    ? const Color(0xFFA9B7C6)
                    : const Color(0xFF000000),
              ),
            ));
          }
          // Token
          final tokenText = text.substring(token.start, token.end);
          final color = highlighter.getColorForToken(
            token.type,
            isDark: widget.isDark,
          );
          FontWeight? weight;
          if (token.type == TokenType.keyword ||
              token.type == TokenType.type ||
              token.type == TokenType.className) {
            weight = FontWeight.w600;
          }
          spans.add(TextSpan(
            text: tokenText,
            style: TextStyle(color: color, fontWeight: weight),
          ));
          lastEnd = token.end;
        }
        // 剩余部分
        if (lastEnd < text.length) {
          spans.add(TextSpan(
            text: text.substring(lastEnd),
            style: TextStyle(
              color: widget.isDark
                  ? const Color(0xFFA9B7C6)
                  : const Color(0xFF000000),
            ),
          ));
        }
      } else {
        spans.add(TextSpan(
          text: text,
          style: TextStyle(
            color: widget.isDark
                ? const Color(0xFFA9B7C6)
                : const Color(0xFF000000),
          ),
        ));
      }
    } else {
      spans.add(TextSpan(
        text: text,
        style: TextStyle(
          color: widget.isDark
              ? const Color(0xFFA9B7C6)
              : const Color(0xFF000000),
        ),
      ));
    }

    return Container(
      height: _lineHeight,
      color: bgColor,
      padding: const EdgeInsets.only(left: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: _fontSize,
            height: 1.5,
          ),
          children: spans,
        ),
        maxLines: 1,
        overflow: TextOverflow.visible,
      ),
    );
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final logicalKey = event.logicalKey;
    final isControl = HardwareKeyboard.instance.controlKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.controlKeysPressed.contains(LogicalKeyboardKey.controlRight);

    if (isControl) {
      switch (logicalKey.keyLabel) {
        case 's':
          // Save handled by parent
          return KeyEventResult.handled;
        case 'z':
          if (HardwareKeyboard.instance.isShiftPressed) {
            widget.buffer.redo();
          } else {
            widget.buffer.undo();
          }
          _notifyCursor();
          return KeyEventResult.handled;
        case 'a':
          widget.buffer.selectAll();
          _notifyCursor();
          return KeyEventResult.handled;
        case 'f':
          // Find handled by parent
          return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    switch (logicalKey.keyLabel) {
      case 'ArrowUp':
        widget.buffer.moveCursorUp();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'ArrowDown':
        widget.buffer.moveCursorDown();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'ArrowLeft':
        if (HardwareKeyboard.instance.isShiftPressed) {
          // Selection handled separately
        }
        widget.buffer.moveCursorLeft();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'ArrowRight':
        widget.buffer.moveCursorRight();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'Home':
        widget.buffer.moveToLineStart();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'End':
        widget.buffer.moveToLineEnd();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'Enter':
        widget.buffer.insertNewline();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'Tab':
        widget.buffer.insertTab();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'Backspace':
        widget.buffer.deleteLeft();
        _notifyCursor();
        return KeyEventResult.handled;
      case 'Delete':
        widget.buffer.deleteRight();
        _notifyCursor();
        return KeyEventResult.handled;
      default:
        if (logicalKey.keyLabel.length == 1) {
          widget.buffer.insertChar(logicalKey.keyLabel);
          _notifyCursor();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  void _notifyCursor() {
    widget.onCursorChanged?.call(widget.buffer.cursor);
    setState(() {});
  }

  double _computeContentWidth(List<String> lines, SyntaxHighlighter? highlighter) {
    int maxLen = 80;
    for (final line in lines) {
      if (line.length > maxLen) maxLen = line.length;
    }
    return maxLen * _fontSize * 0.6 + 24;
  }
}

// 需要引入 KeyboardListener 和 LogicalKeyboardKey
