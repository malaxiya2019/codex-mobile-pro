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
  systemShell,
  curl,
  storageAccess,
  networkAccess,
  node,
  npm,
  git,
  python,
  codexCli,
  mimo2codex,
  deepseekKey,
  flutter,
  rust,
  ubuntu,
  bash,
  tar,
  xz,
}

/// Provider 类型
enum ProviderType { android, app, linux }

/// Capability 健康状态
enum CapabilityHealth { healthy, degraded, unavailable, unknown }

/// Capability 状态
///
/// 至少区分四种状态，不使用简单的 true/false。
enum CapabilityStatus {
  available,
  unavailable,
  unknown,
  degraded,
}

/// Runtime 能力
///
/// 表示一个 Provider 提供的某项能力的状态。
/// 不可变对象，每次检测后创建新实例。
class RuntimeCapability {
  final CapabilityType type;
  final ProviderType provider;
  final bool available;
  final CapabilityStatus status;
  final String? version;
  final String? path;
  final String? executable;
  final CapabilityHealth health;
  final String? reason;
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

  /// 是否已安装（二进制文件存在）
  bool get installed => executable != null || path != null;

  /// 是否健康可用
  bool get healthy =>
      status == CapabilityStatus.available &&
      health == CapabilityHealth.healthy;

  String get displayName {
    switch (type) {
      case CapabilityType.systemShell: return '系统 Shell';
      case CapabilityType.curl: return 'cURL';
      case CapabilityType.storageAccess: return '存储权限';
      case CapabilityType.networkAccess: return '网络连通性';
      case CapabilityType.node: return 'Node.js';
      case CapabilityType.npm: return 'npm';
      case CapabilityType.git: return 'Git';
      case CapabilityType.python: return 'Python 3';
      case CapabilityType.codexCli: return 'Codex CLI';
      case CapabilityType.mimo2codex: return 'mimo2codex';
      case CapabilityType.deepseekKey: return 'DeepSeek API Key';
      case CapabilityType.flutter: return 'Flutter SDK';
      case CapabilityType.rust: return 'Rust 工具链';
      case CapabilityType.bash: return 'Bash';
      case CapabilityType.tar: return 'tar';
      case CapabilityType.xz: return 'xz';
      case CapabilityType.ubuntu: return 'Ubuntu Runtime';
    }
  }

  String get icon {
    switch (type) {
      case CapabilityType.systemShell: return '\u{1F4F1}';
      case CapabilityType.curl: return '\u{1F310}';
      case CapabilityType.storageAccess: return '\u{1F4BE}';
      case CapabilityType.networkAccess: return '\u{1F4E1}';
      case CapabilityType.node: return '\u{1F7E2}';
      case CapabilityType.npm: return '\u{1F4E6}';
      case CapabilityType.git: return '\u{1F500}';
      case CapabilityType.python: return '\u{1F40D}';
      case CapabilityType.codexCli: return '\u{1F916}';
      case CapabilityType.mimo2codex: return '\u{1F50C}';
      case CapabilityType.deepseekKey: return '\u{1F511}';
      case CapabilityType.flutter: return '\u{1F98B}';
      case CapabilityType.rust: return '\u{1F980}';
      case CapabilityType.bash: return '\u{0024}';
      case CapabilityType.tar: return '\u{1F4E6}';
      case CapabilityType.xz: return '\u{1F4A0}';
      case CapabilityType.ubuntu: return '\u{1F427}';
    }
  }

  String get statusDescription {
    if (available) {
      final v = version != null ? ' v$version' : '';
      return '\u2705 可用$v';
    }
    return '\u274C 不可用${reason != null ? ' \u2014 $reason' : ''}';
  }

  @override
  String toString() =>
      '[${available ? '\u2705' : '\u274C'}] $displayName'
      '${version != null ? ' v$version' : ''}'
      '${(executable ?? path) != null ? ' @ ${executable ?? path}' : ''}'
      ' (Provider: $provider, status: $status, health: $health)';
}

/// Capability 缓存条目
class CapabilityCacheEntry {
  final RuntimeCapability capability;
  final DateTime cachedAt;

  const CapabilityCacheEntry({
    required this.capability,
    required this.cachedAt,
  });

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}
