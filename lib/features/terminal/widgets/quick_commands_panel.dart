import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/command_manager.dart';

/// 快捷命令面板 Provider
final commandManagerProvider = Provider<CommandManager>((ref) {
  return CommandManager();
});

/// 快捷命令面板
class QuickCommandsPanel extends ConsumerWidget {
  final void Function(String command) onExecute;

  const QuickCommandsPanel({super.key, required this.onExecute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mgr = ref.watch(commandManagerProvider);

    return DefaultTabController(
      length: CommandCategory.values.length,
      child: Column(
        children: [
          // ── 分类 Tab ──
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: CommandCategory.values.map((cat) {
              return Tab(text: '${cat.icon} ${cat.name}');
            }).toList(),
          ),

          // ── 命令列表 ──
          Expanded(
            child: TabBarView(
              children: CommandCategory.values.map((cat) {
                final commands = mgr.getByCategory(cat);
                if (commands.isEmpty) {
                  return Center(
                    child: Text(
                      '暂无 ${cat.name} 命令',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: commands.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final cmd = commands[index];
                    return ListTile(
                      dense: true,
                      leading: Text(
                        cmd.category.icon,
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: Text(
                        cmd.name,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        cmd.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          cmd.isFavorite ? Icons.star : Icons.star_border,
                          color: cmd.isFavorite ? Colors.amber : null,
                          size: 20,
                        ),
                        onPressed: () => mgr.toggleFavorite(cmd.id),
                      ),
                      onTap: () => onExecute(cmd.command),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
