import 'package:codex_mobile_pro/features/home/providers/counter_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CounterProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('初始值为 0', () {
      final count = container.read(counterProvider);
      expect(count, 0);
    });

    test('increment() 将值增加 1', () {
      container.read(counterProvider.notifier).increment();
      final count = container.read(counterProvider);
      expect(count, 1);
    });

    test('decrement() 将值减少 1', () {
      container.read(counterProvider.notifier).increment();
      container.read(counterProvider.notifier).increment();
      container.read(counterProvider.notifier).decrement();
      final count = container.read(counterProvider);
      expect(count, 1);
    });

    test('reset() 将值重置为 0', () {
      container.read(counterProvider.notifier).increment();
      container.read(counterProvider.notifier).increment();
      container.read(counterProvider.notifier).increment();
      container.read(counterProvider.notifier).reset();
      final count = container.read(counterProvider);
      expect(count, 0);
    });
  });
}
