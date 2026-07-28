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

  // 基础测试命令
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

  // 特殊字符测试
  final _specialCharTests = [
    // #1: 美元符号
    _SpecialTest('\$value', r'echo $((2+2))', '4', '美元符号变量展开'),
    // #2: 双引号嵌套
    _SpecialTest('double_quote', r"""echo "it's \"nested\""""", null, '双引号嵌套'),
    // #3: 单引号
    _SpecialTest('single_quote', r"echo 'it is safe'", null, '单引号字符串'),
    // #4: 反斜杠
    _SpecialTest('backslash', r'echo "path\to\file"', null, '反斜杠路径'),
    // #5: 反引号（旧式命令替换）
    _SpecialTest('backtick', r'echo `echo inner`', null, '反引号命令替换'),
    // #6: 管道链
    _SpecialTest('pipe', r'echo "hello world" | wc -w', '2', '管道输出'),
    // #7: 混合特殊字符
    _SpecialTest('mixed', "echo \"price=\$10 & file='test.txt'\"", null, '混合特殊字符'),
    // #8: 中文输出
    _SpecialTest('chinese', r'echo "你好，世界！"', null, '中文输出编码'),
    // #9: 换行符
    _SpecialTest('newline', r"printf 'line1\nline2\nline3'", null, '换行符输出'),
    // #10: 重定向
    _SpecialTest('redirect', r'echo "temp_data" > /data/local/tmp/codex_test.txt && cat /data/local/tmp/codex_test.txt', 'temp_data', '重定向读写'),
  ];

  // 统计
  int _passed = 0;
  int _failed = 0;
  // int _totalTests = 0; // unused
  final _failedList = <String>[];
  // bool _showOnlyFailed = false; // unused

  @override
  void initState() {
    super.initState();
    _addLog('📱 Termux 通信验证 — 多策略降级测试');
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

  // ── 环境检查 ──

  Future<void> _checkEnvironment() async {
    _addLog('🔍 检查 Termux 环境...');
    setState(() => _isRunning = true);
    try {
      _envCheck = await TermuxService.checkEnvironment();
      _addLog('');
      _addLog('═══ Termux ═══');
      _addLog('  已安装:  ${_envCheck!.termuxInstalled ? "✅" : "❌"}');
      _addLog('  bash 文件存在: ${_envCheck!.bashExists}');
      _addLog('  bash 可读:   ${_envCheck!.bashCanRead}');
      _addLog('  bash 可执行: ${_envCheck!.bashCanExecute}');
      _addLog('  bash 可运行: ${_envCheck!.bashWorks ? "✅" : "❌"}');
      if (_envCheck!.bashLastStderr.isNotEmpty) {
        _addLog('  bash 错误:   ${_envCheck!.bashLastStderr}');
      }
      _addLog('  Intent API:  ${_envCheck!.termuxIntentAvailable ? "✅" : "❌"}');
      _addLog('');
      _addLog('═══ 系统 shell 降级 ═══');
      _addLog('  sh 存在:    ${_envCheck!.systemShExists}');
      _addLog('  sh 可执行:  ${_envCheck!.systemShCanExecute}');
      _addLog('  sh 可运行:  ${_envCheck!.shWorks ? "✅" : "❌"}');
      if (_envCheck!.shLastStderr.isNotEmpty) {
        _addLog('  sh 错误:    ${_envCheck!.shLastStderr}');
      }
      _addLog('');
      _addLog('═══ 结论 ═══');
      if (_envCheck!.termuxMode) {
        _addLog('  ✅ Termux 原生模式可用');
      } else if (_envCheck!.fallbackAvailable) {
        _addLog('  ⚠️  Termux 不可用，使用系统 shell 降级');
      } else {
        _addLog('  ❌ 无可用的 shell 环境');
      }
    } catch (e) {
      _addLog('❌ 环境检查失败: $e');
    }
    setState(() => _isRunning = false);
  }

  // ── 单条命令执行 ──

  Future<void> _executeCommand(String command) async {
    _addLog('');
    _addLog('⚡ \$ $command');
    setState(() => _isRunning = true);
    try {
      final result = await TermuxService.execute(command);
      _formatResultOutput(result);
    } catch (e) {
      _addLog('❌ 命令执行异常: $e');
    }
    setState(() => _isRunning = false);
  }

  void _formatResultOutput(TermuxResult result) {
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
    final statusIcon = result.isSuccess ? '✅' : '❌';
    _addLog('  → $statusIcon exitCode=${result.exitCode} (${result.durationMs}ms)');
  }

  // ── 基础命令测试 ──

  Future<void> _runAllTests() async {
    _addLog('');
    _addLog('═══════════════════════════════');
    _addLog('🚀 开始运行 ${_testCommands.length} 条基础命令测试');
    _addLog('═══════════════════════════════');

    await _checkEnvironment();

    _passed = 0;
    _failed = 0;
    _failedList.clear();
    for (final cmd in _testCommands) {
      _addLog('');
      _addLog('⚡ \$ $cmd');
      setState(() => _isRunning = true);
      try {
        final result = await TermuxService.execute(cmd);
        _formatResultOutput(result);
        if (result.isSuccess) {
          _passed++;
        } else {
          _failed++;
          _failedList.add(cmd);
        }
      } catch (e) {
        _addLog('❌ $e');
        _failed++;
        _failedList.add(cmd);
      }
      setState(() => _isRunning = false);
    }

    _printSummary('基础命令');
  }

  // ── 特殊字符测试 ──

  Future<void> _runSpecialCharTests() async {
    _addLog('');
    _addLog('═══════════════════════════════');
    _addLog('🔣 开始 ${_specialCharTests.length} 条特殊字符测试');
    _addLog('═══════════════════════════════');

    _passed = 0;
    _failed = 0;
    _failedList.clear();
    for (final test in _specialCharTests) {
      _addLog('');
      _addLog('🔣 [${test.name}] ${test.desc}');
      _addLog('⚡ \$ ${test.command}');
      setState(() => _isRunning = true);
      try {
        final result = await TermuxService.execute(test.command);
        _formatResultOutput(result);

        // 检查是否通过
        bool pass;
        if (result.exitCode == 0) {
          if (test.expectedOutput != null) {
            pass = result.stdout.trim().contains(test.expectedOutput!);
          } else {
            pass = result.stdout.isNotEmpty || result.stderr.isEmpty;
          }
        } else {
          pass = false;
        }

        if (pass) {
          _passed++;
          _addLog('  🔸 断言: ✅ 通过');
        } else {
          _failed++;
          _failedList.add('${test.name}: ${test.command}');
          _addLog('  🔸 断言: ❌ 失败${test.expectedOutput != null ? " (期望包含: ${test.expectedOutput})" : ""}');
        }
      } catch (e) {
        _addLog('❌ 异常: $e');
        _failed++;
        _failedList.add('${test.name}: $e');
      }
      setState(() => _isRunning = false);
    }

    _printSummary('特殊字符');
  }

  // ── 批量压力测试 ──

  Future<void> _runBulkTest() async {
    const totalCalls = 50;
    _addLog('');
    _addLog('═══════════════════════════════');
    _addLog('🔥 批量压力测试: ${totalCalls}x 连续调用');
    _addLog('═══════════════════════════════');

    _passed = 0;
    _failed = 0;
    _failedList.clear();
    final timings = <int>[];
    int minTime = 999999;
    int maxTime = 0;
    int totalTime = 0;

    setState(() => _isRunning = true);
    for (int i = 1; i <= totalCalls; i++) {
      final cmd = i.isEven ? 'echo "test_$i"' : 'date +%s';
      try {
        final result = await TermuxService.execute(cmd);
        timings.add(result.durationMs);
        totalTime += result.durationMs;
        if (result.durationMs < minTime) minTime = result.durationMs;
        if (result.durationMs > maxTime) maxTime = result.durationMs;

        if (result.isSuccess) {
          _passed++;
        } else {
          _failed++;
          _failedList.add('#$i: $cmd');
        }

        // 每 10 次打印进度
        if (i % 10 == 0) {
          _addLog('  📊 进度: $i/$totalCalls (✅ $_passed / ❌ $_failed)');
        }
      } catch (e) {
        _failed++;
        _failedList.add('#$i: $e');
        if (i % 10 == 0) {
          _addLog('  📊 进度: $i/$totalCalls (✅ $_passed / ❌ $_failed)');
        }
      }
    }
    setState(() => _isRunning = false);

    // 统计
    final avgTime = totalCalls > 0 ? totalTime ~/ totalCalls : 0;
    _addLog('');
    _addLog('══════ 压力测试统计 ══════');
    _addLog('  总调用:  $totalCalls');
    _addLog('  ✅ 通过:  $_passed');
    _addLog('  ❌ 失败:  $_failed');
    _addLog('  成功率:  ${totalCalls > 0 ? (_passed * 100 / totalCalls).toStringAsFixed(1) : "N/A"}%');
    _addLog('  最慢:    ${maxTime}ms');
    _addLog('  最快:    ${minTime}ms');
    _addLog('  平均:    ${avgTime}ms');
    _addLog('  总耗时:  ${totalTime}ms (${(totalTime / 1000).toStringAsFixed(1)}s)');
    _addLog('═════════════════════════');

    _printSummary('压力测试');
  }

  // ── 完整验证套件 ──

  Future<void> _runFullValidation() async {
    _addLog('');
    _addLog('══════════════════════════════════════');
    _addLog('🏁 完整验证套件启动');
    _addLog('══════════════════════════════════════');

    final startTime = DateTime.now();
    int totalPassed = 0;
    int totalFailed = 0;
    final allFailedList = <String>[];

    // 1. 环境检查
    await _checkEnvironment();

    // 2. 基础命令测试
    _passed = 0;
    _failed = 0;
    _failedList.clear();
    for (final cmd in _testCommands) {
      try {
        final result = await TermuxService.execute(cmd);
        if (result.isSuccess) { _passed++; } else { _failed++; _failedList.add(cmd); }
      } catch (_) { _failed++; }
    }
    totalPassed += _passed;
    totalFailed += _failed;
    allFailedList.addAll(_failedList);
    _addLog('  📊 基础命令: ✅ $_passed / ❌ $_failed');

    // 3. 特殊字符测试
    _passed = 0;
    _failed = 0;
    _failedList.clear();
    for (final test in _specialCharTests) {
      try {
        final result = await TermuxService.execute(test.command);
        bool pass;
        if (result.exitCode == 0) {
          pass = test.expectedOutput == null || result.stdout.trim().contains(test.expectedOutput!);
        } else {
          pass = false;
        }
        if (pass) { _passed++; } else { _failed++; _failedList.add(test.name); }
      } catch (_) { _failed++; }
    }
    totalPassed += _passed;
    totalFailed += _failed;
    allFailedList.addAll(_failedList);
    _addLog('  📊 特殊字符: ✅ $_passed / ❌ $_failed');

    // 4. 批量 50 次
    _passed = 0;
    _failed = 0;
    _failedList.clear();
    for (int i = 1; i <= 50; i++) {
      try {
        final result = await TermuxService.execute(i.isEven ? 'echo "test_$i"' : 'date +%s');
        if (result.isSuccess) { _passed++; } else { _failed++; _failedList.add('#$i'); }
      } catch (_) { _failed++; }
    }
    totalPassed += _passed;
    totalFailed += _failed;
    allFailedList.addAll(_failedList);
    _addLog('  📊 批量 50 次: ✅ $_passed / ❌ $_failed');

    // 汇总
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    _addLog('');
    _addLog('══════════════════════════════════════');
    _addLog('🏁 完整验证套件完成');
    _addLog('  总用例:    ${totalPassed + totalFailed}');
    _addLog('  ✅ 通过:   $totalPassed');
    _addLog('  ❌ 失败:   $totalFailed');
    _addLog('  成功率:    ${(totalPassed * 100 / (totalPassed + totalFailed)).toStringAsFixed(1)}%');
    _addLog('  总耗时:    ${elapsed}ms (${(elapsed / 1000).toStringAsFixed(1)}s)');
    if (allFailedList.isNotEmpty) {
      _addLog('');
      _addLog('══ 失败列表 ══');
      for (final f in allFailedList) {
        _addLog('  ❌ $f');
      }
    }
    _addLog('══════════════════════════════════════');
  }

  void _printSummary(String label) {
    _addLog('');
    _addLog('══════ $label 结果 ══════');
    _addLog('  ✅ 通过: $_passed');
    _addLog('  ❌ 失败: $_failed');
    if (_failedList.isNotEmpty) {
      _addLog('  失败项:');
      for (final f in _failedList) {
        _addLog('    ❌ $f');
      }
    }
    _addLog('═══════════════════════');
  }

  // ── UI ──

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
          // 顶部操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _isRunning ? null : _checkEnvironment,
                        child: const Text('🔍 环境检查'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isRunning ? null : _runAllTests,
                        child: const Text('🚀 基础命令'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isRunning ? null : _runFullValidation,
                        child: const Text('🏁 完整验证'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isRunning ? null : _runSpecialCharTests,
                        child: const Text('🔣 特殊字符'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isRunning ? null : _runBulkTest,
                        child: const Text('🔥 压力 50x'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '清空',
                      onPressed: () => setState(() => _logs.clear()),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 快捷命令按钮
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: _testCommands.map((cmd) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(cmd, style: const TextStyle(fontSize: 10)),
                    onPressed: _isRunning ? null : () => _executeCommand(cmd),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),

          // 进度条
          if (_isRunning) const LinearProgressIndicator(),

          // 日志输出
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
                          Text('点击"环境检查"或"基础命令"开始验证',
                              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Text('或点击"完整验证"一次性运行所有测试',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
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
                        else if (log.startsWith('✅') || log.startsWith('  ✅')) { color = Colors.green; }
                        else if (log.startsWith('⚡') || log.startsWith('🔣')) { color = Colors.amber.shade700; }
                        else if (log.startsWith('  → ✅')) { color = Colors.green; }
                        else if (log.startsWith('  → ❌')) { color = Colors.red; }
                        else if (log.startsWith('══') || log.startsWith('🏁') || log.startsWith('🔥') || log.startsWith('👻')) {
                          color = colorScheme.primary;
                        }
                        else if (log.startsWith('  🔸 断言: ✅')) { color = Colors.green; }
                        else if (log.startsWith('  🔸 断言: ❌')) { color = Colors.red; }
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

/// 特殊字符测试用例
class _SpecialTest {
  final String name;
  final String command;
  final String? expectedOutput;
  final String desc;

  const _SpecialTest(this.name, this.command, this.expectedOutput, this.desc);
}
