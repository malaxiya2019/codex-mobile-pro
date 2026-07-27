import 'package:flutter/services.dart';

/// Termux 命令执行结果
class TermuxResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;

  const TermuxResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
  });

  bool get isSuccess => exitCode == 0;
  bool get isTimeout => exitCode == -1 && stderr.contains('超时');

  @override
  String toString() =>
      'exitCode=$exitCode, stdout=${stdout.length}chars, stderr=${stderr.length}chars, duration=${durationMs}ms';
}

/// 环境检查结果（多策略诊断）
class TermuxEnvCheck {
  // Termux 安装状态
  final bool termuxInstalled;

  // Bash 访问状态
  final bool bashExists;
  final bool bashCanRead;
  final bool bashCanExecute;
  final bool bashWorks;
  final String bashLastStderr;

  // Termux home 目录
  final bool termuxHomeExists;

  // 系统 shell 降级
  final bool systemShExists;
  final bool systemShCanExecute;
  final bool shWorks;
  final String shLastStderr;

  // Intent 通信
  final bool termuxIntentAvailable;

  // 整体状态
  final bool isAvailable;
  final bool fallbackAvailable;

  const TermuxEnvCheck({
    required this.termuxInstalled,
    required this.bashExists,
    required this.bashCanRead,
    required this.bashCanExecute,
    required this.bashWorks,
    required this.bashLastStderr,
    required this.termuxHomeExists,
    required this.systemShExists,
    required this.systemShCanExecute,
    required this.shWorks,
    required this.shLastStderr,
    required this.termuxIntentAvailable,
    required this.isAvailable,
    required this.fallbackAvailable,
  });

  /// Termux 原生模式是否可用
  bool get termuxMode => termuxInstalled && bashWorks;

  /// 降级模式至少可用
  bool get hasAnyShell => fallbackAvailable || termuxMode;

  @override
  String toString() =>
      'termux=$termuxMode (installed=$termuxInstalled, bash=$bashWorks), '
      'sh=$shWorks, intent=$termuxIntentAvailable';
}

/// Termux 通信服务
class TermuxService {
  static const _channel = MethodChannel('com.codexmobile.app/termux');

  /// 检查环境（完整诊断）
  static Future<TermuxEnvCheck> checkEnvironment() async {
    final map = await _channel
        .invokeMethod<Map<Object?, Object?>>('checkEnvironment');
    return TermuxEnvCheck(
      termuxInstalled: map?['termux_installed'] as bool? ?? false,
      bashExists: map?['bash_exists'] as bool? ?? false,
      bashCanRead: map?['bash_can_read'] as bool? ?? false,
      bashCanExecute: map?['bash_can_execute'] as bool? ?? false,
      bashWorks: map?['bash_works'] as bool? ?? false,
      bashLastStderr: map?['bash_last_stderr'] as String? ?? '',
      termuxHomeExists: map?['termux_home_exists'] as bool? ?? false,
      systemShExists: map?['system_sh_exists'] as bool? ?? false,
      systemShCanExecute: map?['system_sh_can_execute'] as bool? ?? false,
      shWorks: map?['sh_works'] as bool? ?? false,
      shLastStderr: map?['sh_last_stderr'] as String? ?? '',
      termuxIntentAvailable: map?['termux_intent_available'] as bool? ?? false,
      isAvailable: map?['is_available'] as bool? ?? false,
      fallbackAvailable: map?['fallback_available'] as bool? ?? false,
    );
  }

  /// 执行单条命令（自动降级）
  static Future<TermuxResult> execute(String command) async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('execute', {
      'command': command,
    });
    return TermuxResult(
      exitCode: map?['exitCode'] as int? ?? -1,
      stdout: map?['stdout'] as String? ?? '',
      stderr: map?['stderr'] as String? ?? '',
      durationMs: map?['durationMs'] as int? ?? 0,
    );
  }
}
