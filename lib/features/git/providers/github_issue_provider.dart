import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/github_pr.dart';
import '../services/github_service.dart';
import 'git_provider.dart';

// ── Issue 列表状态 ──

class IssueListState {
  final List<GitHubIssue> issues;
  final bool isLoading;
  final String? error;
  final String filterState; // 'open', 'closed', 'all'

  const IssueListState({
    this.issues = const [],
    this.isLoading = false,
    this.error,
    this.filterState = 'open',
  });

  IssueListState copyWith({
    List<GitHubIssue>? issues,
    bool? isLoading,
    String? error,
    String? filterState,
  }) {
    return IssueListState(
      issues: issues ?? this.issues,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      filterState: filterState ?? this.filterState,
    );
  }
}

final issueListProvider =
    StateNotifierProvider.family<IssueListNotifier, IssueListState, String>(
  (ref, repoFullName) => IssueListNotifier(
    ref.read(gitHubServiceProvider),
    repoFullName,
  ),
);

class IssueListNotifier extends StateNotifier<IssueListState> {
  final GitHubService _service;
  final String _repoFullName;

  IssueListNotifier(this._service, this._repoFullName)
      : super(const IssueListState());

  String get _owner => _repoFullName.split('/')[0];
  String get _repo => _repoFullName.split('/')[1];

  Future<void> loadIssues({String state = 'open'}) async {
    state = state.copyWith(isLoading: true, error: null, filterState: state);
    try {
      final issues = await _service.getIssues(_owner, _repo, state: state);
      state = IssueListState(issues: issues, filterState: state);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载 Issue 列表失败: $e');
    }
  }
}

// ── Issue 详情状态 ──

class IssueDetailState {
  final GitHubIssue? issue;
  final List<GitHubComment> comments;
  final bool isLoading;
  final String? error;

  const IssueDetailState({
    this.issue,
    this.comments = const [],
    this.isLoading = false,
    this.error,
  });

  IssueDetailState copyWith({
    GitHubIssue? issue,
    List<GitHubComment>? comments,
    bool? isLoading,
    String? error,
  }) {
    return IssueDetailState(
      issue: issue ?? this.issue,
      comments: comments ?? this.comments,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final issueDetailProvider =
    StateNotifierProvider.family<IssueDetailNotifier, IssueDetailState, String>(
  (ref, param) {
    final parts = param.split('/');
    final repoFullName = '${parts[0]}/${parts[1]}';
    final issueNumber = int.parse(parts[2]);
    return IssueDetailNotifier(
      ref.read(gitHubServiceProvider),
      repoFullName,
      issueNumber,
    );
  },
);

class IssueDetailNotifier extends StateNotifier<IssueDetailState> {
  final GitHubService _service;
  final String _repoFullName;
  final int _issueNumber;

  IssueDetailNotifier(this._service, this._repoFullName, this._issueNumber)
      : super(const IssueDetailState());

  String get _owner => _repoFullName.split('/')[0];
  String get _repo => _repoFullName.split('/')[1];

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final issue = await _service.getIssue(_owner, _repo, _issueNumber);
      final comments =
          await _service.getIssueComments(_owner, _repo, _issueNumber);
      state = IssueDetailState(issue: issue, comments: comments);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载 Issue 详情失败: $e');
    }
  }
}
