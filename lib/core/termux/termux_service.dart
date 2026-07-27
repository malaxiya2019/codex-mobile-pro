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
    final result = await _channel.invokeMethod<dynamic>('checkEnvironment');
    final map = result as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
    return TermuxEnvCheck(
      termuxInstalled: _bool(map['termux_installed']),
      bashExists: _bool(map['bash_exists']),
      bashCanRead: _bool(map['bash_can_read']),
      bashCanExecute: _bool(map['bash_can_execute']),
      bashWorks: _bool(map['bash_works']),
      bashLastStderr: _str(map['bash_last_stderr']),
      termuxHomeExists: _bool(map['termux_home_exists']),
      systemShExists: _bool(map['system_sh_exists']),
      systemShCanExecute: _bool(map['system_sh_can_execute']),
      shWorks: _bool(map['sh_works']),
      shLastStderr: _str(map['sh_last_stderr']),
      termuxIntentAvailable: _bool(map['termux_intent_available']),
      isAvailable: _bool(map['is_available']),
      fallbackAvailable: _bool(map['fallback_available']),
    );
  }

  /// 执行单条命令（自动降级）
  static Future<TermuxResult> execute(String command) async {
    final result = await _channel.invokeMethod<dynamic>('execute', {
      'command': command,
    });
    final map = result as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
    return TermuxResult(
      exitCode: _int(map['exitCode'], -1),
      stdout: _str(map['stdout']),
      stderr: _str(map['stderr']),
      durationMs: _int(map['durationMs']),
    );
  }

  /// 安全转换 bool
  static bool _bool(dynamic value) => value == true;

  /// 安全转换 String
  static String _str(dynamic value) => value?.toString() ?? '';

  /// 安全转换 int
  static int _int(dynamic value, [int defaultValue = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return defaultValue;
  }
}
