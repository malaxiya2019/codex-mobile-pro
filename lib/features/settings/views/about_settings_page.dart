import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_info.dart';

/// 关于页面 — 版本号 / 仓库 / 开源许可 / 更新日志入口
class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label已复制：$text')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        children: [
          // ── 应用标识 ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.terminal_rounded,
                    size: 48,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppInfo.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'v${AppInfo.versionLabel}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Android 上的 Codex 移动编程环境',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // ── 信息列表 ──
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('项目仓库'),
                  subtitle: const Text(AppInfo.githubUrl),
                  trailing: const Icon(Icons.copy, size: 18),
                  onTap: () => _copyToClipboard(
                    context,
                    AppInfo.githubUrl,
                    '仓库地址',
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('开源许可'),
                  subtitle: const Text(AppInfo.license),
                  trailing: const Icon(Icons.copy, size: 18),
                  onTap: () => _copyToClipboard(
                    context,
                    AppInfo.license,
                    '许可说明',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── 更新日志摘要 ──
          const Card(
            margin: EdgeInsets.symmetric(horizontal: 16),
            child: ExpansionTile(
              leading: Icon(Icons.history),
              title: Text('更新日志'),
              subtitle: Text('最近变更摘要'),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'v1.0.0\n'
                      '• Sprint 0-8：PoC → 部署中心 / AI 对话 / 内置终端 / '
                      '文件管理 / GitHub 集成 / AI 编程增强\n'
                      '• 终端：Native PTY 流式缓冲、PRoot guest cwd 规范化\n'
                      '• AI：默认接入本地 mimo2codex（zero-auth）\n'
                      '完整变更见仓库 CHANGELOG.md',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'Codex Mobile Pro — 在手机上编程',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
