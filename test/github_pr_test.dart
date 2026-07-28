import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/git/models/github_pr.dart';

void main() {
  group('PullRequest', () {
    test('从 JSON 创建', () {
      final json = {
        'number': 42,
        'title': 'Fix bug',
        'body': 'This fixes the bug',
        'state': 'open',
        'user': {'login': 'testuser', 'avatar_url': 'https://example.com/avatar'},
        'head': {'ref': 'feature-branch'},
        'base': {'ref': 'main'},
        'created_at': '2024-01-15T10:00:00Z',
        'draft': false,
        'comments': 3,
        'commits': 5,
        'additions': 100,
        'deletions': 50,
        'changed_files': 10,
        'html_url': 'https://github.com/owner/repo/pull/42',
      };

      final pr = PullRequest.fromJson(json);
      expect(pr.number, 42);
      expect(pr.title, 'Fix bug');
      expect(pr.state, 'open');
      expect(pr.author, 'testuser');
      expect(pr.headBranch, 'feature-branch');
      expect(pr.baseBranch, 'main');
      expect(pr.isOpen, true);
      expect(pr.isClosed, false);
      expect(pr.isMerged, false);
      expect(pr.isDraft, false);
    });

    test('关闭的 PR', () {
      final json = {
        'number': 1,
        'title': 'Closed PR',
        'state': 'closed',
        'user': {'login': 'user'},
        'head': {'ref': 'branch'},
        'base': {'ref': 'main'},
      };

      final pr = PullRequest.fromJson(json);
      expect(pr.isOpen, false);
      expect(pr.isClosed, true);
    });

    test('Draft PR', () {
      final json = {
        'number': 2,
        'title': 'WIP',
        'state': 'open',
        'draft': true,
        'user': {'login': 'user'},
        'head': {'ref': 'branch'},
        'base': {'ref': 'main'},
      };

      final pr = PullRequest.fromJson(json);
      expect(pr.isDraft, true);
    });
  });

  group('GitHubIssue', () {
    test('从 JSON 创建', () {
      final json = {
        'number': 100,
        'title': 'Bug report',
        'body': 'Something is broken',
        'state': 'open',
        'user': {'login': 'issueuser', 'avatar_url': 'https://example.com/avatar'},
        'labels': [{'name': 'bug'}, {'name': 'critical'}],
        'created_at': '2024-02-20T10:00:00Z',
        'comments': 5,
        'html_url': 'https://github.com/owner/repo/issues/100',
      };

      final issue = GitHubIssue.fromJson(json);
      expect(issue.number, 100);
      expect(issue.title, 'Bug report');
      expect(issue.state, 'open');
      expect(issue.author, 'issueuser');
      expect(issue.labels, contains('bug'));
      expect(issue.labels, contains('critical'));
      expect(issue.isOpen, true);
      expect(issue.isPullRequest, false);
    });

    test('关闭的 Issue', () {
      final json = {
        'number': 200,
        'title': 'Closed issue',
        'state': 'closed',
        'user': {'login': 'user'},
      };

      final issue = GitHubIssue.fromJson(json);
      expect(issue.isOpen, false);
    });
  });

  group('GitHubComment', () {
    test('从 JSON 创建', () {
      final json = {
        'id': 12345,
        'body': 'This is a comment',
        'user': {'login': 'commenter', 'avatar_url': 'https://example.com/avatar'},
        'created_at': '2024-03-10T10:00:00Z',
      };

      final comment = GitHubComment.fromJson(json);
      expect(comment.id, 12345);
      expect(comment.body, 'This is a comment');
      expect(comment.author, 'commenter');
    });
  });
}
