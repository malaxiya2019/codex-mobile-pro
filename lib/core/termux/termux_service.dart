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

  @override
  String toString() =>
      'exitCode=$exitCode, stdout=${stdout.length}chars, stderr=${stderr.length}chars, duration=${durationMs}ms';
}

/// 环境检查结果
class TermuxEnvCheck {
  final bool termuxInstalled;
  final bool bashExists;
  final bool bashCanRead;
  final bool bashCanExecute;
  final bool bashWorks;
  final String bashLastStderr;
  final bool termuxHomeExists;
  final bool systemShExists;
  final bool systemShCanExecute;
  final bool shWorks;
  final String shLastStderr;
  final bool termuxIntentAvailable;
  final bool isAvailable;
  final bool fallbackAvailable;

  const TermuxEnvCheck({
    this.termuxInstalled = false,
    this.bashExists = false,
    this.bashCanRead = false,
    this.bashCanExecute = false,
    this.bashWorks = false,
    this.bashLastStderr = '',
    this.termuxHomeExists = false,
    this.systemShExists = true,
    this.systemShCanExecute = true,
    this.shWorks = true,
    this.shLastStderr = '',
    this.termuxIntentAvailable = false,
    this.isAvailable = false,
    this.fallbackAvailable = true,
  });

  bool get termuxMode => termuxInstalled && bashWorks;
  bool get hasAnyShell => fallbackAvailable || termuxMode;

  @override
  String toString() =>
      'termux=$termuxMode (installed=$termuxInstalled, bash=$bashWorks), '
      'sh=$shWorks, intent=$termuxIntentAvailable';
}

/// Termux 通信服务
///
/// 注意：此服务需要 Android 原生插件实现（MethodChannel）。
/// 在没有原生实现时，返回默认值。
class TermuxService {
  static const _channel = MethodChannel('com.codexmobile.app/termux');

  /// 检查环境
  static Future<TermuxEnvCheck> checkEnvironment() async {
    try {
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
    } catch (_) {
      // MethodChannel 未实现时返回默认值
      return const TermuxEnvCheck();
    }
  }

  /// 执行单条命令
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
      );
    } catch (_) {
      // MethodChannel 未实现时返回默认值
      return const TermuxResult(
        exitCode: -1,
        stdout: 'Termux 服务未实现',
        stderr: 'MethodChannel 未注册',
        durationMs: 0,
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
