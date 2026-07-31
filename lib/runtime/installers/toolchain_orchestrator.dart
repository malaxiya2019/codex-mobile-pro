/// ====================================================================
/// 工具链安装编排器（Coding Runtime）
///
/// 负责 Coding Runtime 工具链的安装顺序、依赖检查与失败恢复。
///
/// 依赖顺序（严格串行，禁止并行）：
///   Node.js → npm（随 nodejs 安装）→ Git → Python → Codex → mimo2codex
///
/// 全部在 Ubuntu 24.04 rootfs 内执行（runtimeId='linux' → PRoot），
/// 禁止依赖 Termux pkg。
///
/// 幂等：每个 Installer 先真实检测（rootfs 内 --version），
///   已安装 → SKIP；
///   安装失败 → 保留真实原因（DeployError），不伪装成功。
///
/// 状态约定（Phase 4）：
///   NOT_INSTALLED / INSTALLING / VERIFYING / INSTALLED / FAILED
///   「暂不支持自动安装」仅保留给真正的平台不支持（无安装器）。
/// ====================================================================
library;

import '../install_models.dart';
import '../runtime_dependency.dart';
import 'apt_toolchain_installers.dart';
import 'npm_toolchain_installers.dart';
import 'toolchain_context.dart';
import 'toolchain_installer.dart';

/// 工具链安装编排器
class ToolchainOrchestrator {
  final List<ToolchainInstaller> _installers;
  final Map<RuntimeTool, ToolchainInstaller> _byTool;

  ToolchainOrchestrator({
    List<ToolchainInstaller>? installers,
  })  : _installers = installers ?? _defaultInstallers(),
        _byTool = {} {
    for (final installer in _installers) {
      _byTool[installer.tool] = installer;
    }
  }

  /// 默认安装器列表（按依赖顺序）
  static List<ToolchainInstaller> _defaultInstallers() => [
        NodeJsInstaller(),
        GitInstaller(),
        PythonInstaller(),
        CodexCliInstaller(),
        Mimo2codexInstaller(),
      ];

  /// 是否存在对应工具链安装器
  ///
  /// false = 真正的平台不支持（非「未实现」占位）。
  bool hasInstallerFor(RuntimeTool tool) => _byTool.containsKey(tool);

  /// 绑定进度回调（透传给所有 Installer）
  void bindProgress(InstallProgressCallback? cb) {
    for (final installer in _installers) {
      installer.bindProgress(cb);
    }
  }

  /// 安装单个工具（完整依赖检查 + 幂等）
  ///
  /// 返回 InstallResult：
  ///   - 无安装器 → UNSUPPORTED
  ///   - Linux Runtime 未就绪 → BLOCKED
  ///   - 依赖未安装 → BLOCKED
  ///   - 已安装 / 安装成功 → success
  ///   - 安装失败 → FAILED（携带真实原因）
  Future<InstallResult> installOne(
    RuntimeTool tool,
    ToolchainContext ctx,
  ) async {
    final installer = _byTool[tool];
    if (installer == null) {
      return InstallResult(
        tool: tool,
        success: false,
        errorMessage: '暂不支持自动安装（当前平台无可用安装器）',
        phase: InstallPhase.failed,
      );
    }

    final dep = RuntimeDependency.forTool(tool);

    // 1. Linux Runtime 依赖检查
    if (dep != null && dep.dependencies.contains(RuntimeTool.ubuntu)) {
      if (!await ctx.isLinuxReady()) {
        return InstallResult(
          tool: tool,
          success: false,
          errorMessage: 'Linux Runtime 未就绪，请先初始化 Linux Runtime',
          phase: InstallPhase.blocked,
        );
      }
    }

    // 2. 其他依赖检查（Node 等）
    if (dep != null) {
      for (final d in dep.dependencies) {
        if (d == RuntimeTool.ubuntu) continue;
        final depInstaller = _byTool[d];
        if (depInstaller != null && !await depInstaller.isInstalled(ctx)) {
          return InstallResult(
            tool: tool,
            success: false,
            errorMessage: '⛔ 依赖 ${depInstaller.displayName} 未安装，跳过',
            phase: InstallPhase.blocked,
          );
        }
      }
    }

    // 3. 幂等安装（安装器内部先真实检测已安装 → SKIP）
    return installer.install(ctx);
  }

  /// 按依赖顺序安装全部 Coding Runtime 工具
  ///
  /// 返回逐个工具的安装结果：
  ///   - 已安装 → SKIP（success）
  ///   - 依赖失败 → BLOCKED（后续工具继续尝试，失败恢复）
  ///   - 安装失败 → FAILED（保留真实原因）
  Future<List<InstallResult>> installAll(ToolchainContext ctx) async {
    final results = <InstallResult>[];
    final failedTools = <RuntimeTool>{};

    for (final installer in _installers) {
      final tool = installer.tool;
      final dep = RuntimeDependency.forTool(tool);

      // 依赖检查 → blocked
      bool blocked = false;
      if (dep != null) {
        for (final d in dep.dependencies) {
          if (d == RuntimeTool.ubuntu) {
            if (!await ctx.isLinuxReady()) {
              results.add(InstallResult(
                tool: tool,
                success: false,
                errorMessage: 'Linux Runtime 未就绪，请先初始化 Linux Runtime',
                phase: InstallPhase.blocked,
              ));
              blocked = true;
              break;
            }
          } else if (failedTools.contains(d)) {
            results.add(InstallResult(
              tool: tool,
              success: false,
              errorMessage: '⛔ 依赖 ${d.name} 安装失败，跳过',
              phase: InstallPhase.blocked,
            ));
            blocked = true;
            break;
          }
        }
      }
      if (blocked) continue;

      final result = await installer.install(ctx);
      results.add(result);
      if (!result.success) failedTools.add(tool);
    }

    return results;
  }
}
