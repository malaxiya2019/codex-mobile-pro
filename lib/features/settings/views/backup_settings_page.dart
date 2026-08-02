import 'package:flutter/material.dart';

import '../../../core/config/backup_service.dart';
import '../../../core/logger/log_service.dart';

/// 备份与恢复页面
///
/// 备份：主题 / 语言 / 终端设置 / 登录（GitHub）/ 工作区 / 项目列表
/// 恢复：从文档目录 backups/ 选择备份文件写回（重启 App 后完全生效）
class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  List<BackupEntry> _backups = const [];
  bool _loading = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _reloadBackups();
  }

  Future<void> _reloadBackups() async {
    final backups = await BackupService.listBackups();
    if (!mounted) return;
    setState(() => _backups = backups);
  }

  Future<void> _export() async {
    setState(() => _loading = true);
    try {
      final path = await BackupService.exportBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份完成：$path')),
      );
      await _reloadBackups();
    } catch (e) {
      LogService.error('BackupUI', '备份失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(BackupEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复备份'),
        content: Text(
          '将用「${entry.fileName}」覆盖当前的主题、语言、终端设置、'
          'GitHub 登录与工作区配置。\n\n恢复后请重启 App 使全部设置生效。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _restoring = true);
    try {
      final restored = await BackupService.restore(entry.filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复完成（${restored.length} 项），请重启 App 生效')),
      );
    } catch (e) {
      LogService.error('BackupUI', '恢复失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 备份 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.save_alt, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '备份配置',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '导出主题、语言、终端设置、GitHub 登录、工作区与项目列表\n'
                    '（保存到应用文档目录，并复制一份到 Download）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _export,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt),
                      label: Text(_loading ? '备份中...' : '立即备份'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 恢复 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.restore, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '从备份恢复',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_backups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          _restoring ? '恢复中...' : '暂无备份文件',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._backups.map(
                      (entry) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(entry.fileName),
                        subtitle: Text(
                          '${_formatTime(entry.createdAt)} · ${_formatSize(entry.size)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _restoring ? null : () => _restore(entry),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              '备份文件为 JSON 格式，可手动编辑后恢复',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}
