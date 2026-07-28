import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/detector/detection_result.dart';
import '../providers/deploy_provider.dart';

class DeployPage extends ConsumerWidget {
  const DeployPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(deployStatusProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('部署中心'),
        centerTitle: true,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          if (status.state == DeployState.completed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新检测',
              onPressed: () =>
                  ref.read(deployStatusProvider.notifier).checkAll(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 顶部状态卡片 ──
          _buildSummaryCard(context, status),

          const SizedBox(height: 16),

          // ── 检测按钮 ──
          if (status.state == DeployState.idle ||
              status.state == DeployState.error)
            Center(
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(deployStatusProvider.notifier).checkAll(),
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始检测'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 48),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),

          // ── 进度条（检测中） ──
          if (status.state == DeployState.checking) ...[
            LinearProgressIndicator(
              value: status.results.isEmpty
                  ? null
                  : status.results.length / status.totalDetectors,
            ),
            const SizedBox(height: 8),
            Text(
              status.summary,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
          ],

          // ── 检测结果列表（按类别分组） ──
          if (status.results.isNotEmpty) ...[
            // ⭐ Runtime 运行环境
            _buildCategorySection(
              context: context,
              title: '⚡ 运行环境（Runtime）',
              description: '缺失显示红色 — 影响 App 基本功能',
              results: status.runtimeResults,
              ref: ref,
              showMissingAsRed: true,
            ),

            const SizedBox(height: 20),

            // 🛠 Development 开发环境
            _buildCategorySection(
              context: context,
              title: '🛠 开发环境（Development）',
              description: '缺失显示黄色 — 不影响 App 基本功能',
              results: status.developmentResults,
              ref: ref,
              showMissingAsRed: false,
            ),
          ],

          // ── 空状态 ──
          if (status.results.isEmpty && status.state == DeployState.idle)
            _buildEmptyState(context),
        ],
      ),
    );
  }

  // ── 类别区块 ──
  Widget _buildCategorySection({
    required BuildContext context,
    required String title,
    required String description,
    required List<DetectionResult> results,
    required WidgetRef ref,
    required bool showMissingAsRed,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (results.isEmpty) return const SizedBox.shrink();

    final installed = results
        .where((r) => r.status == DetectionStatus.installed)
        .length;
    final missing =
        results.where((r) => r.status == DetectionStatus.missing).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '✅ $installed / ❌ $missing',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 8),
        ...results.map(
          (result) => _buildResultCard(
            context,
            result,
            ref,
            showMissingAsRed: showMissingAsRed,
          ),
        ),
      ],
    );
  }

  // ── 顶部摘要卡片 ──

  Widget _buildSummaryCard(BuildContext context, DeployStatus status) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color cardColor;
    IconData icon;
    if (status.state == DeployState.completed && status.allInstalled) {
      cardColor = Colors.green;
      icon = Icons.check_circle;
    } else if (status.state == DeployState.completed) {
      cardColor = Colors.orange;
      icon = Icons.warning_amber;
    } else if (status.state == DeployState.checking) {
      cardColor = Colors.blue;
      icon = Icons.sync;
    } else {
      cardColor = colorScheme.primary;
      icon = Icons.info_outline;
    }

    return Card(
      elevation: 0,
      color: cardColor.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: cardColor, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.state == DeployState.completed
                        ? status.allInstalled
                            ? '🎉 开发环境就绪'
                            : '部分工具缺失'
                        : 'Codex 开发环境',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status.summary,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (status.lastChecked != null)
              Text(
                '${DateTime.now().difference(status.lastChecked!).inMinutes}m前',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  // ── 单个结果卡片 ──

  Widget _buildResultCard(
    BuildContext context,
    DetectionResult result,
    WidgetRef ref, {
    bool showMissingAsRed = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color statusColor;
    IconData statusIcon;
    switch (result.status) {
      case DetectionStatus.installed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case DetectionStatus.missing:
        // Runtime 缺失 → 红色，Development 缺失 → 黄色
        statusColor = showMissingAsRed ? Colors.red : Colors.amber.shade700;
        statusIcon = Icons.error;
        break;
      case DetectionStatus.checking:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        break;
      case DetectionStatus.error:
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        break;
      case DetectionStatus.unknown:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
        break;
    }

    // 缺失时显示友好提示
    final displayName = result.status == DetectionStatus.missing &&
            result.missingHint != null
        ? result.missingHint!
        : '${result.icon} ${result.name}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: result.status == DetectionStatus.installed
              ? null
              : () =>
                  ref.read(deployStatusProvider.notifier).checkOne(result.id),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 状态图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),

                // 名称 + 详情
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (result.version != null)
                        Text(
                          result.version!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant),
                        ),
                      if (result.errorMessage != null &&
                          result.status != DetectionStatus.installed)
                        Text(
                          result.errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red.shade300),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // 路径
                if (result.path != null)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        result.path!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                const SizedBox(width: 8),

                // 时长
                if (result.durationMs > 0)
                  Text(
                    '${result.durationMs}ms',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant, fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 空状态 ──

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.code_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('系统状态仪表盘',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            '检测手机上的开发工具链状态\n点击「开始检测」查看已安装的工具',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}
