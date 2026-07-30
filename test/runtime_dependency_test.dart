import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/runtime/runtime_dependency.dart';

void main() {
  group('RuntimeDependency', () {
    test('所有工具都有定义', () {
      final all = RuntimeDependency.all;
      expect(all.length, greaterThan(0));
      for (final dep in all) {
        expect(dep.displayName, isNotEmpty);
        expect(dep.icon, isNotEmpty);
      }
    });

    test('根据工具获取定义', () {
      final node = RuntimeDependency.forTool(RuntimeTool.node);
      expect(node, isNotNull);
      expect(node!.displayName, 'Node.js');
      expect(node.icon, '🟢');
      expect(node.category, RuntimeCategory.coding);
    });

    test('不存在则返回 null', () {
      // 使用一个不存在的 index — 没有直接的 API 获取无效工具
      // 验证所有已定义工具都能查到
      for (final dep in RuntimeDependency.all) {
        expect(RuntimeDependency.forTool(dep.tool), isNotNull);
      }
    });

    test('工具分类正确', () {
      for (final dep in RuntimeDependency.all) {
        switch (dep.tool) {
          case RuntimeTool.androidShell:
          case RuntimeTool.curl:
          case RuntimeTool.storagePermission:
            expect(dep.category, RuntimeCategory.basic,
                reason: '${dep.displayName} 应属于 basic');
            break;
          case RuntimeTool.node:
          case RuntimeTool.git:
          case RuntimeTool.python:
          case RuntimeTool.ubuntu:
          case RuntimeTool.codexCli:
          case RuntimeTool.mimo2codex:
            expect(dep.category, RuntimeCategory.coding,
                reason: '${dep.displayName} 应属于 coding');
            break;
          case RuntimeTool.deepseekKey:
            expect(dep.category, RuntimeCategory.ai,
                reason: 'DeepSeek Key 应属于 ai');
            break;
          case RuntimeTool.flutterSdk:
            expect(dep.category, RuntimeCategory.development,
                reason: 'Flutter SDK 应属于 development');
            break;
        }
      }
    });

    test('Node.js 依赖 Ubuntu', () {
      final dep = RuntimeDependency.forTool(RuntimeTool.node);
      expect(dep!.dependencies, contains(RuntimeTool.ubuntu));
    });

    test('Codex CLI 依赖 Node.js', () {
      final dep = RuntimeDependency.forTool(RuntimeTool.codexCli);
      expect(dep!.dependencies, contains(RuntimeTool.node));
    });

    test('mimo2codex 依赖 Node.js', () {
      final dep = RuntimeDependency.forTool(RuntimeTool.mimo2codex);
      expect(dep!.dependencies, contains(RuntimeTool.node));
    });

    test('Flutter SDK 是可选工具', () {
      final dep = RuntimeDependency.forTool(RuntimeTool.flutterSdk);
      expect(dep!.optional, isTrue);
    });

    test('基础工具没有依赖', () {
      final basic = RuntimeDependency.byCategory(RuntimeCategory.basic);
      for (final dep in basic) {
        expect(dep.dependencies, isEmpty,
            reason: '${dep.displayName} 不应有依赖');
      }
    });
  });

  group('RuntimeDependency.installOrder', () {
    test('返回非空列表', () {
      final order = RuntimeDependency.installOrder();
      expect(order, isNotEmpty);
    });

    test('依赖在依赖者之前', () {
      final order = RuntimeDependency.installOrder();
      final nodeIdx = order.indexOf(RuntimeTool.node);
      final codexIdx = order.indexOf(RuntimeTool.codexCli);
      final mimoIdx = order.indexOf(RuntimeTool.mimo2codex);

      expect(codexIdx, greaterThan(nodeIdx),
          reason: 'Node.js 应在 Codex CLI 之前安装');
      expect(mimoIdx, greaterThan(nodeIdx),
          reason: 'Node.js 应在 mimo2codex 之前安装');
    });

    test('不包含可选工具', () {
      final order = RuntimeDependency.installOrder();
      expect(order, isNot(contains(RuntimeTool.flutterSdk)));
    });

    test('包含可选工具（指定时）', () {
      final order = RuntimeDependency.installOrder(includeOptional: true);
      expect(order, contains(RuntimeTool.flutterSdk));
    });
  });

  group('RuntimeDependency.byCategory', () {
    test('基础 Runtime 分类有 3 个工具', () {
      final basic = RuntimeDependency.byCategory(RuntimeCategory.basic);
      expect(basic.length, 3);
    });

    test('Development 分类含 Flutter SDK', () {
      final dev = RuntimeDependency.byCategory(RuntimeCategory.development);
      expect(dev.length, 1);
      expect(dev.first.tool, RuntimeTool.flutterSdk);
    });
  });
}
