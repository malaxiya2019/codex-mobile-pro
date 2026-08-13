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

  /// npm -g 可执行名（rootfs PATH 解析用）
  static const String binaryName = 'codex';

  /// 候选安装路径（npm -g 在 Ubuntu rootfs 的常见 prefix）
  ///
  /// 真机实证：Ubuntu noble rootfs 中 npm -g 实际装到 /usr/local/bin/codex
  /// （npm 默认 prefix），早期/特定布局为 /usr/bin/codex。禁止只写死一个
  /// 路径——installedVersion 找不到真实路径会让 install() 验证失败，
  /// 注入（cyo 等）永不执行（cyo: command not found 的根因）。
  /// 统一由 [_resolveNpmGlobalBinary] 解析（rootfs PATH 优先 + 候选兜底）。
  static const List<String> binaryCandidates = [
    '/usr/local/bin/codex',
    '/usr/bin/codex',
  ];

  /// Shell 快捷命令 asset（打包自 config/bashrc-additions.sh，两处保持同步）
  static const String shellAdditionsAsset = 'assets/bashrc-additions.sh';

  /// threadripper 会话监控脚本 asset。
  ///
  /// 来源：deploy.sh install_threadripper() heredoc（手动部署路径），
  /// 此处抽为 asset 供 App 一键部署复制到 rootfs ~/.local/bin/，
  /// thread_start() 用 `nohup node ~/.local/bin/threadripper.js` 拉起。
  static const String threadripperAsset = 'assets/threadripper.js';

  /// DeepSeek 模型元数据目录（model_catalog_json 指向的 JSON 文件）。
  ///
  /// 消除 codex 启动警告 `Model metadata for deepseek-chat not found`：
  /// Codex 内置模型目录只有 OpenAI 模型，deepseek-chat 直连时找不到
  /// 元数据 → 退化为 fallback（上下文窗口等参数全错）。此 asset 以
  /// ModelsResponse 格式（{"models": [...]}）提供合法 ModelInfo 条目，
  /// 由 [_deployModelCatalog] 写入 rootfs 供 codex 启动时加载。
  static const String modelCatalogAsset = 'assets/deepseek-models.json';

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

  /// threadripper.js 内容加载器（测试注入用；null = 从 asset 读取）
  final Future<String> Function()? loadThreadripper;

  /// DeepSeek 模型元数据内容加载器（测试注入用；null = 从 asset 读取）
  final Future<String> Function()? loadModelCatalog;

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
model_catalog_json = "/root/.codex/models.json"

[model_providers.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
env_key = "DEEPSEEK_API_KEY"
wire_api = "responses"
''';

  /// config.toml 已配置的幂等标记
  static const String codexConfigMarker = '[model_providers.deepseek]';

  /// 模型元数据目录在 rootfs 内的绝对路径（与 [codexConfigToml] 中
  /// model_catalog_json 保持一致；codex 在 HOME=/root 下读取）。
  static const String modelCatalogPath = '/root/.codex/models.json';

  /// config.toml 顶层 model_catalog_json 行的幂等标记（旧版本部署的
  /// config 只含 [codexConfigMarker]、不含本行 → 需幂等补写）。
  static const String modelCatalogMarker = 'model_catalog_json';

  /// config.toml 顶层 model_catalog_json 行（必须位于任何 table 之前）
  static const String modelCatalogLine =
      'model_catalog_json = "$modelCatalogPath"';

  CodexCliInstaller({
    this.loadShellAdditions,
    this.loadSkillsBundle,
    this.loadThreadripper,
    this.loadModelCatalog,
  });

  @override
  RuntimeTool get tool => RuntimeTool.codexCli;

  @override
  String get displayName => 'Codex CLI';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    return await _resolveBinary(ctx) != null;
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    final resolved = await _resolveBinary(ctx);
    if (resolved == null) return null;
    return ctx.versionOf(resolved);
  }

  /// 解析 Codex CLI 实际安装路径。
  ///
  /// installedVersion / isInstalled / 安装后健康检查统一走这里，
  /// 保证三处看到同一个真实路径。
  Future<String?> _resolveBinary(ToolchainContext ctx) async {
    return _resolveNpmGlobalBinary(ctx, binaryName, binaryCandidates);
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
      final warnings = <String>[];
      await _injectShellAdditions(ctx, warnings);
      await _writeCodexConfig(ctx, warnings);
      await _deployModelCatalog(ctx, warnings);
      await _deploySkills(ctx, warnings);
      await _deployThreadripper(ctx, warnings);
      return success(ver, skipped: true, warnings: warnings);
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
    final warnings = <String>[];
    await _injectShellAdditions(ctx, warnings);
    await _writeCodexConfig(ctx, warnings);
    await _deployModelCatalog(ctx, warnings);
    await _deploySkills(ctx, warnings);
    await _deployThreadripper(ctx, warnings);
    // 启动指引（部署中心进度区展示，覆盖一键部署与单工具两条路径）
    report(
      ctx,
      InstallPhase.completed,
      1.0,
      '✅ Codex 已就绪：首页「终端」→ 输入 cyo --zh（中文）或 cs（安全模式）即可启动',
    );
    return success(vCodex, warnings: warnings);
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
  Future<void> _injectShellAdditions(
      ToolchainContext ctx, List<String> warnings) async {
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
      _recordWarning(warnings, 'Shell 快捷命令注入失败', e);
    }
  }

  /// 读取 Shell 快捷命令内容（测试注入 → 默认从 asset 加载）
  Future<String> _resolveShellAdditions() async {
    if (loadShellAdditions != null) return loadShellAdditions!();
    return rootBundle.loadString(shellAdditionsAsset);
  }

  /// 记录非致命失败到 [warnings]（不吞掉，供 InstallResult / UI 展示）。
  ///
  /// 增强步骤（shell 注入 / config / skills / threadripper）失败不阻断
  /// Codex 本体安装，但原因必须透出——不再只打 LogService.warning 静默。
  void _recordWarning(List<String> warnings, String what, Object e) {
    final msg = '$what（Codex 本体仍可用）: $e';
    LogService.warning('Toolchain', msg);
    warnings.add(msg);
  }

  /// 部署 threadripper 会话监控脚本到 rootfs `~/.local/bin/threadripper.js`。
  ///
  /// 真机根因：bashrc-additions.sh 的 thread_start() 用
  /// `nohup node ~/.local/bin/threadripper.js` 拉起，但 App 一键部署从不
  /// 复制该脚本 → cyo 即使注入成功，thread_start 也拉不起来。此处把
  /// asset assets/threadripper.js（源自 deploy.sh install_threadripper()
  /// heredoc，非凭空编写）复制到 rootfs 并加可执行位，闭合
  /// cyo → thread_start → threadripper.js → codex 真实闭环。
  ///
  /// 幂等：目标已存在且内容与 asset 一致 → 跳过；不一致 → 更新。
  Future<void> _deployThreadripper(
      ToolchainContext ctx, List<String> warnings) async {
    try {
      final paths = await ctx.resolvePaths();
      final dest = File('${paths.rootfsDir}/root/.local/bin/threadripper.js');
      final content = await _resolveThreadripper();

      if (dest.existsSync() && dest.readAsStringSync() == content) {
        report(ctx, InstallPhase.completed, 1.0, 'threadripper 已部署');
        return;
      }

      await dest.parent.create(recursive: true);
      await dest.writeAsString(content);
      try {
        Process.runSync('chmod', ['+x', dest.path]);
      } catch (_) {}
      report(
        ctx,
        InstallPhase.completed,
        1.0,
        'threadripper 已部署 ~/.local/bin/threadripper.js',
      );
    } catch (e) {
      _recordWarning(warnings, 'threadripper 部署失败', e);
    }
  }

  /// 读取 threadripper.js 内容（测试注入 → 默认从 asset 加载）
  Future<String> _resolveThreadripper() async {
    if (loadThreadripper != null) return loadThreadripper!();
    return rootBundle.loadString(threadripperAsset);
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
  Future<void> _deploySkills(
      ToolchainContext ctx, List<String> warnings) async {
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
      _recordWarning(warnings, 'Codex Skills 部署失败', e);
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

  /// 部署 DeepSeek 模型元数据到 rootfs `~/.codex/models.json`。
  ///
  /// 真机现象：终端 `codex` / `cyo` 启动输出
  ///   ⚠ Model metadata for deepseek-chat not found.
  ///     Defaulting to fallback metadata; this can degrade performance...
  /// 根因：config.toml 用 model_provider=deepseek 直连 api.deepseek.com，
  ///   但 Codex 内置模型目录只有 OpenAI 模型，找不到 deepseek-chat → 退化
  ///   fallback 元数据（上下文窗口等参数全错）。
  /// 修复：把 asset（assets/deepseek-models.json，源自 Codex ModelInfo
  ///   schema + deepseek-chat 官方参数，非凭空编写）写入 [modelCatalogPath]，
  ///   config.toml 顶层 model_catalog_json 指向它，codex 启动加载该目录
  ///   即可命中 deepseek-chat 元数据。
  ///
  /// 幂等：目标已存在且内容与 asset 一致 → 跳过；不一致 → 更新。
  /// 失败不阻断安装：元数据缺失只影响上下文窗口精度，Codex 仍可运行，
  /// 但原因必须透出到 [warnings]（UI 可见）。
  Future<void> _deployModelCatalog(
      ToolchainContext ctx, List<String> warnings) async {
    try {
      final paths = await ctx.resolvePaths();
      final dest = File('${paths.rootfsDir}$modelCatalogPath');
      final content = await _resolveModelCatalog();

      if (dest.existsSync() && dest.readAsStringSync() == content) {
        report(ctx, InstallPhase.completed, 1.0, 'DeepSeek 模型目录已部署');
        return;
      }

      await dest.parent.create(recursive: true);
      await dest.writeAsString(content);
      report(ctx, InstallPhase.completed, 1.0,
          'DeepSeek 模型目录已部署 ~/.codex/models.json');
    } catch (e) {
      _recordWarning(warnings, 'DeepSeek 模型目录部署失败', e);
    }
  }

  /// 读取 DeepSeek 模型元数据内容（测试注入 → 默认从 asset 读取）
  Future<String> _resolveModelCatalog() async {
    if (loadModelCatalog != null) return loadModelCatalog!();
    return rootBundle.loadString(modelCatalogAsset);
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
  Future<void> _writeCodexConfig(
      ToolchainContext ctx, List<String> warnings) async {
    try {
      final paths = await ctx.resolvePaths();
      final config = File('${paths.rootfsDir}/root/.codex/config.toml');

      if (config.existsSync()) {
        final existing = config.readAsStringSync();
        if (existing.contains(codexConfigMarker)) {
          if (existing.contains(modelCatalogMarker)) {
            report(ctx, InstallPhase.completed, 1.0,
                'Codex 已配置 DeepSeek 直连 + 模型目录');
          } else {
            // 旧版本部署的 config：已 DeepSeek 直连但缺 model_catalog_json。
            // TOML 顶层字段必须在任何 table 之前 → 插到文件最前，不覆盖
            // 用户已有内容，消除 codex 启动的 fallback metadata 警告。
            await config.writeAsString('$modelCatalogLine\n$existing');
            report(ctx, InstallPhase.completed, 1.0,
                'Codex 已补写 model_catalog_json（旧 config 升级）');
          }
          return;
        }
      }

      await config.parent.create(recursive: true);
      await config.writeAsString(codexConfigToml);
      report(ctx, InstallPhase.completed, 1.0, 'Codex 已配置 DeepSeek 直连');
    } catch (e) {
      _recordWarning(warnings, 'Codex config 写入失败', e);
    }
  }
}

/// mimo2codex 安装器（npm 包 mimo2codex）
class Mimo2codexInstaller extends ToolchainInstaller {
  /// npm 包名（npm registry 实证）
  static const String npmPackage = 'mimo2codex';

  /// npm -g 可执行名（rootfs PATH 解析用）
  static const String binaryName = 'mimo2codex';

  /// 候选安装路径（npm -g 在 Ubuntu rootfs 的常见 prefix，禁止硬编码单一路径）
  static const List<String> binaryCandidates = [
    '/usr/local/bin/mimo2codex',
    '/usr/bin/mimo2codex',
  ];

  @override
  RuntimeTool get tool => RuntimeTool.mimo2codex;

  @override
  String get displayName => 'mimo2codex';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    return await _resolveBinary(ctx) != null;
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    final resolved = await _resolveBinary(ctx);
    if (resolved == null) return null;
    return ctx.versionOf(resolved);
  }

  /// 解析 mimo2codex 实际安装路径。
  ///
  /// installedVersion / isInstalled / 安装后健康检查统一走这里，
  /// 保证三处看到同一个真实路径。
  Future<String?> _resolveBinary(ToolchainContext ctx) async {
    return _resolveNpmGlobalBinary(ctx, binaryName, binaryCandidates);
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

/// 解析 npm -g 全局工具在 rootfs 内的实际安装路径。
///
/// 优先级：
///   1. rootfs 实际 PATH（`command -v`）——最真实，反映 npm prefix；
///   2. 候选路径兜底（versionOf 能跑通即视为存在）。
///
/// 背景（cyo: command not found 根因）：binary 曾硬编码 /usr/bin/codex，
/// 但 Ubuntu noble rootfs 中 npm -g 实际装到 /usr/local/bin/codex，
/// installedVersion 查 /usr/bin/codex 恒 null → install() 验证失败 →
/// shell 注入永不执行。这里统一解析，保证 installedVersion / isInstalled /
/// 安装后健康检查三处看到同一个真实路径。
Future<String?> _resolveNpmGlobalBinary(
  ToolchainContext ctx,
  String name,
  List<String> candidates,
) async {
  // 1. rootfs 实际 PATH 解析（npm -g prefix 决定，最真实）
  final inPath = await ctx.whichInRootfs(name);
  if (inPath != null && inPath.isNotEmpty) return inPath;
  // 2. 候选路径探测（--version 可执行即视为存在）
  for (final cand in candidates) {
    if (await ctx.versionOf(cand) != null) return cand;
  }
  return null;
}
