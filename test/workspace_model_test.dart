import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/workspace/workspace_model.dart';

void main() {
  group('WorkspaceTemplate', () {
    test('所有模板都有名称', () {
      for (final tpl in WorkspaceTemplate.values) {
        expect(tpl.name, isNotEmpty);
        expect(tpl.icon, isNotEmpty);
        expect(tpl.description, isNotEmpty);
      }
    });

    test('包含 5 种模板', () {
      expect(WorkspaceTemplate.values.length, 5);
    });

    test('Flutter 模板正确', () {
      expect(WorkspaceTemplate.flutter.name, 'Flutter');
      expect(WorkspaceTemplate.flutter.icon, '📱');
    });

    test('Rust 模板正确', () {
      expect(WorkspaceTemplate.rust.name, 'Rust');
      expect(WorkspaceTemplate.rust.icon, '🦀');
    });

    test('Python 模板正确', () {
      expect(WorkspaceTemplate.python.name, 'Python');
      expect(WorkspaceTemplate.python.icon, '🐍');
    });
  });

  group('ProjectRef', () {
    final now = DateTime(2026, 7, 28, 10, 0);
    final project = ProjectRef(
      id: 'proj-1',
      name: 'MyApp',
      path: '/home/projects/myapp',
      createdAt: now,
    );

    test('构造正确', () {
      expect(project.id, 'proj-1');
      expect(project.name, 'MyApp');
      expect(project.path, '/home/projects/myapp');
      expect(project.createdAt, now);
    });

    test('序列化为 JSON', () {
      final json = project.toJson();
      expect(json['id'], 'proj-1');
      expect(json['name'], 'MyApp');
      expect(json['path'], '/home/projects/myapp');
      expect(json['createdAt'], now.toIso8601String());
    });

    test('从 JSON 反序列化', () {
      final json = project.toJson();
      final restored = ProjectRef.fromJson(json);
      expect(restored.id, project.id);
      expect(restored.name, project.name);
      expect(restored.path, project.path);
      expect(restored.createdAt, project.createdAt);
    });
  });

  group('Workspace', () {
    final now = DateTime(2026, 7, 28, 10, 0);
    final later = DateTime(2026, 7, 28, 11, 0);

    final workspace = Workspace(
      id: 'ws-1',
      name: '测试工作区',
      template: WorkspaceTemplate.flutter,
      createdAt: now,
      updatedAt: now,
    );

    test('构造正确', () {
      expect(workspace.id, 'ws-1');
      expect(workspace.name, '测试工作区');
      expect(workspace.template, WorkspaceTemplate.flutter);
      expect(workspace.createdAt, now);
      expect(workspace.updatedAt, now);
      expect(workspace.projects, isEmpty);
    });

    test('copyWith 更新名称', () {
      final updated = workspace.copyWith(name: '新名称', updatedAt: later);
      expect(updated.name, '新名称');
      expect(updated.id, workspace.id);
      expect(updated.template, workspace.template);
      expect(updated.updatedAt, later);
    });

    test('copyWith 更新模板', () {
      final updated = workspace.copyWith(template: WorkspaceTemplate.rust);
      expect(updated.template, WorkspaceTemplate.rust);
    });

    test('copyWith 添加项目', () {
      final project = ProjectRef(
        id: 'proj-1',
        name: 'MyApp',
        path: '/home/projects/myapp',
        createdAt: now,
      );
      final updated = workspace.copyWith(projects: [project]);
      expect(updated.projects.length, 1);
      expect(updated.projects.first.name, 'MyApp');
    });

    test('copyWith 原对象不变', () {
      workspace.copyWith(name: '新名称');
      expect(workspace.name, '测试工作区');
    });

    test('序列化为 JSON', () {
      final json = workspace.toJson();
      expect(json['id'], 'ws-1');
      expect(json['name'], '测试工作区');
      expect(json['template'], 'Flutter');
      expect(json['createdAt'], now.toIso8601String());
      expect(json['updatedAt'], now.toIso8601String());
      expect(json['projects'], isA<List>());
    });

    test('从 JSON 反序列化', () {
      final json = workspace.toJson();
      final restored = Workspace.fromJson(json);
      expect(restored.id, workspace.id);
      expect(restored.name, workspace.name);
      expect(restored.template, workspace.template);
      expect(restored.createdAt, workspace.createdAt);
      expect(restored.updatedAt, workspace.updatedAt);
    });

    test('从 JSON 反序列化（包含项目）', () {
      final project = ProjectRef(
        id: 'proj-1',
        name: 'MyApp',
        path: '/home/projects/myapp',
        createdAt: now,
      );
      final ws = workspace.copyWith(projects: [project]);
      final json = ws.toJson();
      final restored = Workspace.fromJson(json);
      expect(restored.projects.length, 1);
      expect(restored.projects.first.id, 'proj-1');
      expect(restored.projects.first.name, 'MyApp');
    });

    test('未知模板名称回退到 Flutter', () {
      final json = {
        'id': 'ws-x',
        'name': '未知',
        'template': 'NonExistent',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'projects': [],
      };
      final restored = Workspace.fromJson(json);
      expect(restored.template, WorkspaceTemplate.flutter);
    });

    test('空项目列表反序列化', () {
      final json = {
        'id': 'ws-empty',
        'name': '空工作区',
        'template': 'Python',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      final restored = Workspace.fromJson(json);
      expect(restored.projects, isEmpty);
    });
  });
}
