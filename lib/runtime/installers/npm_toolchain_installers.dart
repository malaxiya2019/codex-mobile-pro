/// ====================================================================
/// npm 全局工具安装器（Codex CLI / mimo2codex）
///
/// 依赖 Node.js + npm（apt 阶段先完成），通过
///   npm install -g package
/// 安装到 Ubuntu rootfs 内 /usr/lib/node_modules，可执行文件
/// 位于 /usr/bin/`<bin>`（由 npm 创建符号链接）。
///
/// 包名（2026-08 npm registry 实证，禁止凭记忆猜）：
///   - Codex CLI：@openai/codex   → bin: codex
///   - mimo2codex：mimo2codex     → bin: mimo2codex
///
/// 幂等：已安装（rootfs 内 --version 通过）→ 直接 SKIP。
/// ====================================================================
library;

import '../deploy_error.dart';
import '../install_models.dart';
import '../runtime_dependency.dart';
import 'toolchain_context.dart';
import 'toolchain_installer.dart';

/// Codex CLI 安装器（npm 包 @openai/codex）
class CodexCliInstaller extends ToolchainInstaller {
  /// npm 包名（npm registry 实证）
  static const String npmPackage = '@openai/codex';

  /// rootfs 内可执行名
  static const String binary = '/usr/bin/codex';

  @override
  RuntimeTool get tool => RuntimeTool.codexCli;

  @override
  String get displayName => 'Codex CLI';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    return await ctx.versionOf(binary) != null;
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    return ctx.versionOf(binary);
  }

  @override
  Future<InstallResult> install(ToolchainContext ctx) async {
    final ver = await installedVersion(ctx);
    if (ver != null) {
      report(ctx, InstallPhase.completed, 1.0, '已安装，跳过');
      return success(ver, skipped: true);
    }

    // npm 缺失 → 结构化依赖错误
    if (await ctx.versionOf('/usr/bin/npm') == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.dependencyMissing,
          message: 'Codex CLI 安装失败：npm 缺失',
          detail: '请先完成 Node.js/npm 安装',
          userSuggestion: '先安装 Node.js 后再重试',
        ),
      );
    }

    report(ctx, InstallPhase.installing, 0.3, 'npm 安装 @openai/codex...');
    try {
      await ctx.npmInstallGlobal([npmPackage]);
    } catch (e) {
      return failure(e);
    }

    report(ctx, InstallPhase.verifying, 0.9, '验证 codex...');
    final vCodex = await installedVersion(ctx);
    if (vCodex == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.healthCheckFailed,
          message: 'Codex CLI 安装后验证失败',
          detail: 'npm install 成功但 codex --version 无法执行',
          userSuggestion: '尝试重新初始化后重试',
        ),
      );
    }
    report(ctx, InstallPhase.completed, 1.0, 'Codex CLI 安装完成');
    return success(vCodex);
  }
}

/// mimo2codex 安装器（npm 包 mimo2codex）
class Mimo2codexInstaller extends ToolchainInstaller {
  /// npm 包名（npm registry 实证）
  static const String npmPackage = 'mimo2codex';

  /// rootfs 内可执行名
  static const String binary = '/usr/bin/mimo2codex';

  @override
  RuntimeTool get tool => RuntimeTool.mimo2codex;

  @override
  String get displayName => 'mimo2codex';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    return await ctx.versionOf(binary) != null;
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    return ctx.versionOf(binary);
  }

  @override
  Future<InstallResult> install(ToolchainContext ctx) async {
    final ver = await installedVersion(ctx);
    if (ver != null) {
      report(ctx, InstallPhase.completed, 1.0, '已安装，跳过');
      return success(ver, skipped: true);
    }

    if (await ctx.versionOf('/usr/bin/npm') == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.dependencyMissing,
          message: 'mimo2codex 安装失败：npm 缺失',
          detail: '请先完成 Node.js/npm 安装',
          userSuggestion: '先安装 Node.js 后再重试',
        ),
      );
    }

    report(ctx, InstallPhase.installing, 0.3, 'npm 安装 mimo2codex...');
    try {
      await ctx.npmInstallGlobal([npmPackage]);
    } catch (e) {
      return failure(e);
    }

    report(ctx, InstallPhase.verifying, 0.9, '验证 mimo2codex...');
    final vMimo = await installedVersion(ctx);
    if (vMimo == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.healthCheckFailed,
          message: 'mimo2codex 安装后验证失败',
          detail: 'npm install 成功但 mimo2codex --version 无法执行',
          userSuggestion: '尝试重新初始化后重试',
        ),
      );
    }
    report(ctx, InstallPhase.completed, 1.0, 'mimo2codex 安装完成');
    return success(vMimo);
  }
}
