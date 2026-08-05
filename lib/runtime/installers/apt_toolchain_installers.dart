/// ====================================================================
/// 基础工具链安装器（apt）
///
/// 全部在 Ubuntu 24.04 rootfs 内执行，优先使用 Ubuntu 官方源：
///   - Node.js：apt-get install -y nodejs npm
///   - Git：    apt-get install -y git
///   - Python： apt-get install -y python3 python3-pip
///
/// 幂等：已安装（rootfs 内 --version 通过）→ 直接 SKIP。
/// 不依赖 Termux pkg / 系统 apt。
/// ====================================================================
library;

import '../deploy_error.dart';
import '../install_models.dart';
import '../runtime_dependency.dart';
import 'toolchain_context.dart';
import 'toolchain_installer.dart';

/// Node.js + npm 安装器
///
/// Ubuntu 24.04 noble 官方源提供 nodejs 18.19.x + npm 9.2.x，
/// 满足 Codex CLI（Node 18+）要求，优先使用 apt，不引入第三方源。
class NodeJsInstaller extends ToolchainInstaller {
  @override
  RuntimeTool get tool => RuntimeTool.node;

  @override
  String get displayName => 'Node.js';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    // node 与 npm 都必须可用才算已安装。
    // 真机曾出现 node 已装但 /usr/bin/npm 为 broken symlink
    // （目标 /usr/share/nodejs/npm/bin/npm-cli.js 缺失），此时必须重新安装。
    return await ctx.versionOf('/usr/bin/node') != null &&
        await ctx.versionOf('/usr/bin/npm') != null;
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    return ctx.versionOf('/usr/bin/node');
  }

  @override
  Future<InstallResult> install(ToolchainContext ctx) async {
    // 1. 已安装（node + npm 均可用）→ SKIP
    final nodeVer = await installedVersion(ctx);
    final npmVer = await ctx.versionOf('/usr/bin/npm');
    if (nodeVer != null && npmVer != null) {
      report(ctx, InstallPhase.completed, 1.0, '已安装，跳过');
      return success(nodeVer, skipped: true);
    }

    // 2. 补装缺失部分：
    //    - node/npm 均缺失 → apt install nodejs npm（全新安装）
    //    - node 已装但 npm 缺失/broken → 仅 apt install npm 修复，
    //      不重装 nodejs（真机 npm exit=127 正是此场景）
    if (nodeVer != null && npmVer == null) {
      report(ctx, InstallPhase.installing, 0.3, 'npm 缺失，补装 npm...');
      try {
        await ctx.aptInstall(['npm'],
            onProgress: (p, m) => report(ctx, InstallPhase.installing, p, m));
      } catch (e) {
        return failure(e);
      }
    } else {
      report(ctx, InstallPhase.installing, 0.3, 'apt 安装 nodejs + npm...');
      try {
        await ctx.aptInstall(['nodejs', 'npm'],
            onProgress: (p, m) => report(ctx, InstallPhase.installing, p, m));
      } catch (e) {
        return failure(e);
      }
    }

    // 3. 验证
    report(ctx, InstallPhase.verifying, 0.9, '验证 node/npm...');
    final vNode = await installedVersion(ctx);
    final vNpm = await ctx.versionOf('/usr/bin/npm');
    if (vNode == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.healthCheckFailed,
          message: 'Node.js 安装后验证失败',
          detail: 'apt-get install 成功但 node --version 无法执行',
          userSuggestion: '尝试重新初始化 Linux Runtime 后重试',
        ),
      );
    }
    if (vNpm == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.healthCheckFailed,
          message: 'npm 安装后验证失败',
          detail: 'nodejs 已安装但 npm 缺失',
          userSuggestion: '尝试重新初始化后重试',
        ),
      );
    }
    report(ctx, InstallPhase.completed, 1.0, 'Node.js 安装完成');
    return success('node $vNode / npm $vNpm');
  }
}

/// Git 安装器
class GitInstaller extends ToolchainInstaller {
  @override
  RuntimeTool get tool => RuntimeTool.git;

  @override
  String get displayName => 'Git';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    return await ctx.versionOf('/usr/bin/git') != null;
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    return ctx.versionOf('/usr/bin/git');
  }

  @override
  Future<InstallResult> install(ToolchainContext ctx) async {
    final ver = await installedVersion(ctx);
    if (ver != null) {
      report(ctx, InstallPhase.completed, 1.0, '已安装，跳过');
      return success(ver, skipped: true);
    }

    report(ctx, InstallPhase.installing, 0.3, 'apt 安装 git...');
    try {
      await ctx.aptInstall(['git'],
          onProgress: (p, m) => report(ctx, InstallPhase.installing, p, m));
    } catch (e) {
      return failure(e);
    }

    report(ctx, InstallPhase.verifying, 0.9, '验证 git...');
    final vGit = await installedVersion(ctx);
    if (vGit == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.healthCheckFailed,
          message: 'Git 安装后验证失败',
          userSuggestion: '尝试重新初始化后重试',
        ),
      );
    }
    report(ctx, InstallPhase.completed, 1.0, 'Git 安装完成');
    return success(vGit);
  }
}

/// Python 3 + pip 安装器
///
/// pip 可执行名随发行版变化（pip3 / pip），通过真实检测解析，不硬编码。
class PythonInstaller extends ToolchainInstaller {
  @override
  RuntimeTool get tool => RuntimeTool.python;

  @override
  String get displayName => 'Python 3';

  @override
  Future<bool> isInstalled(ToolchainContext ctx) async {
    return await ctx.versionOf('/usr/bin/python3') != null;
  }

  @override
  Future<String?> installedVersion(ToolchainContext ctx) async {
    return ctx.versionOf('/usr/bin/python3');
  }

  /// 解析 pip 可执行名（pip3 优先，回退 pip）
  Future<String?> _resolvePip(ToolchainContext ctx) async {
    for (final bin in ['/usr/bin/pip3', '/usr/bin/pip']) {
      final v = await ctx.versionOf(bin);
      if (v != null) return '$bin ($v)';
    }
    return null;
  }

  @override
  Future<InstallResult> install(ToolchainContext ctx) async {
    final ver = await installedVersion(ctx);
    if (ver != null) {
      report(ctx, InstallPhase.completed, 1.0, '已安装，跳过');
      return success(ver, skipped: true);
    }

    report(ctx, InstallPhase.installing, 0.3, 'apt 安装 python3 + pip...');
    try {
      await ctx.aptInstall(['python3', 'python3-pip'],
          onProgress: (p, m) => report(ctx, InstallPhase.installing, p, m));
    } catch (e) {
      return failure(e);
    }

    report(ctx, InstallPhase.verifying, 0.9, '验证 python3/pip...');
    final vPy = await installedVersion(ctx);
    if (vPy == null) {
      return failure(
        const DeployError(
          code: DeployErrorCode.healthCheckFailed,
          message: 'Python 3 安装后验证失败',
          userSuggestion: '尝试重新初始化后重试',
        ),
      );
    }
    final vPip = await _resolvePip(ctx);
    report(ctx, InstallPhase.completed, 1.0, 'Python 3 安装完成');
    return success(vPip != null ? '$vPy / $vPip' : '$vPy / pip 未检测到');
  }
}
