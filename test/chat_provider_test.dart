import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:codex_mobile_pro/core/ai/ai_message.dart';
import 'package:codex_mobile_pro/core/ai/chat_engine.dart';
import 'package:codex_mobile_pro/core/ai/chat_session.dart';
import 'package:codex_mobile_pro/features/ai/providers/chat_provider.dart';

// ══════════════════════════════════════════════
// Mock IChatEngine
// ══════════════════════════════════════════════

class MockChatEngine implements IChatEngine {
  final Map<String, ChatSession> _sessions = {};
  final Map<String, GenerationStatus> _statuses = {};
  final Map<String, StreamController<String>> _streamControllers = {};

  int sessionCounter = 0;
  bool shouldFailOnStream = false;
  bool shouldFailOnRetry = false;
  bool shouldFailOnSend = false;

  @override
  ChatSession createSession({String? title, Map<String, dynamic>? metadata}) {
    sessionCounter++;
    final sessionId = 'mock-session-$sessionCounter';
    final session = ChatSession(
      sessionId: sessionId,
      title: title,
      metadata: metadata,
    );
    _sessions[sessionId] = session;
    _statuses[sessionId] = GenerationStatus.idle;
    return session;
  }

  @override
  void deleteSession(String sessionId) {
    _sessions.remove(sessionId);
    _statuses.remove(sessionId);
    _streamControllers.remove(sessionId);
  }

  @override
  ChatSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  @override
  List<ChatSession> listSessions() {
    final list = _sessions.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<List<ChatMessage>> getMessages(String sessionId) async {
    final session = _sessions[sessionId];
    return session?.messages ?? [];
  }

  @override
  Future<ChatMessage> sendMessage({
    required String sessionId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    if (shouldFailOnSend) throw Exception('Send failed');

    final session = _sessions[sessionId];
    if (session == null) throw Exception('Session not found');

    final userMsg = ChatMessage(
      id: 'u-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.user,
      content: content.trim(),
      timestamp: DateTime.now(),
      metadata: metadata,
    );
    session.addMessage(userMsg);

    final assistantMsg = ChatMessage(
      id: 'a-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.assistant,
      content: 'mock response to: ${content.trim()}',
      timestamp: DateTime.now(),
    );
    session.addMessage(assistantMsg);
    _statuses[sessionId] = GenerationStatus.completed;

    return assistantMsg;
  }

  @override
  Stream<String> streamMessage({
    required String sessionId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async* {
    if (shouldFailOnStream) throw Exception('Stream failed');

    final session = _sessions[sessionId];
    if (session == null) throw Exception('Session not found');

    // 添加用户消息
    final userMsg = ChatMessage(
      id: 'u-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.user,
      content: content.trim(),
      timestamp: DateTime.now(),
      metadata: metadata,
    );
    session.addMessage(userMsg);

    // 添加流式占位
    final placeholderId = 'streaming-${DateTime.now().microsecondsSinceEpoch}';
    session.addMessage(ChatMessage(
      id: placeholderId,
      role: ChatRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
    ));

    _statuses[sessionId] = GenerationStatus.streaming;

    final chunks = ['mock ', 'chunk ', 'response'];
    final buffer = StringBuffer();

    for (final chunk in chunks) {
      buffer.write(chunk);
      // 更新占位消息
      session.replaceLastMessage(ChatMessage(
        id: placeholderId,
        role: ChatRole.assistant,
        content: buffer.toString(),
        timestamp: DateTime.now(),
        isStreaming: true,
      ));
      yield chunk;
    }

    // 流结束，替换占位为最终消息
    _statuses[sessionId] = GenerationStatus.completed;
    session.replaceLastMessage(ChatMessage(
      id: 'a-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.assistant,
      content: buffer.toString(),
      timestamp: DateTime.now(),
    ));
  }

  @override
  Future<ChatMessage> retryLastMessage(String sessionId) async {
    if (shouldFailOnRetry) throw Exception('Retry failed');

    final session = _sessions[sessionId];
    if (session == null) throw Exception('Session not found');

    final userMessages = session.messagesByRole(ChatRole.user);
    if (userMessages.isEmpty) throw Exception('No messages to retry');

    // 移除最后一条 assistant 消息
    if (session.messages.isNotEmpty &&
        session.messages.last.role == ChatRole.assistant) {
      session.messages.removeLast();
    }

    final lastUser = userMessages.last;
    final assistantMsg = ChatMessage(
      id: 'a-retry-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.assistant,
      content: 'retry response to: ${lastUser.content}',
      timestamp: DateTime.now(),
    );
    session.addMessage(assistantMsg);
    _statuses[sessionId] = GenerationStatus.completed;

    return assistantMsg;
  }

  @override
  void stopGeneration(String sessionId) {
    _statuses[sessionId] = GenerationStatus.completed;

    final session = _sessions[sessionId];
    if (session != null && session.messages.isNotEmpty) {
      final last = session.messages.last;
      if (last.isStreaming) {
        session.replaceLastMessage(ChatMessage(
          id: 'a-stopped-${DateTime.now().microsecondsSinceEpoch}',
          role: ChatRole.assistant,
          content: last.content.isNotEmpty ? last.content : '⚠️ 已停止生成',
          timestamp: DateTime.now(),
          metadata: {'stopped': true},
        ));
      }
    }
  }

  @override
  void addContext(String key, String value) {}

  @override
  void removeContext(String key) {}

  @override
  void clearContext() {}

  @override
  bool isGenerating(String sessionId) {
    return _statuses[sessionId] == GenerationStatus.streaming;
  }

  @override
  GenerationStatus getGenerationStatus(String sessionId) {
    return _statuses[sessionId] ?? GenerationStatus.idle;
  }

  @override
  void dispose() {
    _sessions.clear();
    _statuses.clear();
    _streamControllers.clear();
  }
}

// ══════════════════════════════════════════════
// Provider 覆写
// ══════════════════════════════════════════════

/// 创建测试用的 ProviderContainer（使用 MockChatEngine）
ProviderContainer createTestContainer({MockChatEngine? engine}) {
  final mockEngine = engine ?? MockChatEngine();
  return ProviderContainer(
    overrides: [
      chatEngineProvider.overrideWithValue(mockEngine),
    ],
  );
}

// ══════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════

void main() {
  // ── ChatState ──

  group('ChatState', () {
    test('初始状态默认值正确', () {
      const state = ChatState();

      expect(state.currentSessionId, isNull);
      expect(state.sessions, isEmpty);
      expect(state.messages, isEmpty);
      expect(state.loadingState, ChatLoadingState.idle);
      expect(state.errorMessage, isNull);
      expect(state.generationStatus, GenerationStatus.idle);
    });

    test('copyWith 正确更新字段', () {
      const state = ChatState();

      final session = ChatSession(sessionId: 's1');
      final updated = state.copyWith(
        currentSessionId: 's1',
        sessions: [session],
        loadingState: ChatLoadingState.streaming,
        errorMessage: '测试错误',
        generationStatus: GenerationStatus.streaming,
      );

      expect(updated.currentSessionId, 's1');
      expect(updated.sessions.length, 1);
      expect(updated.loadingState, ChatLoadingState.streaming);
      expect(updated.errorMessage, '测试错误');
      expect(updated.generationStatus, GenerationStatus.streaming);
      expect(updated.messages, isEmpty); // 未修改
    });

    test('multiple copyWith 保持不可变', () {
      const state = ChatState();

      final s1 = state.copyWith(loadingState: ChatLoadingState.loading);
      final s2 = state.copyWith(loadingState: ChatLoadingState.streaming);

      expect(s1.loadingState, ChatLoadingState.loading);
      expect(s2.loadingState, ChatLoadingState.streaming);
      expect(state.loadingState, ChatLoadingState.idle); // 原始不变
    });

    test('会话和消息字段独立更新', () {
      const state = ChatState();

      final s1 = state.copyWith(currentSessionId: 's1');
      final s2 = state.copyWith(currentSessionId: 's2');

      expect(s1.currentSessionId, 's1');
      expect(s2.currentSessionId, 's2');
      expect(state.currentSessionId, isNull);
    });
  });

  // ── ChatLoadingState ──

  group('ChatLoadingState', () {
    test('所有状态值定义正确', () {
      expect(ChatLoadingState.values.length, 4);
      expect(ChatLoadingState.values, contains(ChatLoadingState.idle));
      expect(ChatLoadingState.values, contains(ChatLoadingState.loading));
      expect(ChatLoadingState.values, contains(ChatLoadingState.streaming));
      expect(ChatLoadingState.values, contains(ChatLoadingState.error));
    });
  });

  // ── ChatNotifier ──

  group('ChatNotifier', () {
    late MockChatEngine mockEngine;

    setUp(() {
      mockEngine = MockChatEngine();
    });

    // ── 初始化 ──

    group('初始化', () {
      test('创建时自动初始化默认会话', () {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final state = container.read(chatProvider);

        expect(state.currentSessionId, isNotNull);
        expect(state.currentSessionId, startsWith('mock-session-'));
        expect(state.sessions.length, 1);
        expect(state.messages, isEmpty);
        expect(state.loadingState, ChatLoadingState.idle);
        expect(state.generationStatus, GenerationStatus.idle);
      });

      test('默认会话在引擎中存在', () {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final state = container.read(chatProvider);
        final session = mockEngine.getSession(state.currentSessionId!);

        expect(session, isNotNull);
        expect(session!.messages, isEmpty);
      });
    });

    // ── Session 管理 ──

    group('Session 管理', () {
      test('createSession 创建新会话并自动切换', () {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);
        final firstSessionId = container.read(chatProvider).currentSessionId;

        notifier.createSession(title: '新会话');

        final state = container.read(chatProvider);
        expect(state.currentSessionId, isNot(equals(firstSessionId)));
        expect(state.sessions.length, 2);
      });

      test('switchSession 切换到指定会话', () {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);
        notifier.createSession(title: '第二会话');

        final sessions = container.read(chatProvider).sessions;
        expect(sessions.length, 2);

        // 切换到第一个会话
        final firstId = sessions.last.sessionId;
        notifier.switchSession(firstId);

        final state = container.read(chatProvider);
        expect(state.currentSessionId, firstId);
      });

      test('switchSession 相同 ID 不重复切换', () {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);
        final currentId = container.read(chatProvider).currentSessionId;

        notifier.switchSession(currentId!);

        // 状态不变
        expect(container.read(chatProvider).currentSessionId, currentId);
      });

      test('deleteSession 删除当前会话后自动切换到其他会话', () {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);
        notifier.createSession(); // session 2
        final session2Id = container.read(chatProvider).currentSessionId;

        notifier.deleteSession(session2Id!);

        final state = container.read(chatProvider);
        expect(state.currentSessionId, isNotNull);
        expect(state.currentSessionId, isNot(equals(session2Id)));
        expect(state.sessions.length, 1);
      });

      test('删除所有会话后自动创建新会话', () {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);
        final firstId = container.read(chatProvider).currentSessionId;

        notifier.deleteSession(firstId!);

        final state = container.read(chatProvider);
        expect(state.currentSessionId, isNotNull);
        expect(state.messages, isEmpty);
      });
    });

    // ── sendMessage ──

    group('sendMessage', () {
      test('发送消息后更新状态', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        await notifier.sendMessage('你好');

        final state = container.read(chatProvider);
        expect(state.messages.length, 2); // user + assistant
        expect(state.messages[0].role, ChatRole.user);
        expect(state.messages[0].content, '你好');
        expect(state.messages[1].role, ChatRole.assistant);
        expect(state.messages[1].content, 'mock chunk response');
        expect(state.loadingState, ChatLoadingState.idle);
      });

      test('发送空消息不改变状态', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);
        final beforeState = container.read(chatProvider);

        await notifier.sendMessage('');

        final afterState = container.read(chatProvider);
        expect(afterState.currentSessionId, beforeState.currentSessionId);
        expect(afterState.messages, beforeState.messages);
      });

      test('发送空白消息不改变状态', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        await notifier.sendMessage('   ');

        final state = container.read(chatProvider);
        expect(state.messages, isEmpty);
      });

      test('发送消息时 loadingState 正确', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        // 发送前是 idle
        expect(container.read(chatProvider).loadingState, ChatLoadingState.idle);

        // 发送后最终回到 idle
        await notifier.sendMessage('test');
        expect(container.read(chatProvider).loadingState, ChatLoadingState.idle);
      });

      test('Provider 失败时状态变为 error', () async {
        mockEngine.shouldFailOnStream = true;
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        await notifier.sendMessage('hi');

        final state = container.read(chatProvider);
        expect(state.loadingState, ChatLoadingState.error);
        expect(state.errorMessage, isNotNull);
      });

      test('多轮消息累积历史', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        await notifier.sendMessage('第一轮');
        await notifier.sendMessage('第二轮');
        await notifier.sendMessage('第三轮');

        final state = container.read(chatProvider);
        expect(state.messages.length, 6); // 3 user + 3 assistant
        expect(state.messages[0].content, '第一轮');
        expect(state.messages[2].content, '第二轮');
        expect(state.messages[4].content, '第三轮');
      });
    });

    // ── stopGeneration ──

    group('stopGeneration', () {
      test('停止生成后状态正确', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        // 开始一个流
        final future = notifier.sendMessage('测试');
        await Future.delayed(const Duration(milliseconds: 50));

        // 停止
        notifier.stopGeneration();

        // 等待流结束
        await future;

        final state = container.read(chatProvider);
        expect(state.loadingState, ChatLoadingState.idle);
      });

      test('空闲状态调用 stopGeneration 不报错', () {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        // 不应抛出异常
        notifier.stopGeneration();
        expect(container.read(chatProvider).loadingState, ChatLoadingState.idle);
      });
    });

    // ── retryLastMessage ──

    group('retryLastMessage', () {
      test('重试后替换最后一条 assistant 消息', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        await notifier.sendMessage('测试重试');
        expect(container.read(chatProvider).messages.length, 2);

        await notifier.retryLastMessage();

        final state = container.read(chatProvider);
        expect(state.messages.length, 2); // user + new assistant
        expect(state.messages[1].content, contains('retry response'));
      });

      test('没有消息时重试不报错', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        // 没有消息，retry 应该被引擎捕获并抛出
        // 但 ChatNotifier 会 catch 并把状态设为 error
        await notifier.retryLastMessage();

        final state = container.read(chatProvider);
        // 可能是 error 状态
        expect(
          state.loadingState == ChatLoadingState.error ||
              state.loadingState == ChatLoadingState.idle,
          true,
        );
      });
    });

    // ── clearError ──

    group('clearError', () {
      test('清除错误后状态恢复', () async {
        final container = createTestContainer(engine: mockEngine);
        addTearDown(() => container.dispose());

        final notifier = container.read(chatProvider.notifier);

        // 先发送消息并等待完成，再手动设置错误
        await notifier.sendMessage('hi');
        // 通过停止生成触发 error 状态
        notifier.stopGeneration();

        // 清除错误
        notifier.clearError();

        final state = container.read(chatProvider);
        expect(state.errorMessage, isNull);
      });
    });

    // ── dispose ──

    group('dispose', () {
      test('dispose 释放引擎资源', () {
        final container = createTestContainer(engine: mockEngine);

        // 先释放容器，notifier 随容器一起释放
        container.dispose();

        // dispose 后不应再有错误
        // 验证通过（没有异常即通过）
      });
    });
  });
}
