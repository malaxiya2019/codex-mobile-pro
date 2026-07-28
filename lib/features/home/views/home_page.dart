import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../features/workspace/workspace_provider.dart';
import '../../workspace/views/workspace_list_page.dart';
import '../../workspace/views/workspace_create_dialog.dart';
import '../providers/counter_provider.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final counter = ref.watch(counterProvider);
    final themeState = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final wsState = ref.watch(workspaceProvider);
    final s = Strings.get(locale);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.homeTitle),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          IconButton(
            icon: Text(
              locale == AppLanguage.zhCN ? '中' : 'EN',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            tooltip: '切换语言',
            onPressed: () => ref.read(localeProvider.notifier).toggleLocale(),
          ),
          IconButton(
            icon: Icon(
              themeState.mode == ThemeModeOption.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            tooltip: '切换主题',
            onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: '主题设置',
            onPressed: () => context.push(RouteNames.themeSettings),
          ),
          IconButton(
            icon: const Icon(Icons.deployed_code),
            tooltip: '部署中心',
            onPressed: () => context.push(RouteNames.deploy),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 工作区信息卡片 ──
          _WorkspaceDashboardCard(
            wsState: wsState,
            s: s,
            colorScheme: colorScheme,
            theme: theme,
            onManage: () => _openWorkspaceList(context, ref),
            onCreate: () => _createWorkspace(context, ref),
          ),
          const SizedBox(height: 16),

          // ── 系统状态卡片 ──
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusHeader(),
                  const SizedBox(height: 12),
                  _StatusRow(
                    label: 'Material 3',
                    value: '✅ v3.0',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    label: 'Riverpod',
                    value: '✅ 已集成',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    label: 'Termux 通信',
                    value: '✅ 已验证',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    label: 'AI 通信',
                    value: '✅ 已验证',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    label: '主题系统',
                    value: '✅ 亮/暗切换',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    label: '工作区管理',
                    value: '✅ 已集成',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    label: '国际化',
                    value: locale == AppLanguage.zhCN ? '✅ 中文' : '✅ English',
                    color: Colors.green,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── AI 状态 + 快捷操作 ──
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.smart_toy_outlined,
                  label: s.workspaceQuickAi,
                  subtitle: wsState.currentWorkspace != null
                      ? '✅ Online'
                      : '⏸ Standby',
                  color: Colors.purple,
                  onTap: () => context.push(RouteNames.aiChat),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.deployed_code,
                  label: s.navDeploy,
                  subtitle: '环境检测',
                  color: Colors.blue,
                  onTap: () => context.push(RouteNames.deploy),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.terminal,
                  label: s.navTermux,
                  subtitle: '通信验证',
                  color: Colors.green,
                  onTap: () => context.push(RouteNames.termuxTest),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── 设置入口 ──
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(s.workspaceListTitle),
                  subtitle: Text(
                    '${wsState.workspaces.length} ${s.workspaceProjects}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openWorkspaceList(context, ref),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: Text('主题设置'),
                  subtitle: Text('亮/暗/跟随系统 · 字体配置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(RouteNames.themeSettings),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text('语言设置'),
                  subtitle: Text('中文 / English'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(RouteNames.localeSettings),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Riverpod 状态管理验证 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Riverpod 状态管理验证', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 32,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$counter',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.tonal(
                        onPressed: () =>
                            ref.read(counterProvider.notifier).decrement(),
                        child: const Icon(Icons.remove),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: () =>
                            ref.read(counterProvider.notifier).reset(),
                        child: const Text('重置'),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.tonal(
                        onPressed: () =>
                            ref.read(counterProvider.notifier).increment(),
                        child: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 环境信息 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('环境信息', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  const _InfoRow(label: 'Flutter', value: '3.x'),
                  const _InfoRow(label: 'Dart', value: '3.5+'),
                  const _InfoRow(label: 'Android', value: '10–15 (API 29–35)'),
                  const _InfoRow(label: '架构', value: 'Material 3 + Riverpod'),
                  const _InfoRow(label: 'Termux 通信', value: '多策略降级'),
                  const _InfoRow(
                    label: 'AI 通信',
                    value: 'DeepSeek + mimo2codex',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              break;
            case 1:
              context.push(RouteNames.deploy);
              break;
            case 2:
              context.push(RouteNames.termuxTest);
              break;
            case 3:
              context.push(RouteNames.aiChat);
              break;
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: s.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.deployed_code_outlined),
            selectedIcon: const Icon(Icons.deployed_code),
            label: s.navDeploy,
          ),
          NavigationDestination(
            icon: const Icon(Icons.terminal_outlined),
            selectedIcon: const Icon(Icons.terminal),
            label: s.navTermux,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_outlined),
            selectedIcon: const Icon(Icons.chat),
            label: s.navAi,
          ),
        ],
      ),
    );
  }

  void _openWorkspaceList(BuildContext context, WidgetRef ref) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WorkspaceListPage()));
  }

  Future<void> _createWorkspace(BuildContext context, WidgetRef ref) async {
    final ws = await WorkspaceCreateDialog.show(context);
    if (ws != null && context.mounted) {
      ref.read(workspaceProvider.notifier).switchWorkspace(ws.id);
    }
  }
}

/// 工作区仪表盘卡片
class _WorkspaceDashboardCard extends StatelessWidget {
  final WorkspaceState wsState;
  final Strings s;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final VoidCallback onManage;
  final VoidCallback onCreate;

  const _WorkspaceDashboardCard({
    required this.wsState,
    required this.s,
    required this.colorScheme,
    required this.theme,
    required this.onManage,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final currentWs = wsState.currentWorkspace;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.workspace_premium,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  s.workspaceInfo,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onManage,
                  icon: const Icon(Icons.settings, size: 16),
                  label: Text(s.settings, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (currentWs != null)
              // 有当前工作区
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      currentWs.template.icon,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentWs.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${currentWs.template.name} · ${currentWs.projects.length} ${s.workspaceProjects}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                  ],
                ),
              )
            else
              // 无工作区
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: colorScheme.surface,
                ),
                child: Column(
                  children: [
                    Text(
                      s.workspaceEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(s.workspaceCreateTitle),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                      ),
                    ),
                  ],
                ),
              ),

            // 快捷操作
            if (currentWs != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _QuickChip(
                    icon: Icons.folder_outlined,
                    label: s.workspaceQuickNew,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _QuickChip(
                    icon: Icons.folder_open_outlined,
                    label: s.workspaceQuickOpen,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _QuickChip(
                    icon: Icons.smart_toy_outlined,
                    label: s.workspaceQuickAi,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _QuickChip(
                    icon: Icons.terminal_outlined,
                    label: s.workspaceQuickTerminal,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 快捷芯片
class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// 快捷操作卡片
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.check_circle, color: colorScheme.primary, size: 28),
        const SizedBox(width: 12),
        Text(
          '系统状态',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: variant),
            ),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
