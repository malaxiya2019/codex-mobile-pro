/// ====================================================================
/// Runtime Capability 模型
///
/// 定义设备上可用的所有 Runtime 能力。
///
/// 设计原则：
///   1. Capability ≠ Detector — Capability 是能力结果，Detector 是检测方式
///   2. Capability ≠ Provider — Provider 提供能力，Capability 是能力描述
///   3. Capability ≠ Installer — Installer 安装能力，Capability 是安装后的状态
///
/// 状态说明：
///   - status:     available / unavailable / unknown / degraded
///   - available:  是否可用（status == available 的快捷判断）
///   - installed:  二进制文件是否存在（path != null）
///   - healthy:    健康可用（status == available && health == healthy）
/// ====================================================================
library;

/// Capability 类型
///
/// 按当前项目实际使用场景定义。
/// 不添加没有真实使用场景的类型。
enum CapabilityType {
  /// Android 系统能力
  systemShell,
  curl,
  storageAccess,
  networkAccess,

  /// Termux 运行环境
  termux,

  /// 开发工具
  node,
  npm,
  git,
  python,
  codexCli,
  mimo2codex,
  deepseekKey,
  flutter,
  rust,

  /// Ubuntu 实验性运行环境
  ubuntu,
}

/// Provider 类型
enum ProviderType { android, app, termux, ubuntu }

/// Capability 健康状态
///
/// 与 status 的区别：
///   status 表示能力「是否可用」，
///   health 表示可用状态下「质量如何」。
enum CapabilityHealth { healthy, degraded, unavailable, unknown }

/// Capability 状态
///
/// 至少区分四种状态，不使用简单的 true/false。
enum CapabilityStatus {
  /// 可用且正常
  available,

  /// 不可用
  unavailable,

  /// 未知（尚未检测）
  unknown,

  /// 降级可用（部分功能受限）
  degraded,
}

/// Runtime 能力
///
/// 表示一个 Provider 提供的某项能力的状态。
/// 不可变对象，每次检测后创建新实例。
class RuntimeCapability {
  /// 能力类型
  final CapabilityType type;

  /// 提供此能力的 Provider
  final ProviderType provider;

  /// 快捷判断：是否可用
  ///
  /// 等价于 status == CapabilityStatus.available
  final bool available;

  /// 能力状态（比 available 更丰富）
  ///
  /// 支持：available, unavailable, unknown, degraded
  final CapabilityStatus status;

  /// 版本号
  final String? version;

  /// 安装路径
  ///
  /// 兼容旧字段。新代码优先使用 executable。
  final String? path;

  /// 可执行文件路径（已解析的绝对路径）
  ///
  /// 例如：/data/data/com.termux/files/usr/bin/node
  /// 与 path 的区别：executable 特指可执行二进制文件，
  /// path 可能指向目录或其他资源。
  final String? executable;

  /// 健康状态
  final CapabilityHealth health;

  /// 状态说明/失败原因
  ///
  /// 例如：'可执行文件不存在'、'权限不足'、'版本不兼容'
  final String? reason;

  /// 最后检测时间
  final DateTime? checkedAt;

  const RuntimeCapability({
    required this.type,
    required this.provider,
    required this.available,
    this.status = CapabilityStatus.unknown,
    this.version,
    this.path,
    this.executable,
    this.health = CapabilityHealth.unknown,
    this.reason,
    this.checkedAt,
  });

  /// ─── 派生属性 ─────────────────────────────────────────────────

  /// 是否已安装（二进制文件存在）
  ///
  /// 注意：installed ≠ available。
  /// 文件存在但权限不足或运行失败时不可用。
  bool get installed => executable != null || path != null;

  /// 是否健康可用
  ///
  /// 同时满足：
  ///   1. status == available
  ///   2. health == healthy
  bool get healthy =>
      status == CapabilityStatus.available &&
      health == CapabilityHealth.healthy;

  /// ─── 显示方法 ─────────────────────────────────────────────────

  String get displayName {
    switch (type) {
      case CapabilityType.systemShell:
        return '系统 Shell';
      case CapabilityType.curl:
        return 'cURL';
      case CapabilityType.storageAccess:
        return '存储权限';
      case CapabilityType.networkAccess:
        return '网络连通性';
      case CapabilityType.termux:
        return 'Termux Runtime';
      case CapabilityType.node:
        return 'Node.js';
      case CapabilityType.npm:
        return 'npm';
      case CapabilityType.git:
        return 'Git';
      case CapabilityType.python:
        return 'Python 3';
      case CapabilityType.codexCli:
        return 'Codex CLI';
      case CapabilityType.mimo2codex:
        return 'mimo2codex';
      case CapabilityType.deepseekKey:
        return 'DeepSeek API Key';
      case CapabilityType.flutter:
        return 'Flutter SDK';
      case CapabilityType.rust:
        return 'Rust 工具链';
      case CapabilityType.ubuntu:
        return 'Ubuntu Runtime';
    }
  }

  String get icon {
    switch (type) {
      case CapabilityType.systemShell:
        return '📱';
      case CapabilityType.curl:
        return '🌐';
      case CapabilityType.storageAccess:
        return '💾';
      case CapabilityType.networkAccess:
        return '📡';
      case CapabilityType.termux:
        return '📦';
      case CapabilityType.node:
        return '🟢';
      case CapabilityType.npm:
        return '📦';
      case CapabilityType.git:
        return '🔀';
      case CapabilityType.python:
        return '🐍';
      case CapabilityType.codexCli:
        return '🤖';
      case CapabilityType.mimo2codex:
        return '🔌';
      case CapabilityType.deepseekKey:
        return '🔑';
      case CapabilityType.flutter:
        return '🦋';
      case CapabilityType.rust:
        return '🦀';
      case CapabilityType.ubuntu:
        return '🐧';
    }
  }

  String get statusDescription {
    if (available) {
      final v = version != null ? ' v$version' : '';
      return '✅ 可用$v';
    }
    return '❌ 不可用${reason != null ? ' — $reason' : ''}';
  }

  @override
  String toString() =>
      '[${available ? "✅" : "❌"}] $displayName'
      '${version != null ? " v$version" : ""}'
      '${executable != null || path != null ? " @ ${executable ?? path}" : ""}'
      ' (Provider: $provider, status: $status, health: $health)';
}

/// ====================================================================
/// Capability 缓存条目
///
/// 用于 CapabilityResolver 的缓存管理。
/// ====================================================================
class CapabilityCacheEntry {
  final RuntimeCapability capability;
  final DateTime cachedAt;

  const CapabilityCacheEntry({
    required this.capability,
    required this.cachedAt,
  });

  /// 是否已过期
  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}
