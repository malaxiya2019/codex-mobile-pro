/// ====================================================================
/// uv / uvx 安装器
///
/// Qwen-MM-Plugins 的 MCP server 通过 `uvx --from <pkg>@git+...` 按需
/// 启动（Python 包由 uvx 临时环境拉取，不污染 rootfs 系统 Python）。
///
/// 安装方式：rootfs 内 `pip install uv`（PythonInstaller 已装好
/// python3 + pip）。pip 会把 uv 装到 /usr/local/bin/uv(x)，
/// 与系统 Python 共存，不引入第三方 apt 源。
///
/// 幂等：rootfs 内 `uvx --version` 通过 → 直接 SKIP。
/// 依赖：Python 3（RuntimeDependency.uv.dependencies 已声明，编排器
/// 保证 Python 先装）。
/// ====================================================================
library;

import '../deploy_error.dart';
import '../install_models.dart';
import '../runtime_dependency.dart';
import 'toolchain_context.dart';
import 'toolchain_installer.dart';

/// uv / uvx 安装器（pip install uv）
class UvInstaller extends ToolchainInstaller {
  /// rootfs 内可执行名（pip 安装默认前缀 /usr/local）
  static const String binary = '/usr/local/bin/uv';

  /// rootfs 内 uvx 可执行名
  static const String uvxBinary = '/usr/local/bin/uvx';

  @override
  RuntimeTool get tool => RuntimeTool.uv;

  @override
  String get displayName => 'uv / uvx';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    return await ctx.versionOf(uvxBinary) != null;
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    return ctx.versionOf(uvxBinary);
  }

  @override
  Future<InstallResult> install(ToolchainContext ctx) async {
    final ver = await installedVersion(ctx);
    if (ver != null) {
      report(ctx, InstallPhase.completed, 1.0, '已安装，跳过');
      return success(ver, skipped: true);
    }

    // python3/pip 缺失 → 结构化依赖错误（PythonInstaller 先于本安装器，
    // 正常不会走到，防御性检查）
    final pythonOk = await ctx.versionOf('/usr/bin/python3') != null;
    final pipOk = await ctx.versionOf('/usr/bin/pip3') != null ||
        await ctx.versionOf('/usr/bin/pip') != null;
    if (!pythonOk || !pipOk) {
      return failure(
        const DeployError(
          code: DeployErrorCode.dependencyMissing,
          message: 'uv 安装失败：Python/pip 缺失',
          detail: 'Qwen-MM-Plugins 需要 Python 3 + pip 来安装 uv',
          userSuggestion: '先完成 Python 3 安装后再重试',
        ),
      );
    }

    report(ctx, InstallPhase.installing, 0.3, 'pip 安装 uv...');
    try {
      await ctx.runInRootfs(
        '/usr/bin/pip3',
        arguments: ['install', '--quiet', 'uv'],
        timeout: const Duration(minutes: 5),
        label: 'pip:install:uv',
      );
      // pip3 不存在时回退 pip
      if (await ctx.versionOf(uvxBinary) == null) {
        await ctx.runInRootfs(
          '/usr/bin/pip',
          arguments: ['install', '--quiet', 'uv'],
          timeout: const Duration(minutes: 5),
          label: 'pip:install:uv',
        );
      }
    } catch (e) {
      return failure(e);
    }

    report(ctx, InstallPhase.verifying, 0.9, '验证 uv/uvx...');
    final vUvx = await installedVersion(ctx);
    if (vUvx == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.healthCheckFailed,
          message: 'uv 安装后验证失败',
          detail: 'pip install uv 成功但 uvx --version 无法执行',
          userSuggestion: '尝试重新初始化后重试',
        ),
      );
    }
    report(ctx, InstallPhase.completed, 1.0, 'uv/uvx 安装完成');
    return success(vUvx);
  }
}
