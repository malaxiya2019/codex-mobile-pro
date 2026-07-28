import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/ai/ai_message.dart';
import 'package:codex_mobile_pro/core/ai/ai_provider.dart';
import 'package:codex_mobile_pro/core/ai/ai_provider_manager.dart';
import 'package:codex_mobile_pro/core/ai/chat_engine.dart';
import 'package:codex_mobile_pro/core/ai/chat_session.dart';

// ══════════════════════════════════════════════
// Mock IAIProviderManager
// ══════════════════════════════════════════════

class MockProviderManager implements IAIProviderManager {
  String? _activeProviderName;
  String _chatResult = 'mock response';
  bool _shouldFail = false;
  bool _shouldStreamFail = false;
  int chatCallCount = 0;
  int streamCallCount = 0;
  final List<List<ChatMessageInput>> _chatHistory = [];
  final List<List<ChatMessageInput>> _streamHistory = [];

  void setChatResult(String result) => _chatResult = result;
  void setShouldFail(bool fail) => _shouldFail = fail;
  void setShouldStreamFail(bool fail) => _shouldStreamFail = fail;

  @override
  AiProvider? get activeProvider => null;

  @override
  String? get activeProviderName => _activeProviderName;

  void setActiveProviderName(String? name) => _activeProviderName = name;

  @override
  List<ProviderRegistration> get registrations => [];

  @override
  void register(AiProvider provider, {ProviderPriority priority = ProviderPriority.fallback}) {}

  @override
  void unregister(String providerName) {}

  @override
  Future<bool> setActiveProvider(String providerName) async => true;

  @override
  AggregatedTokenUsage get tokenUsage => const AggregatedTokenUsage();

  @override
  RateLimitInfo get rateLimitInfo => const RateLimitInfo();

  @override
  Future<String> chat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    chatCallCount++;
    _chatHistory.add(List.from(messages));
    if (_shouldFail) throw Exception('Chat failed');
    return _chatResult;
  }

  @override
  Stream<String> streamChat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async* {
    streamCallCount++;
    _streamHistory.add(List.from(messages));
    if (_shouldStreamFail) throw Exception('Stream failed');

    if (cancelToken?.isCancelled == true) return;

    final chunks = ['mock ', 'chunk ', 'response'];
    for (final chunk in chunks) {
      if (cancelToken?.isCancelled == true) return;
      yield chunk;
    }
  }

  @override
  Future<Map<String, bool>> healthCheckAll() async => {};

  @override
  void dispose() {}
}

// ══════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════

void main() {
  // ── ChatMessage metadata ──

  group('ChatMessage metadata', () {
    test('创建带 metadata 的消息', () {
      final msg = ChatMessage(
        id: '1',
        role: ChatRole.user,
        content: 'hello',
        timestamp: DateTime(2026),
        metadata: {'file': 'main.dart', 'line': 42},
      );

      expect(msg.metadata, isNotNull);
      expect(msg.metadata!['file'], 'main.dart');
      expect(msg.metadata!['line'], 42);
    });

    test('创建不带 metadata 的消息（向后兼容）', () {
      final msg = ChatMessage(
        id: '1',
        role: ChatRole.user,
        content: 'hello',
        timestamp: DateTime(2026),
      );

      expect(msg.metadata, isNull);
    });

    test('copyWith 保留 metadata', () {
      final msg = ChatMessage(
        id: '1',
        role: ChatRole.user,
        content: 'hello',
        timestamp: DateTime(2026),
        metadata: {'key': 'value'},
      );

      final copied = msg.copyWith(content: 'world');
      expect(copied.metadata, isNotNull);
      expect(copied.metadata!['key'], 'value');
    });

    test('copyWith 可以替换 metadata', () {
      final msg = ChatMessage(
        id: '1',
        role: ChatRole.user,
        content: 'hello',
        timestamp: DateTime(2026),
        metadata: {'old': 'value'},
      );

      final copied = msg.copyWith(metadata: {'new': 'data'});
      expect(copied.metadata!['new'], 'data');
      expect(copied.metadata!.containsKey('old'), false);
    });

    test('toApiMap 不包含 metadata', () {
      final msg = ChatMessage(
        id: '1',
        role: ChatRole.user,
        content: 'hello',
        timestamp: DateTime(2026),
        metadata: {'file': 'main.dart'},
      );

      final apiMap = msg.toApiMap();
      expect(apiMap['role'], 'user');
      expect(apiMap['content'], 'hello');
      expect(apiMap.containsKey('metadata'), false);
    });
  });

  // ── ChatSession ──

  group('ChatSession', () {
    test('创建会话默认值正确', () {
      final session = ChatSession(sessionId: 's1');

      expect(session.sessionId, 's1');
      expect(session.title, startsWith('对话 '));
      expect(session.messages, isEmpty);
      expect(session.status, SessionStatus.active);
      expect(session.metadata, isNull);
    });

    test('创建会话可指定 title', () {
      final session = ChatSession(sessionId: 's1', title: '测试会话');
      expect(session.title, '测试会话');
    });

    test('创建会话可指定 metadata', () {
      final session = ChatSession(
        sessionId: 's1',
        metadata: {'model': 'deepseek-chat'},
      );
      expect(session.metadata!['model'], 'deepseek-chat');
    });

    test('addMessage 添加消息', () {
      final session = ChatSession(sessionId: 's1');
      final msg = ChatMessage(
        id: 'm1',
        role: ChatRole.user,
        content: 'test',
        timestamp: DateTime(2026),
      );

      session.addMessage(msg);
      expect(session.messages.length, 1);
      expect(session.messages.first.content, 'test');
    });

    test('addMessage 更新 updatedAt', () async {
      final now = DateTime(2026, 1, 1);
      final session = ChatSession(sessionId: 's1', createdAt: now, updatedAt: now);

      await Future.delayed(const Duration(milliseconds: 1));

      session.addMessage(ChatMessage(
        id: 'm1',
        role: ChatRole.user,
        content: 'test',
        timestamp: DateTime.now(),
      ));

      expect(session.updatedAt.isAfter(now), true);
    });

    test('replaceLastMessage 替换最后一条', () {
      final session = ChatSession(sessionId: 's1');
      session.addMessage(ChatMessage(
        id: 'm1',
        role: ChatRole.user,
        content: 'user msg',
        timestamp: DateTime(2026),
      ));
      session.addMessage(ChatMessage(
        id: 'm2',
        role: ChatRole.assistant,
        content: '',
        timestamp: DateTime(2026),
        isStreaming: true,
      ));

      expect(session.messages.length, 2);

      session.replaceLastMessage(ChatMessage(
        id: 'm3',
        role: ChatRole.assistant,
        content: 'full response',
        timestamp: DateTime(2026),
      ));

      expect(session.messages.length, 2);
      expect(session.messages.last.content, 'full response');
      expect(session.messages.last.isStreaming, false);
    });

    test('messagesByRole 按角色过滤', () {
      final session = ChatSession(sessionId: 's1');
      session.addMessage(ChatMessage(id: 's', role: ChatRole.system, content: 'sys', timestamp: DateTime(2026)));
      session.addMessage(ChatMessage(id: 'u1', role: ChatRole.user, content: 'hi', timestamp: DateTime(2026)));
      session.addMessage(ChatMessage(id: 'a1', role: ChatRole.assistant, content: 'hello', timestamp: DateTime(2026)));
      session.addMessage(ChatMessage(id: 'u2', role: ChatRole.user, content: 'how?', timestamp: DateTime(2026)));

      expect(session.messagesByRole(ChatRole.user).length, 2);
      expect(session.messagesByRole(ChatRole.assistant).length, 1);
      expect(session.messagesByRole(ChatRole.system).length, 1);
    });

    test('lastMessages 返回最后 N 条', () {
      final session = ChatSession(sessionId: 's1');
      for (int i = 0; i < 10; i++) {
        session.addMessage(ChatMessage(
          id: 'm$i',
          role: ChatRole.user,
          content: 'msg $i',
          timestamp: DateTime(2026),
        ));
      }

      final last3 = session.lastMessages(3);
      expect(last3.length, 3);
      expect(last3[0].content, 'msg 7');
      expect(last3[2].content, 'msg 9');
    });

    test('lastMessages 返回全部（不足 N 条）', () {
      final session = ChatSession(sessionId: 's1');
      session.addMessage(ChatMessage(id: 'm1', role: ChatRole.user, content: 'msg 1', timestamp: DateTime(2026)));

      final last5 = session.lastMessages(5);
      expect(last5.length, 1);
    });
  });

  // ── TokenContextManager ──

  group('TokenContextManager', () {
    late TokenContextManager manager;

    setUp(() {
      // 小 Token 限制方便测试
      manager = TokenContextManager(maxTokens: 100, minRecentMessages: 2);
    });

    test('estimateTokens 估算准确', () {
      // 每字符约 0.25 token，4 字符 = 1 token
      expect(manager.estimateTokens('test'), 1);
      expect(manager.estimateTokens('hello world'), 3); // 11 * 0.25 = 2.75 → 3
      expect(manager.estimateTokens(''), 0);
    });

    test('estimateMessagesTokens 计算多条消息', () {
      final msgs = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'hello', timestamp: DateTime(2026)),
        ChatMessage(id: '2', role: ChatRole.assistant, content: 'world', timestamp: DateTime(2026)),
      ];

      // hello: 5*0.25=2 → 2+4=6, world: 5*0.25=2 → 2+4=6, total=12
      expect(manager.estimateMessagesTokens(msgs), 12);
    });

    test('trimContext 全部在限制内不裁剪', () {
      final msgs = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'hi', timestamp: DateTime(2026)),
        ChatMessage(id: '2', role: ChatRole.assistant, content: 'hello', timestamp: DateTime(2026)),
      ];
      final system = ChatMessage(id: 'sys', role: ChatRole.system, content: 'system prompt', timestamp: DateTime(2026));

      final result = manager.trimContext(messages: msgs, systemMessage: system);
      expect(result.length, 3); // system + 2 messages
      expect(result[0].role, ChatRole.system);
    });

    test('trimContext 超限时裁剪旧消息', () {
      final msgs = [
        ChatMessage(id: 'old', role: ChatRole.user, content: 'a' * 200, timestamp: DateTime(2026)),
        ChatMessage(id: 'mid', role: ChatRole.assistant, content: 'b' * 100, timestamp: DateTime(2026)),
        ChatMessage(id: 'recent', role: ChatRole.user, content: 'c', timestamp: DateTime(2026)),
      ];
      final system = ChatMessage(id: 'sys', role: ChatRole.system, content: 'sys', timestamp: DateTime(2026));

      final result = manager.trimContext(messages: msgs, systemMessage: system);

      // System message 应该保留
      expect(result.any((m) => m.id == 'sys'), true);
      // 至少保留 minRecentMessages(2) 条非 system 消息
      expect(result.length, greaterThanOrEqualTo(3)); // system + minRecentMessages
    });

    test('trimContext 空消息列表返回空', () {
      final result = manager.trimContext(messages: []);
      expect(result, isEmpty);
    });

    test('trimContext 没有 system message 时正常处理', () {
      final msgs = [
        ChatMessage(id: '1', role: ChatRole.user, content: 'hi', timestamp: DateTime(2026)),
        ChatMessage(id: '2', role: ChatRole.assistant, content: 'hello', timestamp: DateTime(2026)),
      ];

      final result = manager.trimContext(messages: msgs);
      expect(result.length, 2);
    });
  });

  // ── DefaultContextManager ──

  group('DefaultContextManager', () {
    late DefaultContextManager ctxManager;

    setUp(() {
      ctxManager = DefaultContextManager();
    });

    test('初始状态返回空', () {
      expect(ctxManager.currentFile, isNull);
      expect(ctxManager.selection, isNull);
      expect(ctxManager.workspaceContext, isNull);
      expect(ctxManager.buildContextPrompt(), '');
    });

    test('addContext 和 removeContext', () {
      ctxManager.addContext('file', 'main.dart');
      expect(ctxManager.buildContextPrompt(), contains('main.dart'));

      ctxManager.removeContext('file');
      expect(ctxManager.buildContextPrompt(), '');
    });

    test('clearContext 清空所有', () {
      ctxManager.addContext('file', 'main.dart');
      ctxManager.addContext('selection', 'hello world');
      expect(ctxManager.buildContextPrompt(), isNotEmpty);

      ctxManager.clearContext();
      expect(ctxManager.buildContextPrompt(), '');
    });

    test('buildContextPrompt 格式化正确', () {
      ctxManager.addContext('file', 'main.dart');
      ctxManager.addContext('language', 'dart');

      final prompt = ctxManager.buildContextPrompt();
      expect(prompt, contains('## 上下文信息'));
      expect(prompt, contains('### file'));
      expect(prompt, contains('main.dart'));
      expect(prompt, contains('### language'));
      expect(prompt, contains('dart'));
    });
  });

  // ── ChatEngine ──

  group('ChatEngine', () {
    late MockProviderManager mockProvider;
    late ChatEngine engine;

    setUp(() {
      mockProvider = MockProviderManager();
      mockProvider.setActiveProviderName('MockAI');

      engine = ChatEngine(
        providerManager: mockProvider,
        systemPrompt: '你是一个测试助手',
      );
    });

    tearDown(() {
      engine.dispose();
    });

    // ── Session 管理 ──

    group('Session 管理', () {
      test('createSession 创建新会话', () {
        final session = engine.createSession();
        expect(session.sessionId, isNotEmpty);
        expect(session.title, startsWith('对话 '));
        expect(session.messages, isEmpty);
      });

      test('createSession 可指定 title', () {
        final session = engine.createSession(title: '测试');
        expect(session.title, '测试');
      });

      test('createSession 可指定 metadata', () {
        final session = engine.createSession(metadata: {'model': 'deepseek'});
        expect(session.metadata!['model'], 'deepseek');
      });

      test('getSession 返回已创建会话', () {
        final created = engine.createSession();
        final retrieved = engine.getSession(created.sessionId);
        expect(retrieved, isNotNull);
        expect(retrieved!.sessionId, created.sessionId);
      });

      test('getSession 不存在的会话返回 null', () {
        expect(engine.getSession('non-existent'), isNull);
      });

      test('deleteSession 删除会话', () {
        final session = engine.createSession();
        expect(engine.getSession(session.sessionId), isNotNull);

        engine.deleteSession(session.sessionId);
        expect(engine.getSession(session.sessionId), isNull);
      });

      test('deleteSession 清理生成状态', () {
        final session = engine.createSession();
        engine.deleteSession(session.sessionId);
        expect(engine.getGenerationStatus(session.sessionId), GenerationStatus.idle);
      });

      test('listSessions 返回所有会话（按 updatedAt 降序）', () async {
        engine.createSession(title: '第一'); // s1
        await Future.delayed(const Duration(milliseconds: 1));
        engine.createSession(title: '第二'); // s2

        final sessions = engine.listSessions();
        expect(sessions.length, 2);
        expect(sessions[0].title, '第二'); // 最新的在前
        expect(sessions[1].title, '第一');
      });

      test('listSessions 空列表', () {
        expect(engine.listSessions(), isEmpty);
      });
    });

    // ── sendMessage ──

    group('sendMessage（非流式）', () {
      test('发送消息返回 AI 响应', () async {
        mockProvider.setChatResult('mock response');
        final session = engine.createSession();

        final response = await engine.sendMessage(
          sessionId: session.sessionId,
          content: '你好',
        );

        expect(response.role, ChatRole.assistant);
        expect(response.content, 'mock response');
        expect(mockProvider.chatCallCount, 1);
      });

      test('发送消息后消息历史正确', () async {
        final session = engine.createSession();

        await engine.sendMessage(
          sessionId: session.sessionId,
          content: '你好',
        );

        final messages = await engine.getMessages(session.sessionId);
        expect(messages.length, 2); // user + assistant
        expect(messages[0].role, ChatRole.user);
        expect(messages[0].content, '你好');
        expect(messages[1].role, ChatRole.assistant);
      });

      test('发送空消息抛出异常', () async {
        final session = engine.createSession();

        expect(
          () => engine.sendMessage(
            sessionId: session.sessionId,
            content: '',
          ),
          throwsA(isA<ChatEngineException>()),
        );
      });

      test('空消息不改变消息历史', () async {
        final session = engine.createSession();

        try {
          await engine.sendMessage(sessionId: session.sessionId, content: '');
        } catch (_) {}

        final messages = await engine.getMessages(session.sessionId);
        expect(messages, isEmpty);
      });

      test('不存在的会话抛出异常', () async {
        expect(
          () => engine.sendMessage(sessionId: 'bad-id', content: 'hi'),
          throwsA(isA<ChatEngineException>()),
        );
      });

      test('Provider 失败时抛出异常', () async {
        mockProvider.setShouldFail(true);
        final session = engine.createSession();

        expect(
          () => engine.sendMessage(sessionId: session.sessionId, content: 'hi'),
          throwsException,
        );
      });

      test('首条消息自动更新标题', () async {
        final session = engine.createSession();
        await engine.sendMessage(sessionId: session.sessionId, content: '如何使用 Flutter 开发 App？');

        // 标题从 content 截取
        expect(session.title, isNot(startsWith('对话 ')));
        expect(session.title, contains('Flutter'));
      });

      test('多轮对话保留上下文', () async {
        final session = engine.createSession();

        await engine.sendMessage(sessionId: session.sessionId, content: '第一轮');
        await engine.sendMessage(sessionId: session.sessionId, content: '第二轮');

        final messages = await engine.getMessages(session.sessionId);
        expect(messages.length, 4); // user1 + assistant1 + user2 + assistant2

        // 验证 Provider 收到所有历史消息
        expect(mockProvider.chatCallCount, 2);
      });

      test('响应中包含 Provider 信息', () async {
        mockProvider.setActiveProviderName('MockAI');
        final session = engine.createSession();

        final response = await engine.sendMessage(
          sessionId: session.sessionId,
          content: 'hi',
        );

        expect(response.metadata, isNotNull);
        expect(response.metadata!['provider'], 'MockAI');
      });
    });

    // ── streamMessage ──

    group('streamMessage（流式）', () {
      test('流式返回 chunks', () async {
        final session = engine.createSession();

        final chunks = <String>[];
        await for (final chunk in engine.streamMessage(
          sessionId: session.sessionId,
          content: '你好',
        )) {
          chunks.add(chunk);
        }

        expect(chunks, ['mock ', 'chunk ', 'response']);
        expect(mockProvider.streamCallCount, 1);
      });

      test('流结束后最终消息正确', () async {
        final session = engine.createSession();

        await for (final _ in engine.streamMessage(
          sessionId: session.sessionId,
          content: '你好',
        )) {
          // consume stream
        }

        final messages = await engine.getMessages(session.sessionId);
        expect(messages.length, 2); // user + assistant

        final assistantMsg = messages[1];
        expect(assistantMsg.role, ChatRole.assistant);
        expect(assistantMsg.content, 'mock chunk response');
        expect(assistantMsg.isStreaming, false);
      });

      test('流式发送空消息抛出异常', () async {
        final session = engine.createSession();

        expect(
          engine.streamMessage(sessionId: session.sessionId, content: ''),
          emitsError(isA<ChatEngineException>()),
        );
      });

      test('不存在的会话抛出异常', () async {
        expect(
          engine.streamMessage(sessionId: 'bad', content: 'hi'),
          emitsError(isA<ChatEngineException>()),
        );
      });

      test('并发生成抛出异常', () async {
        final session = engine.createSession();

        // 开始第一个流并立即订阅（async* 生成器需要 listen 才开始执行）
        final stream = engine.streamMessage(
          sessionId: session.sessionId,
          content: '第一轮',
        );
        final sub = stream.listen((_) {});

        // 给生成器一点时间设置 streaming 状态
        await Future.delayed(Duration.zero);

        // 尝试第二个流应抛出 sessionBusy
        expect(
          engine.streamMessage(sessionId: session.sessionId, content: '第二轮'),
          emitsError(isA<ChatEngineException>()),
        );

        // 清理
        sub.cancel();
        engine.stopGeneration(session.sessionId);
      });

      test('流式提供者失败时抛出异常', () async {
        mockProvider.setShouldStreamFail(true);
        final session = engine.createSession();

        expect(
          engine.streamMessage(sessionId: session.sessionId, content: 'hi'),
          emitsError(isA<ChatEngineException>()),
        );
      });

      test('流式响应包含 Provider 信息', () async {
        mockProvider.setActiveProviderName('MockAI');
        final session = engine.createSession();

        await for (final _ in engine.streamMessage(
          sessionId: session.sessionId,
          content: 'hi',
        )) {}

        final messages = await engine.getMessages(session.sessionId);
        final assistantMsg = messages[1];
        expect(assistantMsg.metadata, isNotNull);
        expect(assistantMsg.metadata!['provider'], 'MockAI');
      });
    });

    // ── stopGeneration ──

    group('stopGeneration', () {
      test('停止生成后标记为 completed', () {
        final session = engine.createSession();
        engine.stopGeneration(session.sessionId);
        expect(engine.getGenerationStatus(session.sessionId), GenerationStatus.completed);
      });

      test('停止生成后状态正确', () {
        final session = engine.createSession();
        expect(engine.isGenerating(session.sessionId), false);

        engine.stopGeneration(session.sessionId);
        expect(engine.isGenerating(session.sessionId), false);
      });
    });

    // ── retryLastMessage ──

    group('retryLastMessage', () {
      test('重试发送最后一条用户消息', () async {
        final session = engine.createSession();

        await engine.sendMessage(sessionId: session.sessionId, content: '第一轮');
        expect(mockProvider.chatCallCount, 1);

        mockProvider.setChatResult('retry response');
        await engine.retryLastMessage(session.sessionId);

        // retry 不增加 provider chat call count... 实际上它会调用 sendMessage 内部
        // sendMessage 调用了 provider.chat
        expect(mockProvider.chatCallCount, 2); // 第一次 + retry
      });

      test('没有消息时重试抛出异常', () async {
        final session = engine.createSession();
        expect(
          () => engine.retryLastMessage(session.sessionId),
          throwsA(isA<ChatEngineException>()),
        );
      });

      test('重试时移除上一条 assistant 消息', () async {
        final session = engine.createSession();

        await engine.sendMessage(sessionId: session.sessionId, content: '测试');
        expect((await engine.getMessages(session.sessionId)).length, 2);

        await engine.retryLastMessage(session.sessionId);
        final messages = await engine.getMessages(session.sessionId);
        // 旧 assistant 被移除，新的一轮: user(原) + assistant(新)
        expect(messages.length, 2);
      });
    });

    // ── 上下文管理 ──

    group('上下文管理', () {
      test('addContext 和 clearContext', () {
        engine.addContext('file', 'main.dart');
        engine.addContext('selection', 'hello world');

        engine.clearContext();
        // 不抛出异常即可
      });

      test('上下文注入到 system prompt', () async {
        engine.addContext('current_file', 'lib/main.dart');
        final session = engine.createSession();

        await engine.sendMessage(sessionId: session.sessionId, content: 'hi');

        // Provider 收到的消息应包含上下文
        expect(mockProvider._chatHistory, isNotEmpty);
        final lastMessages = mockProvider._chatHistory.last;
        // system message 应包含上下文信息
        final systemMsg = lastMessages.firstWhere((m) => m.role == 'system');
        expect(systemMsg.content, contains('main.dart'));
      });

      test('removeContext 移除指定上下文', () {
        engine.addContext('file', 'main.dart');
        engine.removeContext('file');
        // 不抛出异常即可
      });
    });

    // ── 状态 ──

    group('状态', () {
      test('初始状态是 idle', () {
        final session = engine.createSession();
        expect(engine.getGenerationStatus(session.sessionId), GenerationStatus.idle);
        expect(engine.isGenerating(session.sessionId), false);
      });

      test('不存在的会话返回 idle', () {
        expect(engine.getGenerationStatus('non-existent'), GenerationStatus.idle);
        expect(engine.isGenerating('non-existent'), false);
      });

      test('流式生成中状态正确', () async {
        final session = engine.createSession();
        bool wasGenerating = false;
        final stream = engine.streamMessage(
          sessionId: session.sessionId,
          content: 'hi',
        );

        await for (final _ in stream) {
          if (!wasGenerating) {
            wasGenerating = engine.isGenerating(session.sessionId);
          }
        }

        expect(wasGenerating, true);
      });
    });

    // ── dispose ──

    group('dispose', () {
      test('dispose 后所有会话清空', () {
        engine.createSession(title: 's1');
        engine.createSession(title: 's2');
        expect(engine.listSessions().length, 2);

        engine.dispose();
        expect(engine.listSessions(), isEmpty);
      });

      test('dispose 后生成状态清空', () {
        final session = engine.createSession();
        engine.dispose();
        expect(engine.getGenerationStatus(session.sessionId), GenerationStatus.idle);
      });

      test('dispose 可多次调用', () {
        engine.dispose();
        engine.dispose();
        // 不抛出异常
      });
    });

    // ── 集成测试 ──

    group('集成场景', () {
      test('完整对话流程', () async {
        // 创建会话
        final session = engine.createSession(title: '集成测试');
        expect(session, isNotNull);

        // 发送消息
        mockProvider.setChatResult('这是一个测试回复');
        final response = await engine.sendMessage(
          sessionId: session.sessionId,
          content: '你好',
        );
        expect(response.content, '这是一个测试回复');

        // 发送第二条消息（多轮）
        mockProvider.setChatResult('第二轮回复');
        final response2 = await engine.sendMessage(
          sessionId: session.sessionId,
          content: '再问一个问题',
        );
        expect(response2.content, '第二轮回复');

        // 获取历史
        final messages = await engine.getMessages(session.sessionId);
        expect(messages.length, 4);

        // 列出会话
        final sessions = engine.listSessions();
        expect(sessions.length, 1);

        // 删除会话
        engine.deleteSession(session.sessionId);
        expect(engine.getSession(session.sessionId), isNull);
      });

      test('流式完整流程', () async {
        final session = engine.createSession();

        // 流式发送
        final chunks = <String>[];
        await for (final chunk in engine.streamMessage(
          sessionId: session.sessionId,
          content: '流式测试',
        )) {
          chunks.add(chunk);
        }

        expect(chunks, isNotEmpty);
        expect(chunks.join(), 'mock chunk response');

        // 流结束后消息正确
        final messages = await engine.getMessages(session.sessionId);
        expect(messages.length, 2);
        expect(messages[0].role, ChatRole.user);
        expect(messages[1].role, ChatRole.assistant);
      });

      test('非流式 + 流式混合', () async {
        final session = engine.createSession();

        // 非流式第一轮
        mockProvider.setChatResult('第一轮回复');
        await engine.sendMessage(sessionId: session.sessionId, content: '第一轮');

        // 流式第二轮
        final chunks = <String>[];
        await for (final chunk in engine.streamMessage(
          sessionId: session.sessionId,
          content: '第二轮',
        )) {
          chunks.add(chunk);
        }

        // 总共 4 条消息
        final messages = await engine.getMessages(session.sessionId);
        expect(messages.length, 4);
        expect(messages[0].content, '第一轮');
        expect(messages[2].content, '第二轮');
      });
    });
  });
}
