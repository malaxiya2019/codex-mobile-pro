import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/log_service.dart';
import '../../../runtime/runtime_manager.dart';

import '../models/git_repository.dart';
import '../services/git_service.dart';
import '../services/github_service.dart';

// ── 单例服务 ──

/// 复用 RuntimeManager 共享 ProcessRunner（已注册 LinuxExecutionAdapter →
/// PRoot → Ubuntu rootfs /usr/bin/git），保证 GitHub 页面的 Git 操作
/// 与部署中心检测/安装走同一条执行链路，不再依赖 Android 宿主 PATH。
/// 若 RuntimeManager 未初始化（processRunner 为 null），GitService 回退到
/// 自建 LinuxExecutionAdapter，行为一致（未部署时明确提示部署 Linux Runtime）。
final gitServiceProvider = Provider<GitService>((ref) {
  final manager = RuntimeManager.instance;
  return GitService(
    runner: manager.processRunner,
    linux: manager.linuxProvider,
  );
});

final gitHubServiceProvider = Provider<GitHubService>((ref) => GitHubService());

// ── GitHub 认证状态 ──

class GitHubAuthState {
  final bool isLoggedIn;
  final String? username;
  final String? avatarUrl;
  final bool isLoading;
  final bool isRestoring;

  const GitHubAuthState({
    this.isLoggedIn = false,
    this.username,
    this.avatarUrl,
    this.isLoading = false,
    this.isRestoring = false,
  });

  GitHubAuthState copyWith({
    bool? isLoggedIn,
    String? username,
    String? avatarUrl,
    bool? isLoading,
    bool? isRestoring,
  }) {
    return GitHubAuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isLoading: isLoading ?? this.isLoading,
      isRestoring: isRestoring ?? this.isRestoring,
    );
  }
}

final gitHubAuthProvider =
    StateNotifierProvider<GitHubAuthNotifier, GitHubAuthState>((ref) {
  return GitHubAuthNotifier(ref.read(gitHubServiceProvider));
});

/// GitHub 认证 Notifier。
///
/// 构造时异步从 secure storage 恢复登录态（[isRestoring] 期间页面应显示加载中，
/// 不要判定「未登录」而弹登录页——这是旧版「重启后要求重新输入」的根因之一）。
class GitHubAuthNotifier extends StateNotifier<GitHubAuthState> {
  final GitHubService _service;

  GitHubAuthNotifier(this._service)
      : super(const GitHubAuthState(isRestoring: true)) {
    _init();
  }

  /// 从 secure storage 恢复登录态。
  ///
  /// 策略：
  /// 1. 有 token → 直接用已缓存用户信息恢复登录（`loadToken` 已加载 `github_user`），
  ///    绝不在网络失败时清除有效 token。
  /// 2. 无 token → 保持未登录。
  /// 只有 GitHub 明确 401（`_apiGet` 内部已 `clearToken`）才清登录态，见
  /// [_refreshUserInfo]。
  Future<void> _init() async {
    try {
      final hasToken = await _service.hasToken();
      if (hasToken) {
        final cachedUser = _service.userInfo;
        state = GitHubAuthState(
          isLoggedIn: true,
          username: cachedUser?['login'],
          avatarUrl: cachedUser?['avatar_url'],
        );
        // 后台刷新用户信息；结果不影响已恢复的登录态。
        unawaited(_refreshUserInfo());
      } else {
        state = const GitHubAuthState();
      }
    } catch (_) {
      LogService.warning('GitHubAuth', '登录状态恢复失败（不阻断）');
      state = const GitHubAuthState();
    }
  }

  /// 后台刷新 GitHub 用户信息。
  ///
  /// - 成功 → 更新用户名/头像。
  /// - 失败且 token 已被 service 判定失效（401 时已 `clearToken`）→ 清登录态。
  /// - 失败但 token 仍在（网络/5xx/限流）→ 保留已恢复的登录态，不误删 token。
  Future<void> _refreshUserInfo() async {
    final user = await _service.getUserInfo();
    if (!mounted) return;
    if (user != null) {
      state = GitHubAuthState(
        isLoggedIn: true,
        username: user['login'],
        avatarUrl: user['avatar_url'],
      );
    } else if (!_service.isLoggedIn) {
      // 仅当 service 已确认 token 失效（401 清除）才清除登录态
      state = const GitHubAuthState();
    }
  }

  Future<bool> loginWithToken(String token) async {
    state = state.copyWith(isLoading: true);
    final user = await _service.verifyToken(token);
    if (user != null) {
      state = GitHubAuthState(
        isLoggedIn: true,
        username: user['login'],
        avatarUrl: user['avatar_url'],
      );
      return true;
    } else {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  Future<void> logout() async {
    await _service.clearToken();
    state = const GitHubAuthState();
  }
}


// ── 仓库列表状态 ──

class RepoListState {
  final List<GitRepository> repos;
  final bool isLoading;
  final String? error;

  const RepoListState({
    this.repos = const [],
    this.isLoading = false,
    this.error,
  });

  RepoListState copyWith({
    List<GitRepository>? repos,
    bool? isLoading,
    String? error,
  }) {
    return RepoListState(
      repos: repos ?? this.repos,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final repoListProvider =
    StateNotifierProvider<RepoListNotifier, RepoListState>((ref) {
  return RepoListNotifier(ref.read(gitHubServiceProvider));
});

class RepoListNotifier extends StateNotifier<RepoListState> {
  final GitHubService _service;

  RepoListNotifier(this._service) : super(const RepoListState());

  Future<void> loadRepos({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(isLoading: true);
    try {
      final repos = await _service.getUserRepos();
      state = RepoListState(repos: repos);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载仓库列表失败: $e');
    }
  }
}

// ── Git 状态 Provider ──

class GitStatusState {
  final GitStatus? status;
  final bool isLoading;
  final String? error;

  const GitStatusState({this.status, this.isLoading = false, this.error});

  GitStatusState copyWith({
    GitStatus? status,
    bool? isLoading,
    String? error,
  }) {
    return GitStatusState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final gitStatusProvider =
    StateNotifierProvider.family<GitStatusNotifier, GitStatusState, String>(
  (ref, path) => GitStatusNotifier(ref.read(gitServiceProvider), path),
);

class GitStatusNotifier extends StateNotifier<GitStatusState> {
  final GitService _service;
  final String _path;

  GitStatusNotifier(this._service, this._path) : super(const GitStatusState());

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final status = await _service.status(_path);
      state = GitStatusState(status: status);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '获取状态失败: $e');
    }
  }

  Future<bool> stageCommitPush(String message) async {
    state = state.copyWith(isLoading: true);
    try {
      await _service.addAll(_path);
      final commitResult = await _service.commit(_path, message);
      if (!commitResult.success) {
        state = state.copyWith(isLoading: false, error: commitResult.error);
        return false;
      }
      await _service.push(_path);
      await refresh();
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }
}
