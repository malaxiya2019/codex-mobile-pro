/// ====================================================================
/// MethodChannelTermuxTransport
///
/// TermuxTransport 的 MethodChannel 实现。
/// 通过 Flutter MethodChannel 与 TermuxBridge.kt 通信。
///
/// 通信协议（不变）：
///   TermuxProvider → Transport → MethodChannel → TermuxBridge.kt
///   → RUN_COMMAND Intent → Termux
///
/// 不修改 Kotlin 侧的 IPC 协议。
/// ====================================================================
library;

import 'dart:io';
import 'package:flutter/services.dart';

import 'termux_transport.dart';

/// MethodChannel Termux Transport
class MethodChannelTermuxTransport implements TermuxTransport {
  static const _channel = MethodChannel('com.codexmobile.app/termux');

  /// 缓存上次诊断结果（避免重复 IPC）
  TermuxDiagnosticResult? _lastDiagnostics;

  @override
  Future<TermuxDiagnosticResult> diagnose() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('checkEnvironment');
      final map = result as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};

      final packageInstalled = _bool(map['termux_installed']);
      final intentAvailable = _bool(map['termux_intent_available']);
      final works = _bool(map['termux_works']);

      final diagnostics = TermuxDiagnosticResult(
        packageInstalled: packageInstalled,
        intentAvailable: intentAvailable,
        works: works,
        version: await _detectVersion(packageInstalled, intentAvailable, works),
        lastError: _str(map['termux_last_stderr']),
      );

      _lastDiagnostics = diagnostics;
      return diagnostics;
    } catch (e) {
      final diagnostics = TermuxDiagnosticResult(
        lastError: 'Transport 诊断失败: $e',
      );
      _lastDiagnostics = diagnostics;
      return diagnostics;
    }
  }

  @override
  Future<TermuxExecResult> execute(String command) async {
    try {
      final result = await _channel.invokeMethod<dynamic>('execute', {
        'command': command,
      });
      final map = result as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
      final source = _str(map['source']);

      return TermuxExecResult(
        exitCode: _int(map['exitCode'], -1),
        stdout: _str(map['stdout']),
        stderr: _str(map['stderr']),
        durationMs: _int(map['durationMs']),
        usedTermux: source == 'termux',
      );
    } catch (e) {
      return TermuxExecResult(
        exitCode: -1,
        stderr: 'Transport 执行失败: $e',
        durationMs: 0,
      );
    }
  }

  @override
  Future<TermuxEnvResult> getEnvironment() async {
    final diag = _lastDiagnostics ?? await diagnose();
    if (!diag.isAvailable) {
      return const TermuxEnvResult();
    }

    // 并行获取环境信息
    final results = await Future.wait([
      execute(r'echo $PREFIX'),
      execute(r'echo $HOME'),
      execute(r'echo $SHELL'),
      execute(r'dpkg --print-architecture 2>/dev/null || uname -m'),
    ]);

    final prefix = results[0].stdout.trim();
    final home = results[1].stdout.trim();
    final shell = results[2].stdout.trim();
    final arch = results[3].stdout.trim();

    final pkgManager = await _detectPackageManager(diag.packageInstalled);

    // 包管理器路径
    String? pkgManagerPath;
    if (pkgManager != TermuxPkgManager.unavailable) {
      final name = _pkgManagerBinary(pkgManager);
      final whichResult = await execute('which $name 2>/dev/null');
      if (whichResult.isSuccess) {
        pkgManagerPath = whichResult.stdout.trim();
      }
    }

    return TermuxEnvResult(
      prefixPath: prefix.isNotEmpty ? prefix : null,
      homePath: home.isNotEmpty ? home : null,
      shellPath: shell.isNotEmpty ? shell : null,
      architecture: arch.isNotEmpty ? arch : null,
      pkgManager: pkgManager,
      pkgManagerPath: pkgManagerPath,
    );
  }

  @override
  Future<String?> which(String binaryName) async {
    final result = await execute('which $binaryName 2>/dev/null');
    if (result.isSuccess && result.stdout.trim().isNotEmpty) {
      final path = result.stdout.trim().split('\n').first;
      // 必须是 Termux 路径（以 /data 开头）
      if (path.startsWith('/data/')) {
        return path;
      }
    }
    return null;
  }

  @override
  Future<TermuxInstallResult> installPackage(
    String packageName, {
    int timeoutMs = 120000,
  }) async {
    final diag = _lastDiagnostics ?? await diagnose();
    if (!diag.isAvailable) {
      return TermuxInstallResult(
        success: false,
        errorMessage: 'Termux 不可用，无法安装 $packageName',
      );
    }

    final manager = await _detectPackageManager(diag.packageInstalled);
    if (manager == TermuxPkgManager.unavailable) {
      return TermuxInstallResult(
        success: false,
        errorMessage: '无可用包管理器',
      );
    }

    final cmd = '${_pkgManagerBinary(manager)} install $packageName -y';
    final result = await execute(cmd);

    return TermuxInstallResult(
      success: result.isSuccess,
      errorMessage: result.isSuccess ? null : result.stderr,
      durationMs: result.durationMs,
      output: result.stdout,
    );
  }

  @override
  Future<TermuxInstallResult> updatePackageList({int timeoutMs = 60000}) async {
    final diag = _lastDiagnostics ?? await diagnose();
    if (!diag.isAvailable) {
      return TermuxInstallResult(
        success: false,
        errorMessage: 'Termux 不可用',
      );
    }

    final manager = await _detectPackageManager(diag.packageInstalled);
    if (manager == TermuxPkgManager.unavailable) {
      return TermuxInstallResult(
        success: false,
        errorMessage: '无可用包管理器',
      );
    }

    final result = await execute('${_pkgManagerBinary(manager)} update -y');
    return TermuxInstallResult(
      success: result.isSuccess,
      errorMessage: result.isSuccess ? null : result.stderr,
      durationMs: result.durationMs,
      output: result.stdout,
    );
  }

  // ─── 内部方法 ───────────────────────────────────────────────

  /// 检测 Termux 包管理器
  Future<TermuxPkgManager> _detectPackageManager(
    bool packageInstalled,
  ) async {
    if (!packageInstalled) return TermuxPkgManager.unavailable;

    // 通过 Termux 自身检测（使用 which）
    // /system/bin/sh 无法访问 Termux 私有目录
    try {
      final pkgResult = await execute('which pkg 2>/dev/null');
      if (pkgResult.isSuccess) return TermuxPkgManager.pkg;

      final aptResult = await execute('which apt 2>/dev/null');
      if (aptResult.isSuccess) return TermuxPkgManager.apt;

      final dpkgResult = await execute('which dpkg 2>/dev/null');
      if (dpkgResult.isSuccess) return TermuxPkgManager.dpkg;
    } catch (_) {}

    return TermuxPkgManager.unavailable;
  }

  /// 检测 Termux 版本
  Future<String?> _detectVersion(
    bool packageInstalled,
    bool intentAvailable,
    bool works,
  ) async {
    if (!packageInstalled || !works) return null;

    // 通过 termux-info 获取版本
    final result = await execute(
      r'termux-info 2>/dev/null | grep "Termux.*:" | head -1',
    );
    if (result.isSuccess && result.stdout.trim().isNotEmpty) {
      return result.stdout.trim();
    }

    // fallback: 通过 pm 查版本
    try {
      final pm = await Process.run(
        '/system/bin/sh',
        ['-c', 'dumpsys package com.termux | grep versionName | head -1'],
      );
      if (pm.exitCode == 0) {
        final line = (pm.stdout as String).trim();
        final match = RegExp(r'versionName=([\d.]+)').firstMatch(line);
        if (match != null) return match.group(1);
      }
    } catch (_) {}

    return null;
  }

  static String _pkgManagerBinary(TermuxPkgManager status) {
    switch (status) {
      case TermuxPkgManager.pkg: return 'pkg';
      case TermuxPkgManager.apt: return 'apt';
      case TermuxPkgManager.dpkg: return 'dpkg';
      case TermuxPkgManager.unavailable: return '';
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
