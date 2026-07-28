import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../workspace_model.dart';
import '../workspace_provider.dart';
import 'workspace_create_dialog.dart';

/// 工作区列表页
class WorkspaceListPage extends ConsumerWidget {
  const WorkspaceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(workspaceProvider);
    final locale = ref.watch(localeProvider);
    final s = Strings.get(locale);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.workspaceListTitle),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          if (state.workspaces.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: s.workspaceCreateTitle,
              onPressed: () => _createWorkspace(context, ref),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.workspaces.isEmpty
          ? _EmptyState(onCreate: () => _createWorkspace(context, ref), s: s)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.workspaces.length,
              itemBuilder: (context, index) {
                final ws = state.workspaces[index];
                final isCurrent = ws.id == state.currentWorkspaceId;
                return _WorkspaceCard(
                  workspace: ws,
                  isCurrent: isCurrent,
                  onTap: () {
                    ref.read(workspaceProvider.notifier).switchWorkspace(ws.id);
                    Navigator.of(context).pop();
                  },
                  onDelete: () => _deleteWorkspace(context, ref, ws),
                  locale: locale,
                  s: s,
                );
              },
            ),
    );
  }

  Future<void> _createWorkspace(BuildContext context, WidgetRef ref) async {
    final ws = await WorkspaceCreateDialog.show(context);
    if (ws != null && context.mounted) {
      ref.read(workspaceProvider.notifier).switchWorkspace(ws.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${Strings.get(ref.read(localeProvider)).workspaceCreated}: ${ws.name}',
          ),
        ),
      );
    }
  }

  Future<void> _deleteWorkspace(
    BuildContext context,
    WidgetRef ref,
    Workspace ws,
  ) async {
    final s = Strings.get(ref.read(localeProvider));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.delete),
        content: Text('${s.workspaceDeleteConfirm} "${ws.name}"？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(s.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      ref.read(workspaceProvider.notifier).delete(ws.id);
    }
  }
}

/// 空状态
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  final Strings s;

  const _EmptyState({required this.onCreate, required this.s});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              s.workspaceEmpty,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              s.workspaceEmptyDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(s.workspaceCreateTitle),
            ),
          ],
        ),
      ),
    );
  }
}

/// 工作区卡片
class _WorkspaceCard extends StatelessWidget {
  final Workspace workspace;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final AppLanguage locale;
  final Strings s;

  const _WorkspaceCard({
    required this.workspace,
    required this.isCurrent,
    required this.onTap,
    required this.onDelete,
    required this.locale,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: isCurrent ? 1 : 0,
      color: isCurrent
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 模板图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _templateColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    workspace.template.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          workspace.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              s.workspaceCurrent,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${workspace.template.name} · ${_projectCount()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _formatDate(workspace.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // 操作
              PopupMenuButton<_Action>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (action) {
                  switch (action) {
                    case _Action.select:
                      onTap();
                    case _Action.delete:
                      onDelete();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: _Action.select,
                    child: Text(
                      isCurrent ? s.workspaceSwitch : s.workspaceSelect,
                    ),
                  ),
                  PopupMenuItem(
                    value: _Action.delete,
                    child: Text(
                      s.delete,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _templateColor() {
    switch (workspace.template) {
      case WorkspaceTemplate.flutter:
        return Colors.blue;
      case WorkspaceTemplate.rust:
        return Colors.orange;
      case WorkspaceTemplate.python:
        return Colors.green;
      case WorkspaceTemplate.learning:
        return Colors.purple;
      case WorkspaceTemplate.experiment:
        return Colors.teal;
    }
  }

  String _projectCount() {
    final count = workspace.projects.length;
    return '$count ${s.workspaceProjects}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${_pad(date.month)}-${_pad(date.day)} '
        '${_pad(date.hour)}:${_pad(date.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

enum _Action { select, delete }
