/// 工作区模板
enum WorkspaceTemplate {
  flutter('Flutter', '📱', '适合 Flutter/Dart 项目'),
  rust('Rust', '🦀', '适合 Rust 项目'),
  python('Python', '🐍', '适合 Python 项目'),
  learning('学习', '📚', '学习笔记和实验'),
  experiment('实验', '🧪', '临时项目和实验');

  final String name;
  final String icon;
  final String description;
  const WorkspaceTemplate(this.name, this.icon, this.description);
}

/// 项目引用
class ProjectRef {
  final String id;
  final String name;
  final String path;
  final DateTime createdAt;
  const ProjectRef({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'createdAt': createdAt.toIso8601String(),
  };
  factory ProjectRef.fromJson(Map<String, dynamic> json) => ProjectRef(
    id: json['id'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// 工作区
class Workspace {
  final String id;
  final String name;
  final WorkspaceTemplate template;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectRef> projects;
  const Workspace({
    required this.id,
    required this.name,
    required this.template,
    required this.createdAt,
    required this.updatedAt,
    this.projects = const [],
  });
  Workspace copyWith({
    String? name,
    WorkspaceTemplate? template,
    DateTime? updatedAt,
    List<ProjectRef>? projects,
  }) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      template: template ?? this.template,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      projects: projects ?? this.projects,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'template': template.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'projects': projects.map((p) => p.toJson()).toList(),
  };
  factory Workspace.fromJson(Map<String, dynamic> json) {
    // 查找匹配的模板
    WorkspaceTemplate tpl = WorkspaceTemplate.flutter;
    final tplName = json['template'] as String?;
    if (tplName != null) {
      for (final t in WorkspaceTemplate.values) {
        if (t.name == tplName) {
          tpl = t;
          break;
        }
      }
    }
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      template: tpl,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      projects:
          (json['projects'] as List<dynamic>?)
              ?.map((p) => ProjectRef.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
