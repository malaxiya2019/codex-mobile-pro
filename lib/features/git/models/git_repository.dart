/// Git 仓库模型
class GitRepository {
  final String id;
  final String name;
  final String fullName;
  final String? description;
  final String? url;
  final String? cloneUrl;
  final String? defaultBranch;
  final bool isPrivate;
  final String? owner;
  final String? ownerAvatarUrl;
  final DateTime? updatedAt;
  final int? starCount;
  final int? forkCount;
  final String? language;

  const GitRepository({
    required this.id,
    required this.name,
    required this.fullName,
    this.description,
    this.url,
    this.cloneUrl,
    this.defaultBranch,
    this.isPrivate = false,
    this.owner,
    this.ownerAvatarUrl,
    this.updatedAt,
    this.starCount,
    this.forkCount,
    this.language,
  });

  factory GitRepository.fromJson(Map<String, dynamic> json) {
    return GitRepository(
      id: (json['id'] ?? '').toString(),
      name: json['name'] ?? '',
      fullName: json['full_name'] ?? json['name'] ?? '',
      description: json['description'],
      url: json['html_url'],
      cloneUrl: json['clone_url'],
      defaultBranch: json['default_branch'],
      isPrivate: json['private'] == true,
      owner: json['owner']?['login'],
      ownerAvatarUrl: json['owner']?['avatar_url'],
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
      starCount: json['stargazers_count'],
      forkCount: json['forks_count'],
      language: json['language'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'full_name': fullName,
    'description': description,
    'html_url': url,
    'clone_url': cloneUrl,
    'default_branch': defaultBranch,
    'private': isPrivate,
    'owner': owner != null ? {'login': owner, 'avatar_url': ownerAvatarUrl} : null,
    'updated_at': updatedAt?.toIso8601String(),
    'stargazers_count': starCount,
    'forks_count': forkCount,
    'language': language,
  };
}

/// Git 分支
class GitBranch {
  final String name;
  final bool isCurrent;
  final String? commitSha;

  const GitBranch({
    required this.name,
    this.isCurrent = false,
    this.commitSha,
  });
}

/// Git 提交
class GitCommit {
  final String sha;
  final String message;
  final String author;
  final String? authorEmail;
  final DateTime? date;

  const GitCommit({
    required this.sha,
    required this.message,
    required this.author,
    this.authorEmail,
    this.date,
  });
}

/// Git 变更文件
class GitFileChange {
  final String path;
  final GitChangeType type;
  final int? additions;
  final int? deletions;

  const GitFileChange({
    required this.path,
    required this.type,
    this.additions,
    this.deletions,
  });
}

enum GitChangeType { added, modified, deleted, renamed, untracked }

/// Git 状态
class GitStatus {
  final String? currentBranch;
  final List<GitFileChange> changes;
  final int ahead;
  final int behind;
  final bool hasConflicts;

  const GitStatus({
    this.currentBranch,
    this.changes = const [],
    this.ahead = 0,
    this.behind = 0,
    this.hasConflicts = false,
  });

  bool get isClean => changes.isEmpty && ahead == 0 && behind == 0;

  int get addedCount => changes.where((c) => c.type == GitChangeType.added).length;
  int get modifiedCount => changes.where((c) => c.type == GitChangeType.modified).length;
  int get deletedCount => changes.where((c) => c.type == GitChangeType.deleted).length;
}
