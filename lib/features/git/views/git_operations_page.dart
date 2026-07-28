import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/git_repository.dart';
import '../services/git_service.dart';
import '../../../core/logger/log_service.dart';
import '../../../core/ai/ai_provider.dart';
import '../../editor/providers/editor_provider.dart';

/// Git 操作页面
///
/// 展示仓库详情和 Git 操作入口：
/// - 仓库信息
/// - Clone 到本地
/// - 分支管理
/// - 提交历史
/// - 状态查看
class GitOperationsPage extends ConsumerStatefulWidget {
  final GitRepository repo;

  const GitOperationsPage({super.key, required this.repo});

  @override
  ConsumerState<GitOperationsPage> createState() => _GitOperationsPageState();
}

class _GitOperationsPageState extends ConsumerState<GitOperationsPage> {
  final _gitService = GitService();
  bool _isCloning = false;
  String? _clonePath;
  String? _cloneError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repo.name),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surfaceContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 仓库信息卡片 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.repo.isPrivate ? Icons.lock : Icons.public,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.repo.fullName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.repo.description != null &&
                      widget.repo.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(widget.repo.description!),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (widget.repo.language != null)
                        _InfoChip(
                          icon: Icons.code,
                          label: widget.repo.language!,
                        ),
                      if (widget.repo.starCount != null)
                        _InfoChip(
                          icon: Icons.star_border,
                          label: '${widget.repo.starCount} stars',
                        ),
                      if (widget.repo.forkCount != null)
                        _InfoChip(
                          icon: Icons.fork_right,
                          label: '${widget.repo.forkCount} forks',
                        ),
                      if (widget.repo.defaultBranch != null)
                        _InfoChip(
                          icon: Icons.call_split,
                          label: widget.repo.defaultBranch!,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Clone 区域 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '克隆到本地',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'HTTPS: ${widget.repo.cloneUrl ?? widget.repo.url}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  if (_isCloning)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                  if (_cloneError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _cloneError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: _isCloning ? null : _cloneRepo,
                    icon: _isCloning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(_isCloning ? '克隆中...' : '克隆到本地'),
                  ),
                  if (_clonePath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '已克隆到: $_clonePath',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 快捷操作 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Git 操作',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  _ActionButton(
                    icon: Icons.list_alt,
                    label: '查看状态',
                    onTap: _showStatus,
                  ),
                  const Divider(height: 1),
                  _ActionButton(
                    icon: Icons.call_split,
                    label: '分支管理',
                    onTap: _showBranches,
                  ),
                  const Divider(height: 1),
                  _ActionButton(
                    icon: Icons.history,
                    label: '提交历史',
                    onTap: _showLog,
                  ),
                  const Divider(height: 1),
                  _ActionButton(
                    icon: Icons.add_circle_outline,
                    label: '新建提交',
                    onTap: _showCommitDialog,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cloneRepo() async {
    if (widget.repo.cloneUrl == null) {
      setState(() => _cloneError = '没有可用的 Clone URL');
      return;
    }

    setState(() {
      _isCloning = true;
      _cloneError = null;
    });

    try {
      final home = '/data/data/com.termux/files/home';
      final destDir = '${home}/${widget.repo.name}';

      final result = await _gitService.clone(
        widget.repo.cloneUrl!,
        destDir,
      );

      if (result.success) {
        setState(() {
          _clonePath = destDir;
          _isCloning = false;
        });
        _showSnackBar('克隆成功到: $destDir');
        LogService.info('Git', '克隆仓库成功: ${widget.repo.fullName}');
      } else {
        setState(() {
          _cloneError = result.error ?? '克隆失败';
          _isCloning = false;
        });
      }
    } catch (e) {
      setState(() {
        _cloneError = '克隆异常: $e';
        _isCloning = false;
      });
    }
  }

  Future<void> _showStatus() async {
    if (_clonePath == null) {
      _showSnackBar('请先克隆仓库');
      return;
    }

    final status = await _gitService.status(_clonePath!);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => _StatusSheet(status: status),
    );
  }

  Future<void> _showBranches() async {
    if (_clonePath == null) {
      _showSnackBar('请先克隆仓库');
      return;
    }

    final branches = await _gitService.branches(_clonePath!);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => _BranchesSheet(
        branches: branches,
        currentPath: _clonePath!,
        gitService: _gitService,
      ),
    );
  }

  Future<void> _showLog() async {
    if (_clonePath == null) {
      _showSnackBar('请先克隆仓库');
      return;
    }

    final commits = await _gitService.log(_clonePath!);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => _LogSheet(commits: commits),
    );
  }

  /// 使用 AI 生成 Commit Message
  Future<String?> _generateCommitMessage() async {
    if (_clonePath == null) return null;

    try {
      // 获取 git diff
      final diff = await _gitService.diff(_clonePath!);
      if (diff == null || diff.isEmpty) {
        if (mounted) {
          _showSnackBar('没有检测到变更内容');
        }
        return null;
      }

      // 使用默认 AI Provider
      final editorNotifier = ref.read(editorProvider.notifier);
      final aiProvider = editorNotifier.aiProvider;
      if (aiProvider == null) {
        if (mounted) {
          _showSnackBar('AI 服务未初始化');
        }
        return null;
      }

      final systemPrompt = '''你是一个 Git Commit Message 专家。
根据 git diff 输出，生成规范的 Commit Message。

格式：<type>(<scope>): <简短描述>

类型：feat/fix/refactor/docs/style/test/chore/ci
scope：影响范围

返回 JSON：
{
  "message": "完整的 commit message"
}

要求：第一行不超过 72 字符，用中文写描述。''';

      final response = await aiProvider.chat(
        messages: [
          ChatMessageInput(role: 'system', content: systemPrompt),
          ChatMessageInput(role: 'user', content: '''根据以下 git diff 生成 commit message：

\`\`\`diff
${diff.length > 8000 ? diff.substring(0, 8000) + '\n... (截断)' : diff}
\`\`\`

Return JSON output only.'''),
        ],
        temperature: 0.3,
        maxTokens: 512,
      );

      // 解析 JSON
      try {
        final jsonStart = response.indexOf('{');
        final jsonEnd = response.lastIndexOf('}');
        if (jsonStart != -1 && jsonEnd != -1) {
          final jsonStr = response.substring(jsonStart, jsonEnd + 1);
          final msgMatch = RegExp(r'"message"\s*:\s*"(.+?)"\s*[,}]', dotAll: true).firstMatch(jsonStr);
          if (msgMatch != null) {
            return msgMatch.group(1)!.replaceAll('\\n', '\n');
          }
        }
      } catch (_) {}

      return response.trim();
    } catch (e) {
      if (mounted) {
        _showSnackBar('生成 Commit Message 失败: $e');
      }
      return null;
    }
  }

  Future<void> _showCommitDialog() async {
    if (_clonePath == null) {
      _showSnackBar('请先克隆仓库');
      return;
    }

    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提交更改'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '提交信息',
            hintText: '描述本次更改...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('AI 生成'),
            onPressed: () async {
              final msg = await _generateCommitMessage();
              if (msg != null && msg.isNotEmpty) {
                controller.text = msg;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: msg.length),
                );
              }
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('提交'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final addResult = await _gitService.addAll(_clonePath!);
      if (addResult.success) {
        final commitResult = await _gitService.commit(_clonePath!, result);
        if (mounted) {
          _showSnackBar(
            commitResult.success ? '提交成功' : '提交失败: ${commitResult.error}',
          );
        }
      } else {
        if (mounted) {
          _showSnackBar('暂存失败: ${addResult.error}');
        }
      }
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ── 辅助组件 ──

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
      dense: true,
    );
  }
}

class _StatusSheet extends StatelessWidget {
  final GitStatus status;

  const _StatusSheet({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '仓库状态',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatusBadge(
                  label: '分支',
                  value: status.currentBranch ?? '-',
                ),
                const SizedBox(width: 12),
                _StatusBadge(
                  label: '变更',
                  value: '${status.changes.length}',
                ),
                const SizedBox(width: 12),
                _StatusBadge(
                  label: '领先',
                  value: '${status.ahead}',
                ),
                const SizedBox(width: 12),
                _StatusBadge(
                  label: '落后',
                  value: '${status.behind}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (status.isClean)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle,
                          size: 48, color: Colors.green),
                      const SizedBox(height: 8),
                      const Text('工作区干净，没有未提交的变更'),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: status.changes.map((c) {
                    IconData icon;
                    Color color;
                    switch (c.type) {
                      case GitChangeType.added:
                        icon = Icons.add_circle_outline;
                        color = Colors.green;
                        break;
                      case GitChangeType.modified:
                        icon = Icons.edit;
                        color = Colors.orange;
                        break;
                      case GitChangeType.deleted:
                        icon = Icons.remove_circle_outline;
                        color = Colors.red;
                        break;
                      case GitChangeType.renamed:
                        icon = Icons.drive_file_rename_outline;
                        color = Colors.blue;
                        break;
                      case GitChangeType.untracked:
                        icon = Icons.help_outline;
                        color = Colors.grey;
                        break;
                    }
                    return ListTile(
                      leading: Icon(icon, color: color, size: 20),
                      title: Text(c.path, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                      dense: true,
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final String value;

  const _StatusBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _BranchesSheet extends StatelessWidget {
  final List<GitBranch> branches;
  final String currentPath;
  final GitService gitService;

  const _BranchesSheet({
    required this.branches,
    required this.currentPath,
    required this.gitService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('分支管理', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: branches.isEmpty
                  ? const Center(child: Text('没有分支'))
                  : ListView(
                      controller: scrollController,
                      children: branches.map((b) => ListTile(
                        leading: Icon(
                          b.isCurrent ? Icons.check_circle : Icons.call_split,
                          color: b.isCurrent ? Colors.green : null,
                        ),
                        title: Text(b.name),
                        subtitle: b.commitSha != null ? Text(b.commitSha!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')) : null,
                        trailing: b.isCurrent ? const Icon(Icons.arrow_forward_ios, size: 14) : null,
                        dense: true,
                      )).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogSheet extends StatelessWidget {
  final List<GitCommit> commits;

  const _LogSheet({required this.commits});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('提交历史', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: commits.isEmpty
                  ? const Center(child: Text('没有提交记录'))
                  : ListView(
                      controller: scrollController,
                      children: commits.map((c) => ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(c.sha.substring(0, 4), style: TextStyle(fontSize: 9, color: theme.colorScheme.onPrimaryContainer)),
                        ),
                        title: Text(c.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${c.author}  ${c.date != null ? _fmtDate(c.date!) : ''}', style: const TextStyle(fontSize: 11)),
                        dense: true,
                      )).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}
