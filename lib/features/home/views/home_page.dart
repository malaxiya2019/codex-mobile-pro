import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../providers/counter_provider.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final counter = ref.watch(counterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Codex Mobile Pro'),
        centerTitle: true,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.deployed_code),
            tooltip: '部署中心',
            onPressed: () => context.push(RouteNames.deploy),
          ),
          IconButton(
            icon: const Icon(Icons.terminal),
            tooltip: 'Termux 通信验证',
            onPressed: () => context.push(RouteNames.termuxTest),
          ),
          IconButton(
            icon: const Icon(Icons.chat_outlined),
            tooltip: 'AI 对话',
            onPressed: () => context.push(RouteNames.aiChat),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('设置页面 — Sprint 9 实现')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 系统状态卡片 ──
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusHeader(),
                  SizedBox(height: 12),
                  _StatusRow(label: 'Material 3', value: '✅ v3.0', color: Colors.green),
                  SizedBox(height: 8),
                  _StatusRow(label: 'Riverpod', value: '✅ 已集成', color: Colors.green),
                  SizedBox(height: 8),
                  _StatusRow(label: 'Termux 通信', value: '✅ 已验证', color: Colors.green),
                  SizedBox(height: 8),
                  _StatusRow(label: 'AI 通信', value: '✅ 已验证', color: Colors.green),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 快捷操作仪表盘 ──
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.deployed_code,
                  label: '部署中心',
                  subtitle: '环境检测',
                  color: Colors.blue,
                  onTap: () => context.push(RouteNames.deploy),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.terminal,
                  label: 'Termux',
                  subtitle: '通信验证',
                  color: Colors.green,
                  onTap: () => context.push(RouteNames.termuxTest),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.chat_outlined,
                  label: 'AI 对话',
                  subtitle: '通信验证',
                  color: Colors.purple,
                  onTap: () => context.push(RouteNames.aiChat),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Riverpod 状态管理验证 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Riverpod 状态管理验证', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
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
                        onPressed: () => ref.read(counterProvider.notifier).decrement(),
                        child: const Icon(Icons.remove),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: () => ref.read(counterProvider.notifier).reset(),
                        child: const Text('重置'),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.tonal(
                        onPressed: () => ref.read(counterProvider.notifier).increment(),
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
                  const _InfoRow(label: 'AI 通信', value: 'DeepSeek + mimo2codex'),
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
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.deployed_code_outlined), selectedIcon: Icon(Icons.deployed_code), label: '部署'),
          NavigationDestination(icon: Icon(Icons.terminal_outlined), selectedIcon: Icon(Icons.terminal), label: 'Termux'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat), label: 'AI'),
        ],
      ),
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
              Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.check_circle, color: colorScheme.primary, size: 28),
        const SizedBox(width: 12),
        Text('系统状态', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: variant)),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
