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
///
/// 真机修复（cyo: command not found）：App 一键部署仅 npm install，
/// 从不把 config/bashrc-additions.sh 追加到 rootfs /root/.bashrc；
/// 手动部署路径由 deploy.sh setup_shell() 追加。本安装器在验证
/// codex 后把 asset（assets/bashrc-additions.sh，与 config/ 保持同步）
/// 幂等追加到 /root/.bashrc，恢复 cyo/cy/cs 快捷命令、PATH 与
/// DEEPSEEK_API_KEY 兜底 export。
/// ====================================================================
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/logger/log_service.dart';
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

  /// Shell 快捷命令 asset（打包自 config/bashrc-additions.sh，两处保持同步）
  static const String shellAdditionsAsset = 'assets/bashrc-additions.sh';

  /// 幂等标记（与 deploy.sh setup_shell 的 grep 标记一致）
  static const String shellMarker = '# Codex Mobile Pro';

  /// Shell 快捷命令内容加载器（测试注入用；null = 从 asset 读取）
  final Future<String> Function()? loadShellAdditions;

  CodexCliInstaller({this.loadShellAdditions});

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
    await _injectShellAdditions(ctx);
    return success(vCodex);
  }

  /// 注入 Shell 快捷命令（cyo/cy/cs 等）到 rootfs /root/.bashrc
  ///
  /// 根因（真机 cyo: command not found）：App 一键部署只执行
  /// npm install -g @openai/codex，从不追加 config/bashrc-additions.sh；
  /// 手动部署路径由 deploy.sh setup_shell() 追加，App 路径缺失。
  /// 修复：安装成功后把 asset 内容幂等追加到 /root/.bashrc，
  ///   同时恢复 PATH 注入与 DEEPSEEK_API_KEY 兜底 export
  ///   （saveDeepSeekKey 已把 DS_API_KEY 写入 /root/.mimo2codex/.env，
  ///   bashrc-additions.sh 交互 shell 从这里 export DEEPSEEK_API_KEY）。
  ///
  /// 幂等：/root/.bashrc 已含 [shellMarker] → 跳过（不重复追加）。
  /// 失败不阻断安装：快捷命令为增强步骤，Codex 本体已可用。
  Future<void> _injectShellAdditions(ToolchainContext ctx) async {
    try {
      final paths = await ctx.resolvePaths();
      final bashrc = File('${paths.rootfsDir}/root/.bashrc');

      if (bashrc.existsSync() &&
          bashrc.readAsStringSync().contains(shellMarker)) {
        report(ctx, InstallPhase.completed, 1.0, 'Shell 快捷命令已存在');
        return;
      }

      final content = await _resolveShellAdditions();
      await bashrc.parent.create(recursive: true);
      await bashrc.writeAsString(content, mode: FileMode.append);
      report(ctx, InstallPhase.completed, 1.0, 'Shell 快捷命令已注入 ~/.bashrc');
    } catch (e) {
      LogService.warning('Toolchain', 'Shell 快捷命令注入失败（不阻断安装）: $e');
    }
  }

  /// 读取 Shell 快捷命令内容（测试注入 → 默认从 asset 加载）
  Future<String> _resolveShellAdditions() async {
    if (loadShellAdditions != null) return loadShellAdditions!();
    return rootBundle.loadString(shellAdditionsAsset);
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
