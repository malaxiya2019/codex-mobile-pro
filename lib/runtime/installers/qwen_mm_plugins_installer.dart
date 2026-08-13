/// ====================================================================
/// Qwen-MM-Plugins 部署器（8 个多模态能力：Skill + MCP server）
///
/// 上游：https://github.com/QwenLM/Qwen-MM-Plugins（Qwen 官方）
/// 技能：core / api / search / video-memory / video-edit / blender /
///       freecad / edu-agent（skill/ 目录已并入 skills/qwen-mm-plugins-*，
///       由 assets/skills.tar.gz 随 Codex 部署到 rootfs ~/.codex/skills/）
///
/// 本安装器补齐「含 MCP」部分：
///   1. 把 8 个能力的 MCP server 写入 rootfs ~/.codex/config.toml
///      （[mcp_servers.qwen-mm-plugins-*]），codex 启动时经 uvx 按需
///      拉取 Python 包运行，不污染 rootfs 系统 Python。
///   2. 写共享配置 ~/.qwen-mm-plugins/config（api/search 等凭证模板）。
///   3. 尽力而为 apt 安装 ffmpeg/ffprobe（core/video-memory 等媒体能力
///      的系统依赖），失败不阻断。
///
/// 幂等：[mcp_servers.qwen-mm-plugins 已存在 → 不重复追加。
/// 依赖：uv / uvx（RuntimeDependency 已声明，编排器保证先装）。
/// ====================================================================
library;

import 'dart:io';

import '../../core/logger/log_service.dart';
import '../install_models.dart';
import '../runtime_dependency.dart';
import 'toolchain_context.dart';
import 'toolchain_installer.dart';

/// Qwen-MM-Plugins 部署器
class QwenMmPluginsInstaller extends ToolchainInstaller {
  /// 上游仓库（MCP server 的 git+ 源）
  static const String repoUrl = 'https://github.com/QwenLM/Qwen-MM-Plugins.git';

  /// 各能力 → (pyproject extra, 发布 tag)，tag 实证自上游 .mcp.json
  static const Map<String, String> capRefs = {
    'core': 'qwen-mm-plugins-core-v1.0.1',
    'api': 'qwen-mm-plugins-api-v1.0.1',
    'search': 'qwen-mm-plugins-search-v1.0.2',
    'video-memory': 'qwen-mm-plugins-video-memory-v1.0.1',
    'video-edit': 'qwen-mm-plugins-video-edit-v1.0.1',
    'blender': 'qwen-mm-plugins-blender-v1.0.1',
    'freecad': 'qwen-mm-plugins-freecad-v1.0.1',
  };

  /// 需要 QWEN_MM_AUTOLAUNCH=1 环境变量的能力（自动拉起桌面应用）
  static const Set<String> autolaunchCaps = {'blender', 'freecad'};

  /// 幂等标记：config.toml 已含该段 → 跳过
  static const String mcpMarker = '[mcp_servers.qwen-mm-plugins';

  /// rootfs 内 Codex 配置路径
  static const String codexConfigRel = 'root/.codex/config.toml';

  /// rootfs 内 Qwen-MM-Plugins 共享配置路径
  static const String qwenMmConfigRel = 'root/.qwen-mm-plugins/config';

  @override
  RuntimeTool get tool => RuntimeTool.qwenMmPlugins;

  @override
  String get displayName => 'Qwen-MM-Plugins';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    try {
      final paths = await ctx.resolvePaths();
      final config = File('${paths.rootfsDir}/$codexConfigRel');
      return config.existsSync() &&
          config.readAsStringSync().contains(mcpMarker);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    final deployed = await isInstalled(ctx);
    return deployed ? '8 skills + MCP' : null;
  }

  @override
  Future<InstallResult> install(ToolchainContext ctx) async {
    final deployed = await isInstalled(ctx);
    if (deployed) {
      report(ctx, InstallPhase.completed, 1.0, 'MCP server 已配置，跳过');
      return success('8 skills + MCP', skipped: true);
    }

    // 1. 写 MCP server 配置到 ~/.codex/config.toml（幂等追加，失败不阻断）
    await _deployMcpServers(ctx);

    // 2. 写共享配置模板 ~/.qwen-mm-plugins/config
    await _deployQwenMmConfig(ctx);

    // 3. 尽力而为安装 ffmpeg/ffprobe（媒体能力系统依赖，失败不阻断）
    await _installFfmpegBestEffort(ctx);

    report(
      ctx,
      InstallPhase.completed,
      1.0,
      'Qwen-MM-Plugins 就绪：8 个多模态 Skill + MCP server（uvx 按需启动）',
    );
    return success('8 skills + MCP');
  }

  /// 写 MCP server 段到 rootfs ~/.codex/config.toml（幂等追加）
  Future<void> _deployMcpServers(ToolchainContext ctx) async {
    try {
      final paths = await ctx.resolvePaths();
      final config = File('${paths.rootfsDir}/$codexConfigRel');
      await config.parent.create(recursive: true);

      var content = config.existsSync() ? config.readAsStringSync() : '';
      if (content.contains(mcpMarker)) {
        report(ctx, InstallPhase.completed, 1.0, 'MCP server 已配置（幂等跳过）');
        return;
      }

      final buffer = StringBuffer();
      if (content.isNotEmpty && !content.endsWith('\n')) {
        buffer.writeln();
      }
      buffer.writeln();
      buffer.writeln('# ── Qwen-MM-Plugins MCP servers (codex-mobile-pro managed) ──');
      capRefs.forEach((cap, tag) {
        final spec = 'qwen-mm-plugins[$cap] @ git+$repoUrl@$tag';
        buffer.writeln('[mcp_servers.qwen-mm-plugins-$cap]');
        buffer.writeln('command = "uvx"');
        buffer.writeln('args = [');
        buffer.writeln('  "--from",');
        buffer.writeln('  "$spec",');
        buffer.writeln('  "qwen-mm-plugins-$cap",');
        buffer.writeln(']');
        if (autolaunchCaps.contains(cap)) {
          buffer.writeln('env = { QWEN_MM_AUTOLAUNCH = "1" }');
        }
        buffer.writeln();
      });

      await config.writeAsString(content + buffer.toString());
      report(
        ctx,
        InstallPhase.completed,
        1.0,
        'MCP server 配置已写入 ~/.codex/config.toml（${capRefs.length} 个能力）',
      );
    } catch (e) {
      LogService.warning(
          'Toolchain', 'Qwen-MM-Plugins MCP 配置写入失败（不阻断安装）: $e');
    }
  }

  /// 写共享配置模板 ~/.qwen-mm-plugins/config（不存在才写）
  Future<void> _deployQwenMmConfig(ToolchainContext ctx) async {
    try {
      final paths = await ctx.resolvePaths();
      final config = File('${paths.rootfsDir}/$qwenMmConfigRel');
      if (config.existsSync()) {
        return;
      }
      await config.parent.create(recursive: true);
      const template = '''# qwen-mm-plugins config — KEY=VALUE per line, read when the var is not in the environment.
# 由 codex-mobile-pro 生成。按需填入真实凭证后，云端/搜索能力即可工作。
# 在线配置：curl -fsSL https://raw.githubusercontent.com/QwenLM/Qwen-MM-Plugins/main/install.sh | bash -s -- configure
DASHSCOPE_API_KEY=
DASHSCOPE_BASE_URL=
SERPER_API_KEY=
EXA_API_KEY=
TAVILY_API_KEY=
''';
      await config.writeAsString(template);
      // chmod 600（上游同权限约定）
      try {
        Process.runSync('chmod', ['600', config.path]);
      } catch (_) {}
      report(ctx, InstallPhase.completed, 1.0,
          'Qwen-MM-Plugins 共享配置模板已写入 ~/.qwen-mm-plugins/config');
    } catch (e) {
      LogService.warning(
          'Toolchain', 'Qwen-MM-Plugins config 写入失败（不阻断安装）: $e');
    }
  }

  /// 尽力而为安装 ffmpeg/ffprobe（core/video-memory/api/video-edit 需要）
  Future<void> _installFfmpegBestEffort(ToolchainContext ctx) async {
    try {
      if (await ctx.versionOf('/usr/bin/ffmpeg') != null) {
        report(ctx, InstallPhase.completed, 1.0, 'ffmpeg 已存在，跳过');
        return;
      }
      report(ctx, InstallPhase.installing, 0.5, 'apt 安装 ffmpeg（媒体能力依赖）...');
      await ctx.aptInstall(
        ['ffmpeg'],
        onProgress: (p, m) => report(ctx, InstallPhase.installing, p, m),
      );
      final v = await ctx.versionOf('/usr/bin/ffmpeg');
      report(ctx, InstallPhase.completed, 1.0, 'ffmpeg 已安装: $v');
    } catch (e) {
      LogService.warning(
          'Toolchain', 'ffmpeg 安装失败（不阻断 Qwen-MM-Plugins 部署）: $e');
    }
  }
}
