import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/github_pr.dart';
import '../services/github_service.dart';
import 'git_provider.dart';

// ── PR 列表状态 ──

class PrListState {
  final List<PullRequest> prs;
  final bool isLoading;
  final String? error;
  final String filterState; // 'open', 'closed', 'all'

  const PrListState({
    this.prs = const [],
    this.isLoading = false,
    this.error,
    this.filterState = 'open',
  });

  PrListState copyWith({
    List<PullRequest>? prs,
    bool? isLoading,
    String? error,
    String? filterState,
  }) {
    return PrListState(
      prs: prs ?? this.prs,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      filterState: filterState ?? this.filterState,
    );
  }
}

final prListProvider =
    StateNotifierProvider.family<PrListNotifier, PrListState, String>(
  (ref, repoFullName) => PrListNotifier(
    ref.read(gitHubServiceProvider),
    repoFullName,
  ),
);

class PrListNotifier extends StateNotifier<PrListState> {
  final GitHubService _service;
  final String _repoFullName;

  PrListNotifier(this._service, this._repoFullName)
      : super(const PrListState());

  String get _owner => _repoFullName.split('/')[0];
  String get _repo => _repoFullName.split('/')[1];

  Future<void> loadPrs({String filterBy = "open"}) async {
    state = state.copyWith(isLoading: true, error: null, filterState: filterBy);
    try {
      final prs = await _service.getPullRequests(_owner, _repo, state: filterBy);
      state = PrListState(prs: prs, filterState: filterBy);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载 PR 列表失败: $e');
    }
  }
}

// ── PR 详情状态 ──

class PrDetailState {
  final PullRequest? pr;
  final List<GitHubComment> comments;
  final bool isLoading;
  final String? error;

  const PrDetailState({
    this.pr,
    this.comments = const [],
    this.isLoading = false,
    this.error,
  });

  PrDetailState copyWith({
    PullRequest? pr,
    List<GitHubComment>? comments,
    bool? isLoading,
    String? error,
  }) {
    return PrDetailState(
      pr: pr ?? this.pr,
      comments: comments ?? this.comments,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final prDetailProvider =
    StateNotifierProvider.family<PrDetailNotifier, PrDetailState, String>(
  (ref, param) {
    final parts = param.split('/');
    final repoFullName = '${parts[0]}/${parts[1]}';
    final prNumber = int.parse(parts[2]);
    return PrDetailNotifier(
      ref.read(gitHubServiceProvider),
      repoFullName,
      prNumber,
    );
  },
);

class PrDetailNotifier extends StateNotifier<PrDetailState> {
  final GitHubService _service;
  final String _repoFullName;
  final int _prNumber;

  PrDetailNotifier(this._service, this._repoFullName, this._prNumber)
      : super(const PrDetailState());

  String get _owner => _repoFullName.split('/')[0];
  String get _repo => _repoFullName.split('/')[1];

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pr = await _service.getPullRequest(_owner, _repo, _prNumber);
      final comments =
          await _service.getPullRequestComments(_owner, _repo, _prNumber);
      state = PrDetailState(pr: pr, comments: comments);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载 PR 详情失败: $e');
    }
  }
}
