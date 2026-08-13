/// ====================================================================
/// Capability Resolver
///
/// 使用 RuntimeProcessRunner 执行真实命令来检测 Capability 状态。
///
/// 职责：
///   1. 调用 Provider 获取可执行文件路径
///   2. 通过 RuntimeProcessRunner 执行 --version 等命令
///   3. 解析输出获取版本号
///   4. 返回增强的 RuntimeCapability（含 executable、checkedAt）
///   5. 缓存管理（TTL、refresh、invalidate）
///
/// 设计原则：
///   - 所有检测命令必须通过 RuntimeProcessRunner，禁止直接 Process.run
///   - 检测失败不能 crash，必须返回结构化状态
///   - 缓存支持手动刷新和失效
///   - Provider 特定执行路由（如 Linux → PRoot）通过 runtimeId 实现
/// ====================================================================
library;

import '../../core/logger/log_service.dart';
import '../../runtime/process/process_runner.dart';
import '../../runtime/process/runner_models.dart';
import '../provider/runtime_capability.dart';
import '../provider/runtime_provider.dart';

/// 检测规格：可执行文件名称 + 版本参数
class _CheckSpec {
  final String binary;
  final List<String> versionArgs;

  const _CheckSpec(this.binary, this.versionArgs);
}

/// Capability 检测结果（解析前的原始数据）
class _DetectResult {
  final bool success;
  final String? version;
  final String? executable;
  final String? error;

  const _DetectResult({
    required this.success,
    this.version,
    this.executable,
    this.error,
  });
}

/// 可执行文件解析结果
///
/// [byWhich] 表示路径是否由 which 真实命中：
///   - true  → 二进制已安装（PATH 中存在）→ 执行失败属于 broken
///   - false → which 未命中，仅作为执行名 fallback → 失败属于 missing
class _ResolvedExecutable {
  final String? path;
  final bool byWhich;

  const _ResolvedExecutable(this.path, this.byWhich);
}

/// ====================================================================
/// CapabilityResolver
/// ====================================================================
class CapabilityResolver {
  final RuntimeProcessRunner _runner;

  /// Capability -> 检测规格映射
  static final Map<CapabilityType, _CheckSpec> _checkSpecs = {
    CapabilityType.node: const _CheckSpec('node', ['--version']),
    CapabilityType.npm: const _CheckSpec('npm', ['--version']),
    CapabilityType.python: const _CheckSpec('python3', ['--version']),
    CapabilityType.uv: const _CheckSpec('uvx', ['--version']),
    CapabilityType.git: const _CheckSpec('git', ['--version']),
    CapabilityType.codexCli: const _CheckSpec('codex', ['--version']),
    CapabilityType.mimo2codex:
        const _CheckSpec('mimo2codex', ['--version']),
    CapabilityType.flutter: const _CheckSpec('flutter', ['--version']),
    CapabilityType.rust: const _CheckSpec('rustc', ['--version']),
    CapabilityType.bash: const _CheckSpec('bash', ['--version']),
    CapabilityType.tar: const _CheckSpec('tar', ['--version']),
    CapabilityType.xz: const _CheckSpec('xz', ['--version']),
  };

  /// 缓存容器
  ///
  /// key = '${providerType.name}:${type.name}'。
  /// 必须带 Provider 维度：同一工具在不同 Provider（app/android/linux）下
  /// 检测结果不同，若只按 type 缓存会互相污染（如 app 的失败结果
  /// 覆盖 linux 的真实结果，导致 rootfs 已装工具被误报为「可安装」）。
  final Map<String, CapabilityCacheEntry> _cache = {};

  /// 缓存 key：Provider 维度 + Capability 维度
  static String _cacheKey(CapabilityType type, ProviderType providerType) =>
      '${providerType.name}:${type.name}';

  /// 默认缓存 TTL
  final Duration _defaultTtl;

  CapabilityResolver({
    RuntimeProcessRunner? runner,
    Duration? defaultTtl,
  })  : _runner = runner ?? RuntimeProcessRunner(),
        _defaultTtl = defaultTtl ?? const Duration(seconds: 30);

  /// 获取 Provider 对应的 runtimeId
  static String? _runtimeIdForProvider(ProviderType type) {
    switch (type) {
      case ProviderType.linux:
        return 'linux';
      case ProviderType.android:
        return 'android';
      case ProviderType.app:
        return 'app';
    }
  }

  // ------------------------------------------------------------------
  // 核心检测方法
  // ------------------------------------------------------------------

  /// 检测指定 Capability
  ///
  /// [type] — 能力类型
  /// [provider] — 提供此能力的 Provider
  /// [forceRefresh] — 是否强制刷新（跳过缓存）
  Future<RuntimeCapability> checkCapability(
    CapabilityType type,
    IRuntimeProvider provider, {
    bool forceRefresh = false,
  }) async {
    // 1. 检查缓存（Provider 维度）
    if (!forceRefresh) {
      final cached = _getFromCache(type, provider.type);
      if (cached != null) return cached;
    }

    final now = DateTime.now();

    // 2. 获取 Provider 状态和环境
    final environment = await provider.getEnvironment();
    final providerInfo = await provider.detect();
    final runtimeId = _runtimeIdForProvider(provider.type);

    // 3. 执行检测
    final result = await _detect(type, providerInfo, environment,
        runtimeId: runtimeId);

    // 4. 构建 Capability
    RuntimeCapability capability;
    if (result.success && result.version != null) {
      capability = RuntimeCapability(
        type: type,
        provider: provider.type,
        available: true,
        status: CapabilityStatus.available,
        version: result.version,
        executable: result.executable,
        health: CapabilityHealth.healthy,
        checkedAt: now,
      );
    } else if (result.success && result.version == null) {
      capability = RuntimeCapability(
        type: type,
        provider: provider.type,
        available: true,
        status: CapabilityStatus.available,
        executable: result.executable,
        health: CapabilityHealth.degraded,
        reason: '可执行但无法获取版本',
        checkedAt: now,
      );
    } else if (result.executable != null) {
      // 可执行文件已解析成功但执行失败 → broken（已安装但异常）。
      // 不能判定为 missing（否则 UI 显示「可安装」且安装按钮禁用）。
      capability = RuntimeCapability(
        type: type,
        provider: provider.type,
        available: false,
        status: CapabilityStatus.degraded,
        health: CapabilityHealth.degraded,
        reason: result.error ?? '已安装但执行失败',
        executable: result.executable,
        checkedAt: now,
      );
    } else {
      capability = RuntimeCapability(
        type: type,
        provider: provider.type,
        available: false,
        status: CapabilityStatus.unavailable,
        health: CapabilityHealth.unavailable,
        reason: result.error ?? '未知错误',
        checkedAt: now,
      );
    }

    // 5. 写入缓存（Provider 维度）
    _cache[_cacheKey(type, provider.type)] = CapabilityCacheEntry(
      capability: capability,
      cachedAt: now,
    );

    LogService.debug(
      'CapabilityResolver',
      '${type.name}: ${capability.available ? "✅" : "❌"}'
      '${capability.version != null ? " v${capability.version}" : ""}'
      '${capability.reason != null ? " — ${capability.reason}" : ""}',
    );

    return capability;
  }

  /// 批量检测多个 Capability
  Future<List<RuntimeCapability>> checkCapabilities(
    List<CapabilityType> types,
    IRuntimeProvider provider, {
    bool forceRefresh = false,
  }) async {
    final results = <RuntimeCapability>[];
    for (final type in types) {
      final cap = await checkCapability(type, provider,
          forceRefresh: forceRefresh);
      results.add(cap);
    }
    return results;
  }

  // ------------------------------------------------------------------
  // 缓存管理
  // ------------------------------------------------------------------

  RuntimeCapability? _getFromCache(
    CapabilityType type,
    ProviderType providerType,
  ) {
    final key = _cacheKey(type, providerType);
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired(_defaultTtl)) {
      _cache.remove(key);
      return null;
    }
    return entry.capability;
  }

  /// 强制刷新（重新检测并更新缓存）
  Future<RuntimeCapability> refresh(
    CapabilityType type,
    IRuntimeProvider provider,
  ) async {
    return checkCapability(type, provider, forceRefresh: true);
  }

  /// 失效指定 Capability 缓存（所有 Provider 维度）
  void invalidate(CapabilityType type) {
    _cache.removeWhere((key, _) => key.endsWith(':${type.name}'));
  }

  /// 失效所有缓存
  void invalidateAll() {
    _cache.clear();
  }

  /// 获取缓存条目（用于调试/诊断）
  ///
  /// 缓存含 Provider 维度，此方法返回第一个匹配 [type] 的条目。
  CapabilityCacheEntry? getCacheEntry(CapabilityType type) {
    for (final entry in _cache.values) {
      if (entry.capability.type == type) return entry;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // 私有方法
  // ------------------------------------------------------------------

  Future<_DetectResult> _detect(
    CapabilityType type,
    ProviderInfo providerInfo,
    Map<String, String> environment, {
    String? runtimeId,
  }) async {
    final spec = _checkSpecs[type];
    if (spec == null) {
      return _detectWithoutSpec(type, providerInfo, environment);
    }

    // 解析可执行文件路径
    String? executablePath;
    var installedByWhich = false;
    try {
      final resolved =
          await _resolveExecutable(spec.binary, environment,
              runtimeId: runtimeId);
      executablePath = resolved.path;
      installedByWhich = resolved.byWhich;
    } catch (_) {}

    if (executablePath == null) {
      return const _DetectResult(
        success: false,
        error: '未找到可执行文件',
      );
    }

    // 执行版本检查命令（使用 Provider 对应的 runtimeId）
    final request = RuntimeProcessRequest(
      executable: executablePath,
      arguments: spec.versionArgs,
      environment: environment,
      timeout: const Duration(seconds: 10),
      runtimeId: runtimeId,
      label: 'capability-check-${type.name}',
    );

    final runnerResult = await _runner.run(request);

    // 可执行文件已解析成功（which 命中），但执行失败：
    // 属于「已安装但异常」（broken），必须携带 executable 供上层区分，
    // 避免被误判为「未安装 → 可安装」。
    if (runnerResult.timedOut) {
      return _DetectResult(
        success: false,
        error: '检测超时 (10s)',
        executable: installedByWhich ? executablePath : null,
      );
    }

    if (runnerResult.cancelled) {
      return _DetectResult(
        success: false,
        error: '检测被取消',
        executable: installedByWhich ? executablePath : null,
      );
    }

    if (runnerResult.failedToStart) {
      return _DetectResult(
        success: false,
        error: runnerResult.error ?? '启动失败',
        executable: installedByWhich ? executablePath : null,
      );
    }

    if (!runnerResult.isSuccess) {
      return _DetectResult(
        success: false,
        error: '命令返回非零退出码 (exit=${runnerResult.exitCode})',
        executable: installedByWhich ? executablePath : null,
      );
    }

    // 解析版本
    final version = _parseVersion(runnerResult.stdout);

    return _DetectResult(
      success: true,
      version: version,
      executable: executablePath,
    );
  }

  /// 解析可执行文件路径
  ///
  /// 返回 [_ResolvedExecutable]：
  ///   - which 命中 → path=真实路径, byWhich=true
  ///   - which 未命中 → path=binary 名称（执行名 fallback）, byWhich=false
  Future<_ResolvedExecutable> _resolveExecutable(
    String binary,
    Map<String, String> environment, {
    String? runtimeId,
  }) async {
    // 先尝试在 Provider 环境中用 which
    final whichResult = await _runner.run(
      RuntimeProcessRequest(
        executable: 'which',
        arguments: [binary],
        environment: environment,
        timeout: const Duration(seconds: 5),
        runtimeId: runtimeId,
        label: 'resolve-$binary',
      ),
    );

    if (whichResult.isSuccess) {
      final path = whichResult.stdout.trim();
      if (path.isNotEmpty && !path.contains('not found')) {
        return _ResolvedExecutable(path, true);
      }
    }

    // fallback: 直接使用 binary 名称（保持原执行行为）
    return _ResolvedExecutable(binary, false);
  }

  /// 从命令行输出中解析版本号
  String? _parseVersion(String stdout) {
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) return null;

    // 取第一行
    final firstLine = trimmed.split('\n').first.trim();

    // 尝试提取语义版本号
    final versionMatch =
        RegExp(r'(\d+\.\d+\.\d+)').firstMatch(firstLine);
    if (versionMatch != null) {
      return versionMatch.group(1);
    }

    // 尝试提取 vx.y.z
    final vVersionMatch =
        RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(firstLine);
    if (vVersionMatch != null) {
      return 'v${vVersionMatch.group(1)}';
    }

    // fallback: 返回第一行（截断过长内容）
    return firstLine.length > 50
        ? '${firstLine.substring(0, 50)}...'
        : firstLine;
  }

  /// 处理没有检测规格的 Capability
  _DetectResult _detectWithoutSpec(
    CapabilityType type,
    ProviderInfo providerInfo,
    Map<String, String> environment,
  ) {
    for (final cap in providerInfo.capabilities) {
      if (cap.type == type) {
        return _DetectResult(
          success: cap.available,
          version: cap.version,
          executable: cap.executable ?? cap.path,
          error: cap.available ? null : (cap.reason ?? '不可用'),
        );
      }
    }
    return const _DetectResult(
      success: false,
      error: 'Provider 未声明此能力',
    );
  }
}
