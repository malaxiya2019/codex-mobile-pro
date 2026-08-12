import 'package:flutter/material.dart';
import '../services/ansi_parser.dart';
import 'extra_keys_toolbar.dart';

/// ANSI 终端输出组件
///
/// 将原始终端文本（含 ANSI 转义序列）渲染为带颜色和样式的富文本。
/// 支持：
/// - ANSI 颜色/样式渲染（保留 AnsiParser 的 SGR/256 色/TrueColor）
/// - 无 ANSI 颜色的文本使用页面传入的默认前景色（Termux 浅灰），
///   不再被解析器内部的 greenAccent 兜底覆盖
/// - 长按弹出系统菜单（复制/全选）
/// - 自定义字体大小/字体
class TerminalOutput extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color defaultForeground;
  final Color defaultBackground;
  final String fontFamily;
  final bool cursorBlink;
  final Color cursorColor;

  const TerminalOutput({
    super.key,
    required this.text,
    this.fontSize = 13,
    this.defaultForeground = kTerminalText,
    this.defaultBackground = kTerminalBlack,
    this.fontFamily = 'monospace',
    this.cursorBlink = true,
    this.cursorColor = Colors.greenAccent,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final parser = AnsiParser();
    final segments = parser.parse(text);

    if (segments.isEmpty) return const SizedBox.shrink();

    return SelectionArea(
      child: SelectableText.rich(
        TextSpan(
          children: segments.map((seg) {
            // 无 ANSI 颜色的文本段使用 defaultForeground（Termux 浅灰），
            // 有颜色的段保留 ANSI 渲染结果，保证 Shell 彩色输出不受影响。
            final style = seg.toTextStyle().copyWith(
              fontSize: fontSize,
              fontFamily: fontFamily,
              color: seg.foreground ?? defaultForeground,
            );
            return TextSpan(text: seg.text, style: style);
          }).toList(),
        ),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          color: defaultForeground,
          height: 1.4,
        ),
        contextMenuBuilder: (context, editableTextState) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            buttonItems: editableTextState.contextMenuButtonItems,
            anchors: editableTextState.contextMenuAnchors,
          );
        },
      ),
    );
  }
}
