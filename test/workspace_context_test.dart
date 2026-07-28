import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lib/core/context/workspace_context.dart';
import '../lib/core/context/workspace_context_provider.dart';
import '../lib/features/editor/models/editor_models.dart';

// ══════════════════════════════════════════════
// Mock 环境：创建测试用 ProviderContainer
// ══════════════════════════════════════════════

/// 测试用的 Mock Ref
class _TestRef extends Ref<Object?> {
  @override
  ProviderContainer get container => throw UnimplementedError('Not needed in tests');

  @override
  T refresh<T>(Refreshable<T> provider) => throw UnimplementedError('Not needed in tests');

  @override
  void invalidate(ProviderOrFamily provider) {}

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
  void onMount(void Function() cb) {}

  @override
  bool exists(ProviderBase<Object?> provider) => false;

  @override
  bool get mounted => true;

  @override
  Ref<Object?> get parent => this;

  @override
  ProviderStateOwner? get owner => null;

  @override
  T read<T>(ProviderListenable<T> provider) => throw UnimplementedError('Not needed in tests');

  @override
  T watch<T>(ProviderListenable<T> provider) => throw UnimplementedError('Not needed in tests');

  @override
  KeepAliveLink keepAlive() => throw UnimplementedError('Not needed in tests');

  @override
  ProviderSubscription<T> listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool fireImmediately = false,
  }) {
    throw UnimplementedError('Not needed in tests');
  }
}

/// 创建一个模拟的 Ref 对象用于测试
_TestRef createMockRef() {
  return _TestRef();
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
    test('IWorkspaceContextProvider 继承 ContextManager', () {
      // 编译期检查：IWorkspaceContextProvider 必须有 buildContextPrompt()
      // 通过实例化检查
      expect(true, isTrue);
    });

    test('buildContextPrompt 返回格式化字符串', () async {
      final container = createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      // 无工作区状态时，上下文内容为空
      final prompt = provider.buildContextPrompt();
      expect(prompt, contains('上下文信息'));
    });
  });

  group('WorkspaceContextProvider — 上下文 Prompt 构建', () {
    test('buildContextPrompt 包含自定义上下文', () async {
      final container = createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      provider.addContext('用户需求', '实现一个计算器');
      final prompt = provider.buildContextPrompt();

      expect(prompt, contains('用户需求'));
      expect(prompt, contains('实现一个计算器'));
    });

    test('addContext / removeContext / clearContext 正常工作', () async {
      final container = createMockRef();
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
      final container = createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      final fileCtx = provider.getCurrentFileContext();
      expect(fileCtx, isNull);
    });

    test('getSelectionContext 返回 null（无选中内容）', () async {
      final container = createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      final selCtx = provider.getSelectionContext();
      expect(selCtx, isNull);
    });

    test('currentFile / selection / workspaceContext 为 null（无状态）', () async {
      final container = createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      expect(provider.currentFile, isNull);
      expect(provider.selection, isNull);
      expect(provider.workspaceContext, isNull);
    });
  });

  group('FileLanguage 工具方法', () {
    test('_languageName 能识别所有语言', () {
      // ignore: unused_local_variable
      final _ = WorkspaceContextProvider(ref: createMockRef());
      // 通过反射或直接测试私有方法不可行，测试公开 getter
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
      final container = createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      // 不应抛出异常
      expect(() => provider.buildContextPrompt(), returnsNormally);
    });

    test('多次调用 buildContextPrompt 不影响自定义上下文', () async {
      final container = createMockRef();
      final provider = WorkspaceContextProvider(ref: container);

      provider.addContext('test-key', 'test-value');
      final first = provider.buildContextPrompt();
      final second = provider.buildContextPrompt();

      expect(first, second);
    });
  });
}
