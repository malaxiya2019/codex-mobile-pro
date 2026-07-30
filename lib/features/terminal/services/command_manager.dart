/// 快捷命令类别
enum CommandCategory {
  flutter('Flutter', '📱'),
  rust('Rust', '🦀'),
  python('Python', '🐍'),
  general('通用', '⚙️'),
  git('Git', '🔗');

  final String name;
  final String icon;
  const CommandCategory(this.name, this.icon);
}

/// 快捷命令
class QuickCommand {
  final String id;
  final String name;
  final String command;
  final String description;
  final CommandCategory category;
  final List<String> parameters;
  final bool isFavorite;

  const QuickCommand({
    required this.id,
    required this.name,
    required this.command,
    required this.description,
    required this.category,
    this.parameters = const [],
    this.isFavorite = false,
  });

  /// 填充参数生成实际命令
  String buildCommand([Map<String, String>? params]) {
    if (params == null || params.isEmpty) return command;

    var result = command;
    params.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  QuickCommand copyWith({bool? isFavorite}) {
    return QuickCommand(
      id: id,
      name: name,
      command: command,
      description: description,
      category: category,
      parameters: parameters,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

/// 命令管理器
///
/// 管理常用命令的收藏、分类和预置模板。
class CommandManager {
  final List<QuickCommand> _commands = [];
  final List<QuickCommand> _favorites = [];

  CommandManager() {
    _initDefaultCommands();
  }

  /// 所有命令
  List<QuickCommand> get commands => List.unmodifiable(_commands);

  /// 收藏命令
  List<QuickCommand> get favorites => List.unmodifiable(_favorites);

  /// 按类别获取命令
  List<QuickCommand> getByCategory(CommandCategory category) {
    return _commands.where((c) => c.category == category).toList();
  }

  /// 切换收藏
  void toggleFavorite(String id) {
    final index = _commands.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final cmd = _commands[index];
    final updated = cmd.copyWith(isFavorite: !cmd.isFavorite);
    _commands[index] = updated;

    if (updated.isFavorite) {
      _favorites.add(updated);
    } else {
      _favorites.removeWhere((c) => c.id == id);
    }
  }

  /// 初始化预置命令
  void _initDefaultCommands() {
    // ── Flutter ──
    _commands.addAll([
      const QuickCommand(
        id: 'flutter-pub-get',
        name: 'flutter pub get',
        command: 'flutter pub get',
        description: '获取 Flutter 依赖包',
        category: CommandCategory.flutter,
      ),
      const QuickCommand(
        id: 'flutter-build-apk',
        name: 'flutter build apk',
        command: 'flutter build apk --debug',
        description: '构建 Android APK',
        category: CommandCategory.flutter,
        parameters: ['mode'],
      ),
      const QuickCommand(
        id: 'flutter-build-release',
        name: 'flutter build release',
        command: 'flutter build apk --release',
        description: '构建 Release APK',
        category: CommandCategory.flutter,
      ),
      const QuickCommand(
        id: 'flutter-test',
        name: 'flutter test',
        command: 'flutter test',
        description: '运行 Flutter 测试',
        category: CommandCategory.flutter,
      ),
      const QuickCommand(
        id: 'flutter-run',
        name: 'flutter run',
        command: 'flutter run',
        description: '运行 Flutter 应用',
        category: CommandCategory.flutter,
      ),
      const QuickCommand(
        id: 'flutter-clean',
        name: 'flutter clean',
        command: 'flutter clean',
        description: '清理 Flutter 构建缓存',
        category: CommandCategory.flutter,
      ),
      const QuickCommand(
        id: 'flutter-analyze',
        name: 'flutter analyze',
        command: 'flutter analyze',
        description: '代码静态分析',
        category: CommandCategory.flutter,
      ),
    ]);

    // ── Rust ──
    _commands.addAll([
      const QuickCommand(
        id: 'cargo-build',
        name: 'cargo build',
        command: 'cargo build',
        description: '编译 Rust 项目',
        category: CommandCategory.rust,
      ),
      const QuickCommand(
        id: 'cargo-release',
        name: 'cargo build --release',
        command: 'cargo build --release',
        description: '编译 Release 版本',
        category: CommandCategory.rust,
      ),
      const QuickCommand(
        id: 'cargo-test',
        name: 'cargo test',
        command: 'cargo test',
        description: '运行 Rust 测试',
        category: CommandCategory.rust,
      ),
      const QuickCommand(
        id: 'cargo-check',
        name: 'cargo check',
        command: 'cargo check',
        description: '检查代码但不生成二进制',
        category: CommandCategory.rust,
      ),
      const QuickCommand(
        id: 'cargo-run',
        name: 'cargo run',
        command: 'cargo run',
        description: '运行 Rust 项目',
        category: CommandCategory.rust,
      ),
      const QuickCommand(
        id: 'cargo-update',
        name: 'cargo update',
        command: 'cargo update',
        description: '更新 Rust 依赖',
        category: CommandCategory.rust,
      ),
    ]);

    // ── Python ──
    _commands.addAll([
      const QuickCommand(
        id: 'pip-install',
        name: 'pip install',
        command: 'pip install -r requirements.txt',
        description: '安装 Python 依赖',
        category: CommandCategory.python,
      ),
      const QuickCommand(
        id: 'python-run',
        name: 'python main.py',
        command: 'python3 main.py',
        description: '运行 Python 项目',
        category: CommandCategory.python,
      ),
      const QuickCommand(
        id: 'python-venv',
        name: '创建 venv',
        command: 'python3 -m venv venv',
        description: '创建虚拟环境',
        category: CommandCategory.python,
      ),
      const QuickCommand(
        id: 'python-test',
        name: 'python -m pytest',
        command: 'python3 -m pytest',
        description: '运行 Python 测试',
        category: CommandCategory.python,
      ),
      const QuickCommand(
        id: 'pip-freeze',
        name: 'pip freeze',
        command: 'pip freeze > requirements.txt',
        description: '导出当前依赖',
        category: CommandCategory.python,
      ),
    ]);

    // ── Git ──
    _commands.addAll([
      const QuickCommand(
        id: 'git-status',
        name: 'git status',
        command: 'git status',
        description: '查看仓库状态',
        category: CommandCategory.git,
      ),
      const QuickCommand(
        id: 'git-add',
        name: 'git add .',
        command: 'git add .',
        description: '暂存所有更改',
        category: CommandCategory.git,
      ),
      const QuickCommand(
        id: 'git-commit',
        name: 'git commit',
        command: 'git commit -m "{message}"',
        description: '提交更改',
        category: CommandCategory.git,
        parameters: ['message'],
      ),
      const QuickCommand(
        id: 'git-push',
        name: 'git push',
        command: 'git push origin {branch}',
        description: '推送到远程',
        category: CommandCategory.git,
        parameters: ['branch'],
      ),
      const QuickCommand(
        id: 'git-pull',
        name: 'git pull',
        command: 'git pull',
        description: '拉取远程更新',
        category: CommandCategory.git,
      ),
      const QuickCommand(
        id: 'git-log',
        name: 'git log',
        command: 'git log --oneline -10',
        description: '查看提交历史',
        category: CommandCategory.git,
      ),
    ]);

    // ── 通用 ──
    _commands.addAll([
      const QuickCommand(
        id: 'clear',
        name: 'clear',
        command: 'clear',
        description: '清屏',
        category: CommandCategory.general,
      ),
      const QuickCommand(
        id: 'ls',
        name: 'ls -la',
        command: 'ls -la',
        description: '列出目录内容',
        category: CommandCategory.general,
      ),
      const QuickCommand(
        id: 'pwd',
        name: 'pwd',
        command: 'pwd',
        description: '显示当前路径',
        category: CommandCategory.general,
      ),
      const QuickCommand(
        id: 'date',
        name: 'date',
        command: 'date',
        description: '显示当前时间',
        category: CommandCategory.general,
      ),
      const QuickCommand(
        id: 'df-h',
        name: 'df -h',
        command: 'df -h',
        description: '查看磁盘使用',
        category: CommandCategory.general,
      ),
      const QuickCommand(
        id: 'free-h',
        name: 'free -h',
        command: 'free -h',
        description: '查看内存使用',
        category: CommandCategory.general,
      ),
    ]);
  }
}
