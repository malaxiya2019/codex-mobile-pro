import 'package:codex_mobile_pro/features/terminal/services/command_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuickCommand', () {
    test('构造正确', () {
      const cmd = QuickCommand(
        id: 'flutter-pub-get',
        name: 'flutter pub get',
        command: 'flutter pub get',
        description: '获取依赖',
        category: CommandCategory.flutter,
      );

      expect(cmd.id, 'flutter-pub-get');
      expect(cmd.name, 'flutter pub get');
      expect(cmd.command, 'flutter pub get');
      expect(cmd.category, CommandCategory.flutter);
      expect(cmd.parameters, isEmpty);
      expect(cmd.isFavorite, false);
    });

    test('无参数构建命令', () {
      const cmd = QuickCommand(
        id: 'test',
        name: 'test',
        command: 'flutter pub get',
        category: CommandCategory.flutter,
        description: '',
      );

      expect(cmd.buildCommand(), 'flutter pub get');
    });

    test('带参数构建命令', () {
      const cmd = QuickCommand(
        id: 'git-commit',
        name: 'git commit',
        command: 'git commit -m "{message}"',
        description: '提交',
        category: CommandCategory.git,
        parameters: ['message'],
      );

      expect(
        cmd.buildCommand({'message': 'fix bug'}),
        'git commit -m "fix bug"',
      );
    });

    test('copyWith 切换收藏', () {
      const cmd = QuickCommand(
        id: 'test',
        name: 'test',
        command: 'echo hello',
        description: '',
        category: CommandCategory.general,
      );

      expect(cmd.isFavorite, false);
      final favorited = cmd.copyWith(isFavorite: true);
      expect(favorited.isFavorite, true);
      expect(favorited.id, cmd.id);
      expect(favorited.command, cmd.command);
    });
  });

  group('CommandCategory', () {
    test('包含所有类别', () {
      expect(CommandCategory.values.length, 5);
    });

    test('Flutter 类别正确', () {
      expect(CommandCategory.flutter.name, 'Flutter');
      expect(CommandCategory.flutter.icon, '📱');
    });

    test('Rust 类别正确', () {
      expect(CommandCategory.rust.name, 'Rust');
      expect(CommandCategory.rust.icon, '🦀');
    });

    test('Python 类别正确', () {
      expect(CommandCategory.python.name, 'Python');
      expect(CommandCategory.python.icon, '🐍');
    });
  });

  group('CommandManager', () {
    late CommandManager mgr;

    setUp(() {
      mgr = CommandManager();
    });

    test('预置命令不为空', () {
      expect(mgr.commands, isNotEmpty);
      expect(mgr.commands.length, greaterThan(20));
    });

    test('初始无收藏', () {
      expect(mgr.favorites, isEmpty);
    });

    test('按类别获取命令', () {
      final flutterCmds = mgr.getByCategory(CommandCategory.flutter);
      expect(flutterCmds, isNotEmpty);
      for (final cmd in flutterCmds) {
        expect(cmd.category, CommandCategory.flutter);
      }
    });

    test('Flutter 包含关键命令', () {
      final flutterCmds = mgr.getByCategory(CommandCategory.flutter);
      final names = flutterCmds.map((c) => c.id).toSet();
      expect(names, contains('flutter-pub-get'));
      expect(names, contains('flutter-build-apk'));
      expect(names, contains('flutter-test'));
    });

    test('Rust 包含关键命令', () {
      final rustCmds = mgr.getByCategory(CommandCategory.rust);
      final names = rustCmds.map((c) => c.id).toSet();
      expect(names, contains('cargo-build'));
      expect(names, contains('cargo-test'));
      expect(names, contains('cargo-run'));
    });

    test('Python 包含关键命令', () {
      final pythonCmds = mgr.getByCategory(CommandCategory.python);
      final names = pythonCmds.map((c) => c.id).toSet();
      expect(names, contains('pip-install'));
      expect(names, contains('python-run'));
      expect(names, contains('python-venv'));
    });

    test('Git 包含关键命令', () {
      final gitCmds = mgr.getByCategory(CommandCategory.git);
      final names = gitCmds.map((c) => c.id).toSet();
      expect(names, contains('git-status'));
      expect(names, contains('git-commit'));
      expect(names, contains('git-push'));
    });

    test('切换收藏', () {
      mgr.toggleFavorite('flutter-pub-get');
      expect(mgr.favorites.length, 1);
      expect(mgr.favorites.first.id, 'flutter-pub-get');

      // 再次切换取消收藏
      mgr.toggleFavorite('flutter-pub-get');
      expect(mgr.favorites, isEmpty);
    });

    test('收藏多个命令', () {
      mgr.toggleFavorite('flutter-pub-get');
      mgr.toggleFavorite('cargo-build');
      mgr.toggleFavorite('pip-install');

      expect(mgr.favorites.length, 3);
    });

    test('切换不存在的 ID 不崩溃', () {
      mgr.toggleFavorite('non-existent');
      expect(mgr.favorites, isEmpty);
    });
  });
}
