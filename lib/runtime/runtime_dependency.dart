/// ====================================================================
/// Runtime 依赖关系图
///
/// 定义工具间的依赖关系，用于确定安装顺序和验证依赖是否满足。
/// ====================================================================

/// 运行时工具标识
enum RuntimeTool {
  androidShell,
  curl,
  storagePermission,
  node,
  git,
  python,
  codexCli,
  mimo2codex,
  deepseekKey,
  flutterSdk,
}

/// 运行时类别
enum RuntimeCategory {
  /// 基础 Runtime — Android Shell / cURL / Storage
  basic,

  /// Coding Runtime — Node.js / Git / Python / Codex CLI / mimo2codex
  coding,

  /// AI Runtime — DeepSeek API Key
  ai,

  /// Development Runtime — Flutter SDK（可选）
  development,
}

/// 依赖关系定义
class RuntimeDependency {
  /// 工具
  final RuntimeTool tool;

  /// 依赖项（必须先安装的工具）
  final List<RuntimeTool> dependencies;

  /// 类别
  final RuntimeCategory category;

  /// 显示名称
  final String displayName;

  /// 图标
  final String icon;

  /// 是否可选
  final bool optional;

  /// 友好提示
  final String? hint;

  const RuntimeDependency({
    required this.tool,
    required this.displayName,
    required this.icon,
    this.dependencies = const [],
    this.category = RuntimeCategory.coding,
    this.optional = false,
    this.hint,
  });

  /// 获取所有工具依赖定义
  static List<RuntimeDependency> get all => [
        // ── 基础 Runtime ──
        const RuntimeDependency(
          tool: RuntimeTool.androidShell,
          displayName: 'Android Shell',
          icon: '📱',
          category: RuntimeCategory.basic,
        ),
        const RuntimeDependency(
          tool: RuntimeTool.curl,
          displayName: 'cURL',
          icon: '🌐',
          category: RuntimeCategory.basic,
        ),
        const RuntimeDependency(
          tool: RuntimeTool.storagePermission,
          displayName: '存储权限',
          icon: '💾',
          category: RuntimeCategory.basic,
        ),

        // ── Coding Runtime ──
        const RuntimeDependency(
          tool: RuntimeTool.node,
          displayName: 'Node.js',
          icon: '🟢',
          category: RuntimeCategory.coding,
          dependencies: [RuntimeTool.curl],
        ),
        const RuntimeDependency(
          tool: RuntimeTool.git,
          displayName: 'Git',
          icon: '🔀',
          category: RuntimeCategory.coding,
          dependencies: [RuntimeTool.curl],
        ),
        const RuntimeDependency(
          tool: RuntimeTool.python,
          displayName: 'Python 3',
          icon: '🐍',
          category: RuntimeCategory.coding,
          dependencies: [RuntimeTool.curl],
        ),
        const RuntimeDependency(
          tool: RuntimeTool.codexCli,
          displayName: 'Codex CLI',
          icon: '🤖',
          category: RuntimeCategory.coding,
          dependencies: [RuntimeTool.node],
        ),
        const RuntimeDependency(
          tool: RuntimeTool.mimo2codex,
          displayName: 'mimo2codex',
          icon: '🔌',
          category: RuntimeCategory.coding,
          dependencies: [RuntimeTool.node],
        ),

        // ── AI Runtime ──
        const RuntimeDependency(
          tool: RuntimeTool.deepseekKey,
          displayName: 'DeepSeek API Key',
          icon: '🔑',
          category: RuntimeCategory.ai,
          dependencies: [],
          hint: '用于 AI 代码补全（mimo2codex / AI Provider）',
        ),

        // ── Development Runtime ──
        const RuntimeDependency(
          tool: RuntimeTool.flutterSdk,
          displayName: 'Flutter SDK',
          icon: '🦋',
          category: RuntimeCategory.development,
          optional: true,
          hint: '可选 — 仅用于 Flutter 项目开发，不影响 App 基本运行',
        ),
      ];

  /// 根据 RuntimeTool 获取依赖定义
  static RuntimeDependency? forTool(RuntimeTool tool) {
    for (final dep in all) {
      if (dep.tool == tool) return dep;
    }
    return null;
  }

  /// 获取指定类别的工具列表
  static List<RuntimeDependency> byCategory(RuntimeCategory category) {
    return all.where((d) => d.category == category).toList();
  }

  /// 获取安装顺序（拓扑排序）
  ///
  /// 按照依赖关系排序，确保依赖先安装。
  /// 不包含 optional=true 的工具，除非 [includeOptional] 为 true。
  static List<RuntimeTool> installOrder({bool includeOptional = false}) {
    final tools = all.where((d) => includeOptional || !d.optional).toList();
    final visited = <RuntimeTool>{};
    final result = <RuntimeTool>[];

    void dfs(RuntimeTool tool) {
      if (visited.contains(tool)) return;
      visited.add(tool);

      final dep = forTool(tool);
      if (dep != null) {
        for (final d in dep.dependencies) {
          dfs(d);
        }
      }
      result.add(tool);
    }

    for (final dep in tools) {
      dfs(dep.tool);
    }

    return result;
  }
}
