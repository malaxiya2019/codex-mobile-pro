/// ====================================================================
/// Termux Execution Adapter
///
/// 将 TermuxTransport 的执行结果适配为统一的 RuntimeProcessResult 模型。
///
/// 通信协议（不变）：
///   RuntimeProcessRunner → TermuxExecutionAdapter
///   → TermuxTransport → MethodChannel → TermuxBridge.kt → RUN_COMMAND Intent
///
/// 本阶段不改变此通信协议。
/// ====================================================================
library;

import '../termux/method_channel_transport.dart';
import '../termux/termux_transport.dart';
import 'runner_models.dart';

/// Termux 执行适配器
///
/// 将 TermuxTransport 的 IPC 结果映射为 RuntimeProcessResult。
/// Termux 不可用时，返回 RUNTIME_UNAVAILABLE 错误。
class TermuxExecutionAdapter implements IExecutionAdapter {
  final TermuxTransport _transport;

  TermuxExecutionAdapter({TermuxTransport? transport})
    : _transport = transport ?? MethodChannelTermuxTransport();

  @override
  String get id => 'termux';

  @override
  bool supports(RuntimeProcessRequest request) {
    return request.runtimeId == 'termux';
  }

  @override
  Future<RuntimeProcessResult> execute(RuntimeProcessRequest request) async {
    final start = DateTime.now();

    // ─── 1. 构建 Termux 命令 ───────────────────────────────────
    final command = _buildTermuxCommand(request);

    // ─── 2. 通过 Transport 执行 ────────────────────────────────
    final transportResult = await _transport.execute(command);

    final duration = DateTime.now().difference(start);

    // ─── 3. 检查是否降级 ───────────────────────────────────────
    if (!transportResult.usedTermux) {
      return RuntimeProcessResult(
        exitCode: transportResult.exitCode,
        stdout: transportResult.stdout,
        stderr: transportResult.stderr,
        duration: duration,
        error:
            transportResult.exitCode == -1
                ? 'Termux Runtime 不可用'
                : '命令降级到系统 Shell 执行',
        request: request,
      );
    }

    // ─── 4. 映射结果 ───────────────────────────────────────────
    return RuntimeProcessResult(
      exitCode: transportResult.exitCode,
      stdout: transportResult.stdout,
      stderr: transportResult.stderr,
      duration: duration,
      request: request,
    );
  }

  /// 构建 Termux 单条命令字符串
  String _buildTermuxCommand(RuntimeProcessRequest request) {
    final buf = StringBuffer();
    buf.write(request.executable);

    for (final arg in request.arguments) {
      buf.write(' ');
      buf.write(_shellEscape(arg));
    }

    return buf.toString();
  }

  /// Shell 转义
  static String _shellEscape(String arg) {
    if (arg.isEmpty) return "''";
    if (RegExp(r'[^\w@%+=:,./-]').hasMatch(arg)) {
      return "'${arg.replaceAll("'", "'\\''")}'";
    }
    return arg;
  }
}
