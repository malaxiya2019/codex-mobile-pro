import 'package:flutter/material.dart';
import '../models/editor_models.dart';

/// 查找/替换面板
class EditorFindPanel extends StatelessWidget {
  final FindReplaceState state;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onReplaceChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;
  final VoidCallback onToggleCase;
  final VoidCallback onToggleRegex;
  final VoidCallback onClose;

  const EditorFindPanel({
    super.key,
    required this.state,
    required this.onQueryChanged,
    required this.onReplaceChanged,
    required this.onNext,
    required this.onPrev,
    required this.onReplace,
    required this.onReplaceAll,
    required this.onToggleCase,
    required this.onToggleRegex,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 查找行
          Row(
            children: [
              Icon(Icons.search, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '查找...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      filled: true,
                      fillColor: colorScheme.surface,
                    ),
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    onChanged: onQueryChanged,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 匹配计数
              if (state.query.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    state.totalMatches > 0
                        ? '${state.currentMatch}/${state.totalMatches}'
                        : '无匹配',
                    style: TextStyle(
                      fontSize: 12,
                      color: state.totalMatches > 0
                          ? colorScheme.primary
                          : colorScheme.error,
                    ),
                  ),
                ),
              // 大小写
              IconButton(
                icon: Icon(
                  Icons.text_fields,
                  size: 18,
                  color: state.caseSensitive
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                tooltip: '区分大小写',
                onPressed: onToggleCase,
                visualDensity: VisualDensity.compact,
              ),
              // 正则
              IconButton(
                icon: Text(
                  '.*',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: state.useRegex
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                tooltip: '正则表达式',
                onPressed: onToggleRegex,
                visualDensity: VisualDensity.compact,
              ),
              // 上一个
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                tooltip: '上一个',
                onPressed: onPrev,
                visualDensity: VisualDensity.compact,
              ),
              // 下一个
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 18),
                tooltip: '下一个',
                onPressed: onNext,
                visualDensity: VisualDensity.compact,
              ),
              // 关闭
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),

          // 替换行
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.find_replace, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '替换为...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      filled: true,
                      fillColor: colorScheme.surface,
                    ),
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    onChanged: onReplaceChanged,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onReplace,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('替换', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onReplaceAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('全部替换', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
