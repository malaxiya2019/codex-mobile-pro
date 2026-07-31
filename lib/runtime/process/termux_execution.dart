/// ====================================================================
/// Termux Execution Adapter
///
/// 将 Termux Runtime Bridge 的 IPC 执行方式适配为统一的
/// RuntimeProcessResult 模型。
///
/// 通信协议（不变）：
///   TermuxExecutionAdapter
///   → TermuxRuntimeBridge.executeInTermux()
///   → MethodChannel
///   → TermuxBridge.kt
///   → RUN_COMMAND Intent
///
/// 本阶段不改变此通信协议。
/// ====================================================================
library;

import '../../core/termux/termux_runtime_bridge.dart';
import 'runner_models.dart';

/// Termux 执行适配器
///
/// 将 TermuxRuntimeBridge 的 IPC 结果映射为 RuntimeProcessResult。
/// Termux 不可用时，返回 RUNTIME_UNAVAILABLE 错误。
class TermuxExecutionAdapter implements IExecutionAdapter {
  final TermuxRuntimeBridge _bridge;

  TermuxExecutionAdapter({TermuxRuntimeBridge? bridge})
    : _bridge = bridge ?? TermuxRuntimeBridge.instance;

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
    // Termux 执行是通过 RUN_COMMAND Intent，只接受单条命令字符串
    final command = _buildTermuxCommand(request);

    // ─── 2. 执行 ───────────────────────────────────────────────
    final bridgeResult = await _bridge.executeInTermux(command);

    final duration = DateTime.now().difference(start);

    // ─── 3. 检查是否降级 ───────────────────────────────────────
    if (!bridgeResult.usedTermux) {
      return RuntimeProcessResult(
        exitCode: bridgeResult.exitCode,
        stdout: bridgeResult.stdout,
        stderr: bridgeResult.stderr,
        duration: duration,
        error:
            bridgeResult.exitCode == -1
                ? 'Termux Runtime 不可用'
                : '命令降级到系统 Shell 执行',
        request: request,
      );
    }

    // ─── 4. 映射结果 ───────────────────────────────────────────
    return RuntimeProcessResult(
      exitCode: bridgeResult.exitCode,
      stdout: bridgeResult.stdout,
      stderr: bridgeResult.stderr,
      duration: duration,
      request: request,
    );
  }

  /// 构建 Termux 单条命令字符串
  ///
  /// Termux RUN_COMMAND Intent 接受单条命令字符串。
  /// 将 executable + arguments 组合为 shell 命令。
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
    // 如果包含特殊字符，用单引号包裹
    if (RegExp(r'[^\w@%+=:,./-]').hasMatch(arg)) {
      return "'${arg.replaceAll("'", "'\\''")}'";
    }
    return arg;
  }
}
