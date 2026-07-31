/// ====================================================================
/// Provider Capability Enhancer
///
/// 将 CapabilityResolver 的运行时检测结果与 Provider 的静态声明
/// 合并，提供增强的能力状态。
///
/// 职责：
///   1. 接收 Provider 的静态 Capability 列表
///   2. 使用 CapabilityResolver 执行运行时验证
///   3. 合并结果（Resolver 结果优先）
///   4. 返回增强的 Capability 列表
///
/// 设计原则：
///   - 不修改 Provider 接口或实现
///   - 运行时检测结果覆盖静态声明
///   - 检测失败保留 Provider 的原始状态
/// ====================================================================
library;

import '../../runtime/process/process_runner.dart';
import '../provider/runtime_capability.dart';
import '../provider/runtime_provider.dart';
import 'capability_resolver.dart';

/// 可执行 Capability 类型列表
///
/// 这些能力可以通过 RuntimeProcessRunner 执行 --version 验证。
const executableCapabilityTypes = <CapabilityType>{
  CapabilityType.node,
  CapabilityType.npm,
  CapabilityType.python,
  CapabilityType.git,
  CapabilityType.codexCli,
  CapabilityType.mimo2codex,
  CapabilityType.flutter,
  CapabilityType.rust,
  CapabilityType.bash,
  CapabilityType.tar,
  CapabilityType.xz,
};

/// Provider Capability Enhancer
///
/// 使用方式：
///   final enhancer = ProviderCapabilityEnhancer(resolver, runner);
///   final enhancedCaps = await enhancer.enhanceCapabilities(provider, [CapabilityType.node, CapabilityType.git]);
class ProviderCapabilityEnhancer {
  final CapabilityResolver _resolver;

  ProviderCapabilityEnhancer({
    CapabilityResolver? resolver,
    RuntimeProcessRunner? runner,
  }) : _resolver = resolver ?? CapabilityResolver(runner: runner);

  /// 增强指定 Provider 的 Capability 列表
  ///
  /// 对 [capabilityTypes] 中的每个类型：
  ///   1. 如果是在可执行类型列表中 → 使用 Resolver 执行运行时检测
  ///   2. 如果不是可执行类型 → 使用 Provider 的静态声明
  ///
  /// 返回增强后的 Capability 列表。
  Future<List<RuntimeCapability>> enhanceProviderCapabilities(
    IRuntimeProvider provider, {
    List<CapabilityType>? capabilityTypes,
    bool forceRefresh = false,
  }) async {
    final providerCaps = provider.capabilities;

    // 如果未指定类型列表，使用 Provider 声明的所有类型
    final types = capabilityTypes ??
        providerCaps.map((c) => c.type).toList();

    final results = <RuntimeCapability>[];

    for (final type in types) {
      if (executableCapabilityTypes.contains(type)) {
        // 运行时验证的可执行能力
        try {
          final resolved = await _resolver.checkCapability(
            type,
            provider,
            forceRefresh: forceRefresh,
          );
          results.add(resolved);
        } catch (e) {
          // Resolver 失败时使用 Provider 静态声明
          final static = providerCaps.where((c) => c.type == type);
          results.addAll(static);
        }
      } else {
        // 非可执行能力（systemShell, storageAccess 等）
        // 使用 Provider 静态声明
        results.addAll(providerCaps.where((c) => c.type == type));
      }
    }

    return results;
  }

  /// 获取 Provider 的单项增强 Capability
  Future<RuntimeCapability?> enhanceCapability(
    IRuntimeProvider provider,
    CapabilityType type, {
    bool forceRefresh = false,
  }) async {
    final caps = await enhanceProviderCapabilities(
      provider,
      capabilityTypes: [type],
      forceRefresh: forceRefresh,
    );
    return caps.isNotEmpty ? caps.first : null;
  }
}
