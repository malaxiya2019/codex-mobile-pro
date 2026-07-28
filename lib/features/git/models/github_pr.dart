/// Pull Request 模型
class PullRequest {
  final int number;
  final String title;
  final String body;
  final String state; // 'open', 'closed', 'merged'
  final String author;
  final String? authorAvatarUrl;
  final String headBranch;
  final String baseBranch;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isDraft;
  final int commentCount;
  final int commitCount;
  final int additions;
  final int deletions;
  final int changedFiles;
  final String? htmlUrl;

  const PullRequest({
    required this.number,
    required this.title,
    this.body = '',
    this.state = 'open',
    required this.author,
    this.authorAvatarUrl,
    required this.headBranch,
    required this.baseBranch,
    this.createdAt,
    this.updatedAt,
    this.isDraft = false,
    this.commentCount = 0,
    this.commitCount = 0,
    this.additions = 0,
    this.deletions = 0,
    this.changedFiles = 0,
    this.htmlUrl,
  });

  bool get isOpen => state == 'open';
  bool get isClosed => state == 'closed';
  bool get isMerged => state == 'merged';

  factory PullRequest.fromJson(Map<String, dynamic> json) {
    return PullRequest(
      number: json['number'] ?? 0,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      state: json['state'] ?? 'open',
      author: json['user']?['login'] ?? '',
      authorAvatarUrl: json['user']?['avatar_url'],
      headBranch: json['head']?['ref'] ?? '',
      baseBranch: json['base']?['ref'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
      isDraft: json['draft'] == true,
      commentCount: json['comments'] ?? 0,
      commitCount: json['commits'] ?? 0,
      additions: json['additions'] ?? 0,
      deletions: json['deletions'] ?? 0,
      changedFiles: json['changed_files'] ?? 0,
      htmlUrl: json['html_url'],
    );
  }
}

/// Issue 模型
class GitHubIssue {
  final int number;
  final String title;
  final String body;
  final String state; // 'open', 'closed'
  final String author;
  final String? authorAvatarUrl;
  final List<String> labels;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;
  final int commentCount;
  final bool isPullRequest;
  final String? htmlUrl;

  const GitHubIssue({
    required this.number,
    required this.title,
    this.body = '',
    this.state = 'open',
    required this.author,
    this.authorAvatarUrl,
    this.labels = const [],
    this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.commentCount = 0,
    this.isPullRequest = false,
    this.htmlUrl,
  });

  bool get isOpen => state == 'open';

  factory GitHubIssue.fromJson(Map<String, dynamic> json) {
    final labelsList = (json['labels'] as List<dynamic>?)
            ?.map((l) => l is Map ? (l['name'] ?? '').toString() : l.toString())
            .toList() ??
        [];

    return GitHubIssue(
      number: json['number'] ?? 0,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      state: json['state'] ?? 'open',
      author: json['user']?['login'] ?? '',
      authorAvatarUrl: json['user']?['avatar_url'],
      labels: labelsList,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
      closedAt: json['closed_at'] != null
          ? DateTime.tryParse(json['closed_at'])
          : null,
      commentCount: json['comments'] ?? 0,
      isPullRequest: json['pull_request'] != null,
      htmlUrl: json['html_url'],
    );
  }
}

/// PR/Issue 评论
class GitHubComment {
  final int id;
  final String body;
  final String author;
  final String? authorAvatarUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const GitHubComment({
    required this.id,
    this.body = '',
    required this.author,
    this.authorAvatarUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory GitHubComment.fromJson(Map<String, dynamic> json) {
    return GitHubComment(
      id: json['id'] ?? 0,
      body: json['body'] ?? '',
      author: json['user']?['login'] ?? '',
      authorAvatarUrl: json['user']?['avatar_url'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }
}
