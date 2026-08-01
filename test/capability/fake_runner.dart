/// ====================================================================
/// Fake RuntimeProcessRunner — 用于 Capability 测试
///
/// 返回预设结果，不执行真实进程。
/// 支持模拟：成功执行、超时、启动失败、权限拒绝等场景。
/// ====================================================================

import 'package:codex_mobile_pro/runtime/process/process_runner.dart';
import 'package:codex_mobile_pro/runtime/process/runner_models.dart';

/// 预设执行结果
class FakeCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool cancelled;
  final String? error;

  const FakeCommandResult({
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
    this.cancelled = false,
    this.error,
  });
}

/// Fake RuntimeProcessRunner
///
/// 覆盖 run() 方法，根据 executable 返回预设结果。
/// 未预设的 executable 使用 LocalProcessExecution 真实执行。
///
/// 使用方式：
///   final runner = FakeProcessRunner();
///   runner.when('node --version', exitCode: 0, stdout: 'v22.0.0');
///   final result = await runner.run(RuntimeProcessRequest(executable: 'node', arguments: ['--version']));
class FakeProcessRunner extends RuntimeProcessRunner {
  final Map<String, FakeCommandResult> _results = {};
  final Map<String, List<FakeCommandResult>> _sequences = {};
  final List<RuntimeProcessRequest> _executedRequests = [];
  int _callCount = 0;

  FakeProcessRunner() : super(adapters: []);

  /// 注册预设结果
  ///
  /// [key] 使用 "${executable} ${arguments.join(' ')}" 格式。
  /// 也可以只使用 executable 名称。
  void when(String executableOrKey, FakeCommandResult result) {
    _results[executableOrKey] = result;
  }

  /// 注册版本检测成功
  void whenVersion(String binary, String version) {
    _results['$binary --version'] = FakeCommandResult(
      exitCode: 0,
      stdout: 'v$version\n',
    );
  }

  /// 注册 which 成功
  void whenWhich(String binary, String resolvedPath) {
    _results['which $binary'] = FakeCommandResult(
      exitCode: 0,
      stdout: '$resolvedPath\n',
    );
  }

  /// 注册可执行文件不存在
  void whenNotFound(String binary) {
    _results['$binary --version'] = FakeCommandResult(
      exitCode: -1,
      error: '可执行文件不存在: $binary',
    );
    _results['which $binary'] = FakeCommandResult(
      exitCode: 1,
      stdout: '$binary not found\n',
    );
  }

  /// 注册超时
  void whenTimeout(String executable) {
    _results[executable] = FakeCommandResult(timedOut: true);
  }

  /// 注册权限拒绝
  void whenPermissionDenied(String binary) {
    _results['$binary --version'] = FakeCommandResult(
      exitCode: -1,
      error: '权限不足: $binary',
    );
  }

  /// 注册序列响应（按调用顺序依次返回，耗尽后返回最后一个）
  ///
  /// 用于模拟「第一次失败、修复后复验成功」等场景。
  void whenSequence(String executableOrKey, List<FakeCommandResult> results) {
    // 序列覆盖同名单值预设（避免 _results 优先级更高导致序列不生效）
    _results.remove(executableOrKey);
    _sequences[executableOrKey] = List.of(results);
  }

  /// 清空所有预设
  void reset() {
    _results.clear();
    _sequences.clear();
    _executedRequests.clear();
    _callCount = 0;
  }

  /// 已执行的请求列表
  List<RuntimeProcessRequest> get executedRequests =>
      List.unmodifiable(_executedRequests);

  /// 调用次数
  int get callCount => _callCount;

  @override
  Future<RuntimeProcessResult> run(RuntimeProcessRequest request) async {
    _callCount++;
    _executedRequests.add(request);

    // 构建 key：先尝试完整匹配（绝对路径），
    // 再尝试 basename 匹配（模拟真实 shell 行为：which 解析出绝对路径后，
    // 执行 --version 的效果与直接执行裸名相同）。
    final fullKey =
        '${request.executable} ${request.arguments.join(' ')}'.trim();
    final basename = request.executable.split('/').last;
    final baseKey = '$basename ${request.arguments.join(' ')}'.trim();
    final result = _results[fullKey] ??
        _results[baseKey] ??
        _results[request.executable] ??
        _results[basename];

    if (result != null) {
      return _toResult(result, request);
    }

    // 序列响应
    final seq = _sequences[fullKey] ??
        _sequences[baseKey] ??
        _sequences[request.executable] ??
        _sequences[basename];
    if (seq != null && seq.isNotEmpty) {
      final seqResult = seq.length == 1 ? seq.first : seq.removeAt(0);
      return _toResult(seqResult, request);
    }

    // 未预设 → 真实执行（仅用于集成测试）
    return super.run(request);
  }

  /// 将预设结果转换为 RuntimeProcessResult
  RuntimeProcessResult _toResult(
      FakeCommandResult result, RuntimeProcessRequest request) {
    return RuntimeProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      duration: const Duration(milliseconds: 5),
      timedOut: result.timedOut,
      cancelled: result.cancelled,
      error: result.error,
      request: request,
    );
  }
}
