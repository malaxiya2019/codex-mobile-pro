import 'dart:async';
import 'dart:math';

import 'ai_provider.dart';

// ──────────────────────────────────────────────
// 模型定义
// ──────────────────────────────────────────────

/// Token 用量记录
class TokenUsage {
  final String providerName;
  final String model;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final DateTime timestamp;

  TokenUsage({
    required this.providerName,
    required this.model,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  TokenUsage copyWith({
    String? providerName,
    String? model,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
    DateTime? timestamp,
  }) {
    return TokenUsage(
      providerName: providerName ?? this.providerName,
      model: model ?? this.model,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  static TokenUsage fromChatUsage(dynamic usage, {required String providerName, required String model}) {
    if (usage == null) {
      return TokenUsage(providerName: providerName, model: model);
    }
    return TokenUsage(
      providerName: providerName,
      model: model,
      promptTokens: _safeInt(usage, 'promptTokens', 'prompt_tokens'),
      completionTokens: _safeInt(usage, 'completionTokens', 'completion_tokens'),
      totalTokens: _safeInt(usage, 'totalTokens', 'total_tokens'),
    );
  }

  static int _safeInt(dynamic obj, String field1, String field2) {
    if (obj is Map) {
      final v = obj[field1] ?? obj[field2];
      if (v is int) return v;
      if (v is num) return v.toInt();
    }
    return 0;
  }
}

/// Token 用量聚合（累计）
class AggregatedTokenUsage {
  final int totalPromptTokens;
  final int totalCompletionTokens;
  final int totalTokens;
  final Map<String, int> byProvider;

  const AggregatedTokenUsage({
    this.totalPromptTokens = 0,
    this.totalCompletionTokens = 0,
    this.totalTokens = 0,
    this.byProvider = const {},
  });

  AggregatedTokenUsage merge(TokenUsage usage) {
    final newByProvider = Map<String, int>.from(byProvider);
    newByProvider[usage.providerName] =
        (newByProvider[usage.providerName] ?? 0) + usage.totalTokens;

    return AggregatedTokenUsage(
      totalPromptTokens: totalPromptTokens + usage.promptTokens,
      totalCompletionTokens: totalCompletionTokens + usage.completionTokens,
      totalTokens: totalTokens + usage.totalTokens,
      byProvider: newByProvider,
    );
  }
}

/// Provider 优先级
enum ProviderPriority {
  primary(0),
  fallback(1),
  secondary(2),
  tertiary(3);

  final int level;
  const ProviderPriority(this.level);
}

/// Provider 注册信息
class ProviderRegistration {
  final AiProvider provider;
  final ProviderPriority priority;
  final Set<int> excludedErrorCodes;
  int consecutiveFailures;
  DateTime? lastFailureAt;
  bool enabled;

  ProviderRegistration({
    required this.provider,
    this.priority = ProviderPriority.fallback,
    this.excludedErrorCodes = const {},
    this.consecutiveFailures = 0,
    this.lastFailureAt,
    this.enabled = true,
  });
}

/// Provider 错误类型
enum ProviderErrorType {
  network,
  timeout,
  rateLimit,
  auth,
  server,
  cancelled,
  unknown,
}

/// Provider 错误
class ProviderError {
  final ProviderErrorType type;
  final String message;
  final String? providerName;

  const ProviderError({
    required this.type,
    required this.message,
    this.providerName,
  });

  @override
  String toString() => '[${providerName ?? '?'}] $type: $message';
}

/// 速率限制信息
class RateLimitInfo {
  final int requestsPerMinute;
  final int tokensPerMinute;
  final int remainingRequests;
  final int remainingTokens;
  final DateTime? resetAt;

  const RateLimitInfo({
    this.requestsPerMinute = 60,
    this.tokensPerMinute = 100000,
    this.remainingRequests = 60,
    this.remainingTokens = 100000,
    this.resetAt,
  });
}

// ──────────────────────────────────────────────
// AIProviderManager 配置
// ──────────────────────────────────────────────

class AIProviderManagerConfig {
  final Duration defaultTimeout;
  final int maxRetries;
  final Duration retryDelay;
  final bool enableFailover;
  final bool trackTokenUsage;
  final int maxTokenUsageHistory;
  final Duration healthCheckInterval;

  const AIProviderManagerConfig({
    this.defaultTimeout = const Duration(seconds: 30),
    this.maxRetries = 2,
    this.retryDelay = const Duration(seconds: 1),
    this.enableFailover = true,
    this.trackTokenUsage = true,
    this.maxTokenUsageHistory = 1000,
    this.healthCheckInterval = const Duration(seconds: 60),
  });
}

// ──────────────────────────────────────────────
// IAIProviderManager 接口
// ──────────────────────────────────────────────

/// AI Provider 统一管理器接口
///
/// UI 层通过此接口访问所有 AI 能力。
abstract class IAIProviderManager {
  AiProvider? get activeProvider;
  String? get activeProviderName;
  List<ProviderRegistration> get registrations;

  void register(AiProvider provider, {ProviderPriority priority = ProviderPriority.fallback});
  void unregister(String providerName);
  Future<bool> setActiveProvider(String providerName);

  AggregatedTokenUsage get tokenUsage;
  RateLimitInfo get rateLimitInfo;

  Future<String> chat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
    Duration? timeout,
  });

  Stream<String> streamChat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
    Duration? timeout,
  });

  Future<Map<String, bool>> healthCheckAll();
  void dispose();
}

// ──────────────────────────────────────────────
// AIProviderManager 实现
// ──────────────────────────────────────────────

class AIProviderManager implements IAIProviderManager {
  final AIProviderManagerConfig config;
  final List<ProviderRegistration> _registrations = [];
  final List<TokenUsage> _tokenUsageHistory = [];
  AggregatedTokenUsage _aggregatedUsage = const AggregatedTokenUsage();
  RateLimitInfo _rateLimitInfo = const RateLimitInfo();
  String? _activeProviderName;
  Timer? _healthCheckTimer;

  AIProviderManager({AIProviderManagerConfig? config})
      : config = config ?? const AIProviderManagerConfig();

  // ── 属性 ──

  @override
  AiProvider? get activeProvider {
    if (_activeProviderName == null) return null;
    final reg = _findRegistration(_activeProviderName!);
    if (reg == null || !reg.enabled) return null;
    return reg.provider;
  }

  @override
  String? get activeProviderName => _activeProviderName;

  @override
  List<ProviderRegistration> get registrations => List.unmodifiable(_registrations);

  @override
  AggregatedTokenUsage get tokenUsage => _aggregatedUsage;

  @override
  RateLimitInfo get rateLimitInfo => _rateLimitInfo;

  // ── 注册管理 ──

  @override
  void register(AiProvider provider, {ProviderPriority priority = ProviderPriority.fallback}) {
    _registrations.removeWhere((r) => r.provider.name == provider.name);
    _registrations.add(ProviderRegistration(
      provider: provider,
      priority: priority,
    ));
    _registrations.sort((a, b) => a.priority.level.compareTo(b.priority.level));

    if (_activeProviderName == null && provider.status == AiProviderStatus.ready) {
      _activeProviderName = provider.name;
    }

    _startHealthCheck();
  }

  @override
  void unregister(String providerName) {
    _registrations.removeWhere((r) => r.provider.name == providerName);
    if (_activeProviderName == providerName) {
      _activeProviderName = _findNextReadyProvider()?.provider.name;
    }
  }

  @override
  Future<bool> setActiveProvider(String providerName) async {
    final reg = _findRegistration(providerName);
    if (reg == null || !reg.enabled) return false;

    if (reg.provider.status == AiProviderStatus.ready) {
      _activeProviderName = providerName;
      return true;
    }

    try {
      await reg.provider.initialize();
      if (reg.provider.status == AiProviderStatus.ready) {
        _activeProviderName = providerName;
        reg.consecutiveFailures = 0;
        return true;
      }
    } catch (_) {}

    return false;
  }

  // ── 聊天 ──

  @override
  Future<String> chat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    if (cancelToken?.isCancelled == true) return '';

    final effectiveTimeout = timeout ?? config.defaultTimeout;
    int attempt = 0;

    while (attempt <= config.maxRetries) {
      attempt++;

      final reg = _selectProvider();
      if (reg == null) return '';

      final provider = reg.provider;
      final callCancelToken = CancelToken();

      try {
        final result = await provider
            .chat(
              messages: messages,
              temperature: temperature,
              maxTokens: maxTokens,
              cancelToken: callCancelToken,
            )
            .timeout(effectiveTimeout);

        reg.consecutiveFailures = 0;
        if (config.trackTokenUsage) {
          _trackUsage(provider.name, TokenUsage(
            providerName: provider.name,
            model: provider.name,
          ));
        }
        return result;
      } catch (e) {
        callCancelToken.cancel();
        reg.consecutiveFailures++;
        reg.lastFailureAt = DateTime.now();

        if (cancelToken?.isCancelled == true) return '';

        if (config.enableFailover && _shouldFailover(reg, e)) {
          _tryFailover(reg);
        }

        if (attempt <= config.maxRetries) {
          final delayMs = config.retryDelay.inMilliseconds * (1 << (attempt - 1));
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          if (cancelToken?.isCancelled == true) return '';
          continue;
        }

        if (_classifyError(e) == ProviderErrorType.rateLimit) {
          _handleRateLimit();
        }
      }
    }

    return '';
  }

  @override
  Stream<String> streamChat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async* {
    final effectiveTimeout = timeout ?? config.defaultTimeout;
    int attempt = 0;

    while (attempt <= config.maxRetries) {
      attempt++;
      final reg = _selectProvider();
      if (reg == null) return;

      final provider = reg.provider;
      final streamCancelToken = CancelToken();

      try {
        final stream = provider.streamChat(
          messages: messages,
          temperature: temperature,
          maxTokens: maxTokens,
          cancelToken: streamCancelToken,
        );

        await for (final chunk in stream.timeout(effectiveTimeout)) {
          if (cancelToken?.isCancelled == true) {
            streamCancelToken.cancel();
            return;
          }
          yield chunk;
        }

        reg.consecutiveFailures = 0;
        return;
      } catch (e) {
        streamCancelToken.cancel();
        reg.consecutiveFailures++;
        reg.lastFailureAt = DateTime.now();

        if (cancelToken?.isCancelled == true) return;

        if (config.enableFailover && _shouldFailover(reg, e)) {
          _tryFailover(reg);
        }

        if (attempt <= config.maxRetries) {
          final delayMs = config.retryDelay.inMilliseconds * (1 << (attempt - 1));
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          if (cancelToken?.isCancelled == true) return;
          continue;
        }
      }
    }
  }

  // ── 健康检查 ──

  @override
  Future<Map<String, bool>> healthCheckAll() async {
    final result = <String, bool>{};
    for (final reg in _registrations) {
      try {
        result[reg.provider.name] = await reg.provider.healthCheck();
      } catch (_) {
        result[reg.provider.name] = false;
      }
    }
    return result;
  }

  // ── 资源释放 ──

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    for (final reg in _registrations) {
      reg.provider.dispose();
    }
    _registrations.clear();
    _tokenUsageHistory.clear();
  }

  // ── 内部方法 ──

  ProviderRegistration? _findRegistration(String name) {
    for (final reg in _registrations) {
      if (reg.provider.name == name) return reg;
    }
    return null;
  }

  ProviderRegistration? _findNextReadyProvider() {
    for (final reg in _registrations) {
      if (reg.enabled && reg.provider.status == AiProviderStatus.ready) {
        return reg;
      }
    }
    return null;
  }

  ProviderRegistration? _selectProvider() {
    if (_activeProviderName != null) {
      final active = _findRegistration(_activeProviderName!);
      if (active != null && active.enabled) return active;
    }
    return _findNextReadyProvider();
  }

  bool _shouldFailover(ProviderRegistration reg, Object error) {
    if (reg.consecutiveFailures >= 3) return true;
    final errorType = _classifyError(error);
    return errorType == ProviderErrorType.network ||
        errorType == ProviderErrorType.timeout ||
        errorType == ProviderErrorType.server;
  }

  void _tryFailover(ProviderRegistration failedReg) {
    failedReg.enabled = false;

    for (final reg in _registrations) {
      if (reg.provider.name != failedReg.provider.name &&
          reg.enabled &&
          reg.priority.level <= failedReg.priority.level &&
          reg.provider.status == AiProviderStatus.ready) {
        _activeProviderName = reg.provider.name;
        return;
      }
    }

    for (final reg in _registrations) {
      if (reg.enabled && reg.provider.status == AiProviderStatus.ready) {
        _activeProviderName = reg.provider.name;
        return;
      }
    }

    failedReg.enabled = true;
  }

  ProviderErrorType _classifyError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('timeout')) return ProviderErrorType.timeout;
    if (msg.contains('network') || msg.contains('connection') || msg.contains('dns')) {
      return ProviderErrorType.network;
    }
    if (msg.contains('rate') || msg.contains('429') || msg.contains('too many')) {
      return ProviderErrorType.rateLimit;
    }
    if (msg.contains('auth') || msg.contains('401') || msg.contains('403') || msg.contains('key')) {
      return ProviderErrorType.auth;
    }
    if (msg.contains('500') || msg.contains('502') || msg.contains('503')) {
      return ProviderErrorType.server;
    }
    if (msg.contains('cancel')) return ProviderErrorType.cancelled;
    return ProviderErrorType.unknown;
  }

  void _handleRateLimit() {
    _rateLimitInfo = RateLimitInfo(
      requestsPerMinute: _rateLimitInfo.requestsPerMinute,
      tokensPerMinute: _rateLimitInfo.tokensPerMinute,
      remainingRequests: max(0, _rateLimitInfo.remainingRequests - 1),
      remainingTokens: _rateLimitInfo.remainingTokens,
      resetAt: DateTime.now().add(const Duration(seconds: 30)),
    );
  }

  void _trackUsage(String providerName, TokenUsage usage) {
    final tracked = usage.copyWith(providerName: providerName);
    _tokenUsageHistory.add(tracked);
    _aggregatedUsage = _aggregatedUsage.merge(tracked);

    if (_tokenUsageHistory.length > config.maxTokenUsageHistory) {
      _tokenUsageHistory.removeAt(0);
    }
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(config.healthCheckInterval, (_) async {
      for (final reg in _registrations) {
        try {
          final healthy = await reg.provider.healthCheck();
          if (healthy && !reg.enabled) {
            reg.enabled = true;
          }
        } catch (_) {}
      }
    });
  }
}
