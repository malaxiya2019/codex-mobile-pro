import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod 集成演示 Provider
///
/// 一个简单的计数器，用于验证 Riverpod 状态管理正常工作。
/// Sprint 2 将替换为正式的首页状态管理。
final counterProvider = StateNotifierProvider<CounterNotifier, int>((ref) {
  return CounterNotifier();
});

class CounterNotifier extends StateNotifier<int> {
  CounterNotifier() : super(0);

  void increment() => state++;
  void decrement() => state--;
  void reset() => state = 0;
}
