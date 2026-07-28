import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/github_pr.dart';
import '../providers/github_issue_provider.dart';

/// Issue 列表页
class IssueListPage extends ConsumerWidget {
  final String repoFullName;

  const IssueListPage({super.key, required this.repoFullName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(issueListProvider(repoFullName));

    return Scaffold(
      appBar: AppBar(
        title: Text('Issues · $repoFullName'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (s) =>
                ref.read(issueListProvider(repoFullName).notifier).loadIssues(state: s),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: Text('Open')),
              const PopupMenuItem(value: 'closed', child: Text('Closed')),
              const PopupMenuItem(value: 'all', child: Text('All')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(issueListProvider(repoFullName).notifier).loadIssues(),
          ),
        ],
      ),
      body: _buildBody(state, theme, colorScheme, ref),
    );
  }

  Widget _buildBody(
    IssueListState state,
    ThemeData theme,
    ColorScheme colorScheme,
    WidgetRef ref,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(state.error!, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.read(issueListProvider(repoFullName).notifier).loadIssues(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bug_report_outlined, size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('暂无 Issue',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.issues.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final issue = state.issues[index];
        return _IssueListTile(issue: issue, colorScheme: colorScheme, theme: theme);
      },
    );
  }
}

class _IssueListTile extends StatelessWidget {
  final GitHubIssue issue;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _IssueListTile({
    required this.issue,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundImage: issue.authorAvatarUrl != null
            ? NetworkImage(issue.authorAvatarUrl!)
            : null,
        child: issue.authorAvatarUrl == null
            ? Text(issue.author.isNotEmpty ? issue.author[0].toUpperCase() : '?')
            : null,
      ),
      title: Row(
        children: [
          // 状态图标
          Icon(
            issue.isOpen ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: issue.isOpen ? Colors.green : Colors.purple,
          ),
          const SizedBox(width: 8),
          // 标题
          Expanded(
            child: Text(
              issue.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Text('#${issue.number}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            Text(' · ${issue.author}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            if (issue.createdAt != null)
              Text(' · ${_formatDate(issue.createdAt!)}',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      trailing: issue.commentCount > 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.comment_outlined, size: 14,
                    color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${issue.commentCount}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            )
          : null,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}个月前';
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    return '刚刚';
  }
}
