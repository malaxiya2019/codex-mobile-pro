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
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

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

  /// 内置 Codex Skills 打包文件（由 skills/ 目录生成，含 .system 系统级）
  ///
  /// 为什么打包成单个 tar.gz 而非直接声明 skills/ 目录：skills/ 内含
  /// .system 隐藏目录，Flutter asset 打包会忽略隐藏目录；tar 归档不
  /// 区分隐藏文件，可完整保留。部署时用 archive 包（依赖已有）在 Dart
  /// 侧解压写入 rootfs，不依赖 rootfs 内任何解压工具。
  static const String skillsBundleAsset = 'assets/skills.tar.gz';

  /// Skills 已部署幂等标记（写在 rootfs ~/.codex/skills/ 下）
  static const String skillsMarker = '.codex-mobile-skills.marker';

  /// Skills 打包内容加载器（测试注入用；null = 从 asset 读取）
  final Future<Uint8List> Function()? loadSkillsBundle;

  /// 幂等标记（与 deploy.sh setup_shell 的 grep 标记一致）
  static const String shellMarker = '# Codex Mobile Pro';

  /// Shell 快捷命令内容加载器（测试注入用；null = 从 asset 读取）
  final Future<String> Function()? loadShellAdditions;

  /// Codex CLI 配置文件内容（DeepSeek 直连）
  ///
  /// 让终端 `codex` / `cyo` 直接用 DEEPSEEK_API_KEY（bashrc-additions.sh
  /// 从 ~/.mimo2codex/.env export），跳过 ChatGPT 登录引导
  /// （否则 codex 首次运行弹 Welcome to Codex 要求 Sign in）。
  /// 与 codex_runner.dart（App 内 AI 对话）同一套模型提供方配置。
  static const String codexConfigToml = '''
model = "deepseek-chat"
model_provider = "deepseek"

[model_providers.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
env_key = "DEEPSEEK_API_KEY"
wire_api = "responses"
''';

  /// config.toml 已配置的幂等标记
  static const String codexConfigMarker = '[model_providers.deepseek]';

  CodexCliInstaller({this.loadShellAdditions, this.loadSkillsBundle});

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
      // 自愈：修复前部署的旧 rootfs codex 已装但 .bashrc 无快捷命令，
      // 幂等补注入 cyo/cy/cs（含标记则跳过），避免「已安装跳过→永不注入」；
      // 同时补写 ~/.codex/config.toml（DeepSeek 直连），否则终端 codex
      // 会弹 ChatGPT 登录引导。
      await _injectShellAdditions(ctx);
      await _writeCodexConfig(ctx);
      await _deploySkills(ctx);
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
      await ctx.npmInstallGlobal([npmPackage],
          onProgress: (p, m) => report(ctx, InstallPhase.installing, p, m));
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
    await _writeCodexConfig(ctx);
    await _deploySkills(ctx);
    // 启动指引（部署中心进度区展示，覆盖一键部署与单工具两条路径）
    report(
      ctx,
      InstallPhase.completed,
      1.0,
      '✅ Codex 已就绪：首页「终端」→ 输入 cyo --zh（中文）或 cs（安全模式）即可启动',
    );
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


  /// 部署内置 Codex Skills 到 rootfs `~/.codex/skills/`（含 .system 系统级）
  ///
  /// 场景：App 一键部署只 npm install codex，从不带 skills；手动部署由
  /// deploy.sh deploy_skills() 负责。这里让一键部署也补上全部内置 skills，
  /// codex 在 rootfs 内可直接使用完整技能集（imagegen/openai-docs/分析/逆向等）。
  ///
  /// 实现：读 asset 内 tar.gz → archive 包解压（纯 Dart，不依赖 rootfs
  /// 工具）→ 写 rootfs 文件，保留可执行位（rev-dex-dumper 二进制）。
  /// 幂等：[skillsMarker] 存在 → 跳过。失败不阻断安装。
  Future<void> _deploySkills(ToolchainContext ctx) async {
    try {
      final paths = await ctx.resolvePaths();
      final target = Directory('${paths.rootfsDir}/root/.codex/skills');
      final marker = File('${target.path}/$skillsMarker');

      if (marker.existsSync()) {
        report(ctx, InstallPhase.completed, 1.0, 'Codex Skills 已部署');
        return;
      }

      final bytes = await _resolveSkillsBundle();
      final tarBytes = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(tarBytes);

      target.createSync(recursive: true);
      var count = 0;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final rel = _safeSkillRelPath(entry.name);
        if (rel == null) continue;
        final dest = File('${target.path}/$rel');
        dest.parent.createSync(recursive: true);
        dest.writeAsBytesSync(entry.content as List<int>);
        // 保留可执行位（如 rev-dex-dumper/panda-dex-dumper）
        if ((entry.mode & 0x40) != 0) {
          try {
            Process.runSync('chmod', ['+x', dest.path]);
          } catch (_) {}
        }
        count++;
      }

      marker.writeAsStringSync('deployed=${DateTime.now().toIso8601String()}\n');
      report(
        ctx,
        InstallPhase.completed,
        1.0,
        'Codex Skills 已部署 $count 个文件（含 .system 系统级）',
      );
    } catch (e) {
      LogService.warning('Toolchain', 'Codex Skills 部署失败（不阻断安装）: $e');
    }
  }

  /// 读取 Skills 打包内容（测试注入 → 默认从 asset 加载）
  Future<Uint8List> _resolveSkillsBundle() async {
    if (loadSkillsBundle != null) return loadSkillsBundle!();
    final data = await rootBundle.load(skillsBundleAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// 将 tar 条目名转为安全相对路径（去 ./ 前缀，拒绝 .. 穿越）
  static String? _safeSkillRelPath(String tarPath) {
    final cleaned = path.posix.normalize(tarPath);
    if (cleaned == '..' ||
        cleaned.startsWith('../') ||
        path.posix.isAbsolute(cleaned)) {
      return null;
    }
    final rel = cleaned.startsWith('./') ? cleaned.substring(2) : cleaned;
    if (rel.isEmpty || rel == '.') return null;
    return rel;
  }

  /// 写入 rootfs `~/.codex/config.toml`（DeepSeek 直连，幂等）
  ///
  /// 真机现象：终端 `codex` / `cyo --zh` 进 Welcome to Codex 登录引导
  /// （Sign in with ChatGPT / Device Code / API key）。根因是 App 部署
  /// 只 npm install codex，从不写 config.toml，codex 默认要求登录。
  /// 修复：写入 [codexConfigToml]，codex 读取 `env_key` 指向的环境变量
  /// DEEPSEEK_API_KEY（由 bashrc-additions.sh 从 ~/.mimo2codex/.env
  /// export），直连 DeepSeek、跳过登录。
  ///
  /// 幂等：已含 [codexConfigMarker] → 跳过。失败不阻断安装。
  Future<void> _writeCodexConfig(ToolchainContext ctx) async {
    try {
      final paths = await ctx.resolvePaths();
      final config = File('${paths.rootfsDir}/root/.codex/config.toml');

      if (config.existsSync() &&
          config.readAsStringSync().contains(codexConfigMarker)) {
        report(ctx, InstallPhase.completed, 1.0, 'Codex 已配置 DeepSeek 直连');
        return;
      }

      await config.parent.create(recursive: true);
      await config.writeAsString(codexConfigToml);
      report(ctx, InstallPhase.completed, 1.0, 'Codex 已配置 DeepSeek 直连');
    } catch (e) {
      LogService.warning('Toolchain', 'Codex config 写入失败（不阻断安装）: $e');
    }
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
      await ctx.npmInstallGlobal([npmPackage],
          onProgress: (p, m) => report(ctx, InstallPhase.installing, p, m));
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
