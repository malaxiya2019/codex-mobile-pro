import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页状态
///
/// Sprint 2 将扩展为完整的状态模型。
class HomeState {
  final bool isInitialized;
  final String appVersion;
  final String? currentWorkspace;

  const HomeState({
    this.isInitialized = false,
    this.appVersion = '1.0.0',
    this.currentWorkspace,
  });

  HomeState copyWith({
    bool? isInitialized,
    String? appVersion,
    String? currentWorkspace,
  }) {
    return HomeState(
      isInitialized: isInitialized ?? this.isInitialized,
      appVersion: appVersion ?? this.appVersion,
      currentWorkspace: currentWorkspace ?? this.currentWorkspace,
    );
  }
}

/// 首页状态 Provider
final homeStateProvider = StateNotifierProvider<HomeStateNotifier, HomeState>(
  (ref) => HomeStateNotifier(),
);

class HomeStateNotifier extends StateNotifier<HomeState> {
  HomeStateNotifier() : super(const HomeState());

  /// 标记初始化完成
  void markInitialized() {
    state = state.copyWith(isInitialized: true);
  }

  /// 设置当前工作区
  void setWorkspace(String name) {
    state = state.copyWith(currentWorkspace: name);
  }
}
