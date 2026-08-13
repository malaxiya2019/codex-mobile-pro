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
import 'runtime_dependency.dart';
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
  ),
  _CapabilityToResult(
    type: CapabilityType.npm,
    id: 'npm',
    name: 'npm',
    icon: '📦',
    missingHint: 'npm（随 Node.js 一并安装，无需单独安装）',
  ),
  _CapabilityToResult(
    type: CapabilityType.git,
    id: 'git',
    name: 'Git',
    icon: '🔀',
  ),
  _CapabilityToResult(
    type: CapabilityType.python,
    id: 'python',
    name: 'Python 3',
    icon: '🐍',
  ),
  _CapabilityToResult(
    type: CapabilityType.uv,
    id: 'uv',
    name: 'uv / uvx',
    icon: '🚀',
    missingHint: 'Qwen-MM-Plugins MCP server 按需启动所需',
  ),
  _CapabilityToResult(
    type: CapabilityType.codexCli,
    id: 'codex',
    name: 'Codex CLI',
    icon: '🤖',
  ),
  _CapabilityToResult(
    type: CapabilityType.qwenMmPlugins,
    id: 'qwen_mm_plugins',
    name: 'Qwen-MM-Plugins',
    icon: '🖼️',
    missingHint: 'Qwen 多模态能力（8 个 Skill + MCP server），随 Codex 部署',
  ),
  _CapabilityToResult(
    type: CapabilityType.mimo2codex,
    id: 'mimo2codex',
    name: 'mimo2codex',
    icon: '🔮',
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

  // DeepSeek API Key：非二进制能力（App 私有目录配置文件），
  // 在 _detectCapabilities / detectOne 中特判检测，不经过 CapabilityResolver。
  _CapabilityToResult(
    type: CapabilityType.deepseekKey,
    id: 'deepseek_key',
    name: 'DeepSeek API Key',
    icon: '🔑',
    subCategory: RuntimeSubCategory.ai,
    missingHint: '用于 AI 代码补全（mimo2codex / AI Provider）',
  ),
];

/// 将 RuntimeCapability 转换为 DetectionResult
DetectionResult _capabilityToResult(
  _CapabilityToResult mapping,
  RuntimeCapability cap,
  int durationMs,
) {
  // broken：可执行文件已解析成功（已安装）但执行失败 → error 状态。
  // 不能判定为 missing（否则 UI 显示「可安装」且安装按钮禁用）。
  // 例如 npm 随 Node.js 安装但 exit=127（dpkg interrupted 遗留）。
  final status = cap.available
      ? DetectionStatus.installed
      : (cap.health == CapabilityHealth.degraded && cap.executable != null)
          ? DetectionStatus.error
          : DetectionStatus.missing;

  return DetectionResult(
    id: mapping.id,
    name: mapping.name,
    icon: mapping.icon,
    status: status,
    version: cap.version,
    path: cap.executable ?? cap.path,
    errorMessage: status == DetectionStatus.error
        ? '已安装但执行失败: ${cap.reason ?? "未知错误"}'
        : cap.reason,
    durationMs: durationMs,
    category: mapping.category,
    subCategory: mapping.subCategory,
    missingHint: mapping.missingHint,
  );
}

/// 生成「依赖 Linux Runtime」的 missing 结果
///
/// PRoot + Ubuntu rootfs 未就绪（全新安装 / 卸载重装 / 初始化中断）时，
/// rootfs 内工具（node/npm/git/python/codex/mimo2codex/flutter）一律不经过
/// CapabilityResolver：
///   - resolver 会 fallback 到宿主 shell 执行 `node --version` 等命令
///     → command not found exit=127
///   - _capabilityToResult 将其误判为「已安装但执行失败（error）」
///   - error 不计入 codingMissing → 一键部署按钮永不出现（APK-238 死锁根因）
/// → 统一标记 missing，引导用户先完成一键部署。
DetectionResult _rootfsDependencyMissing(_CapabilityToResult mapping) {
  return DetectionResult(
    id: mapping.id,
    name: mapping.name,
    icon: mapping.icon,
    status: DetectionStatus.missing,
    category: mapping.category,
    subCategory: mapping.subCategory,
    missingHint: '依赖 Linux Runtime（请先一键部署 Coding 环境）',
  );
}

// ─── RuntimeDetectionResult ───────────────────────────────────

/// 检测结果（按类别分组）
class RuntimeDetectionResult {
  final List<DetectionResult> basic; // Layer 0: Android 系统
  final List<DetectionResult> linux; // Layer 1: Linux Runtime
  final List<DetectionResult> coding; // Layer 2: Coding Runtime
  final List<DetectionResult> advanced; // Layer 3: 高级工具
  final List<DetectionResult> ai;
  final List<DetectionResult> development;
  final List<DetectionResult> all;
  final bool isComplete;

  const RuntimeDetectionResult({
    this.basic = const [],
    this.linux = const [],
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
  bool get codingReady => codingInstalled >= codingTotal - codingUnsupported;

  /// 环境就绪状态
  bool get isEnvironmentReady => codingReady;

  /// 摘要文字
  String get summary {
    final parts = <String>[];
    if (basic.isNotEmpty) {
      final i =
          basic.where((r) => r.status == DetectionStatus.installed).length;
      parts.add('基础 ✅$i/${basic.length}');
    }
    if (linux.isNotEmpty) {
      final i =
          linux.where((r) => r.status == DetectionStatus.installed).length;
      parts.add('Linux ✅$i/${linux.length}');
    }
    if (coding.isNotEmpty) {
      parts.add('编码 ✅$codingInstalled/$codingTotal');
    }
    if (ai.isNotEmpty) {
      final i = ai.where((r) => r.status == DetectionStatus.installed).length;
      parts.add('AI ✅$i/${ai.length}');
    }
    if (development.isNotEmpty) {
      final i = development
          .where((r) => r.status == DetectionStatus.installed)
          .length;
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
        _capabilityResolver = capabilityResolver ?? _sharedCapabilityResolver(),
        _runner = runner ?? _sharedProcessRunner(),
        _systemService = DetectorService.createSystemDetectors();

  /// 复用 RuntimeManager 共享 resolver（已注册 LinuxExecutionAdapter）。
  ///
  /// 保证无参构造（如 checkOne 中 `RuntimeDetector()`）与安装链路
  /// 走同一执行通道（runtimeId='linux' → PRoot），避免宿主直连 rootfs ELF。
  static CapabilityResolver _sharedCapabilityResolver() {
    final shared = RuntimeManager.instance.capabilityResolver;
    return shared ?? CapabilityResolver();
  }

  /// 复用 RuntimeManager 共享 runner（已注册 LinuxExecutionAdapter）。
  static RuntimeProcessRunner _sharedProcessRunner() {
    final shared = RuntimeManager.instance.processRunner;
    return shared ?? RuntimeProcessRunner();
  }

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
    final toolResults = await _detectCapabilities(environment);
    results.addAll(toolResults);

    // 3. Linux Runtime 补充检测（PRoot + Ubuntu rootfs）
    if (environment != null) {
      results.addAll(await _detectLinux(environment));
    }

    return reGroupResults(results);
  }

  /// 通过 CapabilityResolver 检测工具能力
  Future<List<DetectionResult>> _detectCapabilities(
    RuntimeEnvironment? environment,
  ) async {
    final results = <DetectionResult>[];

    // DeepSeek API Key：非二进制能力（App 私有目录 .mimo2codex/.env），
    // 与 Provider 无关，统一在入口生成一次。
    results.add(await _detectDeepSeekKey(environment));

    // Qwen-MM-Plugins：配置部署型能力（rootfs ~/.codex/config.toml 的
    // [mcp_servers.qwen-mm-plugins-*]），非二进制，与 Provider 无关。
    results.add(await _detectQwenMmPlugins(environment));

    // 获取所有可用 Provider
    final providers = _runtimeManager.registeredProviders;
    if (providers.isEmpty) {
      // 无可用 Provider，标记所有工具为 missing
      for (final mapping in _kCapabilityMappings) {
        if (mapping.type == CapabilityType.deepseekKey ||
            mapping.type == CapabilityType.qwenMmPlugins) {
          continue;
        }
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

    // Coding 工具（node/npm/git/python/codex/mimo2codex/flutter）全部位于
    // Ubuntu rootfs 内，只有 Linux Runtime Provider 能给出真实状态。
    // 对 app/android 也跑一遍只会产生「宿主找不到 → 可安装」的噪音卡片，
    // 且 CapabilityResolver 按 type 缓存会跨 Provider 互相污染。
    // → Linux Provider 存在时只检测它；否则回退全部 Provider。
    final linuxProviders =
        providers.where((p) => p.type == ProviderType.linux).toList();
    final effectiveProviders =
        linuxProviders.isNotEmpty ? linuxProviders : providers;

    // Linux Runtime 未就绪（全新安装 / 卸载重装）时，rootfs 内工具一律
    // 不经过 CapabilityResolver，避免宿主 shell fallback 误报 exit=127
    // 被标成 error（→ codingMissing=0 → 一键部署按钮不出现，APK-238 死锁）。
    // 统一标记 missing 并引导先完成一键部署。
    final env = environment ?? _runtimeManager.environment;
    final linuxNotReady =
        linuxProviders.isNotEmpty && env != null && !env.isLinuxReady;

    // 对每个 Provider 检测能力
    for (final provider in effectiveProviders) {
      for (final mapping in _kCapabilityMappings) {
        if (mapping.type == CapabilityType.deepseekKey ||
            mapping.type == CapabilityType.qwenMmPlugins) {
          continue;
        }
        if (linuxNotReady) {
          results.add(_rootfsDependencyMissing(mapping));
          continue;
        }
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

  /// 检测 Linux Runtime（PRoot + Ubuntu rootfs）
  Future<List<DetectionResult>> _detectLinux(RuntimeEnvironment env) async {
    final results = <DetectionResult>[];
    final ubuntuDir = env.ubuntuRootfsDir;
    final prootFile = File(p.join(env.ubuntuBinDir, 'proot'));
    final bashFile = File(p.join(ubuntuDir, 'usr', 'bin', 'bash'));

    String? version;
    DetectionStatus status;
    String? missingHint;
    String? errorMessage;

    if (prootFile.existsSync() && bashFile.existsSync()) {
      // 目录存在并不等于安装完成：必须同时存在完成标记
      if (!env.hasPartialUbuntuInstall) {
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
        // 半成品 rootfs（上次初始化中断/失败）→ 明确提示重新初始化
        status = DetectionStatus.error;
        missingHint = 'Linux Runtime 上次初始化未完成，请重新初始化';
        errorMessage = '检测到不完整的安装（缺少完成标记），为避免误用已标记为失败';
      }
    } else {
      status = DetectionStatus.missing;
      missingHint = 'Linux Runtime 未初始化（PRoot + Ubuntu rootfs）';
    }

    results.add(DetectionResult(
      id: 'linux',
      name: 'Linux Runtime',
      icon: '🐧',
      status: status,
      version: version,
      missingHint: missingHint,
      errorMessage: errorMessage,
    ));

    return results;
  }

  /// 重新检测单个工具
  ///
  /// 支持两类 ID：
  ///   - 工具 ID（node / git / python / codex / flutter 等）→ CapabilityResolver
  ///   - 系统 ID（shell / network / storage 等）→ DetectorService
  Future<DetectionResult?> detectOne(
    String id, {
    RuntimeEnvironment? environment,
  }) async {
    // DeepSeek API Key：非二进制能力，直接检查 App 私有目录配置文件
    if (id == 'deepseek_key') {
      return _detectDeepSeekKey(environment ?? _runtimeManager.environment);
    }
    // Qwen-MM-Plugins：非二进制能力，检查 rootfs Codex config 的 MCP 段
    if (id == 'qwen_mm_plugins') {
      return _detectQwenMmPlugins(environment ?? _runtimeManager.environment);
    }

    // 1. 先尝试 CapabilityResolver（工具能力）
    for (final mapping in _kCapabilityMappings) {
      if (mapping.id != id) continue;

      // 与 _detectCapabilities 保持一致：Coding 工具只由
      // Linux Runtime Provider 提供真实检测，避免 app/android 噪音。
      final providers = _runtimeManager.registeredProviders;
      final linuxProviders =
          providers.where((p) => p.type == ProviderType.linux).toList();
      final effective = linuxProviders.isNotEmpty ? linuxProviders : providers;

      // 与 _detectCapabilities 一致：Linux 未就绪时跳过 resolver，
      // 避免宿主 shell fallback 误报 exit=127。
      final env = environment ?? _runtimeManager.environment;
      if (linuxProviders.isNotEmpty && env != null && !env.isLinuxReady) {
        return _rootfsDependencyMissing(mapping);
      }
      for (final provider in effective) {
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

  /// 查找 capability 映射（deepseek_key 特判用）
  static _CapabilityToResult _findCapabilityMapping(String id) {
    for (final m in _kCapabilityMappings) {
      if (m.id == id) return m;
    }
    throw StateError('缺少 capability 映射: $id');
  }

  /// DeepSeek API Key：非二进制能力检测
  ///
  /// 检查 App 私有目录 `.mimo2codex/.env` 中是否已保存 DS_API_KEY。
  /// 不执行任何二进制命令，只依赖 RuntimeEnvironment.isToolInstalled。
  Future<DetectionResult> _detectDeepSeekKey(
    RuntimeEnvironment? environment,
  ) async {
    final mapping = _findCapabilityMapping('deepseek_key');
    final ready = environment != null &&
        await environment.isToolInstalled(RuntimeTool.deepseekKey);
    return DetectionResult(
      id: mapping.id,
      name: mapping.name,
      icon: mapping.icon,
      status: ready ? DetectionStatus.installed : DetectionStatus.missing,
      category: mapping.category,
      subCategory: mapping.subCategory,
      missingHint: mapping.missingHint,
    );
  }

  /// Qwen-MM-Plugins 检测：rootfs ~/.codex/config.toml 是否已含 MCP 段。
  ///
  /// 该能力为配置部署型（无独立二进制），部署状态由 Codex 配置决定：
  /// 含 [mcp_servers.qwen-mm-plugins-*] → 已部署。
  Future<DetectionResult> _detectQwenMmPlugins(
    RuntimeEnvironment? environment,
  ) async {
    final mapping = _findCapabilityMapping('qwen_mm_plugins');
    final ready = environment != null &&
        await environment.isToolInstalled(RuntimeTool.qwenMmPlugins);
    return DetectionResult(
      id: mapping.id,
      name: mapping.name,
      icon: mapping.icon,
      status: ready ? DetectionStatus.installed : DetectionStatus.missing,
      category: mapping.category,
      subCategory: mapping.subCategory,
      missingHint: mapping.missingHint,
    );
  }

  /// 将检测结果按 RuntimeCategory 分组
  RuntimeDetectionResult reGroupResults(List<DetectionResult> results) {
    final basic = <DetectionResult>[];
    final linux = <DetectionResult>[];
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
          if (r.id == 'linux') {
            linux.add(r);
          } else if (r.id == 'node' ||
              r.id == 'git' ||
              r.id == 'python' ||
              r.id == 'npm' ||
              r.id == 'codex') {
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
      linux: linux,
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
        environment.getRuntimeType() == RuntimeType.linux) {
      // Linux Runtime 就绪时一律在 PRoot（rootfs）内执行真实版本检测，
      // 与检测卡片共用同一执行链路，避免两个口径互相矛盾：
      //   - 旧实现用宿主侧 File.existsSync() 判「未安装」，对 rootfs 内
      //     broken symlink（宿主侧目标不存在）误报「未安装」，
      //     而卡片却显示 exit=127（已安装但异常），用户被误导。
      //   - 新实现直接执行 `node --version` 等（PATH 为 rootfs 内标准
      //     PATH），未安装 → command not found；broken → exit=127，
      //     与卡片口径一致。
      for (final tool in ['node', 'git', 'python3', 'codex']) {
        try {
          final req = RuntimeProcessRequest(
            executable: tool,
            arguments: ['--version'],
            runtimeId: 'linux',
          );
          final result = await _runner.run(req);
          final stderr = result.stderr.toString().trim();
          results.add(VerificationResult(
            tool: tool,
            success: result.exitCode == 0,
            output:
                result.exitCode == 0 ? result.stdout.toString().trim() : null,
            error: result.exitCode != 0
                ? (stderr.isNotEmpty
                    ? stderr
                    : '命令不可用 (exit=${result.exitCode})')
                : null,
          ));
        } catch (e) {
          results.add(VerificationResult(
            tool: tool,
            success: false,
            error: e.toString(),
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
