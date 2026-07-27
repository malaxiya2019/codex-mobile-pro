import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/counter_provider.dart';
import '../providers/home_state_provider.dart';

/// 首页 — Material 3 + Riverpod 集成验证页面
///
/// 展示内容：
/// 1. Material 3 组件（AppBar, Card, FilledButton, NavigationBar）
/// 2. Riverpod 状态管理（计数器 + 首页状态）
/// 3. 响应式布局
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 读取 Riverpod 状态
    final counter = ref.watch(counterProvider);
    final homeState = ref.watch(homeStateProvider);

    return Scaffold(
      // ── AppBar：Material 3 风格 ──
      appBar: AppBar(
        title: const Text('Codex Mobile Pro'),
        centerTitle: true,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          // 设置按钮
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

      // ── 主体内容 ──
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 状态卡片：验证 Material 3 Card ──
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '系统状态',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
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
                    label: '版本',
                    value: homeState.appVersion,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Riverpod 功能验证：计数器 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Riverpod 状态管理验证', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 20),

                  // 计数器显示
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

                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Material 3 FilledButton
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
                  _InfoRow(label: 'Flutter', value: '3.x'),
                  _InfoRow(label: 'Dart', value: '3.5+'),
                  _InfoRow(label: 'Android', value: '10–15 (API 29–35)'),
                  _InfoRow(label: '架构', value: 'Material 3 + Riverpod'),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── 底部导航栏：Material 3 NavigationBar ──
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('页面 ${index + 1} — 后续 Sprint 实现')),
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal),
            label: '终端',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '文件',
          ),
        ],
      ),
    );
  }
}

/// 状态行组件
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

/// 信息行组件
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
