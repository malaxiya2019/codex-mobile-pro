import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:codex_mobile_pro/core/ai/ai_message.dart';
import 'package:codex_mobile_pro/core/ai/ai_service.dart';
import 'package:codex_mobile_pro/features/ai/providers/chat_provider.dart';

void main() {
  group('ChatState', () {
    test('初始状态默认值正确', () {
      const state = ChatState();
      expect(state.messages, isEmpty);
      expect(state.loadingState, ChatLoadingState.idle);
      expect(state.errorMessage, isNull);
      expect(state.totalTokens, 0);
      expect(state.serviceStatus, AiServiceStatus.proxyDown);
    });

    test('copyWith 正确更新字段', () {
      const state = ChatState();
      final updated = state.copyWith(
        loadingState: ChatLoadingState.streaming,
        errorMessage: '测试错误',
        serviceStatus: AiServiceStatus.ready,
      );
      expect(updated.loadingState, ChatLoadingState.streaming);
      expect(updated.errorMessage, '测试错误');
      expect(updated.serviceStatus, AiServiceStatus.ready);
      expect(updated.messages, isEmpty); // 未修改
    });

    test('cleared 清空消息但保留服务状态', () {
      final state = ChatState(
        messages: [
          ChatMessage(id: '1', role: ChatRole.user, content: '你好', timestamp: DateTime(2026)),
          ChatMessage(id: '2', role: ChatRole.assistant, content: '您好', timestamp: DateTime(2026)),
        ],
        serviceStatus: AiServiceStatus.ready,
      );
      final cleared = state.cleared();
      expect(cleared.messages, isEmpty);
      expect(cleared.serviceStatus, AiServiceStatus.ready);
      expect(cleared.loadingState, ChatLoadingState.idle);
    });

    test('multiple copyWith 调用保持不可变', () {
      const state = ChatState();
      final s1 = state.copyWith(loadingState: ChatLoadingState.loading);
      final s2 = state.copyWith(loadingState: ChatLoadingState.streaming);
      expect(s1.loadingState, ChatLoadingState.loading);
      expect(s2.loadingState, ChatLoadingState.streaming);
      expect(state.loadingState, ChatLoadingState.idle); // 原始未变
    });
  });

  group('ChatNotifier', () {
    test('初始状态为 proxyDown', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final state = container.read(chatProvider);
      expect(state.serviceStatus, AiServiceStatus.proxyDown);
    });

    test('clearChat 清空对话', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(chatProvider.notifier);

      // 先添加一些状态
      container.read(chatProvider.notifier);
      notifier.clearChat();

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
      expect(state.loadingState, ChatLoadingState.idle);
    });

    test('发送空消息不改变状态', () async {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(chatProvider.notifier);
      final beforeState = container.read(chatProvider);

      await notifier.sendMessage('');

      final afterState = container.read(chatProvider);
      expect(afterState.messages, beforeState.messages);
      expect(afterState.loadingState, beforeState.loadingState);
    });

    test('发送空白消息不改变状态', () async {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(chatProvider.notifier);

      await notifier.sendMessage('   ');

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
    });

    test('setService 可以注入测试服务', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(chatProvider.notifier);
      final testService = AiService(
        config: const AiConfig(baseUrl: 'http://test.local/v1'),
      );

      notifier.setService(testService);
      testService.dispose();
      // 没有异常即通过
    });
  });

  group('ChatLoadingState', () {
    test('所有状态值定义正确', () {
      expect(ChatLoadingState.values.length, 4);
      expect(ChatLoadingState.values, contains(ChatLoadingState.idle));
      expect(ChatLoadingState.values, contains(ChatLoadingState.loading));
      expect(ChatLoadingState.values, contains(ChatLoadingState.streaming));
      expect(ChatLoadingState.values, contains(ChatLoadingState.error));
    });
  });
}
