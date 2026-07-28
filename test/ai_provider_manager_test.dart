import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/ai/ai_provider.dart';
import 'package:codex_mobile_pro/core/ai/ai_provider_manager.dart';

/// 模拟 AI Provider（用于测试管理器）
class MockAiProvider extends AiProvider {
  final String _name;
  final AiProviderStatus _initialStatus;
  bool _shouldFailOnChat = false;
  int chatCallCount = 0;
  int streamCallCount = 0;
  bool _healthCheckResult = true;

  MockAiProvider({
    String name = 'MockAI',
    AiProviderStatus status = AiProviderStatus.ready,
  }) : _name = name,
       _initialStatus = status;

  void setShouldFail(bool fail) => _shouldFailOnChat = fail;
  void setHealthCheckResult(bool ok) => _healthCheckResult = ok;

  @override
  String get name => _name;

  @override
  AiProviderStatus get status => _initialStatus;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<InlineCompletion>> getInlineCompletions({
    required InlineCompletionRequest request,
    CompletionTriggerKind triggerKind = CompletionTriggerKind.automatic,
    CancelToken? cancelToken,
  }) async => [];

  @override
  Stream<String> streamChat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
  }) async* {
    streamCallCount++;
    if (_shouldFailOnChat) throw Exception('Stream failed');
    yield 'hello ';
    yield 'world';
  }

  @override
  Future<String> chat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
  }) async {
    chatCallCount++;
    if (_shouldFailOnChat) throw Exception('Chat failed');
    return 'hello world';
  }

  @override
  Future<bool> healthCheck() async => _healthCheckResult;

  @override
  void dispose() {}
}

void main() {
  group('TokenUsage', () {
    test('创建 Token 用量记录', () {
      final usage = TokenUsage(
        providerName: 'DeepSeek',
        model: 'deepseek-chat',
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
      );

      expect(usage.providerName, 'DeepSeek');
      expect(usage.promptTokens, 100);
      expect(usage.completionTokens, 50);
      expect(usage.totalTokens, 150);
      expect(usage.timestamp, isNotNull);
    });

    test('copyWith 正确复制', () {
      final usage = TokenUsage(
        providerName: 'A',
        model: 'm1',
        totalTokens: 100,
      );

      final copied = usage.copyWith(totalTokens: 200);
      expect(copied.providerName, 'A');
      expect(copied.totalTokens, 200);
      expect(copied.promptTokens, 0);
    });
  });

  group('AggregatedTokenUsage', () {
    test('空聚合结果正确', () {
      const agg = AggregatedTokenUsage();
      expect(agg.totalTokens, 0);
      expect(agg.byProvider, isEmpty);
    });

    test('合并多个 Token 用量', () {
      const agg = AggregatedTokenUsage();

      final r1 = agg.merge(TokenUsage(
        providerName: 'ProviderA',
        model: 'm1',
        promptTokens: 50,
        completionTokens: 30,
        totalTokens: 80,
      ));

      expect(r1.totalTokens, 80);
      expect(r1.byProvider['ProviderA'], 80);

      final r2 = r1.merge(TokenUsage(
        providerName: 'ProviderB',
        model: 'm2',
        totalTokens: 120,
      ));

      expect(r2.totalTokens, 200);
      expect(r2.byProvider['ProviderA'], 80);
      expect(r2.byProvider['ProviderB'], 120);
    });
  });

  group('AIProviderManager', () {
    test('注册 Provider', () {
      final manager = AIProviderManager();
      final provider = MockAiProvider(name: 'TestAI');

      manager.register(provider);
      expect(manager.registrations.length, 1);
      expect(manager.activeProviderName, 'TestAI');
    });

    test('注册多个 Provider 按优先级排序', () {
      final manager = AIProviderManager();
      final primary = MockAiProvider(name: 'Primary');
      final fallback = MockAiProvider(name: 'Fallback');

      manager.register(fallback, priority: ProviderPriority.fallback);
      manager.register(primary, priority: ProviderPriority.primary);

      expect(manager.registrations.length, 2);
      expect(manager.registrations[0].provider.name, 'Primary');
      expect(manager.registrations[1].provider.name, 'Fallback');
    });

    test('注销 Provider', () {
      final manager = AIProviderManager();
      final provider = MockAiProvider(name: 'TestAI');

      manager.register(provider);
      expect(manager.activeProviderName, 'TestAI');

      manager.unregister('TestAI');
      expect(manager.registrations, isEmpty);
      expect(manager.activeProviderName, isNull);
    });

    test('设置活动 Provider', () async {
      final manager = AIProviderManager();
      final p1 = MockAiProvider(name: 'P1');
      final p2 = MockAiProvider(name: 'P2');

      manager.register(p1);
      manager.register(p2);

      final switched = await manager.setActiveProvider('P2');
      expect(switched, true);
      expect(manager.activeProviderName, 'P2');
    });

    test('设置不存在的 Provider 返回 false', () async {
      final manager = AIProviderManager();
      final result = await manager.setActiveProvider('NonExistent');
      expect(result, false);
    });

    test('chat 调用活动 Provider', () async {
      final manager = AIProviderManager();
      final provider = MockAiProvider(name: 'ChatAI');

      manager.register(provider);

      final result = await manager.chat(
        messages: [const ChatMessageInput(role: 'user', content: 'hello')],
      );

      expect(result, 'hello world');
      expect(provider.chatCallCount, 1);
    });

    test('streamChat 调用活动 Provider', () async {
      final manager = AIProviderManager();
      final provider = MockAiProvider(name: 'StreamAI');

      manager.register(provider);

      final chunks = <String>[];
      await for (final chunk in manager.streamChat(
        messages: [const ChatMessageInput(role: 'user', content: 'hi')],
      )) {
        chunks.add(chunk);
      }

      expect(chunks, ['hello ', 'world']);
      expect(provider.streamCallCount, 1);
    });

    test('Failover 到备用 Provider', () async {
      final manager = AIProviderManager(
        config: const AIProviderManagerConfig(maxRetries: 1),
      );

      final primary = MockAiProvider(name: 'Primary');
      final fallback = MockAiProvider(name: 'Fallback');

      primary.setShouldFail(true); // Primary 失败

      manager.register(primary, priority: ProviderPriority.primary);
      manager.register(fallback, priority: ProviderPriority.fallback);

      // 先设置 primary 为活动
      await manager.setActiveProvider('Primary');
      expect(manager.activeProviderName, 'Primary');

      // Primary 连续失败 3 次触发 failover
      for (int i = 0; i < 3; i++) {
        await manager.chat(
          messages: [const ChatMessageInput(role: 'user', content: 'test')],
        );
      }

      // 应该 failover 到 fallback
      expect(manager.activeProviderName, 'Fallback');
    });

    test('healthCheckAll 返回所有 Provider 状态', () async {
      final manager = AIProviderManager();
      final p1 = MockAiProvider(name: 'P1');
      final p2 = MockAiProvider(name: 'P2');

      p1.setHealthCheckResult(true);
      p2.setHealthCheckResult(false);

      manager.register(p1);
      manager.register(p2);

      final results = await manager.healthCheckAll();
      expect(results['P1'], true);
      expect(results['P2'], false);
    });

    test('dispose 释放所有资源', () async {
      final manager = AIProviderManager();
      final provider = MockAiProvider(name: 'Disposable');

      manager.register(provider);
      expect(manager.registrations, isNotEmpty);

      manager.dispose();
      expect(manager.registrations, isEmpty);
    });

    test('Token 用量追踪', () async {
      final manager = AIProviderManager();
      final provider = MockAiProvider(name: 'TokenAI');

      manager.register(provider);

      expect(manager.tokenUsage.totalTokens, 0);

      await manager.chat(
        messages: [const ChatMessageInput(role: 'user', content: 'hi')],
      );

      expect(manager.tokenUsage.byProvider.containsKey('TokenAI'), true);
      expect(manager.tokenUsage.totalTokens, greaterThan(0));
    });

    test('取消进行中的 chat', () async {
      final manager = AIProviderManager();
      final provider = MockAiProvider(name: 'CancelTest');

      manager.register(provider);

      final cancelToken = CancelToken();
      cancelToken.cancel(); // 预取消

      final result = await manager.chat(
        messages: [const ChatMessageInput(role: 'user', content: 'test')],
        cancelToken: cancelToken,
      );

      expect(result, ''); // 取消时返回空
    });

    test('streamChat 支持取消', () async {
      final manager = AIProviderManager();
      final provider = MockAiProvider(name: 'StreamCancel');

      manager.register(provider);

      final cancelToken = CancelToken();
      cancelToken.cancel();

      final chunks = <String>[];
      await for (final chunk in manager.streamChat(
        messages: [const ChatMessageInput(role: 'user', content: 'test')],
        cancelToken: cancelToken,
      )) {
        chunks.add(chunk);
      }

      expect(chunks, isEmpty);
    });
  });

  group('ProviderPriority', () {
    test('主 Provider 级别最低（最高优先级）', () {
      expect(ProviderPriority.primary.level, 0);
      expect(ProviderPriority.fallback.level, 1);
    });

    test('优先级排序', () {
      final priorities = [ProviderPriority.secondary, ProviderPriority.primary, ProviderPriority.fallback];
      priorities.sort((a, b) => a.level.compareTo(b.level));

      expect(priorities[0], ProviderPriority.primary);
      expect(priorities[1], ProviderPriority.fallback);
      expect(priorities[2], ProviderPriority.secondary);
    });
  });
}
