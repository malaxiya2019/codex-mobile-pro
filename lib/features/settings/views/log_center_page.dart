import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/log_service.dart';
import '../services/log_parser.dart';

/// 日志中心 — 统一查看 App 日志
///
/// 功能：
/// - 查看完整日志（含轮转文件）
/// - 级别过滤（全部 / DEBUG / INFO / WARN / ERROR）
/// - 崩溃过滤（仅显示全局捕获的崩溃日志）
/// - 导出到 Download / 清除
class LogCenterPage extends ConsumerStatefulWidget {
  const LogCenterPage({super.key, this.logsLoader});

  /// 日志读取函数（测试注入用；默认读取真实日志文件）
  final Future<String> Function()? logsLoader;

  @override
  ConsumerState<LogCenterPage> createState() => _LogCenterPageState();
}

/// 过滤选项
enum _LogFilter {
  all('全部', null, false),
  debug('DEBUG', LogEntryLevel.debug, false),
  info('INFO', LogEntryLevel.info, false),
  warning('WARN', LogEntryLevel.warning, false),
  error('ERROR', LogEntryLevel.error, false),
  crash('崩溃', LogEntryLevel.error, true);

  final String label;
  final LogEntryLevel? minLevel;
  final bool onlyCrash;
  const _LogFilter(this.label, this.minLevel, this.onlyCrash);
}

class _LogCenterPageState extends ConsumerState<LogCenterPage> {
  List<LogEntry> _allEntries = const [];
  _LogFilter _filter = _LogFilter.all;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final text = await (widget.logsLoader ?? LogService.readAllLogs)();
    if (!mounted) return;
    setState(() {
      _allEntries = parseLogText(text);
      _loading = false;
    });
  }

  List<LogEntry> get _visibleEntries => filterLogEntries(
        _allEntries,
        minLevel: _filter.minLevel ?? LogEntryLevel.debug,
        onlyCrash: _filter.onlyCrash,
      );

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await LogService.exportLogsToDownload();
    if (!mounted) return;
    messenger.showSnackBar(
      path != null
          ? SnackBar(content: Text('日志已导出：$path'))
          : const SnackBar(content: Text('导出失败：无日志或权限不足')),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除日志'),
        content: const Text('确定清除全部日志吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await LogService.clearLogs();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEntries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志中心'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: '导出',
            icon: const Icon(Icons.ios_share),
            onPressed: _export,
          ),
          IconButton(
            tooltip: '清除',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(context),
          const Divider(height: 1),
          Expanded(child: _buildBody(context, visible)),
        ],
      ),
    );
  }

  /// 级别/崩溃过滤条
  Widget _buildFilterBar(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final option in _LogFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(option.label),
                selected: _filter == option,
                onSelected: (_) => setState(() => _filter = option),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<LogEntry> visible) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              _allEntries.isEmpty ? '暂无日志' : '没有符合过滤条件的日志',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: visible.length,
      itemBuilder: (context, index) => _buildRow(context, visible[index]),
    );
  }

  Widget _buildRow(BuildContext context, LogEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _levelColor(entry.level, colorScheme);
    final time = entry.timestamp != null
        ? _formatTime(entry.timestamp!)
        : '--:--:--';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 级别色条
          Container(
            width: 4,
            height: 16,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$time [${entry.level.label}] ${entry.tag}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(LogEntryLevel level, ColorScheme scheme) {
    return switch (level) {
      LogEntryLevel.error => Colors.red.shade400,
      LogEntryLevel.warning => Colors.orange.shade400,
      LogEntryLevel.info => Colors.blue.shade400,
      LogEntryLevel.debug => Colors.grey.shade500,
    };
  }

  String _formatTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
