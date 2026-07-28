import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/git_provider.dart';
import '../models/git_repository.dart';
import 'github_login_page.dart';
import 'git_operations_page.dart';

/// 仓库列表页
class RepoListPage extends ConsumerStatefulWidget {
  const RepoListPage({super.key});

  @override
  ConsumerState<RepoListPage> createState() => _RepoListPageState();
}

class _RepoListPageState extends ConsumerState<RepoListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndLoad();
    });
  }

  Future<void> _checkAuthAndLoad() async {
    final authState = ref.read(gitHubAuthProvider);
    if (!authState.isLoggedIn) {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const GitHubLoginPage()),
      );
      if (result == true && mounted) {
        ref.read(repoListProvider.notifier).loadRepos();
      }
    } else {
      ref.read(repoListProvider.notifier).loadRepos();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(gitHubAuthProvider);
    final repoState = ref.watch(repoListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 仓库'),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surfaceContainer,
        actions: [
          if (authState.isLoggedIn)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'refresh':
                    ref.read(repoListProvider.notifier).loadRepos(refresh: true);
                    break;
                  case 'logout':
                    ref.read(gitHubAuthProvider.notifier).logout();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'refresh', child: Text('刷新')),
                const PopupMenuItem(value: 'logout', child: Text('登出')),
              ],
            ),
        ],
      ),
      body: _buildBody(theme, authState, repoState),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    GitHubAuthState authState,
    RepoListState repoState,
  ) {
    if (!authState.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '未登录 GitHub',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '登录后可浏览和管理仓库',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const GitHubLoginPage()),
                );
                if (result == true && mounted) {
                  ref.read(repoListProvider.notifier).loadRepos();
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('登录 GitHub'),
            ),
          ],
        ),
      );
    }

    if (repoState.isLoading && repoState.repos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (repoState.error != null && repoState.repos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(repoState.error!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () =>
                  ref.read(repoListProvider.notifier).loadRepos(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (repoState.repos.isEmpty) {
      return Center(
        child: Text(
          '没有找到仓库',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(repoListProvider.notifier).loadRepos(refresh: true),
      child: ListView.builder(
        itemCount: repoState.repos.length,
        itemBuilder: (context, index) {
          final repo = repoState.repos[index];
          return _RepoListItem(
            repo: repo,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GitOperationsPage(repo: repo),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RepoListItem extends StatelessWidget {
  final GitRepository repo;
  final VoidCallback onTap;

  const _RepoListItem({required this.repo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            repo.isPrivate ? Icons.lock : Icons.public,
            color: theme.colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          repo.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (repo.description != null && repo.description!.isNotEmpty)
              Text(
                repo.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (repo.starCount != null) ...[
                  const Icon(Icons.star_border, size: 14),
                  const SizedBox(width: 2),
                  Text('${repo.starCount}', style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 12),
                ],
                if (repo.language != null) ...[
                  Text(repo.language!, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 12),
                ],
                if (repo.updatedAt != null)
                  Text(
                    _formatDate(repo.updatedAt!),
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return '今天';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30} 个月前';
    return '${diff.inDays ~/ 365} 年前';
  }
}
