/// Runtime Capability 模型
library;

enum CapabilityType {
  systemShell, curl, storageAccess, networkAccess,
  termux,
  node, npm, git, python,
  codexCli, mimo2codex, deepseekKey,
  flutter, rust,
  ubuntu,
}

enum ProviderType { android, app, termux, ubuntu }

enum CapabilityHealth { healthy, degraded, unavailable, unknown }

class RuntimeCapability {
  final CapabilityType type;
  final ProviderType provider;
  final bool available;
  final String? version;
  final String? path;
  final CapabilityHealth health;
  final String? reason;

  const RuntimeCapability({
    required this.type,
    required this.provider,
    required this.available,
    this.version,
    this.path,
    this.health = CapabilityHealth.unknown,
    this.reason,
  });

  String get displayName {
    switch (type) {
      case CapabilityType.systemShell: return '系统 Shell';
      case CapabilityType.curl: return 'cURL';
      case CapabilityType.storageAccess: return '存储权限';
      case CapabilityType.networkAccess: return '网络连通性';
      case CapabilityType.termux: return 'Termux Runtime';
      case CapabilityType.node: return 'Node.js';
      case CapabilityType.npm: return 'npm';
      case CapabilityType.git: return 'Git';
      case CapabilityType.python: return 'Python 3';
      case CapabilityType.codexCli: return 'Codex CLI';
      case CapabilityType.mimo2codex: return 'mimo2codex';
      case CapabilityType.deepseekKey: return 'DeepSeek API Key';
      case CapabilityType.flutter: return 'Flutter SDK';
      case CapabilityType.rust: return 'Rust 工具链';
      case CapabilityType.ubuntu: return 'Ubuntu Runtime';
    }
  }

  String get icon {
    switch (type) {
      case CapabilityType.systemShell: return '📱';
      case CapabilityType.curl: return '🌐';
      case CapabilityType.storageAccess: return '💾';
      case CapabilityType.networkAccess: return '📡';
      case CapabilityType.termux: return '📦';
      case CapabilityType.node: return '🟢';
      case CapabilityType.npm: return '📦';
      case CapabilityType.git: return '🔀';
      case CapabilityType.python: return '🐍';
      case CapabilityType.codexCli: return '🤖';
      case CapabilityType.mimo2codex: return '🔌';
      case CapabilityType.deepseekKey: return '🔑';
      case CapabilityType.flutter: return '🦋';
      case CapabilityType.rust: return '🦀';
      case CapabilityType.ubuntu: return '🐧';
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
  String toString() => '[${available ? "✅" : "❌"}] $displayName'
      '${version != null ? " v$version" : ""}'
      '${path != null ? " @ $path" : ""}'
      ' (Provider: $provider)';
}
