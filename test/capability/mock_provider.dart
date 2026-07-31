/// ====================================================================
/// Mock Runtime Provider — 用于测试
///
/// 返回预设的 Provider 信息，不执行真实检测。
/// ====================================================================

import '../../lib/runtime/provider/runtime_capability.dart';
import '../../lib/runtime/provider/runtime_provider.dart';

/// Mock Provider 配置
class MockProviderConfig {
  final String id;
  final String name;
  final ProviderType type;
  final ProviderStatus status;
  final List<RuntimeCapability> capabilities;
  final Map<String, String> environment;

  const MockProviderConfig({
    required this.id,
    required this.name,
    required this.type,
    this.status = ProviderStatus.available,
    this.capabilities = const [],
    this.environment = const {},
  });
}

/// Mock Runtime Provider
///
/// 使用方式：
///   final provider = MockProvider(MockProviderConfig(
///     id: 'android',
///     type: ProviderType.android,
///     capabilities: [RuntimeCapability(type: CapabilityType.node, ...)],
///   ));
class MockProvider implements IRuntimeProvider {
  final MockProviderConfig _config;

  MockProvider(this._config);

  @override
  String get id => _config.id;

  @override
  String get name => _config.name;

  @override
  ProviderType get type => _config.type;

  @override
  ProviderStatus get status => _config.status;

  @override
  List<RuntimeCapability> get capabilities => _config.capabilities;

  @override
  Future<ProviderInfo> detect() async {
    return ProviderInfo(
      type: _config.type,
      status: _config.status,
      capabilities: _config.capabilities,
      description: 'Mock ${_config.name}',
    );
  }

  @override
  Future<Map<String, String>> getEnvironment({String? appHome}) async {
    return _config.environment;
  }

  @override
  Future<bool> isAvailable() async {
    return _config.status == ProviderStatus.available;
  }

  @override
  Future<ProviderHealth> healthCheck() async {
    return ProviderHealth(
      healthy: _config.status == ProviderStatus.available,
    );
  }
}
