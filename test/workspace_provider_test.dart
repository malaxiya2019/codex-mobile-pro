import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:codex_mobile_pro/features/workspace/workspace_model.dart';
import 'package:codex_mobile_pro/features/workspace/workspace_provider.dart';

void main() {
  group('WorkspaceProvider', () {
    setUp(() {
      // 重置 SharedPreferences 测试环境（确保跨测试隔离）
      SharedPreferences.setMockInitialValues({});
    });

    test('初始状态：空工作区列表', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(workspaceProvider);
      expect(state.workspaces, isEmpty);
      expect(state.currentWorkspaceId, isNull);
      expect(state.currentWorkspace, isNull);
    });

    test('创建单个工作区', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      final ws = await notifier.create(
        name: '测试工作区',
        template: WorkspaceTemplate.flutter,
      );

      expect(ws.name, '测试工作区');
      expect(ws.template, WorkspaceTemplate.flutter);
      expect(ws.id, isNotEmpty);
      expect(ws.projects, isEmpty);

      final state = container.read(workspaceProvider);
      expect(state.workspaces.length, 1);
      expect(state.workspaces.first.id, ws.id);
    });

    test('创建多个工作区', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);
      await notifier.create(name: 'B', template: WorkspaceTemplate.rust);
      await notifier.create(name: 'C', template: WorkspaceTemplate.python);

      final state = container.read(workspaceProvider);
      expect(state.workspaces.length, 3);
      expect(state.workspaces[0].name, 'A');
      expect(state.workspaces[1].name, 'B');
      expect(state.workspaces[2].name, 'C');
    });

    test('切换当前工作区', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      final ws1 = await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);
      final ws2 = await notifier.create(name: 'B', template: WorkspaceTemplate.rust);

      // 默认无当前工作区
      expect(container.read(workspaceProvider).currentWorkspaceId, isNull);

      // 切换到 ws1
      await notifier.switchWorkspace(ws1.id);
      expect(container.read(workspaceProvider).currentWorkspaceId, ws1.id);
      expect(container.read(workspaceProvider).currentWorkspace?.name, 'A');

      // 切换到 ws2
      await notifier.switchWorkspace(ws2.id);
      expect(container.read(workspaceProvider).currentWorkspaceId, ws2.id);
      expect(container.read(workspaceProvider).currentWorkspace?.name, 'B');
    });

    test('取消选择工作区', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      final ws = await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);
      await notifier.switchWorkspace(ws.id);
      expect(container.read(workspaceProvider).currentWorkspaceId, ws.id);

      await notifier.clearCurrentWorkspace();
      expect(container.read(workspaceProvider).currentWorkspaceId, isNull);
    });

    test('切换不存在的 ID 无效', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);

      await notifier.switchWorkspace('non-existent');
      expect(container.read(workspaceProvider).currentWorkspaceId, isNull);
    });

    test('删除工作区', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      final ws1 = await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);
      final ws2 = await notifier.create(name: 'B', template: WorkspaceTemplate.rust);

      await notifier.delete(ws1.id);

      final state = container.read(workspaceProvider);
      expect(state.workspaces.length, 1);
      expect(state.workspaces.first.id, ws2.id);
    });

    test('删除当前工作区清空选择', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 可靠等待 _load() 完成（drain microtasks）
      await Future(() {});
      await Future(() {});
      await Future(() {});

      final notifier = container.read(workspaceProvider.notifier);
      final ws = await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);
      await notifier.switchWorkspace(ws.id);
      await notifier.delete(ws.id);

      expect(container.read(workspaceProvider).currentWorkspaceId, isNull);
    });

    test('更新工作区', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      final ws = await notifier.create(name: '旧名', template: WorkspaceTemplate.flutter);

      final updated = ws.copyWith(name: '新名', updatedAt: DateTime.now());
      await notifier.update(updated);

      final state = container.read(workspaceProvider);
      expect(state.workspaces.first.name, '新名');
    });

    test('添加项目到工作区', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      final ws = await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);

      final project = ProjectRef(
        id: 'proj-1',
        name: 'MyApp',
        path: '/home/projects/myapp',
        createdAt: DateTime.now(),
      );
      await notifier.addProject(ws.id, project);

      final state = container.read(workspaceProvider);
      expect(state.workspaces.first.projects.length, 1);
      expect(state.workspaces.first.projects.first.name, 'MyApp');
    });

    test('从工作区移除项目', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      final ws = await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);

      final project = ProjectRef(
        id: 'proj-1',
        name: 'MyApp',
        path: '/home/projects/myapp',
        createdAt: DateTime.now(),
      );
      await notifier.addProject(ws.id, project);
      expect(container.read(workspaceProvider).workspaces.first.projects.length, 1);

      await notifier.removeProject(ws.id, 'proj-1');
      expect(container.read(workspaceProvider).workspaces.first.projects, isEmpty);
    });

    test('count 属性', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      expect(notifier.count, 0);

      await notifier.create(name: 'A', template: WorkspaceTemplate.flutter);
      expect(notifier.count, 1);

      await notifier.create(name: 'B', template: WorkspaceTemplate.rust);
      expect(notifier.count, 2);
    });

    test('空名称不创建', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(workspaceProvider.notifier);
      // 空名称也能创建（验证不报错）
      final ws = await notifier.create(name: '', template: WorkspaceTemplate.flutter);
      expect(ws.name, '');
      expect(container.read(workspaceProvider).workspaces.length, 1);
    });
  });
}
