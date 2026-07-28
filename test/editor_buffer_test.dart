import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/editor/models/editor_models.dart';
import 'package:codex_mobile_pro/features/editor/services/editor_buffer.dart';

void main() {
  group('EditorBuffer', () {
    late EditorBuffer buffer;

    setUp(() {
      buffer = EditorBuffer(
        filePath: '/test/test.dart',
        initialContent: ['void main() {', '  print("hello");', '}'],
      );
    });

    test('初始属性正确', () {
      expect(buffer.lineCount, 3);
      expect(buffer.lines[0], 'void main() {');
      expect(buffer.language, FileLanguage.dart);
      expect(buffer.isDirty, false);
      expect(buffer.canUndo, false);
      expect(buffer.canRedo, false);
    });

    test('插入字符', () {
      buffer.moveCursor(const CursorPosition(line: 0, column: 0));
      buffer.insertChar('x');
      expect(buffer.lines[0], 'xvoid main() {');
      expect(buffer.isDirty, true);
    });

    test('移动光标', () {
      buffer.moveCursor(const CursorPosition(line: 1, column: 2));
      expect(buffer.cursor.line, 1);
      expect(buffer.cursor.column, 2);
    });

    test('光标边界 - 起始', () {
      buffer.moveCursor(const CursorPosition(line: 0, column: 0));
      buffer.moveCursorLeft();
      expect(buffer.cursor.line, 0);
      expect(buffer.cursor.column, 0);
    });

    test('光标边界 - 结尾', () {
      buffer.moveCursor(const CursorPosition(line: 2, column: 1));
      buffer.moveCursorRight();
      expect(buffer.cursor.line, 2);
      expect(buffer.cursor.column, 1);
    });

    test('向上移动光标', () {
      buffer.moveCursor(const CursorPosition(line: 2, column: 0));
      buffer.moveCursorUp();
      expect(buffer.cursor.line, 1);
    });

    test('向下移动光标', () {
      buffer.moveCursor(const CursorPosition(line: 0, column: 0));
      buffer.moveCursorDown();
      expect(buffer.cursor.line, 1);
    });

    test('行首', () {
      buffer.moveCursor(const CursorPosition(line: 1, column: 5));
      buffer.moveToLineStart();
      expect(buffer.cursor.column, 0);
    });

    test('行尾', () {
      buffer.moveCursor(const CursorPosition(line: 1, column: 0));
      buffer.moveToLineEnd();
      expect(buffer.cursor.column, buffer.lines[1].length);
    });

    test('文件起始', () {
      buffer.moveCursor(const CursorPosition(line: 2, column: 1));
      buffer.moveToFileStart();
      expect(buffer.cursor.line, 0);
      expect(buffer.cursor.column, 0);
    });

    test('文件结尾', () {
      buffer.moveCursor(const CursorPosition(line: 0, column: 0));
      buffer.moveToFileEnd();
      expect(buffer.cursor.line, 2);
      expect(buffer.cursor.column, buffer.lines[2].length);
    });

    test('删除左侧字符', () {
      buffer.moveCursor(const CursorPosition(line: 1, column: 2));
      buffer.deleteLeft();
      expect(buffer.lines[1], ' print("hello");');
    });

    test('删除右侧字符', () {
      buffer.moveCursor(const CursorPosition(line: 1, column: 2));
      buffer.deleteRight();
      // 列索引 2 处为 'p'，删除后剩下 '  rint("hello");'
      expect(buffer.lines[1], '  rint("hello");');
    });

    test('插入换行', () {
      buffer.moveCursor(const CursorPosition(line: 1, column: 8));
      buffer.insertNewline();
      expect(buffer.lineCount, 4);
      expect(buffer.lines[1], '  print(');
      // 智能缩进：上一行以 ( 结尾，自动增加一级缩进
      expect(buffer.lines[2], '    "hello");');
    });

    test('撤销操作', () {
      buffer.moveCursor(const CursorPosition(line: 0, column: 0));
      buffer.insertChar('x');
      expect(buffer.lines[0], 'xvoid main() {');
      buffer.undo();
      expect(buffer.lines[0], 'void main() {');
    });

    test('重做操作', () {
      buffer.moveCursor(const CursorPosition(line: 0, column: 0));
      buffer.insertChar('x');
      buffer.undo();
      buffer.redo();
      expect(buffer.lines[0], 'xvoid main() {');
    });

    test('选择文本', () {
      buffer.selectAll();
      expect(buffer.hasSelection, true);
      final selected = buffer.selectedText;
      expect(selected, 'void main() {\n  print("hello");\n}');
    });

    test('清除选择', () {
      buffer.selectAll();
      buffer.clearSelection();
      expect(buffer.hasSelection, false);
    });

    test('文本查找', () {
      final matches = buffer.findAll('print');
      expect(matches.length, 1);
      expect(matches[0].line, 1);
    });

    test('全文替换', () {
      final count = buffer.replaceAll('hello', 'world');
      expect(count, 1);
      expect(buffer.lines[1], '  print("world");');
    });

    test('语言检测', () {
      expect(FileLanguage.fromFileName('test.dart'), FileLanguage.dart);
      expect(FileLanguage.fromFileName('main.rs'), FileLanguage.rust);
      expect(FileLanguage.fromFileName('app.py'), FileLanguage.python);
      expect(FileLanguage.fromFileName('data.json'), FileLanguage.json);
      expect(FileLanguage.fromFileName('config.yaml'), FileLanguage.yaml);
      expect(FileLanguage.fromFileName('readme.md'), FileLanguage.markdown);
      expect(FileLanguage.fromFileName('Cargo.toml'), FileLanguage.toml);
      expect(FileLanguage.fromFileName('build.sh'), FileLanguage.shell);
      expect(FileLanguage.fromFileName('unknown.xyz'), FileLanguage.unknown);
    });
  });
}
