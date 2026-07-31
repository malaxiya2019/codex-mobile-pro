/// ====================================================================
/// Runtime Process Runner
///
/// 统一、可靠、可测试地执行 Runtime 命令。
///
/// 职责（只做四件事）：
///   1. 选择正确的 ExecutionAdapter
///   2. 合并环境变量
///   3. 执行命令（带超时/取消）
///   4. 返回统一结果
///
/// 不负责：
///   - 解析 executable（由 Provider 负责）
///   - 管理 Runtime（由 RuntimeManager 负责）
///   - PTY / 交互式 session（由 TerminalSessionRunner 负责）
///
/// 使用方式：
///   final runner = RuntimeProcessRunner();
///   final result = await runner.run(RuntimeProcessRequest(
///     executable: '/path/to/node',
///     arguments: ['--version'],
///   ));
/// ====================================================================
library;

import 'dart:async';
import 'dart:io';

import '../../core/logger/log_service.dart';
import 'runner_models.dart';

/// ====================================================================
/// LocalProcessExecution
///
/// 在本地进程中直接执行命令。
/// 包装 dart:io Process.run / Process.start。
///
/// 适用于：
///   - Android System Runtime（/system/bin/sh, /system/bin/curl）
///   - App Bundled Runtime（已安装的 node/python/git）
/// ====================================================================
class LocalProcessExecution implements IExecutionAdapter {
  @override
  String get id => 'local';

  @override
  bool supports(RuntimeProcessRequest request) {
    // 本地执行支持 android / app 请求
    // Linux Runtime 由 LinuxExecutionAdapter 处理（PRoot）
    return request.runtimeId == null ||
        request.runtimeId == 'android' ||
        request.runtimeId == 'app';
  }

  @override
  Future<RuntimeProcessResult> execute(RuntimeProcessRequest request) async {
    final start = DateTime.now();

    try {
      // ─── Shell 模式下使用 Process.run with runInShell ───────
      if (request.runInShell) {
        final result = await Process.run(
          request.executable,
          request.arguments,
          environment: request.environment,
          workingDirectory: request.workingDirectory,
          runInShell: true,
        );

        return RuntimeProcessResult(
          exitCode: result.exitCode,
          stdout: (result.stdout as String?) ?? '',
          stderr: (result.stderr as String?) ?? '',
          duration: DateTime.now().difference(start),
          request: request,
        );
      }

      // ─── Direct execution ────────────────────────────────────
      // 使用 Process.start 以获得更好的超时/取消控制
      final process = await Process.start(
        request.executable,
        request.arguments,
        environment: request.environment,
        workingDirectory: request.workingDirectory,
      );

      // ─── 超时处理 ────────────────────────────────────────────
      Completer<void>? timeoutCompleter;
      Timer? timeoutTimer;

      if (request.timeout != null) {
        timeoutCompleter = Completer<void>();
        timeoutTimer = Timer(request.timeout!, () {
          timeoutCompleter?.complete();
        });
      }

      // ─── 取消处理 ────────────────────────────────────────────
      final cancelCompleter = Completer<void>();
      final cancelFuture = cancelCompleter.future;

      // ─── 收集输出 ────────────────────────────────────────────
      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();

      // 保存流完成 Future：进程 exitCode 可能先于管道数据到达，
      // 必须在返回前等待输出流消费完成，否则会丢失尾部输出。
      final stdoutDone = process.stdout
          .transform(const SystemEncoding().decoder)
          .listen((data) => stdoutBuf.write(data))
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(const SystemEncoding().decoder)
          .listen((data) => stderrBuf.write(data))
          .asFuture<void>();

      // ─── 等待进程完成（可被超时/取消中断） ────────────────────
      int exitCode;
      bool timedOut = false;
      bool cancelled = false;

      await Future.any([
        process.exitCode,
        if (timeoutCompleter != null) timeoutCompleter.future,
        cancelFuture,
      ]);

      if (timeoutCompleter != null && timeoutCompleter.isCompleted) {
        // 超时 → kill 进程
        timedOut = true;
        process.kill();
        exitCode = -2;
      } else if (cancelCompleter.isCompleted) {
        // 取消 → kill 进程
        cancelled = true;
        process.kill();
        exitCode = -3;
      } else {
        exitCode = await process.exitCode;
      }

      timeoutTimer?.cancel();

      // 等待输出流完全消费（进程可能已退出但 stdout 管道仍有数据）
      await stdoutDone;
      await stderrDone;

      return RuntimeProcessResult(
        exitCode: exitCode,
        stdout: stdoutBuf.toString(),
        stderr: stderrBuf.toString(),
        duration: DateTime.now().difference(start),
        timedOut: timedOut,
        cancelled: cancelled,
        request: request,
      );
    } on ProcessException catch (e) {
      return RuntimeProcessResult(
        exitCode: -1,
        error: _processExceptionMessage(e),
        duration: DateTime.now().difference(start),
        request: request,
      );
    } on ArgumentError catch (e) {
      return RuntimeProcessResult(
        exitCode: -1,
        error: '参数错误: $e',
        duration: DateTime.now().difference(start),
        request: request,
      );
    } catch (e) {
      return RuntimeProcessResult(
        exitCode: -1,
        error: '启动失败: $e',
        duration: DateTime.now().difference(start),
        request: request,
      );
    }
  }

  /// 将 ProcessException 转为人类可读的消息
  static String _processExceptionMessage(ProcessException e) {
    final msg = e.toString();
    if (msg.contains('No such file or directory')) {
      return '可执行文件不存在: ${e.executable}';
    }
    if (msg.contains('Permission denied')) {
      return '权限不足: ${e.executable}';
    }
    return msg;
  }
}

/// ====================================================================
/// RuntimeProcessRunner
///
/// 统一入口：选择适配器 → 执行 → 返回统一结果。
///
/// 所有 Runtime 命令执行都应通过此 Runner。
/// ====================================================================
class RuntimeProcessRunner {
  final List<IExecutionAdapter> _adapters;

  RuntimeProcessRunner({
    List<IExecutionAdapter>? adapters,
  }) : _adapters = adapters ?? [LocalProcessExecution()];

  /// 注册执行适配器
  void registerAdapter(IExecutionAdapter adapter) {
    _adapters.add(adapter);
  }

  /// 执行命令
  ///
  /// 自动选择适配器，合并环境，执行并返回结果。
  Future<RuntimeProcessResult> run(RuntimeProcessRequest request) async {
    // ─── 1. 选择适配器 ──────────────────────────────────────────
    final adapter = _selectAdapter(request);
    if (adapter == null) {
      return RuntimeProcessResult(
        exitCode: -1,
        error: '没有适配器支持此请求 (runtimeId=${request.runtimeId}, '
            'executable=${request.executable})',
        request: request,
      );
    }

    LogService.debug(
      'ProcessRunner',
      '${request.label ?? adapter.id}: ${request.executable} '
      '${request.arguments.join(" ")}',
    );

    // ─── 2. 执行 ────────────────────────────────────────────────
    try {
      final result = await adapter.execute(request);
      return result;
    } catch (e) {
      return RuntimeProcessResult(
        exitCode: -1,
        error: '适配器执行失败: $e',
        request: request,
      );
    }
  }

  /// 便捷方法：运行并获取 stdout（自动 trim）
  ///
  /// 如果执行失败，返回 null。
  Future<String?> runAndGetStdout(RuntimeProcessRequest request) async {
    final result = await run(request);
    if (result.isSuccess && result.stdout.trim().isNotEmpty) {
      return result.stdout.trim();
    }
    return null;
  }

  /// 便捷方法：运行并检查 exitCode == 0
  Future<bool> runAndCheck(RuntimeProcessRequest request) async {
    final result = await run(request);
    return result.isSuccess;
  }

  /// 选择适配器
  IExecutionAdapter? _selectAdapter(RuntimeProcessRequest request) {
    // 优先级：注册顺序
    for (final adapter in _adapters) {
      if (adapter.supports(request)) return adapter;
    }
    return null;
  }

  /// 获取已注册的适配器列表
  List<IExecutionAdapter> get registeredAdapters =>
      List.unmodifiable(_adapters);
}
