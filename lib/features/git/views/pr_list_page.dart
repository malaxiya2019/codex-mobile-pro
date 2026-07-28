import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/github_pr.dart';
import '../providers/github_pr_provider.dart';

/// Pull Request 列表页
class PrListPage extends ConsumerWidget {
  final String repoFullName;

  const PrListPage({super.key, required this.repoFullName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(prListProvider(repoFullName));

    return Scaffold(
      appBar: AppBar(
        title: Text('PR · $repoFullName'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          // 状态过滤
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (s) =>
                ref.read(prListProvider(repoFullName).notifier).loadPrs(filterBy: s),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: Text('Open')),
              const PopupMenuItem(value: 'closed', child: Text('Closed')),
              const PopupMenuItem(value: 'all', child: Text('All')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(prListProvider(repoFullName).notifier).loadPrs(),
          ),
        ],
      ),
      body: _buildBody(state, theme, colorScheme, ref),
    );
  }

  Widget _buildBody(
    PrListState state,
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
                  ref.read(prListProvider(repoFullName).notifier).loadPrs(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.prs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.merge_type, size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('暂无 Pull Request',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.prs.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final pr = state.prs[index];
        return _PrListTile(pr: pr, colorScheme: colorScheme, theme: theme);
      },
    );
  }
}

class _PrListTile extends StatelessWidget {
  final PullRequest pr;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _PrListTile({
    required this.pr,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    theme.brightness == Brightness.dark; // isDark

    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundImage: pr.authorAvatarUrl != null
            ? NetworkImage(pr.authorAvatarUrl!)
            : null,
        child: pr.authorAvatarUrl == null
            ? Text(pr.author.isNotEmpty ? pr.author[0].toUpperCase() : '?')
            : null,
      ),
      title: Row(
        children: [
          // 状态图标
          _buildStateIcon(),
          const SizedBox(width: 8),
          // Draft 标记
          if (pr.isDraft)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('Draft', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
            ),
          // 标题
          Expanded(
            child: Text(
              pr.title,
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
            Text('#${pr.number}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            Text(' · ${pr.author}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            if (pr.createdAt != null) ...[
              Text(' · ${_formatDate(pr.createdAt!)}',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pr.additions > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('+${pr.additions}',
                  style: TextStyle(fontSize: 11, color: Colors.green)),
            ),
          if (pr.deletions > 0)
            Text('-${pr.deletions}',
                style: TextStyle(fontSize: 11, color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildStateIcon() {
    if (pr.isMerged) {
      return Icon(Icons.merge, size: 18, color: Colors.purple);
    }
    if (pr.isClosed) {
      return Icon(Icons.close, size: 18, color: Colors.red);
    }
    // Open
    return Icon(Icons.fiber_manual_record, size: 18, color: Colors.green);
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
