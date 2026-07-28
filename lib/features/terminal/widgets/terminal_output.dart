import 'package:flutter/material.dart';
import '../services/ansi_parser.dart';

/// ANSI 终端输出组件
///
/// 将原始终端文本（含 ANSI 转义序列）渲染为带颜色和样式的富文本。
class TerminalOutput extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color defaultForeground;
  final Color defaultBackground;

  const TerminalOutput({
    super.key,
    required this.text,
    this.fontSize = 13,
    this.defaultForeground = Colors.greenAccent,
    this.defaultBackground = Colors.black87,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final parser = AnsiParser();
    final segments = parser.parse(text);

    if (segments.isEmpty) return const SizedBox.shrink();

    return SelectableText.rich(
      TextSpan(
        children: segments.map((seg) {
          final style = seg.toTextStyle().copyWith(
            fontSize: fontSize,
          );
          return TextSpan(text: seg.text, style: style);
        }).toList(),
      ),
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        color: defaultForeground,
        height: 1.5,
      ),
    );
  }
}
