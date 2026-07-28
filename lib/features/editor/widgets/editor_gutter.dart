import 'package:flutter/material.dart';

/// 行号栏
class EditorGutter extends StatelessWidget {
  final int lineCount;
  final int currentLine;
  final double lineHeight;
  final int topLine;

  const EditorGutter({
    super.key,
    required this.lineCount,
    required this.currentLine,
    this.lineHeight = 20.0,
    this.topLine = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 48,
      color: colorScheme.surfaceContainerLow,
      child: ListView.builder(
        padding: EdgeInsets.only(top: 8 - topLine * lineHeight),
        itemCount: lineCount,
        itemExtent: lineHeight,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final lineNum = index + 1;
          final isCurrentLine = index == currentLine;

          return Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isCurrentLine
                  ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : null,
            ),
            child: Text(
              '$lineNum',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: isCurrentLine
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontWeight: isCurrentLine ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }
}
