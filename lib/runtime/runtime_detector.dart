import 'dart:io';
import '../core/detector/detection_result.dart';
import '../core/detector/detector.dart';
import '../core/detector/detector_service.dart';
import 'runtime_dependency.dart';

/// ====================================================================
/// Runtime 检测器
///
/// 封装现有的 DetectorService，增加按 RuntimeCategory 分组和
/// 与 RuntimeEnvironment 集成的能力。
/// ====================================================================

/// 检测结果（按类别分组）
class RuntimeDetectionResult {
  /// 基础 Runtime 检测结果
  final List<DetectionResult> basic;

  /// Coding Runtime 检测结果
  final List<DetectionResult> coding;

  /// AI Runtime 检测结果
  final List<DetectionResult> ai;

  /// Development Runtime 检测结果
  final List<DetectionResult> development;

  /// 所有结果（不分类别）
  final List<DetectionResult> all;

  /// 检测是否完成
  final bool isComplete;

  const RuntimeDetectionResult({
    this.basic = const [],
    this.coding = const [],
    this.ai = const [],
    this.development = const [],
    this.all = const [],
    this.isComplete = false,
  });

  /// Coding Runtime 统计
  int get codingInstalled =>
      coding.where((r) => r.status == DetectionStatus.installed).length;
  int get codingTotal => coding.length;
  bool get codingReady => codingInstalled == codingTotal;

  /// 环境就绪状态
  bool get isEnvironmentReady => codingReady;

  /// 摘要文字
  String get summary {
    final parts = <String>[];
    if (basic.isNotEmpty) {
      final i = basic.where((r) => r.status == DetectionStatus.installed).length;
      parts.add('基础 ✅$i/${basic.length}');
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

  RuntimeDetector() : _service = DetectorService.create();

  /// 执行所有检测并按类别分组
  Future<RuntimeDetectionResult> detectAll() async {
    final allResults = await _service.detectAll();
    return _groupResults(allResults);
  }

  /// 重新检测单个工具
  Future<DetectionResult?> detectOne(String id) async {
    return _service.detectOne(id);
  }

  /// 将检测结果按 RuntimeCategory 分组
  RuntimeDetectionResult _groupResults(List<DetectionResult> results) {
    final basic = <DetectionResult>[];
    final coding = <DetectionResult>[];
    final ai = <DetectionResult>[];
    final development = <DetectionResult>[];

    for (final r in results) {
      // 根据检测器 id 映射到 RuntimeCategory
      final category = _mapToRuntimeCategory(r.id);
      switch (category) {
        case RuntimeCategory.basic:
          basic.add(r);
          break;
        case RuntimeCategory.coding:
          coding.add(r);
          break;
        case RuntimeCategory.ai:
          ai.add(r);
          break;
        case RuntimeCategory.development:
          development.add(r);
          break;
      }
    }

    return RuntimeDetectionResult(
      basic: basic,
      coding: coding,
      ai: ai,
      development: development,
      all: results,
      isComplete: true,
    );
  }

  /// 将检测器 id 映射到 Runtime 类别
  static RuntimeCategory _mapToRuntimeCategory(String detectorId) {
    switch (detectorId) {
      case 'termux':
      case 'curl':
      case 'storage':
        return RuntimeCategory.basic;
      case 'node':
      case 'git':
      case 'python':
      case 'codex':
      case 'mimo2codex':
        return RuntimeCategory.coding;
      case 'deepseek_key':
        return RuntimeCategory.ai;
      case 'flutter':
        return RuntimeCategory.development;
      default:
        return RuntimeCategory.basic;
    }
  }

  /// 验证 Coding 环境
  ///
  /// 执行所有 Coding Runtime 工具的命令行验证。
  Future<List<VerificationResult>> verifyCodingEnvironment() async {
    final results = <VerificationResult>[];
    final tools = [
      ('node', ['--version']),
      ('git', ['--version']),
      ('python3', ['--version']),
      ('codex', ['--version']),
      ('mimo2codex', ['--version']),
    ];

    for (final (tool, args) in tools) {
      try {
        final result = await Process.run(tool, args, runInShell: true);
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

    return results;
  }

  /// 验证环境变量和网络
  Future<Map<String, bool>> verifyEnvironment() async {
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
