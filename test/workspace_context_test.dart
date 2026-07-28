import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codex_mobile_pro/core/context/workspace_context.dart';
import 'package:codex_mobile_pro/core/context/workspace_context_provider.dart';
import 'package:codex_mobile_pro/features/editor/models/editor_models.dart';
import 'package:codex_mobile_pro/features/editor/providers/editor_provider.dart';
import 'package:codex_mobile_pro/features/workspace/workspace_provider.dart';

/// 测试用的 Mock Ref — 使用真实 ProviderContainer
class _TestRef extends Ref<Object?> {
  final ProviderContainer _container;

  _TestRef(this._container);

  @override
  ProviderContainer get container => _container;

  @override
  T refresh<T>(Refreshable<T> provider) => _container.refresh(provider);

  @override
  void invalidate(ProviderOrFamily provider) => _container.invalidate(provider);

  @override
  void notifyListeners() {}

  @override
  void listenSelf(
    void Function(Object? previous, Object? next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {}

  @override
  void invalidateSelf() {}

  @override
  void onAddListener(void Function() cb) {}

  @override
  void onRemoveListener(void Function() cb) {}

  @override
  void onResume(void Function() cb) {}

  @override
  void onCancel(void Function() cb) {}

  @override
  void onDispose(void Function() cb) {}

  @override
  bool exists(ProviderBase<Object?> provider) =>
      _container.read(provider) != null;

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  T watch<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  KeepAliveLink keepAlive() =>
      throw UnsupportedError('keepAlive() is not supported in test ref');

  @override
  ProviderSubscription<T> listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool fireImmediately = false,
  }) =>
      _container.listen(provider, listener,
          onError: onError, fireImmediately: fireImmediately);
}

/// 创建一个模拟的 Ref 对象用于测试
Future<_TestRef> createMockRef() async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      editorProvider.overrideWith((ref) => EditorNotifier()),
      workspaceProvider.overrideWith((ref) => WorkspaceNotifier()),
    ],
  );
  return _TestRef(container);
}

void main() {
  group('WorkspaceContext — 数据模型', () {
    test('FileContext 创建', () {
      final ctx = FileContext(
        path: '/test/main.dart',
        language: 'dart',
        content: 'void main() {}',
        lineCount: 1,
      );

      expect(ctx.path, '/test/main.dart');
      expect(ctx.language, 'dart');
      expect(ctx.content, 'void main() {}');
      expect(ctx.lineCount, 1);
    });

    test('SelectionContext 创建', () {
      final ctx = SelectionContext(
        filePath: '/test/main.dart',
        startLine: 1,
        startColumn: 0,
        endLine: 1,
        endColumn: 10,
        selectedText: 'void main()',
      );

      expect(ctx.filePath, '/test/main.dart');
      expect(ctx.startLine, 1);
      expect(ctx.endColumn, 10);
      expect(ctx.selectedText, 'void main()');
    });

    test('WorkspaceStructure 创建', () {
      final ctx = WorkspaceStructure(
        workspacePath: '/projects/myapp',
        files: ['lib/main.dart', 'pubspec.yaml'],
        projectInfo: {'name': 'myapp', 'template': 'Flutter'},
      );

      expect(ctx.workspacePath, '/projects/myapp');
      expect(ctx.files.length, 2);
      expect(ctx.projectInfo['name'], 'myapp');
    });

    test('GitContext 创建', () {
      final ctx = GitContext(
        branch: 'main',
        modifiedFiles: ['lib/main.dart'],
        diff: '--- a/lib/main.dart\n+++ b/lib/main.dart\n@@ -1 +1 @@\n-old\n+new',
        isClean: false,
        ahead: 2,
        behind: 0,
      );

      expect(ctx.branch, 'main');
      expect(ctx.modifiedFiles.length, 1);
      expect(ctx.diff, isNotNull);
      expect(ctx.isClean, false);
      expect(ctx.ahead, 2);
    });

    test('GitContext 默认值为干净工作区', () {
      final ctx = const GitContext();
      expect(ctx.isClean, true);
      expect(ctx.branch, isNull);
      expect(ctx.modifiedFiles, isEmpty);
      expect(ctx.ahead, 0);
      expect(ctx.behind, 0);
    });
  });

  group('WorkspaceContextProvider — 接口', () {
    test('IWorkspaceContextProvider 继承 ContextManager', () async {
      final container = await createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      final prompt = provider.buildContextPrompt();
      expect(prompt, contains('上下文信息'));
    });
  });

  group('WorkspaceContextProvider — 上下文 Prompt 构建', () {
    test('buildContextPrompt 包含自定义上下文', () async {
      final container = await createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      provider.addContext('用户需求', '实现一个计算器');
      final prompt = provider.buildContextPrompt();

      expect(prompt, contains('用户需求'));
      expect(prompt, contains('实现一个计算器'));
    });

    test('addContext / removeContext / clearContext 正常工作', () async {
      final container = await createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      provider.addContext('key1', 'value1');
      provider.addContext('key2', 'value2');

      String prompt = provider.buildContextPrompt();
      expect(prompt, contains('key1'));
      expect(prompt, contains('value1'));
      expect(prompt, contains('key2'));

      provider.removeContext('key1');
      prompt = provider.buildContextPrompt();
      expect(prompt, isNot(contains('key1')));
      expect(prompt, contains('key2'));

      provider.clearContext();
      prompt = provider.buildContextPrompt();
      expect(prompt, isNot(contains('key2')));
    });

    test('getCurrentFileContext 返回 null（无活动编辑器）', () async {
      final container = await createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      final fileCtx = provider.getCurrentFileContext();
      expect(fileCtx, isNull);
    });

    test('getSelectionContext 返回 null（无选中内容）', () async {
      final container = await createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      final selCtx = provider.getSelectionContext();
      expect(selCtx, isNull);
    });

    test('currentFile / selection / workspaceContext 为 null（无状态）', () async {
      final container = await createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      expect(provider.currentFile, isNull);
      expect(provider.selection, isNull);
      expect(provider.workspaceContext, isNull);
    });
  });

  group('FileLanguage 工具方法', () {
    test('FileLanguage.fromFileName 识别所有语言', () {
      expect(FileLanguage.fromFileName('main.dart'), FileLanguage.dart);
      expect(FileLanguage.fromFileName('main.rs'), FileLanguage.rust);
      expect(FileLanguage.fromFileName('main.py'), FileLanguage.python);
      expect(FileLanguage.fromFileName('config.json'), FileLanguage.json);
      expect(FileLanguage.fromFileName('config.yaml'), FileLanguage.yaml);
      expect(FileLanguage.fromFileName('README.md'), FileLanguage.markdown);
      expect(FileLanguage.fromFileName('Cargo.toml'), FileLanguage.toml);
      expect(FileLanguage.fromFileName('build.sh'), FileLanguage.shell);
      expect(FileLanguage.fromFileName('app.ts'), FileLanguage.typescript);
      expect(FileLanguage.fromFileName('app.js'), FileLanguage.javascript);
      expect(FileLanguage.fromFileName('config.html'), FileLanguage.html);
      expect(FileLanguage.fromFileName('style.css'), FileLanguage.css);
      expect(FileLanguage.fromFileName('Main.java'), FileLanguage.java);
      expect(FileLanguage.fromFileName('main.cpp'), FileLanguage.cpp);
      expect(FileLanguage.fromFileName('data.bin'), FileLanguage.unknown);
    });
  });

  group('WorkspaceContextProvider — Token 估算', () {
    test('buildContextPrompt 对空内容不报错', () async {
      final container = await createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      expect(() => provider.buildContextPrompt(), returnsNormally);
    });

    test('多次调用 buildContextPrompt 不影响自定义上下文', () async {
      final container = await createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      provider.addContext('test-key', 'test-value');
      final first = provider.buildContextPrompt();
      final second = provider.buildContextPrompt();

      expect(first, second);
    });
  });
}
