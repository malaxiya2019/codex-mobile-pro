import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/termux/termux_service.dart';

/// Termux 通信验证页面
class TermuxTestPage extends ConsumerStatefulWidget {
  const TermuxTestPage({super.key});

  @override
  ConsumerState<TermuxTestPage> createState() => _TermuxTestPageState();
}

class _TermuxTestPageState extends ConsumerState<TermuxTestPage> {
  final _outputController = ScrollController();
  final _logs = <String>[];
  bool _isRunning = false;
  TermuxEnvCheck? _envCheck;

  final _testCommands = [
    'pwd',
    'ls',
    'echo "Hello from Termux!"',
    'whoami',
    'uname -a',
    'id',
    'date',
    'uptime',
    'which bash',
    'env | grep HOME',
  ];

  @override
  void initState() {
    super.initState();
    _addLog('📱 Termux 通信验证页面已加载');
  }

  @override
  void dispose() {
    _outputController.dispose();
    super.dispose();
  }

  void _addLog(String msg) {
    setState(() => _logs.add(msg));
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_outputController.hasClients) {
        _outputController.animateTo(
          _outputController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _checkEnvironment() async {
    _addLog('🔍 检查 Termux 环境...');
    setState(() => _isRunning = true);
    try {
      _envCheck = await TermuxService.checkEnvironment();
      _addLog('  bash 文件存在: ${_envCheck!.bashExists}');
      _addLog('  home 目录存在: ${_envCheck!.termuxHomeExists}');
      _addLog('  bash 可执行: ${_envCheck!.bashExecutable}');
      _addLog('  → 整体可用: ${_envCheck!.isAvailable}');
    } catch (e) {
      _addLog('❌ 环境检查失败: $e');
    }
    setState(() => _isRunning = false);
  }

  Future<void> _executeCommand(String command) async {
    _addLog('');
    _addLog('⚡ \$ $command');
    setState(() => _isRunning = true);
    try {
      final result = await TermuxService.execute(command);
      if (result.stdout.isNotEmpty) {
        for (final line in result.stdout.split('\n')) {
          if (line.isNotEmpty) _addLog('  $line');
        }
      }
      if (result.stderr.isNotEmpty) {
        for (final line in result.stderr.split('\n')) {
          if (line.isNotEmpty) _addLog('  ⚠️ $line');
        }
      }
      _addLog('  → exitCode=${result.exitCode} (${result.durationMs}ms)');
    } catch (e) {
      _addLog('❌ 命令执行异常: $e');
    }
    setState(() => _isRunning = false);
  }

  Future<void> _runAllTests() async {
    _addLog('');
    _addLog('═══════════════════════════════');
    _addLog('🚀 开始运行 ${_testCommands.length} 条测试命令');
    _addLog('═══════════════════════════════');

    await _checkEnvironment();

    int passed = 0;
    int failed = 0;
    for (final cmd in _testCommands) {
      _addLog('');
      _addLog('⚡ \$ $cmd');
      setState(() => _isRunning = true);
      try {
        final result = await TermuxService.execute(cmd);
        if (result.stdout.isNotEmpty) {
          for (final line in result.stdout.split('\n')) {
            if (line.isNotEmpty) _addLog('  $line');
          }
        }
        if (result.stderr.isNotEmpty) {
          for (final line in result.stderr.split('\n')) {
            if (line.isNotEmpty) _addLog('  ⚠️ $line');
          }
        }
        _addLog('  → exitCode=${result.exitCode} (${result.durationMs}ms)');
        if (result.isSuccess) {
          passed++;
        } else {
          failed++;
        }
      } catch (e) {
        _addLog('❌ $e');
        failed++;
      }
      setState(() => _isRunning = false);
    }

    _addLog('');
    _addLog('═══════════════════════════════');
    _addLog('📊 测试完成: ✅ $passed 通过 / ❌ $failed 失败');
    _addLog('═══════════════════════════════');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Termux 通信验证'),
        centerTitle: true,
        backgroundColor: colorScheme.surfaceContainer,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _isRunning ? null : _checkEnvironment,
                    child: const Text('🔍 检查环境'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _isRunning ? null : _runAllTests,
                    child: const Text('🚀 全部测试'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '清空日志',
                  onPressed: () => setState(() => _logs.clear()),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _testCommands.map((cmd) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(cmd, style: const TextStyle(fontSize: 12)),
                    onPressed: _isRunning ? null : () => _executeCommand(cmd),
                  ),
                );
              }).toList(),
            ),
          ),

          if (_isRunning) const LinearProgressIndicator(),

          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.terminal, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text('点击"检查环境"或"全部测试"开始验证', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _outputController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        Color? color;
                        if (log.startsWith('❌')) { color = Colors.red; }
                        else if (log.startsWith('✅')) { color = Colors.green; }
                        else if (log.startsWith('⚡')) { color = Colors.amber; }
                        else if (log.startsWith('  → exitCode=0')) { color = Colors.green; }
                        else if (log.startsWith('  → exitCode=')) { color = Colors.red; }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: color ?? colorScheme.onSurface,
                              height: 1.4,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
