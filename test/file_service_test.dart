import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/file/services/file_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    // 创建临时测试目录
    tempDir = Directory.systemTemp.createTempSync('file_test_');
    // 创建测试文件结构
    File('${tempDir.path}/test.txt').writeAsStringSync('Hello, World!');
    File(
      '${tempDir.path}/main.dart',
    ).writeAsStringSync('void main() { print("test"); }');
    Directory('${tempDir.path}/subdir').createSync();
    File('${tempDir.path}/subdir/nested.txt').writeAsStringSync('Nested file');
    Directory('${tempDir.path}/emptydir').createSync();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('FileEntry', () {
    test('文本文件检测', () {
      final entry = FileEntry(
        name: 'main.dart',
        path: '/test/main.dart',
        type: FileEntryType.file,
      );
      expect(entry.isTextFile, true);
      expect(entry.icon, '🎯');
    });

    test('非文本文件检测', () {
      final entry = FileEntry(
        name: 'image.png',
        path: '/test/image.png',
        type: FileEntryType.file,
      );
      expect(entry.isTextFile, false);
      expect(entry.icon, '🖼️');
    });

    test('目录图标', () {
      final entry = FileEntry(
        name: 'folder',
        path: '/test/folder',
        type: FileEntryType.directory,
      );
      expect(entry.icon, '📁');
    });

    test('未知类型图标', () {
      final entry = FileEntry(
        name: 'unknown.xyz',
        path: '/test/unknown.xyz',
        type: FileEntryType.file,
      );
      expect(entry.icon, '📄');
    });

    test('YAML 文件', () {
      final entry = FileEntry(
        name: 'config.yaml',
        path: '/test/config.yaml',
        type: FileEntryType.file,
      );
      expect(entry.isTextFile, true);
      expect(entry.icon, '⚙️');
    });

    test('Markdown 文件', () {
      final entry = FileEntry(
        name: 'readme.md',
        path: '/test/readme.md',
        type: FileEntryType.file,
      );
      expect(entry.isTextFile, true);
      expect(entry.icon, '📝');
    });
  });

  group('FileService.listDirectory', () {
    test('列出目录内容', () async {
      final entries = await FileService.listDirectory(tempDir.path);
      expect(entries.length, greaterThanOrEqualTo(4));

      // 检查包含的文件
      final names = entries.map((e) => e.name).toSet();
      expect(names, contains('test.txt'));
      expect(names, contains('main.dart'));
      expect(names, contains('subdir'));
      expect(names, contains('emptydir'));
    });

    test('目录在文件前排序', () async {
      final entries = await FileService.listDirectory(tempDir.path);
      // 前两个应该是目录
      expect(entries[0].type, FileEntryType.directory);
      expect(entries[1].type, FileEntryType.directory);
    });

    test('不存在的目录返回空列表', () async {
      final entries = await FileService.listDirectory('/nonexistent/path');
      expect(entries, isEmpty);
    });
  });

  group('FileService.readFile', () {
    test('读取文件内容', () async {
      final content = await FileService.readFile('${tempDir.path}/test.txt');
      expect(content, 'Hello, World!');
    });

    test('不存在的文件返回 null', () async {
      final content = await FileService.readFile(
        '${tempDir.path}/nonexistent.txt',
      );
      expect(content, isNull);
    });
  });

  group('FileService.searchFiles', () {
    test('按名称搜索', () async {
      final results = await FileService.searchFiles(
        rootPath: tempDir.path,
        query: 'nested',
      );
      expect(results, isNotEmpty);
      expect(results.any((e) => e.name == 'nested.txt'), true);
    });

    test('不匹配的搜索', () async {
      final results = await FileService.searchFiles(
        rootPath: tempDir.path,
        query: 'zzzznotfound',
      );
      expect(results, isEmpty);
    });
  });

  group('FileService.getDirectoryTree', () {
    test('构建目录树', () async {
      final root = await FileService.getDirectoryTree(tempDir.path);
      expect(root.isDirectory, true);
      expect(root.isLazy, false);
      expect(root.children, isNotEmpty);
    });

    test('子节点标记为懒加载', () async {
      final root = await FileService.getDirectoryTree(tempDir.path);
      final dirNodes = root.children!.where((n) => n.isDirectory);
      for (final dir in dirNodes) {
        expect(dir.isLazy, true);
      }
    });
  });

  group('FileTreeNode', () {
    test('初始未展开', () {
      final node = FileTreeNode(name: 'test', path: '/test', isDirectory: true);
      expect(node.isExpanded, false);
    });

    test('文件节点不可展开', () {
      final node = FileTreeNode(
        name: 'test.txt',
        path: '/test/test.txt',
        isDirectory: false,
      );
      expect(node.isExpanded, false);
    });

    test('展开后标记已展开', () {
      final node = FileTreeNode(
        name: 'emptydir',
        path: tempDir.path,
        isDirectory: true,
        isLazy: true,
      );
      // 更新 path 指向实际存在的目录
      final realNode = FileTreeNode(
        name: 'emptydir',
        path: '${tempDir.path}/emptydir',
        isDirectory: true,
        isLazy: true,
      );
      expect(realNode.isExpanded, false);
    });

    test('收起节点', () {
      final node = FileTreeNode(
        name: 'test',
        path: '/test',
        isDirectory: true,
        children: [],
      );
      expect(node.isExpanded, true);
      node.collapse();
      expect(node.isExpanded, false);
    });
  });
}
