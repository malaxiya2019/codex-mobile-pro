import 'package:flutter/services.dart';

/// Termux 命令执行结果
class TermuxResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final String source; // "termux", "system_sh", "timeout", "error"

  const TermuxResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.source = 'termux',
  });

  bool get isSuccess => exitCode == 0;

  @override
  String toString() =>
      'exitCode=$exitCode, source=$source, stdout=${stdout.length}chars, '
      'stderr=${stderr.length}chars, duration=${durationMs}ms';
}

/// 环境检查结果
class TermuxEnvCheck {
  final bool termuxInstalled;
  final bool termuxIntentAvailable;
  final bool termuxWorks;
  final String termuxLastStderr;
  final bool shWorks;
  final String shLastStderr;
  final bool isAvailable;
  final bool fallbackAvailable;

  const TermuxEnvCheck({
    this.termuxInstalled = false,
    this.termuxIntentAvailable = false,
    this.termuxWorks = false,
    this.termuxLastStderr = '',
    this.shWorks = true,
    this.shLastStderr = '',
    this.isAvailable = false,
    this.fallbackAvailable = true,
  });

  bool get termuxMode => termuxInstalled && (termuxWorks || termuxIntentAvailable);
  bool get hasAnyShell => fallbackAvailable || termuxMode;

  @override
  String toString() =>
      'termuxMode=$termuxMode (installed=$termuxInstalled, '
      'intent=$termuxIntentAvailable, works=$termuxWorks), '
      'sh=$shWorks';
}

/// Termux 通信服务
///
/// 通过 MethodChannel 与 Android 原生层通信。
/// 支持：
/// - execute() — 执行命令（自动降级：Termux → 系统 Shell）
/// - executeInTermux() — 强制在 Termux 中执行
/// - checkEnvironment() — 检查环境状态
class TermuxService {
  static const _channel = MethodChannel('com.codexmobile.app/termux');

  /// 检查环境（包括 Termux 和系统 Shell）
  static Future<TermuxEnvCheck> checkEnvironment() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('checkEnvironment');
      final map = result as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
      return TermuxEnvCheck(
        termuxInstalled: _bool(map['termux_installed']),
        termuxIntentAvailable: _bool(map['termux_intent_available']),
        termuxWorks: _bool(map['termux_works']),
        termuxLastStderr: _str(map['termux_last_stderr']),
        shWorks: _bool(map['sh_works']),
        shLastStderr: _str(map['sh_last_stderr']),
        isAvailable: _bool(map['is_available']),
        fallbackAvailable: _bool(map['fallback_available']),
      );
    } catch (_) {
      return const TermuxEnvCheck();
    }
  }

  /// 执行单条命令（自动降级：Termux → 系统 Shell）
  static Future<TermuxResult> execute(String command) async {
    try {
      final result = await _channel.invokeMethod<dynamic>('execute', {
        'command': command,
      });
      final map = result as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
      return TermuxResult(
        exitCode: _int(map['exitCode'], -1),
        stdout: _str(map['stdout']),
        stderr: _str(map['stderr']),
        durationMs: _int(map['durationMs']),
        source: _str(map['source']),
      );
    } catch (e) {
      return TermuxResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Termux 服务调用失败: $e',
        durationMs: 0,
        source: 'error',
      );
    }
  }

  static bool _bool(dynamic value) => value == true;
  static String _str(dynamic value) => value?.toString() ?? '';
  static int _int(dynamic value, [int defaultValue = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return defaultValue;
  }
}
