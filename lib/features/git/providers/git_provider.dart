import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  const GitHubAuthState({
    this.isLoggedIn = false,
    this.username,
    this.avatarUrl,
    this.isLoading = false,
  });

  GitHubAuthState copyWith({
    bool? isLoggedIn,
    String? username,
    String? avatarUrl,
    bool? isLoading,
  }) {
    return GitHubAuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final gitHubAuthProvider =
    StateNotifierProvider<GitHubAuthNotifier, GitHubAuthState>((ref) {
  return GitHubAuthNotifier(ref.read(gitHubServiceProvider));
});

class GitHubAuthNotifier extends StateNotifier<GitHubAuthState> {
  final GitHubService _service;

  GitHubAuthNotifier(this._service) : super(const GitHubAuthState()) {
    _init();
  }

  Future<void> _init() async {
    final hasToken = await _service.hasToken();
    if (hasToken) {
      state = state.copyWith(isLoading: true);
      final user = await _service.getUserInfo();
      if (user != null) {
        state = GitHubAuthState(
          isLoggedIn: true,
          username: user['login'],
          avatarUrl: user['avatar_url'],
        );
      } else {
        await _service.clearToken();
        state = const GitHubAuthState();
      }
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
