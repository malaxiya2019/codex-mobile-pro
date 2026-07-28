import 'package:flutter/material.dart';
import '../extensions/code_review.dart';

/// 代码审查结果 BottomSheet
///
/// 展示 AI 代码审查结果，包括：
/// - 总体评分与总结
/// - 按严重级别分组的审查条目
/// - Bug / 性能 / 安全 / 风格 / 重构分类
class CodeReviewSheet extends StatelessWidget {
  final CodeReviewResult result;
  final void Function()? onClose;

  const CodeReviewSheet({
    super.key,
    required this.result,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // 标题栏
              _buildHeader(colorScheme, theme),
              const Divider(),

              // 错误状态
              if (result.hasError && result.errorMessage != null)
                _buildErrorSection(colorScheme, theme),

              // 有效结果
              if (result.isValid) ...[
                // 评分和总结
                _buildScoreSection(colorScheme, theme),
                const SizedBox(height: 16),

                // 严重级别概览
                _buildSeverityOverview(colorScheme, theme),
                const SizedBox(height: 16),

                // 审查条目列表
                ...result.items.map((item) => _buildReviewItem(item, colorScheme, theme)),
              ],

              // 空结果
              if (!result.isValid && !result.hasError)
                _buildEmptyState(colorScheme, theme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.rate_review_outlined, color: colorScheme.primary, size: 20),
        const SizedBox(width: 8),
        Text('代码审查结果', style: theme.textTheme.titleMedium),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: onClose ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildScoreSection(ColorScheme colorScheme, ThemeData theme) {
    final score = result.overallScore;
    final scoreColor = score >= 8.0
        ? Colors.green
        : score >= 6.0
            ? Colors.orange
            : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('总体评分', style: theme.textTheme.titleSmall),
                const SizedBox(width: 12),
                Text(
                  score.toStringAsFixed(1),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Text('/ 10', style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                )),
                const Spacer(),
                _buildScoreIndicator(score, colorScheme),
              ],
            ),
            if (result.summary != null && result.summary!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                result.summary!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreIndicator(double score, ColorScheme colorScheme) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score / 10.0,
            strokeWidth: 4,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              score >= 8.0
                  ? Colors.green
                  : score >= 6.0
                      ? Colors.orange
                      : Colors.red,
            ),
          ),
          Text(
            '${score.round()}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityOverview(ColorScheme colorScheme, ThemeData theme) {
    return Row(
      children: [
        if (result.criticalCount > 0)
          _severityBadge('严重', result.criticalCount, Colors.red, colorScheme),
        const SizedBox(width: 8),
        if (result.warningCount > 0)
          _severityBadge('警告', result.warningCount, Colors.orange, colorScheme),
        const SizedBox(width: 8),
        _severityBadge('信息', result.items.length, colorScheme.primary, colorScheme),
      ],
    );
  }

  Widget _severityBadge(String label, int count, Color color, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$label $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewItem(ReviewItem item, ColorScheme colorScheme, ThemeData theme) {
    final severityColor = _severityColor(item.severity);
    final categoryIcon = _categoryIcon(item.category);
    final categoryLabel = _categoryLabel(item.category);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: severityColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(categoryIcon, size: 14, color: severityColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // 类别标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    categoryLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),

            // 描述
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            // 行号
            if (item.line != null) ...[
              const SizedBox(height: 4),
              Text(
                '第 ${item.line! + 1} 行',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.primary,
                  fontFamily: 'monospace',
                ),
              ),
            ],

            // 改进建议
            if (item.suggestion != null && item.suggestion!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.suggestion!,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorSection(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('审查失败', style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.error,
                )),
                const SizedBox(height: 4),
                Text(
                  result.errorMessage ?? '未知错误',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('未发现问题', style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 4),
            Text('代码质量良好', style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            )),
          ],
        ),
      ),
    );
  }

  Color _severityColor(ReviewSeverity severity) {
    switch (severity) {
      case ReviewSeverity.critical:
        return Colors.red;
      case ReviewSeverity.warning:
        return Colors.orange;
      case ReviewSeverity.info:
        return Colors.blue;
      case ReviewSeverity.suggestion:
        return Colors.green;
    }
  }

  IconData _categoryIcon(ReviewCategory category) {
    switch (category) {
      case ReviewCategory.bug:
        return Icons.bug_report;
      case ReviewCategory.performance:
        return Icons.speed;
      case ReviewCategory.security:
        return Icons.security;
      case ReviewCategory.style:
        return Icons.palette;
      case ReviewCategory.refactor:
        return Icons.refresh;
      case ReviewCategory.bestPractice:
        return Icons.auto_awesome;
    }
  }

  String _categoryLabel(ReviewCategory category) {
    switch (category) {
      case ReviewCategory.bug:
        return 'Bug';
      case ReviewCategory.performance:
        return '性能';
      case ReviewCategory.security:
        return '安全';
      case ReviewCategory.style:
        return '风格';
      case ReviewCategory.refactor:
        return '重构';
      case ReviewCategory.bestPractice:
        return '最佳实践';
    }
  }
}
