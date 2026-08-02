import 'package:flutter/material.dart';

import '../../../core/config/app_info.dart';
import '../../../core/logger/log_service.dart';
import '../../../core/update/update_installer_channel.dart';
import '../services/update_checker.dart';
import '../services/update_downloader.dart';

/// 检查更新页面
///
/// 查询 GitHub 最新 Release → 下载 APK → 拉起系统安装器。
class UpdateSettingsPage extends StatefulWidget {
  const UpdateSettingsPage({super.key});

  @override
  State<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends State<UpdateSettingsPage> {
  final UpdateChecker _checker = UpdateChecker(
    currentVersion: AppInfo.version,
  );
  final UpdateDownloader _downloader = UpdateDownloader();

  bool _checking = false;
  UpdateInfo? _update;

  // 下载状态
  bool _downloading = false;
  double _progress = 0;
  String? _downloadPath;

  @override
  void dispose() {
    _checker.dispose();
    _downloader.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _update = null;
      _downloadPath = null;
      _progress = 0;
    });
    try {
      final update = await _checker.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _update = update;
      });
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本')),
        );
      }
    } catch (e) {
      LogService.error('UpdateUI', '检查更新失败: $e');
      if (!mounted) return;
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：$e')),
      );
    }
  }

  Future<void> _download() async {
    final update = _update;
    final url = update?.downloadUrl;
    if (update == null || url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该 Release 没有 APK 资产')),
      );
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      final path = await _downloader.download(
        url,
        fileName: 'codex-mobile-pro-${update.version}.apk',
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadPath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成，点击「安装」开始更新')),
      );
    } catch (e) {
      LogService.error('UpdateUI', '下载失败: $e');
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    }
  }

  Future<void> _install() async {
    final path = _downloadPath;
    if (path == null) return;
    try {
      await UpdateInstallerChannel.installApk(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已拉起系统安装器，请按系统提示完成安装')),
      );
    } catch (e) {
      LogService.error('UpdateUI', '拉起安装器失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拉起安装器失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final update = _update;

    return Scaffold(
      appBar: AppBar(title: const Text('检查更新')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 当前版本 ──
          Card(
            child: ListTile(
              leading: Icon(Icons.info_outline, color: colorScheme.primary),
              title: const Text('当前版本'),
              subtitle: const Text('v${AppInfo.versionLabel}'),
              trailing: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.icon(
                      onPressed: _downloadPath != null ? null : _check,
                      icon: const Icon(Icons.system_update_alt),
                      label: const Text('检查更新'),
                    ),
            ),
          ),

          if (_downloading) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('正在下载更新…'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 8),
                    Text(
                      '${(_progress * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (update != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.new_releases, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              '发现新版本 v${update.version}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (update.publishedAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '发布于 ${update.publishedAt!.toLocal()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (update.releaseNotes != null &&
                            update.releaseNotes!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            update.releaseNotes!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _downloadPath != null
                        ? FilledButton.icon(
                            onPressed: _install,
                            icon: const Icon(Icons.system_update_alt),
                            label: const Text('安装更新'),
                          )
                        : OutlinedButton.icon(
                            onPressed: _downloading ? null : _download,
                            icon: const Icon(Icons.download),
                            label: Text(
                              update.hasApkAsset ? '下载 APK' : '无 APK 资产',
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Text(
            '更新来源：GitHub Release（${UpdateChecker.defaultRepoOwner}/'
            '${UpdateChecker.defaultRepoName}）\n'
            '下载完成后将拉起系统安装器，'
            '首次安装未知来源应用时请在系统弹窗中允许',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
