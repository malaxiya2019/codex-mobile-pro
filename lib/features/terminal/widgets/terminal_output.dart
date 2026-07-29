import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ansi_parser.dart';

/// ANSI 终端输出组件
///
/// 将原始终端文本（含 ANSI 转义序列）渲染为带颜色和样式的富文本。
/// 支持：
/// - ANSI 颜色/样式渲染
/// - 长按弹出菜单（复制/全选）
/// - 自定义字体大小
/// - 光标闪烁模拟
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
    this.defaultForeground = Colors.greenAccent,
    this.defaultBackground = Colors.black87,
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
      onSelectionChanged: (_) {
        // 选择变化时更新剪贴板状态
      },
      child: SelectableText.rich(
        TextSpan(
          children: segments.map((seg) {
            final style = seg.toTextStyle().copyWith(
              fontSize: fontSize,
              fontFamily: fontFamily,
            );
            return TextSpan(text: seg.text, style: style);
          }).toList(),
        ),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          color: defaultForeground,
          height: 1.5,
        ),
        // 使用系统上下文菜单
        contextMenuBuilder: (context, editableTextState) {
          return _TerminalContextMenu(
            editableTextState: editableTextState,
            onCopyAll: () {
              _copyAll(context, text);
            },
          );
        },
      ),
    );
  }

  void _copyAll(BuildContext context, String fullText) {
    if (fullText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: fullText));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制全部'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}

/// 终端上下文菜单 — 在系统菜单基础上增加「全选复制」
class _TerminalContextMenu extends StatelessWidget {
  final EditableTextState editableTextState;
  final VoidCallback onCopyAll;

  const _TerminalContextMenu({
    required this.editableTextState,
    required this.onCopyAll,
  });

  @override
  Widget build(BuildContext context) {
    final adaptor = EditableText.getAdaptiveInputConnectionActivator(
      editableTextState,
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      buttonItems: [
        ...editableTextState.contextMenuButtonItems,
        const ContextMenuButtonItem(
          label: '全选复制',
          type: ContextMenuButtonType.copy,
        ),
      ],
      anchors: editableTextState.contextMenuAnchors,
    );
  }
}
