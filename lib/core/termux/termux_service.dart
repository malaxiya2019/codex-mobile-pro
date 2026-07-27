/// Codex Mobile Pro — Termux 通信服务
///
/// 通过 MethodChannel 与 Native (Kotlin) 桥交互，
/// 在 Termux 环境中执行命令并获取输出。

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

/// 环境检查结果
class TermuxEnvCheck {
  final bool bashExists;
  final bool termuxHomeExists;
  final bool bashExecutable;

  const TermuxEnvCheck({
    required this.bashExists,
    required this.termuxHomeExists,
    required this.bashExecutable,
  });

  bool get isAvailable => bashExists && termuxHomeExists && bashExecutable;

  @override
  String toString() =>
      'bash=$bashExists, home=$termuxHomeExists, executable=$bashExecutable';
}

/// Termux 通信服务
class TermuxService {
  static const _channel = MethodChannel('com.codexmobile.app/termux');

  /// 检查 Termux 环境是否可用
  static Future<TermuxEnvCheck> checkEnvironment() async {
    final map = await _channel.invokeMethod<Map>('checkEnvironment');
    return TermuxEnvCheck(
      bashExists: map?['bash_exists'] as bool? ?? false,
      termuxHomeExists: map?['termux_home_exists'] as bool? ?? false,
      bashExecutable: map?['bash_executable'] as bool? ?? false,
    );
  }

  /// 执行单条命令
  static Future<TermuxResult> execute(String command) async {
    final map = await _channel.invokeMethod<Map>('execute', {
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
