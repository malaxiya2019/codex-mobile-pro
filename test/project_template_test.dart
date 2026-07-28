import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/project/models/project_template.dart';

void main() {
  group('ProjectTemplateType', () {
    test('包含 3 种类型', () {
      expect(ProjectTemplateType.values.length, 3);
    });

    test('Flutter 类型正确', () {
      expect(ProjectTemplateType.flutter.name, 'Flutter');
      expect(ProjectTemplateType.flutter.icon, '📱');
      expect(ProjectTemplateType.flutter.description, isNotEmpty);
    });

    test('Rust 类型正确', () {
      expect(ProjectTemplateType.rust.name, 'Rust');
      expect(ProjectTemplateType.rust.icon, '🦀');
    });

    test('Python 类型正确', () {
      expect(ProjectTemplateType.python.name, 'Python');
      expect(ProjectTemplateType.python.icon, '🐍');
    });
  });

  group('TemplateVersion', () {
    final version = TemplateVersion(
      version: '1.0.0',
      changelog: '初始版本',
      releaseDate: DateTime(2026, 7, 28),
    );

    test('构造正确', () {
      expect(version.version, '1.0.0');
      expect(version.changelog, '初始版本');
      expect(version.releaseDate, DateTime(2026, 7, 28));
    });

    test('JSON 序列化', () {
      final json = version.toJson();
      expect(json['version'], '1.0.0');
      expect(json['changelog'], '初始版本');

      final restored = TemplateVersion.fromJson(json);
      expect(restored.version, version.version);
      expect(restored.changelog, version.changelog);
    });
  });

  group('ProjectTemplate', () {
    final template = ProjectTemplate(
      id: 'flutter-default',
      type: ProjectTemplateType.flutter,
      name: 'Flutter 默认模板',
      description: '标准 Flutter 项目',
      icon: '📱',
      version: TemplateVersion(
        version: '1.0.0',
        releaseDate: DateTime(2026, 7, 28),
      ),
      requiredTools: ['flutter', 'dart'],
      generatedFiles: ['lib/main.dart', 'pubspec.yaml'],
      defaultConfig: {'org': 'com.example'},
    );

    test('构造正确', () {
      expect(template.id, 'flutter-default');
      expect(template.type, ProjectTemplateType.flutter);
      expect(template.name, 'Flutter 默认模板');
      expect(template.requiredTools, ['flutter', 'dart']);
      expect(template.generatedFiles.length, 2);
      expect(template.defaultConfig['org'], 'com.example');
    });

    test('JSON 序列化', () {
      final json = template.toJson();
      expect(json['id'], 'flutter-default');
      expect(json['type'], 'Flutter');
      expect(json['name'], 'Flutter 默认模板');
      expect(json['version'], isA<Map>());
      expect(json['requiredTools'], isA<List>());
      expect(json['generatedFiles'], isA<List>());
      expect(json['defaultConfig'], isA<Map>());
    });
  });

  group('ProjectCreateConfig', () {
    test('构造正确', () {
      final config = ProjectCreateConfig(
        name: 'MyApp',
        path: '/home/projects',
        type: ProjectTemplateType.flutter,
        options: {'org': 'com.myapp'},
      );

      expect(config.name, 'MyApp');
      expect(config.path, '/home/projects');
      expect(config.type, ProjectTemplateType.flutter);
      expect(config.options['org'], 'com.myapp');
    });

    test('空 options 默认空 Map', () {
      final config = ProjectCreateConfig(
        name: 'Test',
        path: '/tmp',
        type: ProjectTemplateType.rust,
      );
      expect(config.options, isEmpty);
    });
  });

  group('ProjectCreateResult', () {
    test('成功结果', () {
      final result = ProjectCreateResult(
        success: true,
        projectPath: '/home/projects/MyApp',
        exitCode: 0,
        stdout: 'Created project',
      );

      expect(result.success, true);
      expect(result.projectPath, '/home/projects/MyApp');
      expect(result.exitCode, 0);
      expect(result.stdout, 'Created project');
      expect(result.stderr, isNull);
    });

    test('失败结果', () {
      final result = ProjectCreateResult(
        success: false,
        projectPath: '/home/projects/MyApp',
        errorMessage: 'Flutter not found',
      );

      expect(result.success, false);
      expect(result.errorMessage, 'Flutter not found');
    });
  });

  group('ProjectInfo', () {
    final now = DateTime(2026, 7, 28);
    final info = ProjectInfo(
      name: 'MyApp',
      path: '/home/projects/MyApp',
      type: ProjectTemplateType.flutter,
      createdAt: now,
      initialized: true,
    );

    test('构造正确', () {
      expect(info.name, 'MyApp');
      expect(info.path, '/home/projects/MyApp');
      expect(info.type, ProjectTemplateType.flutter);
      expect(info.initialized, true);
    });

    test('JSON 序列化', () {
      final json = info.toJson();
      expect(json['name'], 'MyApp');
      expect(json['type'], 'Flutter');

      final restored = ProjectInfo.fromJson(json);
      expect(restored.name, info.name);
      expect(restored.path, info.path);
      expect(restored.type, info.type);
      expect(restored.initialized, info.initialized);
    });

    test('未知类型回退到 Flutter', () {
      final json = {
        'name': 'Test',
        'path': '/tmp/test',
        'type': 'UnknownLang',
        'createdAt': now.toIso8601String(),
        'initialized': false,
      };
      final restored = ProjectInfo.fromJson(json);
      expect(restored.type, ProjectTemplateType.flutter);
    });
  });
}
