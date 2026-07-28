import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';

/// 主题设置页面
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('主题设置'),
        backgroundColor: colorScheme.surfaceContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 主题模式 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题模式', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  _ThemeModeTile(
                    icon: Icons.light_mode,
                    label: '浅色模式',
                    selected: themeState.mode == ThemeModeOption.light,
                    onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeModeOption.light),
                  ),
                  _ThemeModeTile(
                    icon: Icons.dark_mode,
                    label: '深色模式',
                    selected: themeState.mode == ThemeModeOption.dark,
                    onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeModeOption.dark),
                  ),
                  _ThemeModeTile(
                    icon: Icons.settings_suggest,
                    label: '跟随系统',
                    selected: themeState.mode == ThemeModeOption.system,
                    onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeModeOption.system),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 字体设置 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('字体设置', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 16),

                  // 字体选择
                  Row(
                    children: [
                      Text('字体', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      DropdownButton<String>(
                        value: themeState.fontConfig.family,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'Roboto', child: Text('Roboto')),
                          DropdownMenuItem(value: 'Noto Sans SC', child: Text('Noto Sans SC')),
                          DropdownMenuItem(value: 'monospace', child: Text('等宽字体')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            ref.read(themeProvider.notifier).setFontFamily(value);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 字体缩放
                  Row(
                    children: [
                      Text('字体大小', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text('${(themeState.fontConfig.scale * 100).toInt()}%',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: themeState.fontConfig.scale,
                    min: 0.8,
                    max: 1.5,
                    divisions: 7,
                    label: '${(themeState.fontConfig.scale * 100).toInt()}%',
                    onChanged: (value) {
                      ref.read(themeProvider.notifier).setFontScale(value);
                    },
                  ),

                  // 字体预览
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('预览文本',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Codex Mobile Pro — 手机上的 AI IDE',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '支持简体中文、English 混合显示',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeModeTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? colorScheme.primary : null),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle, color: colorScheme.primary, size: 20)
          : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
