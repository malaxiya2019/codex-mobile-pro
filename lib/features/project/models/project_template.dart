/// 项目模板类型
enum ProjectTemplateType {
  flutter('Flutter', '📱', 'Flutter/Dart 项目'),
  rust('Rust', '🦀', 'Rust 项目'),
  python('Python', '🐍', 'Python 项目');

  final String name;
  final String icon;
  final String description;

  const ProjectTemplateType(this.name, this.icon, this.description);
}

/// 项目模板版本信息
class TemplateVersion {
  final String version;
  final String? changelog;
  final DateTime releaseDate;

  const TemplateVersion({
    required this.version,
    this.changelog,
    required this.releaseDate,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'changelog': changelog,
    'releaseDate': releaseDate.toIso8601String(),
  };

  factory TemplateVersion.fromJson(Map<String, dynamic> json) =>
      TemplateVersion(
        version: json['version'] as String,
        changelog: json['changelog'] as String?,
        releaseDate: DateTime.parse(json['releaseDate'] as String),
      );
}

/// 项目模板
class ProjectTemplate {
  final String id;
  final ProjectTemplateType type;
  final String name;
  final String description;
  final String icon;
  final TemplateVersion version;
  final List<String> requiredTools;
  final List<String> generatedFiles;
  final Map<String, String> defaultConfig;

  const ProjectTemplate({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    required this.version,
    this.requiredTools = const [],
    this.generatedFiles = const [],
    this.defaultConfig = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'description': description,
    'icon': icon,
    'version': version.toJson(),
    'requiredTools': requiredTools,
    'generatedFiles': generatedFiles,
    'defaultConfig': defaultConfig,
  };
}

/// 项目创建配置
class ProjectCreateConfig {
  final String name;
  final String path;
  final ProjectTemplateType type;
  final Map<String, String> options;

  const ProjectCreateConfig({
    required this.name,
    required this.path,
    required this.type,
    this.options = const {},
  });
}

/// 项目创建结果
class ProjectCreateResult {
  final bool success;
  final String projectPath;
  final String? errorMessage;
  final int? exitCode;
  final String? stdout;
  final String? stderr;

  const ProjectCreateResult({
    required this.success,
    required this.projectPath,
    this.errorMessage,
    this.exitCode,
    this.stdout,
    this.stderr,
  });
}

/// 项目信息
class ProjectInfo {
  final String name;
  final String path;
  final ProjectTemplateType type;
  final DateTime createdAt;
  final bool initialized;

  const ProjectInfo({
    required this.name,
    required this.path,
    required this.type,
    required this.createdAt,
    this.initialized = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'type': type.name,
    'createdAt': createdAt.toIso8601String(),
    'initialized': initialized,
  };

  factory ProjectInfo.fromJson(Map<String, dynamic> json) => ProjectInfo(
    name: json['name'] as String,
    path: json['path'] as String,
    type: _parseType(json['type'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    initialized: json['initialized'] as bool? ?? false,
  );

  static ProjectTemplateType _parseType(String name) {
    for (final t in ProjectTemplateType.values) {
      if (t.name == name) return t;
    }
    return ProjectTemplateType.flutter;
  }
}
