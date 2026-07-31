/// ====================================================================
/// Runtime 检测器
///
/// 封装 RuntimeManager + CapabilityResolver，将 RuntimeProvider 检测结果
/// 转换为 DetectionResult 格式，保持与 Deploy UI 的兼容性。
///
/// 不再使用旧 DetectorService 和 EnvironmentService。
/// ====================================================================
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/detector/detection_result.dart';
import '../core/detector/detector.dart';
import '../core/detector/detector_service.dart';
import 'capability/capability_resolver.dart';
import 'process/process_runner.dart';
import 'process/runner_models.dart';
import 'provider/runtime_capability.dart';
import 'runtime_environment.dart';
import 'runtime_manager.dart';

// ─── Capability → DetectionResult 桥接 ────────────────────────

/// Capability 类型到检测结果的映射表
///
/// 用于将 CapabilityResolver 检测结果转换为 UI 兼容的 DetectionResult。
class _CapabilityToResult {
  final CapabilityType type;
  final String id;
  final String name;
  final String icon;
  final DetectorCategory category;
  final RuntimeSubCategory subCategory;
  final String? missingHint;

  const _CapabilityToResult({
    required this.type,
    required this.id,
    required this.name,
    required this.icon,
    this.category = DetectorCategory.runtime,
    this.subCategory = RuntimeSubCategory.coding,
    this.missingHint,
  });
}

/// 所有可检测的 Capability 映射
const _kCapabilityMappings = <_CapabilityToResult>[
  _CapabilityToResult(
    type: CapabilityType.node,
    id: 'node',
    name: 'Node.js',
    icon: '🟢',
    subCategory: RuntimeSubCategory.coding,
  ),
  _CapabilityToResult(
    type: CapabilityType.npm,
    id: 'npm',
    name: 'npm',
    icon: '📦',
    subCategory: RuntimeSubCategory.coding,
  ),
  _CapabilityToResult(
    type: CapabilityType.git,
    id: 'git',
    name: 'Git',
    icon: '🔀',
    subCategory: RuntimeSubCategory.coding,
  ),
  _CapabilityToResult(
    type: CapabilityType.python,
    id: 'python',
    name: 'Python 3',
    icon: '🐍',
    subCategory: RuntimeSubCategory.coding,
  ),
  _CapabilityToResult(
    type: CapabilityType.codexCli,
    id: 'codex',
    name: 'Codex CLI',
    icon: '🤖',
    subCategory: RuntimeSubCategory.coding,
  ),
  _CapabilityToResult(
    type: CapabilityType.mimo2codex,
    id: 'mimo2codex',
    name: 'mimo2codex',
    icon: '🔮',
    subCategory: RuntimeSubCategory.coding,
  ),
  _CapabilityToResult(
    type: CapabilityType.flutter,
    id: 'flutter',
    name: 'Flutter SDK',
    icon: '🦋',
    category: DetectorCategory.development,
    subCategory: RuntimeSubCategory.development,
    missingHint: 'Flutter SDK（可选，用于 Flutter 开发）',
  ),
];

/// 将 RuntimeCapability 转换为 DetectionResult
DetectionResult _capabilityToResult(
    _CapabilityToResult mapping,
    RuntimeCapability cap,
    int durationMs,
    ) {
  return DetectionResult(
    id: mapping.id,
    name: mapping.name,
    icon: mapping.icon,
    status: cap.available ? DetectionStatus.installed : DetectionStatus.missing,
    version: cap.version,
    path: cap.executable ?? cap.path,
    errorMessage: cap.reason,
    durationMs: durationMs,
    category: mapping.category,
    subCategory: mapping.subCategory,
    missingHint: mapping.missingHint,
  );
}

// ─── RuntimeDetectionResult ───────────────────────────────────

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

// ─── RuntimeDetector ──────────────────────────────────────────

/// Runtime 检测器
///
/// 通过 RuntimeManager + CapabilityResolver 执行真实环境检测，
/// 输出 DetectionResult 以保持与 Deploy UI 的兼容性。
class RuntimeDetector {
  final RuntimeManager _runtimeManager;
  final CapabilityResolver _capabilityResolver;
  final RuntimeProcessRunner _runner;
  final DetectorService _systemService;

  RuntimeDetector({
    RuntimeManager? runtimeManager,
    CapabilityResolver? capabilityResolver,
    RuntimeProcessRunner? runner,
  })  : _runtimeManager = runtimeManager ?? RuntimeManager.instance,
        _capabilityResolver = capabilityResolver ?? CapabilityResolver(),
        _runner = runner ?? RuntimeProcessRunner(),
        _systemService = DetectorService._withSystemDetectors();

  /// 执行所有检测并按类别分组
  ///
  /// [environment] — 可选的 RuntimeEnvironment，用于增强检测（如 Ubuntu 检测）
  Future<RuntimeDetectionResult> detectAll({
    RuntimeEnvironment? environment,
  }) async {
    final results = <DetectionResult>[];

    // 1. 系统级检测（Android shell, 网络, 存储权限等）
    //    这些不是工具能力检测，保留旧 DetectorService
    final systemResults = await _systemService.detectAll();
    results.addAll(systemResults);

    // 2. 通过 RuntimeManager + CapabilityResolver 检测工具能力
    final toolResults = await _detectCapabilities();
    results.addAll(toolResults);

    // 3. 检测 Termux Runtime（特殊处理 — 需要完整诊断）
    if (results.any((r) => r.id == 'termux')) {
      // TermuxDetector 已由 _systemService 提供，保留
    }

    // 4. Ubuntu 补充检测
    if (environment != null) {
      results.addAll(await _detectUbuntu(environment));
    }

    return _reGroupResults(results);
  }

  /// 通过 CapabilityResolver 检测工具能力
  Future<List<DetectionResult>> _detectCapabilities() async {
    final results = <DetectionResult>[];

    // 获取所有可用 Provider
    final providers = _runtimeManager.registeredProviders;
    if (providers.isEmpty) {
      // 无可用 Provider，标记所有工具为 missing
      for (final mapping in _kCapabilityMappings) {
        results.add(DetectionResult(
          id: mapping.id,
          name: mapping.name,
          icon: mapping.icon,
          status: DetectionStatus.missing,
          category: mapping.category,
          subCategory: mapping.subCategory,
          missingHint: mapping.missingHint,
        ));
      }
      return results;
    }

    // 对每个 Provider 检测能力
    for (final provider in providers) {
      for (final mapping in _kCapabilityMappings) {
        final start = DateTime.now();
        final cap = await _capabilityResolver.checkCapability(
          mapping.type,
          provider,
        );
        final elapsed = DateTime.now().difference(start).inMilliseconds;

        results.add(_capabilityToResult(mapping, cap, elapsed));
      }
    }

    return results;
  }

  /// 检测 Ubuntu Runtime
  Future<List<DetectionResult>> _detectUbuntu(
      RuntimeEnvironment env) async {
    final results = <DetectionResult>[];
    final ubuntuDir = env.ubuntuRootfsDir;
    final prootFile = File(p.join(env.ubuntuBinDir, 'proot'));
    final bashFile = File(p.join(ubuntuDir, 'usr', 'bin', 'bash'));

    String? version;
    DetectionStatus status;

    if (prootFile.existsSync() && bashFile.existsSync()) {
      status = DetectionStatus.installed;
      final osRelease = File(p.join(ubuntuDir, 'etc', 'os-release'));
      if (osRelease.existsSync()) {
        try {
          final content = osRelease.readAsStringSync();
          final versionMatch =
          RegExp(r'VERSION_ID="([^"]+)"').firstMatch(content);
          if (versionMatch != null) {
            version = 'Ubuntu ${versionMatch.group(1)}';
          }
        } catch (_) {}
      }
      version ??= '24.04';
    } else {
      status = DetectionStatus.missing;
    }

    results.add(DetectionResult(
      id: 'ubuntu',
      name: 'Ubuntu Runtime',
      icon: '🐧',
      status: status,
      version: version,
      subCategory: RuntimeSubCategory.coding,
    ));

    return results;
  }

  /// 重新检测单个工具
  ///
  /// 支持两类 ID：
  ///   - 工具 ID（node / git / python / codex / flutter 等）→ CapabilityResolver
  ///   - 系统 ID（termux / shell / network / storage 等）→ DetectorService
  Future<DetectionResult?> detectOne(String id) async {
    // 1. 先尝试 CapabilityResolver（工具能力）
    for (final mapping in _kCapabilityMappings) {
      if (mapping.id != id) continue;

      final providers = _runtimeManager.registeredProviders;
      for (final provider in providers) {
        final cap = await _capabilityResolver.checkCapability(
          mapping.type,
          provider,
        );
        return _capabilityToResult(mapping, cap, 0);
      }
      // 无可用 Provider → missing
      return DetectionResult(
        id: mapping.id,
        name: mapping.name,
        icon: mapping.icon,
        status: DetectionStatus.missing,
        category: mapping.category,
        subCategory: mapping.subCategory,
        missingHint: mapping.missingHint,
      );
    }

    // 2. 回退到系统检测器
    return _systemService.detectOne(id);
  }

  /// 将检测结果按 RuntimeCategory 分组
  RuntimeDetectionResult _reGroupResults(List<DetectionResult> results) {
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
          if (r.id == 'termux') {
            termux.add(r);
          } else if (r.id == 'node' || r.id == 'git' || r.id == 'python' ||
              r.id == 'ubuntu' || r.id == 'npm') {
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
  Future<List<VerificationResult>> verifyCodingEnvironment({
    RuntimeEnvironment? environment,
  }) async {
    final results = <VerificationResult>[];

    if (environment != null &&
        environment.getRuntimeType() == RuntimeType.ubuntu) {
      final ubuntuBin = p.join(environment.ubuntuRootfsDir, 'usr', 'bin');
      for (final tool in ['node', 'git', 'python3']) {
        final toolPath = p.join(ubuntuBin, tool);
        final file = File(toolPath);
        if (file.existsSync()) {
          try {
            final req = RuntimeProcessRequest(
              executable: toolPath,
              arguments: ['--version'],
            );
            final result = await _runner.run(req);
            results.add(VerificationResult(
              tool: tool,
              success: result.exitCode == 0,
              output:
              result.exitCode == 0 ? result.stdout.toString().trim() : null,
              error:
              result.exitCode != 0 ? result.stderr.toString().trim() : null,
            ));
          } catch (e) {
            results.add(VerificationResult(
              tool: tool,
              success: false,
              error: e.toString(),
            ));
          }
        } else {
          results.add(VerificationResult(
            tool: tool,
            success: false,
            error: '未安装',
          ));
        }
      }
    } else {
      for (final entry in [
        ('node', ['--version']),
        ('git', ['--version']),
        ('python3', ['--version']),
        ('codex', ['--version']),
        ('mimo2codex', ['--version']),
      ]) {
        try {
          final req = RuntimeProcessRequest(
            executable: entry.$1,
            arguments: entry.$2,
            runInShell: true,
          );
          final result = await _runner.run(req);
          results.add(VerificationResult(
            tool: entry.$1,
            success: result.exitCode == 0,
            output:
            result.exitCode == 0 ? result.stdout.toString().trim() : null,
            error:
            result.exitCode != 0 ? result.stderr.toString().trim() : null,
          ));
        } catch (e) {
          results.add(VerificationResult(
            tool: entry.$1,
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
