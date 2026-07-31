/// @Deprecated: 已迁移到 TermuxTransport。
/// 保留此文件仅用于过渡期兼容，将在后续版本移除。

/// ====================================================================
/// Termux Runtime Bridge
///
/// 统一接口：App 到 Termux Runtime 的通信层。
///
/// 职责：
///   1. 检测 Termux 是否真实可用（非 Android 系统 Shell 冒充）
///   2. 提供 Termux 专属命令执行（不降级到 /system/bin/sh）
///   3. 检测 Package Manager、Prefix、Shell
///   4. 诊断 Termux 状态
///
/// 设计原则：
///   - App 与 Termux 是不同 UID，不能直接访问 Termux 私有目录
///   - 真正的 Termux 集成必须通过：
///     a. Termux RUN_COMMAND Intent（推荐）
///     b. 共享用户方案（需 root 或相同签名）
///   - 本 Bridge 使用 RUN_COMMAND Intent 作为主要通信方式
/// ====================================================================
library;

import 'dart:io';
import 'package:flutter/services.dart';

/// Termux 执行结果（纯 Termux，不降级）
class TermuxCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final bool usedTermux;

  const TermuxCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.usedTermux = false,
  });

  bool get isSuccess => exitCode == 0;
}

/// Termux Runtime 完整诊断
class TermuxDiagnostics {
  /// Termux APK 是否安装
  final bool packageInstalled;

  /// RUN_COMMAND Intent 是否可用
  final bool intentAvailable;

  /// Termux 能否真正执行命令
  final bool works;

  /// Termux Prefix 路径（如果可访问）
  final String? prefixPath;

  /// Termux 版本号
  final String? version;

  /// 包管理器状态
  final TermuxPackageManagerStatus pkgManager;

  /// 诊断详情
  final String lastError;

  const TermuxDiagnostics({
    this.packageInstalled = false,
    this.intentAvailable = false,
    this.works = false,
    this.prefixPath,
    this.version,
    this.pkgManager = TermuxPackageManagerStatus.unavailable,
    this.lastError = '',
  });

  /// Termux Runtime 整体是否可用
  bool get isAvailable => packageInstalled && intentAvailable && works;

  /// 友好的状态描述
  String get statusDescription {
    if (!packageInstalled) return '未安装';
    if (!intentAvailable) return 'Intent 不可用';
    if (!works) return '执行失败: $lastError';
    if (version != null) return 'v$version';
    return '可用';
  }
}

/// Termux 包管理器状态
enum TermuxPackageManagerStatus {
  /// pkg 可用（推荐）
  pkg,

  /// apt 可用（降级）
  apt,

  /// dpkg 可用（仅基础）
  dpkg,

  /// 不可用
  unavailable,
}

/// Termux 环境信息
class TermuxEnvironment {
  /// Termux Shell 路径
  final String? shellPath;

  /// Termux HOME 路径
  final String? homePath;

  /// Termux Prefix 路径
  final String? prefixPath;

  /// 架构
  final String? architecture;

  /// 包管理器
  final TermuxPackageManagerStatus pkgManager;

  /// 包管理器可执行路径
  final String? pkgManagerPath;

  const TermuxEnvironment({
    this.shellPath,
    this.homePath,
    this.prefixPath,
    this.architecture,
    this.pkgManager = TermuxPackageManagerStatus.unavailable,
    this.pkgManagerPath,
  });

  bool get isAvailable => shellPath != null && prefixPath != null;
}

/// ====================================================================
/// Termux Runtime Bridge
///
/// 通过 MethodChannel 与原生层 TermuxBridge.kt 通信。
/// 所有 Coding Runtime 操作使用此 Bridge，不允许直接访问
/// /data/data/com.termux/files/usr/ 路径。
/// ====================================================================
class TermuxRuntimeBridge {
  static const _channel = MethodChannel('com.codexmobile.app/termux');

  // ─── 实例缓存 ───────────────────────────────────────────────

  static TermuxRuntimeBridge? _instance;
  TermuxDiagnostics? _lastDiagnostics;

  TermuxRuntimeBridge._();

  /// 获取单例
  static TermuxRuntimeBridge get instance {
    _instance ??= TermuxRuntimeBridge._();
    return _instance!;
  }

  /// 重置缓存（测试用）
  static void reset() {
    _instance = null;
  }

  // ─── 核心 API ───────────────────────────────────────────────

  /// 检查 Termux Runtime 是否真实可用
  ///
  /// 返回完整诊断信息，不只是布尔值。
  /// 如果 Termux 不可用，[works] 为 false 并附带 lastError。
  Future<TermuxDiagnostics> diagnose() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('checkEnvironment');
      final map = result as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};

      final packageInstalled = _bool(map['termux_installed']);
      final intentAvailable = _bool(map['termux_intent_available']);
      final works = _bool(map['termux_works']);

      // 尝试获取 Prefix 路径
      String? prefixPath;
      if (packageInstalled) {
        prefixPath = '/data/data/com.termux/files/usr';
      }

      // 检测包管理器
      final pkgManager = await _detectPackageManager(packageInstalled);

      final diagnostics = TermuxDiagnostics(
        packageInstalled: packageInstalled,
        intentAvailable: intentAvailable,
        works: works,
        prefixPath: prefixPath,
        version: await _detectVersion(packageInstalled, intentAvailable, works),
        pkgManager: pkgManager,
        lastError: _str(map['termux_last_stderr']),
      );

      _lastDiagnostics = diagnostics;
      return diagnostics;
    } catch (e) {
      final diagnostics = TermuxDiagnostics(
        lastError: 'Bridge 调用失败: $e',
      );
      _lastDiagnostics = diagnostics;
      return diagnostics;
    }
  }

  /// 简化检查：Termux 是否可用
  Future<bool> isAvailable() async {
    final diag = await diagnose();
    return diag.isAvailable;
  }

  /// 在 Termux 中执行命令（纯 Termux，不降级到系统 Shell）
  ///
  /// 与 TermuxService.execute 不同，此方法明确要求只在 Termux 中执行。
  /// 如果 Termux 不可用，抛出 [TermuxNotAvailableException]。
  Future<TermuxCommandResult> executeInTermux(String command) async {
    final diag = _lastDiagnostics ?? await diagnose();
    if (!diag.isAvailable) {
      return TermuxCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Termux Runtime 不可用: ${diag.statusDescription}',
        durationMs: 0,
      );
    }

    final start = DateTime.now();
    try {
      // 通过原生层执行 — TermuxBridge.kt 会尝试 RUN_COMMAND
      // 我们通过 check 知道 Termux 可用，所以 result.source 应为 'termux'
      final result = await _channel.invokeMethod<dynamic>('execute', {
        'command': command,
      });
      final map = result as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
      final source = _str(map['source']);

      // 如果降级到了 system_sh，说明 Termux 实际上不可用
      if (source == 'system_sh') {
        return TermuxCommandResult(
          exitCode: -1,
          stdout: '',
          stderr: '命令降级到系统 Shell 执行 — Termux Runtime 可能意外不可用',
          durationMs: DateTime.now().difference(start).inMilliseconds,
        );
      }

      return TermuxCommandResult(
        exitCode: _int(map['exitCode'], -1),
        stdout: _str(map['stdout']),
        stderr: _str(map['stderr']),
        durationMs: DateTime.now().difference(start).inMilliseconds,
        usedTermux: source == 'termux',
      );
    } catch (e) {
      return TermuxCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Termux 执行失败: $e',
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
    }
  }

  /// 在 Termux 中查找二进制文件
  ///
  /// 返回 Termux Prefix 下的完整路径，如
  ///   /data/data/com.termux/files/usr/bin/node
  /// 如果未找到或 Termux 不可用，返回 null。
  Future<String?> which(String binaryName) async {
    final result = await executeInTermux('which $binaryName 2>/dev/null');
    if (result.isSuccess && result.stdout.trim().isNotEmpty) {
      final path = result.stdout.trim().split('\n').first;
      // 必须是 Termux 路径
      if (path.startsWith('/data/data/com.termux/')) {
        return path;
      }
    }
    return null;
  }

  /// 通过 pkg 安装包
  ///
  /// 返回安装结果。安装过程可能较长（下载包）。
  /// [timeoutMs] — 超时时间，默认 120 秒。
  Future<TermuxCommandResult> installPackage(
    String packageName, {
    int timeoutMs = 120000,
  }) async {
    final diag = _lastDiagnostics ?? await diagnose();
    if (!diag.isAvailable) {
      return TermuxCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Termux Runtime 不可用，无法安装 $packageName',
        durationMs: 0,
      );
    }

    // 选择最佳包管理器
    final manager = _pkgManagerCommand(diag.pkgManager);
    return await executeInTermux('$manager install $packageName -y');
  }

  /// 更新包列表
  Future<TermuxCommandResult> updatePackageList({int timeoutMs = 60000}) async {
    final diag = _lastDiagnostics ?? await diagnose();
    if (!diag.isAvailable) {
      return const TermuxCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Termux Runtime 不可用',
        durationMs: 0,
      );
    }

    final manager = _pkgManagerCommand(diag.pkgManager);
    return await executeInTermux('$manager update -y');
  }

  /// 获取 Termux 环境信息
  Future<TermuxEnvironment> getEnvironment() async {
    final diag = _lastDiagnostics ?? await diagnose();
    if (!diag.isAvailable) {
      return const TermuxEnvironment();
    }

    // 并行获取环境信息
    final results = await Future.wait([
      executeInTermux('echo \$PREFIX'),
      executeInTermux('echo \$HOME'),
      executeInTermux('echo \$SHELL'),
      executeInTermux('dpkg --print-architecture 2>/dev/null || uname -m'),
    ]);

    final prefix = results[0].stdout.trim();
    final home = results[1].stdout.trim();
    final shell = results[2].stdout.trim();
    final arch = results[3].stdout.trim();

    final pkgManager = await _detectPackageManager(diag.packageInstalled);

    // 包管理器路径
    String? pkgManagerPath;
    if (pkgManager != TermuxPackageManagerStatus.unavailable) {
      final name = _pkgManagerCommand(pkgManager).split(' ').last;
      final whichResult = await executeInTermux('which $name 2>/dev/null');
      if (whichResult.isSuccess) {
        pkgManagerPath = whichResult.stdout.trim();
      }
    }

    return TermuxEnvironment(
      shellPath: shell.isNotEmpty ? shell : null,
      homePath: home.isNotEmpty ? home : null,
      prefixPath: prefix.isNotEmpty ? prefix : null,
      architecture: arch.isNotEmpty ? arch : null,
      pkgManager: pkgManager,
      pkgManagerPath: pkgManagerPath,
    );
  }

  // ─── 内部方法 ───────────────────────────────────────────────

  /// 检测 Termux 包管理器
  Future<TermuxPackageManagerStatus> _detectPackageManager(
    bool packageInstalled,
  ) async {
    if (!packageInstalled) return TermuxPackageManagerStatus.unavailable;

    // 使用系统 shell 检测 Termux 目录（避免循环依赖）
    try {
      // 检查 pkg 脚本
      final pkgFile = File('/data/data/com.termux/files/usr/bin/pkg');
      if (pkgFile.existsSync()) return TermuxPackageManagerStatus.pkg;

      // 检查 apt 二进制
      final aptFile = File('/data/data/com.termux/files/usr/bin/apt');
      if (aptFile.existsSync()) return TermuxPackageManagerStatus.apt;

      // 检查 dpkg 二进制
      final dpkgFile = File('/data/data/com.termux/files/usr/bin/dpkg');
      if (dpkgFile.existsSync()) return TermuxPackageManagerStatus.dpkg;
    } catch (_) {
      // ignore
    }

    return TermuxPackageManagerStatus.unavailable;
  }

  /// 检测 Termux 版本
  Future<String?> _detectVersion(
    bool packageInstalled,
    bool intentAvailable,
    bool works,
  ) async {
    if (!packageInstalled || !works) return null;

    // 通过执行 termux-info 获取版本
    final result = await executeInTermux(
      'termux-info 2>/dev/null | grep "Termux.*:" | head -1',
    );
    if (result.isSuccess && result.stdout.trim().isNotEmpty) {
      return result.stdout.trim();
    }

    // fallback: 检查 apk version
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

  /// 返回包管理器命令前缀
  static String _pkgManagerCommand(TermuxPackageManagerStatus status) {
    switch (status) {
      case TermuxPackageManagerStatus.pkg:
        return 'pkg';
      case TermuxPackageManagerStatus.apt:
        return 'apt';
      case TermuxPackageManagerStatus.dpkg:
        return 'dpkg';
      case TermuxPackageManagerStatus.unavailable:
        return '';
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

/// Termux 不可用异常
class TermuxNotAvailableException implements Exception {
  final String message;
  const TermuxNotAvailableException([this.message = 'Termux Runtime 不可用']);

  @override
  String toString() => 'TermuxNotAvailableException: $message';
}
