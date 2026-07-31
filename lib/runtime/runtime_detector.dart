/// ====================================================================
/// Runtime 检测器
///
/// 封装现有的 DetectorService，增加按 RuntimeCategory 分组和
/// 与 RuntimeEnvironment 集成的能力。
///
/// 分层架构（2025-07重构）：
///   Layer 0: Android 系统环境（shell, curl, 存储 — /system/bin/ 路径）
///   Layer 1: Termux Runtime（Termux 包 + Prefix + 包管理器）
///   Layer 2: Coding Runtime（Node, Git, Python — 依赖 Termux）
///   Layer 3: 高级工具（Codex CLI, mimo2codex — 依赖 Node）
/// ====================================================================
library;

import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/detector/detection_result.dart';
import '../core/detector/detector.dart';
import '../core/detector/detector_service.dart';
import 'process/process_runner.dart';
import 'process/runner_models.dart';
import 'runtime_environment.dart';

/// 检测结果（按类别分组）
class RuntimeDetectionResult {
  final List<DetectionResult> basic;       // Layer 0: Android 系统
  final List<DetectionResult> termux;      // Layer 1: Termux Runtime
  final List<DetectionResult> coding;      // Layer 2: Coding Runtime
  final List<DetectionResult> advanced;    // Layer 3: 高级工具
  final List<DetectionResult> ai;
  final List<DetectionResult> development;
  final List<DetectionResult> all;
  final bool isComplete;

  const RuntimeDetectionResult({
    this.basic = const [],
    this.termux = const [],
    this.coding = const [],
    this.advanced = const [],
    this.ai = const [],
    this.development = const [],
    this.all = const [],
    this.isComplete = false,
  });

  /// Coding Runtime 统计（Layer 2 + Layer 3）
  int get codingInstalled =>
      coding.where((r) => r.status == DetectionStatus.installed).length;
  int get codingTotal => coding.length;
  int get codingUnsupported =>
      coding.where((r) => r.status == DetectionStatus.unsupported).length;
  bool get codingReady =>
      codingInstalled >= codingTotal - codingUnsupported;

  /// 环境就绪状态
  bool get isEnvironmentReady => codingReady;

  /// 摘要文字
  String get summary {
    final parts = <String>[];
    if (basic.isNotEmpty) {
      final i = basic.where((r) => r.status == DetectionStatus.installed).length;
      parts.add('基础 ✅$i/${basic.length}');
    }
    if (termux.isNotEmpty) {
      final i = termux.where((r) => r.status == DetectionStatus.installed).length;
      parts.add('Termux ✅$i/${termux.length}');
    }
    if (coding.isNotEmpty) {
      parts.add('编码 ✅$codingInstalled/$codingTotal');
    }
    if (ai.isNotEmpty) {
      final i = ai.where((r) => r.status == DetectionStatus.installed).length;
      parts.add('AI ✅$i/${ai.length}');
    }
    if (development.isNotEmpty) {
      final i =
          development.where((r) => r.status == DetectionStatus.installed).length;
      parts.add('开发 ✅$i/${development.length}');
    }
    return parts.join(' · ');
  }
}

/// Runtime 检测器
class RuntimeDetector {
  final DetectorService _service;
  final RuntimeProcessRunner _runner = RuntimeProcessRunner();

  RuntimeDetector() : _service = DetectorService.create();

  /// 执行所有检测并按类别分组
  ///
  /// [environment] — 可选的 RuntimeEnvironment，用于增强检测（如 Ubuntu 检测）
  Future<RuntimeDetectionResult> detectAll({RuntimeEnvironment? environment}) async {
    // 先运行原有检测
    final allResults = await _service.detectAll();

    // 如果提供了 RuntimeEnvironment，补充 Ubuntu 检测
    List<DetectionResult> results = allResults;
    if (environment != null) {
      results = await _supplementWithUbuntuDetection(environment, results);
    }

    return reGroupResults(results);
  }

  /// 在已有检测结果基础上补充 Ubuntu Runtime 检测
  Future<List<DetectionResult>> _supplementWithUbuntuDetection(
    RuntimeEnvironment env,
    List<DetectionResult> existing,
  ) async {
    // 检查是否已有 ubuntu 条目
    if (existing.any((r) => r.id == 'ubuntu')) {
      return existing;
    }

    final ubuntuDir = env.ubuntuRootfsDir;
    final prootFile = File(path.join(env.ubuntuBinDir, 'proot'));
    final bashFile = File(path.join(ubuntuDir, 'usr', 'bin', 'bash'));
    final aptFile = File(path.join(ubuntuDir, 'usr', 'bin', 'apt'));

    String? version;
    DetectionStatus status;

    if (prootFile.existsSync() && bashFile.existsSync()) {
      // Ubuntu Runtime 已安装
      status = DetectionStatus.installed;
      // 尝试获取 rootfs 版本
      final osRelease = File(path.join(ubuntuDir, 'etc', 'os-release'));
      if (osRelease.existsSync()) {
        try {
          final content = osRelease.readAsStringSync();
          final versionMatch = RegExp(r'VERSION_ID="([^"]+)"').firstMatch(content);
          if (versionMatch != null) {
            version = 'Ubuntu ${versionMatch.group(1)}';
          }
        } catch (_) {}
      }
      version ??= '24.04';
    } else if (!prootFile.existsSync() && !aptFile.existsSync()) {
      // 部分安装或未安装
      status = DetectionStatus.missing;
    } else {
      status = DetectionStatus.missing;
    }

    existing.add(DetectionResult(
      id: 'ubuntu',
      name: 'Ubuntu Runtime',
      icon: '🐧',
      status: status,
      version: version,
    ));

    return existing;
  }

  /// 重新检测单个工具
  Future<DetectionResult?> detectOne(String id) async {
    return _service.detectOne(id);
  }

  /// 将检测结果按 RuntimeCategory 分组
  RuntimeDetectionResult reGroupResults(List<DetectionResult> results) {
    final basic = <DetectionResult>[];
    final termux = <DetectionResult>[];
    final coding = <DetectionResult>[];
    final advanced = <DetectionResult>[];
    final ai = <DetectionResult>[];
    final development = <DetectionResult>[];

    for (final r in results) {
      switch (r.subCategory) {
        case RuntimeSubCategory.basic:
          basic.add(r);
          break;
        case RuntimeSubCategory.coding:
          // 进一步区分 Termux vs Coding vs Advanced
          if (r.id == 'termux') {
            termux.add(r);
          } else if (r.id == 'node' || r.id == 'git' || r.id == 'python' || r.id == 'ubuntu') {
            coding.add(r);
          } else {
            advanced.add(r);
          }
          break;
        case RuntimeSubCategory.ai:
          ai.add(r);
          break;
        case RuntimeSubCategory.development:
          development.add(r);
          break;
      }
    }

    return RuntimeDetectionResult(
      basic: basic,
      termux: termux,
      coding: coding,
      advanced: advanced,
      ai: ai,
      development: development,
      all: results,
      isComplete: true,
    );
  }

  /// 验证 Coding 环境
  ///
  /// [environment] — 可选的 RuntimeEnvironment，用于 Ubuntu 环境验证。
  Future<List<VerificationResult>> verifyCodingEnvironment({
    RuntimeEnvironment? environment,
  }) async {
    final results = <VerificationResult>[];

    // 确定验证命令
    if (environment != null && environment.getRuntimeType() == RuntimeType.ubuntu) {
      // 在 Ubuntu Runtime 环境下验证
      final ubuntuBin = path.join(environment.ubuntuRootfsDir, 'usr', 'bin');
      final tools = [
        path.join(ubuntuBin, 'node'),
        path.join(ubuntuBin, 'git'),
        path.join(ubuntuBin, 'python3'),
      ];
      for (final toolPath in tools) {
        final name = path.basename(toolPath);
        final file = File(toolPath);
        if (file.existsSync()) {
          try {
            final req = RuntimeProcessRequest(executable: toolPath, arguments: [r'--version']);
            final result = await _runner.run(req);
            results.add(VerificationResult(
              tool: name,
              success: result.exitCode == 0,
              output: result.exitCode == 0 ? result.stdout.toString().trim() : null,
              error: result.exitCode != 0 ? result.stderr.toString().trim() : null,
            ));
          } catch (e) {
            results.add(VerificationResult(
              tool: name,
              success: false,
              error: e.toString(),
            ));
          }
        } else {
          results.add(VerificationResult(
            tool: name,
            success: false,
            error: '未安装',
          ));
        }
      }
    } else {
      // 系统环境验证
      for (final (tool, args) in [
        ('node', ['--version']),
        ('git', ['--version']),
        ('python3', ['--version']),
        ('codex', ['--version']),
        ('mimo2codex', ['--version']),
      ]) {
        try {
          final req = RuntimeProcessRequest(
              executable: tool, arguments: args, runInShell: true,
            );
            final procResult = await _runner.run(req);
            final result = procResult;
          results.add(VerificationResult(
            tool: tool,
            success: result.exitCode == 0,
            output: result.exitCode == 0 ? result.stdout.toString().trim() : null,
            error: result.exitCode != 0 ? result.stderr.toString().trim() : null,
          ));
        } catch (e) {
          results.add(VerificationResult(
            tool: tool,
            success: false,
            error: e.toString(),
          ));
        }
      }
    }

    return results;
  }

  /// 验证环境变量
  Future<Map<String, bool>> verifyEnv() async {
    final env = Platform.environment;
    return {
      'PATH': env['PATH'] != null,
      'HOME': env['HOME'] != null,
      'SHELL': env['SHELL'] != null,
      'TERM': env['TERM'] != null,
    };
  }
}

/// 验证结果
class VerificationResult {
  final String tool;
  final bool success;
  final String? output;
  final String? error;

  const VerificationResult({
    required this.tool,
    required this.success,
    this.output,
    this.error,
  });
}
