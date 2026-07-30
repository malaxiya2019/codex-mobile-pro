import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/detector/detection_result.dart';
import '../../../runtime/runtime_dependency.dart';
import '../../../runtime/runtime_detector.dart';
import '../../../runtime/runtime_manager.dart';
import '../providers/deploy_provider.dart';

/// ====================================================================
/// 部署中心页面
///
/// 从"环境检测页面"升级为"Coding Runtime 管理中心"。
///
/// 布局：
///   1. 顶部状态卡片
///   2. 基础 Runtime（⚡ Basic Runtime）
///   3. Coding Runtime（💻 Coding Runtime）
///   4. AI Runtime（🤖 AI Runtime）
///   5. Development Runtime（🛠 Development）
///   6. 操作按钮（一键部署 / 验证 / 重新检测）
/// ====================================================================

class DeployPage extends ConsumerStatefulWidget {
  const DeployPage({super.key});

  @override
  ConsumerState<DeployPage> createState() => _DeployPageState();
}

class _DeployPageState extends ConsumerState<DeployPage> {
  /// 验证结果缓存
  List<VerificationResult>? _verificationResults;

  /// 滚动的文本控制器
  final _installLogController = StreamController<String>.broadcast();

  @override
  void initState() {
    super.initState();
    // 页面打开时自动初始化
    Future.microtask(() {
      ref.read(deployStatusProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _installLogController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── 顶部状态卡片 ──
                _buildSummaryCard(context, status),

                const SizedBox(height: 16),

                // ── 网络状态警告（DNS 失败时显示） ──
                if (status.detectionResult != null && !status.networkOk)
                  _buildNetworkWarning(context, status),

                const SizedBox(height: 8),

                // ── 检测 / 安装进度 ──
                if (status.state == DeployState.checking)
                  _buildCheckingIndicator(context, status),

                if (status.state == DeployState.installing)
                  _buildInstallingIndicator(context, status),

                if (status.state == DeployState.verifying)
                  _buildVerifyingIndicator(context),

                // ── 开始检测按钮 ──
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

                // ── 检测结果（不含底部操作按钮）──
                if (status.detectionResult != null) ...[
                  // ⚡ 基础 Runtime
                  if (status.detectionResult!.basic.isNotEmpty)
                    _buildCategorySection(
                      context: context,
                      title: '⚡ Android 基础环境',
                      icon: Icons.settings,
                      results: status.detectionResult!.basic,
                      ref: ref,
                      showActionButtons: false,
                    ),

                  const SizedBox(height: 16),

                  // 📦 Termux Runtime
                  if (status.detectionResult!.termux.isNotEmpty)
                    _buildCategorySection(
                      context: context,
                      title: '📦 Termux Runtime',
                      icon: Icons.terminal,
                      results: status.detectionResult!.termux,
                      ref: ref,
                      showActionButtons: false,
                    ),

                  const SizedBox(height: 16),

                  // 💻 Coding Runtime
                  if (status.detectionResult!.coding.isNotEmpty)
                    _buildCategorySection(
                      context: context,
                      title: '💻 Coding Runtime',
                      icon: Icons.code,
                      results: status.detectionResult!.coding,
                      ref: ref,
                      showActionButtons: true,
                    ),

                  const SizedBox(height: 16),

                  // 🤖 AI Runtime
                  if (status.detectionResult!.ai.isNotEmpty)
                    _buildCategorySection(
                      context: context,
                      title: '🤖 AI Runtime',
                      icon: Icons.auto_awesome,
                      results: status.detectionResult!.ai,
                      ref: ref,
                      showActionButtons: true,
                    ),

                  const SizedBox(height: 16),

                  // 🛠 Development
                  if (status.detectionResult!.development.isNotEmpty)
                    _buildCategorySection(
                      context: context,
                      title: '🛠 Development',
                      icon: Icons.build,
                      results: status.detectionResult!.development,
                      ref: ref,
                      showActionButtons: false,
                      showMissingAsRed: false,
                      description: '可选 — 仅用于 Flutter 项目开发，不影响 App 基本运行',
                    ),
                ],

                // ── 验证结果 ──
                if (_verificationResults != null) ...[
                  const SizedBox(height: 16),
                  _buildVerificationResults(context, _verificationResults!),
                ],

                // ── 空状态 ──
                if (status.detectionResult == null &&
                    status.state == DeployState.idle)
                  _buildEmptyState(context),
              ],
            ),
          ),

          // ── 固定底部操作栏 ──
          if (status.detectionResult != null)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _buildActionButtons(context, status),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 类别区块
  // ════════════════════════════════════════════════════════════════

  Widget _buildCategorySection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<DetectionResult> results,
    required WidgetRef ref,
    bool showActionButtons = true,
    bool showMissingAsRed = true,
    String? description,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final installed =
        results.where((r) => r.status == DetectionStatus.installed).length;
    final total = results.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '✅ $installed / $total',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
        const SizedBox(height: 8),

        // 结果卡片
        ...results.map(
          (result) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _buildResultCard(
              context,
              result,
              ref,
              showMissingAsRed: showMissingAsRed,
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 顶部状态卡片
  // ════════════════════════════════════════════════════════════════

  Widget _buildSummaryCard(BuildContext context, DeployStatus status) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color cardColor;
    IconData iconData;
    String title;
    String subtitle;

    if (status.state == DeployState.installing) {
      cardColor = Colors.blue;
      iconData = Icons.downloading;
      title = '正在部署 Coding Runtime';
      subtitle = status.currentProgress?.message ?? '准备中...';
    } else if (status.state == DeployState.verifying) {
      cardColor = Colors.blue;
      iconData = Icons.verified;
      title = '验证环境中';
      subtitle = '请稍候...';
    } else if (status.state == DeployState.completed &&
        status.detectionResult != null) {
      final detection = status.detectionResult!;
      final ready = detection.codingReady;
      final installed = detection.codingInstalled;
      final total = detection.codingTotal;
      final unsupported = detection.codingUnsupported;
      final missing = total - installed - unsupported;

      if (ready) {
        cardColor = Colors.green;
        iconData = Icons.check_circle;
        title = '✅ Coding Environment READY';
        subtitle = detection.summary;
      } else if (missing == 0 && unsupported > 0) {
        cardColor = Colors.green;
        iconData = Icons.check_circle;
        title = '✅ Coding Environment 可用';
        subtitle = '已安装 $installed 个，$unsupported 个暂不支持自动安装';
      } else {
        cardColor = Colors.orange;
        iconData = Icons.warning_amber;
        title = '⚠️ Coding Environment 未就绪';
        subtitle = '$installed/$total 已安装 · $missing 个待安装 · $unsupported 个暂不支持';
      }
    } else if (status.state == DeployState.checking) {
      cardColor = Colors.blue;
      iconData = Icons.sync;
      title = '检测中';
      subtitle = '请稍候...';
    } else if (status.state == DeployState.error) {
      final errMsg = status.errorMessage ?? '';
      final isNetworkError = errMsg.contains('网络不可用') || errMsg.contains('DNS');
      cardColor = isNetworkError ? Colors.red : Colors.orange;
      iconData = isNetworkError ? Icons.wifi_off : Icons.error;
      title = isNetworkError ? '📡 网络连接失败' : '检测出错';
      subtitle = errMsg;
    } else {
      cardColor = colorScheme.primary;
      iconData = Icons.info_outline;
      title = 'Codex 开发环境';
      subtitle = '检测手机上的开发工具链状态';
    }

    return Card(
      elevation: 0,
      color: cardColor.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(iconData, color: cardColor, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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

  // ════════════════════════════════════════════════════════════════
  // 检测进度
  // ════════════════════════════════════════════════════════════════

  /// 网络错误警告卡片
  Widget _buildNetworkWarning(BuildContext context, DeployStatus status) {
    final theme = Theme.of(context);
    final suggestion = status.networkSuggestion ?? '请检查网络连接后重试';

    return Card(
      elevation: 0,
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.red.shade700, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '📡 网络连接异常',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                suggestion,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.6,
                  color: Colors.red.shade900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref.read(deployStatusProvider.notifier).checkAll();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新检测网络'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckingIndicator(
      BuildContext context, DeployStatus status) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在检测系统环境...'),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 安装进度
  // ════════════════════════════════════════════════════════════════

  Widget _buildInstallingIndicator(
      BuildContext context, DeployStatus status) {
    final theme = Theme.of(context);
    final progress = status.currentProgress;

    if (progress == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('准备安装...'),
            ],
          ),
        ),
      );
    }

    final toolName = RuntimeDependency.forTool(progress.tool)?.displayName ??
        progress.tool.name;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.downloading, size: 20),
                const SizedBox(width: 8),
                Text(
                  '部署 Coding Runtime',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '[$toolName] ${progress.message}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (progress.progress > 0)
              Text(
                '${(progress.progress * 100).toInt()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 验证进度
  // ════════════════════════════════════════════════════════════════

  Widget _buildVerifyingIndicator(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('验证 Coding 环境...'),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 操作按钮
  // ════════════════════════════════════════════════════════════════

  Widget _buildActionButtons(BuildContext context, DeployStatus status) {

    final detection = status.detectionResult;

    if (detection == null) return const SizedBox.shrink();

    final codingMissing = detection.coding
        .where((r) => r.status == DetectionStatus.missing)
        .length;

    return Column(
      children: [
        // 一键部署（仅在有可安装的工具时显示）
        if (codingMissing > 0 && !status.isInstalling)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref.read(deployStatusProvider.notifier)
                    .installCodingRuntime();
              },
              icon: const Icon(Icons.rocket_launch),
              label: Text('一键部署 Coding 环境'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ),

        if (codingMissing > 0 && !status.isInstalling)
          const SizedBox(height: 8),

        // 验证 & 重新检测
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: status.isInstalling
                    ? null
                    : () async {
                        final results = await ref
                            .read(deployStatusProvider.notifier)
                            .verifyEnvironment();
                        setState(() => _verificationResults = results);
                      },
                icon: const Icon(Icons.verified, size: 18),
                label: const Text('验证环境'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: status.isInstalling
                    ? null
                    : () {
                        ref.read(deployStatusProvider.notifier).checkAll();
                      },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新检测'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 验证结果
  // ════════════════════════════════════════════════════════════════

  Widget _buildVerificationResults(
      BuildContext context, List<VerificationResult> results) {
    final theme = Theme.of(context);
    final allPassed = results.every((r) => r.success);

    return Card(
      elevation: 0,
      color: allPassed
          ? Colors.green.withValues(alpha: 0.12)
          : Colors.orange.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allPassed ? Icons.check_circle : Icons.warning,
                  color: allPassed ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  allPassed
                      ? '✅ Coding Environment Ready'
                      : '⚠️ 部分验证未通过',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...results.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      r.success ? Icons.check_circle : Icons.error,
                      size: 16,
                      color: r.success ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.tool,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.success
                            ? r.output ?? '正常'
                            : r.error ?? '未找到',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: r.success
                              ? theme.colorScheme.onSurfaceVariant
                              : Colors.red.shade300,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 单个结果卡片
  // ════════════════════════════════════════════════════════════════

  Widget _buildResultCard(
    BuildContext context,
    DetectionResult result,
    WidgetRef ref, {
    bool showMissingAsRed = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = ref.watch(deployStatusProvider);

    Color statusColor;
    IconData statusIcon;
    switch (result.status) {
      case DetectionStatus.installed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case DetectionStatus.missing:
        statusColor = Colors.orange;
        statusIcon = Icons.info_outline;
        break;
      case DetectionStatus.unsupported:
        statusColor = Colors.grey;
        statusIcon = Icons.block;
        break;
      case DetectionStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case DetectionStatus.blocked:
        statusColor = Colors.grey;
        statusIcon = Icons.block;
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

    final displayName = result.status == DetectionStatus.missing &&
            result.missingHint != null
        ? result.missingHint!
        : '${result.icon} ${result.name}';

    // 判断是否显示安装按钮
    final showInstall = result.status == DetectionStatus.missing &&
        _canInstall(result.id) &&
        !status.isInstalling;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: result.status == DetectionStatus.installed
            ? null
            : () => ref
                .read(deployStatusProvider.notifier)
                .checkOne(result.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      result.path!,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // 安装按钮
              if (showInstall)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _installTool(result.id),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('安装', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),

              // 配置按钮（DeepSeek Key）
              if (result.id == 'deepseek_key' &&
                  result.status == DetectionStatus.missing)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _showApiKeyDialog(context),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('配置', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),

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
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 工具方法
  // ════════════════════════════════════════════════════════════════

  /// 哪些工具支持自动安装
  /// node 已实现完整 Node.js 安装流程（Termux .deb + SHA256 + 健康检查）
  /// git/python/codex/mimo2codex 暂未实现自动安装
  bool _canInstall(String id) {
    // node 已实现完整安装流程
    // ubuntu 已实现 rootfs + proot 安装流程
    // git/python/codex/mimo2codex 暂未实现安装
    return id == 'node' || id == 'ubuntu';
  }

  /// 安装工具
  void _installTool(String id) {
    RuntimeTool? tool;
    switch (id) {
      case 'node':
        tool = RuntimeTool.node;
        break;
      case 'ubuntu':
        tool = RuntimeTool.ubuntu;
        break;
      case 'git':
        tool = RuntimeTool.git;
        break;
      case 'python':
        tool = RuntimeTool.python;
        break;
      case 'codex':
        tool = RuntimeTool.codexCli;
        break;
      case 'mimo2codex':
        tool = RuntimeTool.mimo2codex;
        break;
    }
    if (tool != null) {
      ref.read(deployStatusProvider.notifier).installTool(tool);
    }
  }

  /// DeepSeek API Key 配置对话框
  void _showApiKeyDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置 DeepSeek API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '输入你的 DeepSeek API Key，用于 AI 代码补全功能。\n'
              'Key 将保存在 App 私有目录中。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'sk-...',
                border: OutlineInputBorder(),
                labelText: 'API Key',
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                _saveApiKey(key);
                Navigator.pop(ctx);
                ref.read(deployStatusProvider.notifier).checkOne('deepseek_key');
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 保存 API Key
  Future<void> _saveApiKey(String key) async {
    try {
      final dir = Directory('${RuntimeManager.instance.environment?.runtimeDir ?? ""}/.mimo2codex');
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/.env');
      await file.writeAsString('DS_API_KEY=$key\n');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  // 空状态
  // ════════════════════════════════════════════════════════════════

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
          Text('Coding Runtime 管理中心',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            '检测并安装开发工具链\n一键部署 Node.js / Git / Python / Codex CLI',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

