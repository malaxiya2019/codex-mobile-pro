import 'package:codex_mobile_pro/features/git/models/git_repository.dart';
import 'package:codex_mobile_pro/features/git/services/git_service.dart';
import 'package:codex_mobile_pro/features/git/services/github_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitResult', () {
    test('创建成功结果', () {
      const result = GitResult(success: true, output: 'ok');
      expect(result.success, true);
      expect(result.output, 'ok');
      expect(result.exitCode, 0);
    });

    test('创建失败结果', () {
      const result = GitResult(success: false, error: 'error msg', exitCode: 1);
      expect(result.success, false);
      expect(result.error, 'error msg');
      expect(result.exitCode, 1);
    });
  });

  group('GitRepository', () {
    test('从 JSON 创建', () {
      final repo = GitRepository.fromJson({
        'id': 123456,
        'name': 'test-repo',
        'full_name': 'user/test-repo',
        'description': 'A test repository',
        'html_url': 'https://github.com/user/test-repo',
        'clone_url': 'https://github.com/user/test-repo.git',
        'default_branch': 'main',
        'private': false,
        'owner': {'login': 'user', 'avatar_url': 'https://avatars.githubusercontent.com/u/1?v=4'},
        'updated_at': '2026-07-28T10:00:00Z',
        'stargazers_count': 10,
        'forks_count': 5,
        'language': 'Dart',
      });

      expect(repo.name, 'test-repo');
      expect(repo.fullName, 'user/test-repo');
      expect(repo.description, 'A test repository');
      expect(repo.isPrivate, false);
      expect(repo.owner, 'user');
      expect(repo.starCount, 10);
      expect(repo.forkCount, 5);
      expect(repo.language, 'Dart');
    });

    test('JSON 缺少字段时使用默认值', () {
      final repo = GitRepository.fromJson({
        'id': 1,
        'name': 'repo',
      });

      expect(repo.name, 'repo');
      expect(repo.fullName, 'repo');
      expect(repo.isPrivate, false);
      expect(repo.description, isNull);
      expect(repo.starCount, isNull);
    });

    test('toJson 序列化', () {
      const repo = GitRepository(
        id: '1',
        name: 'test',
        fullName: 'user/test',
        description: 'desc',
        isPrivate: true,
        owner: 'user',
        cloneUrl: 'https://github.com/user/test.git',
        starCount: 5,
        language: 'Rust',
      );

      final json = repo.toJson();
      expect(json['name'], 'test');
      expect(json['private'], true);
      expect(json['language'], 'Rust');
    });
  });

  group('GitStatus', () {
    test('干净工作区', () {
      const status = GitStatus(currentBranch: 'main');
      expect(status.isClean, true);
      expect(status.currentBranch, 'main');
      expect(status.changes, isEmpty);
    });

    test('有变更的工作区', () {
      const status = GitStatus(
        currentBranch: 'dev',
        changes: [
          GitFileChange(path: 'file1.dart', type: GitChangeType.modified),
          GitFileChange(path: 'file2.dart', type: GitChangeType.added),
          GitFileChange(path: 'file3.dart', type: GitChangeType.deleted),
        ],
        ahead: 2,
        behind: 1,
      );

      expect(status.isClean, false);
      expect(status.modifiedCount, 1);
      expect(status.addedCount, 1);
      expect(status.deletedCount, 1);
      expect(status.ahead, 2);
      expect(status.behind, 1);
    });

    test('变更计数', () {
      const status = GitStatus(
        changes: [
          GitFileChange(path: 'a.dart', type: GitChangeType.added),
          GitFileChange(path: 'b.dart', type: GitChangeType.modified),
          GitFileChange(path: 'c.dart', type: GitChangeType.deleted),
          GitFileChange(path: 'd.dart', type: GitChangeType.renamed),
          GitFileChange(path: 'e.dart', type: GitChangeType.untracked),
        ],
      );

      expect(status.addedCount, 1);
      expect(status.modifiedCount, 1);
      expect(status.deletedCount, 1);
      expect(status.changes.length, 5);
    });
  });

  group('GitCommit', () {
    test('创建提交', () {
      const commit = GitCommit(
        sha: 'abc1234',
        message: 'Fix bug',
        author: 'Dev',
        authorEmail: 'dev@example.com',
      );

      expect(commit.sha, 'abc1234');
      expect(commit.message, 'Fix bug');
      expect(commit.author, 'Dev');
    });
  });

  group('GitBranch', () {
    test('创建分支', () {
      const branch = GitBranch(name: 'feature-x', isCurrent: true);
      expect(branch.name, 'feature-x');
      expect(branch.isCurrent, true);
    });

    test('非当前分支', () {
      const branch = GitBranch(name: 'main');
      expect(branch.isCurrent, false);
    });
  });

  group('GitHubService', () {
    test('初始未登录', () {
      final service = GitHubService();
      expect(service.isLoggedIn, false);
      expect(service.username, isNull);
    });

    test('Token 管理', () async {
      final service = GitHubService();
      expect(service.isLoggedIn, false);

      await service.saveToken('test_token');
      // 内存中
      expect(service.isLoggedIn, true);
    });

    test('Token 清除', () async {
      final service = GitHubService();
      await service.saveToken('test_token');
      expect(service.isLoggedIn, true);

      await service.clearToken();
      expect(service.isLoggedIn, false);
      expect(service.username, isNull);
    });

    test('无效 Token 验证返回 null', () async {
      final service = GitHubService();
      final result = await service.verifyToken('invalid_token_xxx');
      // 网络请求会失败，返回 null
      expect(result, isNull);
    });
  });

  group('GitService', () {
    test('GitService 可创建', () {
      final service = GitService();
      expect(service, isNotNull);
    });
  });
}
