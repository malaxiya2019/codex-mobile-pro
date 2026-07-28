import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/logger/log_service.dart';
import '../../../core/ai/ai_provider.dart';
import '../services/git_service.dart';
import '../services/github_service.dart';
import '../models/git_repository.dart';
import '../models/github_pr.dart';

/// Git 工作流操作结果
class WorkflowResult {
  final bool success;
  final String? message;
  final Map<String, dynamic>? data;

  const WorkflowResult({
    this.success = false,
    this.message,
    this.data,
  });
}

/// Git 工作流 Provider
///
/// 统一管理 Git 工作流操作：
/// - Commit & Push
/// - Create & Merge PR
/// - Create Issue
/// - Review PR
///
/// 支持 Provider 化接入不同 Git 后端。
final gitWorkflowProvider = Provider<GitWorkflowProvider>((ref) {
  final gitService = ref.read(gitServiceProvider);
  final githubService = ref.read(gitHubServiceProvider);
  return GitWorkflowProvider(
    gitService: gitService,
    githubService: githubService,
  );
});

class GitWorkflowProvider {
  final GitService _gitService;
  final GitHubService _githubService;
  AiProvider? _aiProvider;

  GitWorkflowProvider({
    required GitService gitService,
    required GitHubService githubService,
    AiProvider? aiProvider,
  })  : _gitService = gitService,
        _githubService = githubService,
        _aiProvider = aiProvider;

  /// 设置 AI Provider（用于 Review PR）
  void setAiProvider(AiProvider? provider) {
    _aiProvider = provider;
  }

  /// 是否已登录 GitHub
  bool get isLoggedIn => _githubService.isLoggedIn;

  // ══════════════════════════════════════════════════
  //  Commit & Push
  // ══════════════════════════════════════════════════

  /// 执行 git commit
  Future<WorkflowResult> commit({
    required String repoPath,
    required String message,
    List<String>? files,
    bool amend = false,
  }) async {
    try {
      // 检查是否有变更
      final result = await _gitService.execute(
        repoPath,
        ['status', '--porcelain'],
      );
      if (result.exitCode != 0) {
        return WorkflowResult(success: false, message: '无法获取 Git 状态');
      }
      if (result.stdout.trim().isEmpty) {
        return WorkflowResult(success: false, message: '没有需要提交的变更');
      }

      // git add
      if (files != null && files.isNotEmpty) {
        for (final file in files) {
          await _gitService.execute(repoPath, ['add', file]);
        }
      } else {
        await _gitService.execute(repoPath, ['add', '-A']);
      }

      // git commit
      final commitArgs = ['commit', '-m', message];
      if (amend) commitArgs.add('--amend');
      final commitResult = await _gitService.execute(repoPath, commitArgs);

      if (commitResult.exitCode != 0) {
        return WorkflowResult(
          success: false,
          message: 'Commit 失败: ${commitResult.stderr}',
        );
      }

      // 解析 commit SHA
      final shaResult = await _gitService.execute(
        repoPath,
        ['rev-parse', 'HEAD'],
      );
      final sha = shaResult.stdout.trim();

      return WorkflowResult(
        success: true,
        message: '提交成功',
        data: {'sha': sha},
      );
    } catch (e) {
      return WorkflowResult(success: false, message: 'Commit 异常: $e');
    }
  }

  /// 执行 git push
  Future<WorkflowResult> push({
    required String repoPath,
    String remote = 'origin',
    String? branch,
  }) async {
    try {
      // 获取当前分支
      if (branch == null) {
        final result = await _gitService.execute(
          repoPath,
          ['rev-parse', '--abbrev-ref', 'HEAD'],
        );
        branch = result.stdout.trim();
      }

      final result = await _gitService.execute(
        repoPath,
        ['push', remote, branch],
      );

      if (result.exitCode != 0) {
        return WorkflowResult(
          success: false,
          message: 'Push 失败: ${result.stderr}',
        );
      }

      return WorkflowResult(success: true, message: '推送成功到 $remote/$branch');
    } catch (e) {
      return WorkflowResult(success: false, message: 'Push 异常: $e');
    }
  }

  /// Commit + Push 组合
  Future<WorkflowResult> commitAndPush({
    required String repoPath,
    required String message,
    List<String>? files,
    String remote = 'origin',
    String? branch,
  }) async {
    final commitResult = await commit(
      repoPath: repoPath,
      message: message,
      files: files,
    );
    if (!commitResult.success) return commitResult;

    return push(
      repoPath: repoPath,
      remote: remote,
      branch: branch,
    );
  }

  // ══════════════════════════════════════════════════
  //  Pull Request
  // ══════════════════════════════════════════════════

  /// 创建 Pull Request
  Future<WorkflowResult> createPullRequest({
    required String owner,
    required String repo,
    required String title,
    required String head,
    required String base,
    String? body,
    bool draft = false,
  }) async {
    try {
      if (!_githubService.isLoggedIn) {
        return const WorkflowResult(success: false, message: '请先登录 GitHub');
      }

      final payload = {
        'title': title,
        'head': head,
        'base': base,
        'body': body ?? '',
        'draft': draft,
      };

      final response = await _githubApiPost(
        '/repos/$owner/$repo/pulls',
        payload,
      );

      if (response == null) {
        return const WorkflowResult(success: false, message: '创建 PR 失败');
      }

      return WorkflowResult(
        success: true,
        message: 'PR #${response['number']} 创建成功',
        data: {'number': response['number'], 'html_url': response['html_url']},
      );
    } catch (e) {
      return WorkflowResult(success: false, message: '创建 PR 异常: $e');
    }
  }

  /// 合并 Pull Request
  Future<WorkflowResult> mergePullRequest({
    required String owner,
    required String repo,
    required int number,
    String method = 'merge',
    String? commitTitle,
  }) async {
    try {
      if (!_githubService.isLoggedIn) {
        return const WorkflowResult(success: false, message: '请先登录 GitHub');
      }

      final payload = <String, dynamic>{
        'merge_method': method,
      };
      if (commitTitle != null) payload['commit_title'] = commitTitle;

      final response = await _githubApiPut(
        '/repos/$owner/$repo/pulls/$number/merge',
        payload,
      );

      if (response == null) {
        return const WorkflowResult(success: false, message: '合并 PR 失败');
      }

      return WorkflowResult(
        success: true,
        message: 'PR #$number 已合并',
        data: {'sha': response['sha']},
      );
    } catch (e) {
      return WorkflowResult(success: false, message: '合并 PR 异常: $e');
    }
  }

  /// 获取 PR 列表
  Future<List<PullRequest>> getPullRequests({
    required String owner,
    required String repo,
    String state = 'open',
  }) async {
    if (!_githubService.isLoggedIn) return [];
    return _githubService.getPullRequests(owner, repo, state: state);
  }

  /// 获取 PR 详情
  Future<PullRequest?> getPullRequest(String owner, String repo, int number) async {
    if (!_githubService.isLoggedIn) return null;
    return _githubService.getPullRequest(owner, repo, number);
  }

  // ══════════════════════════════════════════════════
  //  Issue
  // ══════════════════════════════════════════════════

  /// 创建 Issue
  Future<WorkflowResult> createIssue({
    required String owner,
    required String repo,
    required String title,
    String? body,
    List<String>? labels,
    List<String>? assignees,
  }) async {
    try {
      if (!_githubService.isLoggedIn) {
        return const WorkflowResult(success: false, message: '请先登录 GitHub');
      }

      final payload = <String, dynamic>{
        'title': title,
        'body': body ?? '',
      };
      if (labels != null && labels.isNotEmpty) payload['labels'] = labels;
      if (assignees != null && assignees.isNotEmpty) payload['assignees'] = assignees;

      final response = await _githubApiPost(
        '/repos/$owner/$repo/issues',
        payload,
      );

      if (response == null) {
        return const WorkflowResult(success: false, message: '创建 Issue 失败');
      }

      return WorkflowResult(
        success: true,
        message: 'Issue #${response['number']} 创建成功',
        data: {'number': response['number'], 'html_url': response['html_url']},
      );
    } catch (e) {
      return WorkflowResult(success: false, message: '创建 Issue 异常: $e');
    }
  }

  /// 获取 Issue 列表
  Future<List<GitHubIssue>> getIssues({
    required String owner,
    required String repo,
    String state = 'open',
  }) async {
    if (!_githubService.isLoggedIn) return [];
    return _githubService.getIssues(owner, repo, state: state);
  }

  // ══════════════════════════════════════════════════
  //  Review
  // ══════════════════════════════════════════════════

  /// 提交 PR Review
  Future<WorkflowResult> reviewPullRequest({
    required String owner,
    required String repo,
    required int number,
    required String body,
    required String event, // 'APPROVE', 'REQUEST_CHANGES', 'COMMENT'
  }) async {
    try {
      if (!_githubService.isLoggedIn) {
        return const WorkflowResult(success: false, message: '请先登录 GitHub');
      }

      final payload = {
        'body': body,
        'event': event,
      };

      final response = await _githubApiPost(
        '/repos/$owner/$repo/pulls/$number/reviews',
        payload,
      );

      if (response == null) {
        return const WorkflowResult(success: false, message: '提交 Review 失败');
      }

      return WorkflowResult(success: true, message: 'Review 已提交');
    } catch (e) {
      return WorkflowResult(success: false, message: 'Review 异常: $e');
    }
  }

  // ══════════════════════════════════════════════════
  //  内部
  // ══════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _githubApiPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (!_githubService.isLoggedIn) return null;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(
        Uri.parse('https://api.github.com$path'),
      );
      final token = _githubService.accessToken;
      if (token == null) return null;
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'CodexMobilePro/1.0');
      request.write(jsonEncode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }
      LogService.warning('GitHub', 'POST $path 失败: ${response.statusCode}');
      return null;
    } catch (e) {
      LogService.error('GitHub', 'POST $path 异常: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _githubApiPut(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (!_githubService.isLoggedIn) return null;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.putUrl(
        Uri.parse('https://api.github.com$path'),
      );
      final token = _githubService.accessToken;
      if (token == null) return null;
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'CodexMobilePro/1.0');
      request.write(jsonEncode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }
      LogService.warning('GitHub', 'PUT $path 失败: ${response.statusCode}');
      return null;
    } catch (e) {
      LogService.error('GitHub', 'PUT $path 异常: $e');
      return null;
    }
  }
}


