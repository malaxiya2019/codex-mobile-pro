import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../logger/log_service.dart';

/// 错误页面 — 用户友好的错误显示
///
/// 调试模式：显示详细错误信息 + 堆栈
/// 生产模式：显示友好的错误提示 + 操作按钮
class ErrorPage extends StatelessWidget {
  final Object error;
  final StackTrace? stack;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final bool isFatal;

  const ErrorPage({
    super.key,
    required this.error,
    this.stack,
    this.title,
    this.message,
    this.onRetry,
    this.onBack,
    this.isFatal = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 记录错误到日志
    LogService.exception('ErrorPage', error, stack);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── 错误图标 ──
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isFatal
                      ? colorScheme.errorContainer
                      : colorScheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFatal ? Icons.error_outline : Icons.warning_amber_rounded,
                  size: 40,
                  color: isFatal
                      ? colorScheme.error
                      : colorScheme.tertiary,
                ),
              ),
              const SizedBox(height: 24),

              // ── 标题 ──
              Text(
                title ?? (isFatal ? '应用出现错误' : '操作遇到问题'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // ── 友好提示 ──
              Text(
                message ?? (isFatal
                    ? '应用遇到意外错误，请尝试重新启动。如果问题持续，请联系支持。'
                    : '请稍后重试，或返回上一页。'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // ── 调试模式：详细错误 ──
              if (kDebugMode) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bug_report, size: 16, color: colorScheme.error),
                          const SizedBox(width: 8),
                          Text('调试信息',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${error.runtimeType}: $error',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      if (stack != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _formatStack(stack!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── 操作按钮 ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onBack != null)
                    OutlinedButton(
                      onPressed: onBack,
                      child: const Text('返回'),
                    ),
                  if (onBack != null && onRetry != null)
                    const SizedBox(width: 12),
                  if (onRetry != null)
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重试'),
                      onPressed: onRetry,
                    ),
                  if (onRetry == null && onBack == null)
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('返回'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 格式化堆栈（取前 10 行）
  String _formatStack(StackTrace stack) {
    final lines = stack.toString().split('\n');
    final relevant = lines.take(10).join('\n');
    if (lines.length > 10) {
      return '$relevant\n  ... (${lines.length - 10} more lines)';
    }
    return relevant;
  }
}
