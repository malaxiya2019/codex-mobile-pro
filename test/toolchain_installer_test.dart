/// ====================================================================
/// Coding Runtime 工具链安装器测试
///
/// 覆盖 Phase 8（工具链自动安装）：
///   1. Node.js 已安装 → SKIP（幂等）
///   2. Node.js 缺失 → apt install → verify → INSTALLED
///   3. apt-get update 失败 → FAILED（aptUpdateFailed，不伪装成功）
///   4. apt install 失败 → FAILED（aptInstallFailed）
///   5. Git / Python 安装与验证
///   6. Codex CLI / mimo2codex 通过 npm 全局安装
///   7. npm 缺失 → 依赖 blocked
///   8. Linux Runtime 未就绪 → blocked
///   9. 无安装器 → 真正的 UNSUPPORTED（非「未实现」占位）
///  10. 部分失败恢复（partial resume）：首次 Node 失败 → 修复后重试
///      全部成功且已成功的工具不被破坏
///
/// 说明：
///   - 全部使用 FakeToolchainAdapter（IExecutionAdapter 内存实现），
///     不依赖真实 Ubuntu rootfs / Termux / 网络。
///   - isLinuxReady 通过临时目录中的 proot + bash 文件满足。
/// ====================================================================
library;

import 'dart:io';

import 'package:codex_mobile_pro/runtime/deploy_error.dart';
import 'package:codex_mobile_pro/runtime/install_models.dart';
import 'package:codex_mobile_pro/runtime/installers/apt_toolchain_installers.dart';
import 'package:codex_mobile_pro/runtime/installers/npm_toolchain_installers.dart';
import 'package:codex_mobile_pro/runtime/installers/toolchain_context.dart';
import 'package:codex_mobile_pro/runtime/installers/toolchain_orchestrator.dart';
import 'package:codex_mobile_pro/runtime/process/process_runner.dart';
import 'package:codex_mobile_pro/runtime/process/runner_models.dart';
import 'package:codex_mobile_pro/runtime/provider/linux_runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/runtime_dependency.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存 Fake 执行适配器：模拟 Ubuntu rootfs 内的命令行为
///
///   - `installedVersions[exe]` 存在 → `exe --version` 返回该版本（exit 0）
///   - 不存在 → exit 127（command not found）
///   - apt-get update / install、npm install 会更新 installedVersions
class FakeToolchainAdapter implements IExecutionAdapter {
  final Map<String, String> installedVersions = {};
  bool failAptUpdate = false;
  bool failAptInstall = false;
  bool failNpmInstall = false;
  final List<String> log = [];

  @override
  String get id => 'fake-toolchain';

  @override
  bool supports(RuntimeProcessRequest request) => request.runtimeId == 'linux';

  RuntimeProcessResult _ok(RuntimeProcessRequest r, [String stdout = '']) =>
      RuntimeProcessResult(exitCode: 0, stdout: stdout, request: r);

  @override
  Future<RuntimeProcessResult> execute(RuntimeProcessRequest request) async {
    final exe = request.executable;
    final args = request.arguments;
    log.add('$exe ${args.join(' ')}');

    if (exe == '/usr/bin/apt-get') {
      if (args.contains('update')) {
        if (failAptUpdate) {
          return RuntimeProcessResult(
            exitCode: 100,
            stderr: 'E: Failed to fetch ... 404',
            request: request,
          );
        }
        return _ok(request);
      }
      if (args.contains('install')) {
        if (failAptInstall) {
          return RuntimeProcessResult(
            exitCode: 100,
            stderr: 'E: Unable to locate package nodejs',
            request: request,
          );
        }
        for (final pkg in args) {
          switch (pkg) {
            case 'nodejs':
              installedVersions['/usr/bin/node'] = 'v18.19.1';
              installedVersions['/usr/bin/npm'] = '9.2.0';
            case 'npm':
              installedVersions['/usr/bin/npm'] = '9.2.0';
            case 'git':
              installedVersions['/usr/bin/git'] = '2.43.0';
            case 'python3':
              installedVersions['/usr/bin/python3'] = '3.12.3';
              installedVersions['/usr/bin/pip3'] = 'pip 24.0 from /usr/lib/python3/dist-packages (python 3.12)';
            case 'python3-pip':
              installedVersions['/usr/bin/pip3'] = 'pip 24.0 from /usr/lib/python3/dist-packages (python 3.12)';
          }
        }
        return _ok(request);
      }
      return _ok(request);
    }

    if (exe == '/usr/bin/npm') {
      if (args.contains('install')) {
        if (failNpmInstall) {
          return RuntimeProcessResult(
            exitCode: 1,
            stderr: 'npm ERR! code EAI_AGAIN',
            request: request,
          );
        }
        final pkg = args.last;
        if (pkg == '@openai/codex') {
          installedVersions['/usr/bin/codex'] = '0.9.0';
        } else if (pkg == 'mimo2codex') {
          installedVersions['/usr/bin/mimo2codex'] = '1.2.0';
        }
        return _ok(request);
      }
      // npm --version
      final v = installedVersions['/usr/bin/npm'];
      return v != null ? _ok(request, v) : RuntimeProcessResult(exitCode: 127, request: request);
    }

    // 通用 --version
    final v = installedVersions[exe];
    if (v != null) return _ok(request, v);
    return RuntimeProcessResult(
      exitCode: 127,
      stderr: '$exe: command not found',
      request: request,
    );
  }
}

/// 测试夹具：临时 rootfs + FakeAdapter + ToolchainContext
class ToolchainFixture {
  late final Directory temp;
  late final FakeToolchainAdapter adapter;
  late final RuntimeProcessRunner runner;
  late final ToolchainContext ctx;
  late final ToolchainOrchestrator orchestrator;

  ToolchainFixture() {
    temp = Directory.systemTemp.createTempSync('toolchain_test_');
    // 满足 isLinuxReady：proot + rootfs bash 真实存在
    File('${temp.path}/proot').createSync(recursive: true);
    final bashDir = Directory('${temp.path}/rootfs/usr/bin');
    bashDir.createSync(recursive: true);
    File('${bashDir.path}/bash').createSync();

    adapter = FakeToolchainAdapter();
    runner = RuntimeProcessRunner(adapters: [adapter]);
    ctx = ToolchainContext(
      runner: runner,
      injectedPaths: LinuxRuntimePaths(
        prootExecutable: '${temp.path}/proot',
        rootfsDir: '${temp.path}/rootfs',
        loaderPath: '${temp.path}/loader',
      ),
    );
    orchestrator = ToolchainOrchestrator();
  }

  void dispose() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  group('Node.js 安装器', () {
    test('已安装 → SKIP（幂等，不执行 apt）', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      f.adapter.installedVersions['/usr/bin/npm'] = '9.2.0';

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(result.version, contains('v18.19.1'));
      expect(f.adapter.log.where((l) => l.contains('apt-get install')), isEmpty,
          reason: '已安装时不得重复 apt install');
    });

    test('缺失 → apt install → 验证 → INSTALLED', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(f.adapter.log, contains('/usr/bin/apt-get update'));
      expect(f.adapter.log,
          contains('/usr/bin/apt-get install -y nodejs npm'));
      expect(f.adapter.installedVersions['/usr/bin/node'], 'v18.19.1');
      expect(f.adapter.installedVersions['/usr/bin/npm'], '9.2.0');
      expect(result.version, contains('node'));
    });

    test('apt-get update 失败 → FAILED（aptUpdateFailed）', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.failAptUpdate = true;

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isFalse);
      expect(result.phase, InstallPhase.failed);
      expect(result.errorMessage, contains('apt'));
    });

    test('apt install 失败 → FAILED（aptInstallFailed，非“暂不支持”）',
        () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.failAptInstall = true;

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isFalse);
      expect(result.phase, InstallPhase.failed);
      expect(result.errorMessage, contains('失败'));
      expect(result.errorMessage, isNot(contains('暂不支持')));
    });
  });

  group('Git / Python 安装器', () {
    test('Git 缺失 → apt install → 验证', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final installer = GitInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(f.adapter.log, contains('/usr/bin/apt-get install -y git'));
      expect(f.adapter.installedVersions['/usr/bin/git'], '2.43.0');
    });

    test('Git 已安装 → SKIP', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/git'] = '2.43.0';

      final result = await GitInstaller().install(f.ctx);

      expect(result.success, isTrue);
      expect(f.adapter.log.where((l) => l.contains('apt-get install')), isEmpty);
    });

    test('Python 缺失 → apt install python3+python3-pip → 验证 pip3',
        () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final installer = PythonInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(f.adapter.log,
          contains('/usr/bin/apt-get install -y python3 python3-pip'));
      expect(f.adapter.installedVersions['/usr/bin/python3'], '3.12.3');
      expect(result.version, contains('pip'));
    });
  });

  group('Codex CLI / mimo2codex（npm）', () {
    test('Node+npm 已装 → npm install -g @openai/codex → 验证', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      f.adapter.installedVersions['/usr/bin/npm'] = '9.2.0';

      final installer = CodexCliInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(f.adapter.log,
          contains('/usr/bin/npm install -g --no-fund --no-audit @openai/codex'));
      expect(f.adapter.installedVersions['/usr/bin/codex'], '0.9.0');
    });

    test('Node+npm 已装 → npm install -g mimo2codex → 验证', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      f.adapter.installedVersions['/usr/bin/npm'] = '9.2.0';

      final installer = Mimo2codexInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(f.adapter.log,
          contains('/usr/bin/npm install -g --no-fund --no-audit mimo2codex'));
      expect(f.adapter.installedVersions['/usr/bin/mimo2codex'], '1.2.0');
    });

    test('npm 缺失 → 依赖 blocked（dependencyMissing）', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final installer = CodexCliInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('npm'));
    });

    test('npm install 失败 → FAILED（npmInstallFailed）', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      f.adapter.installedVersions['/usr/bin/npm'] = '9.2.0';
      f.adapter.failNpmInstall = true;

      final result = await CodexCliInstaller().install(f.ctx);

      expect(result.success, isFalse);
      expect(result.phase, InstallPhase.failed);
      expect(result.errorMessage, contains('npm'));
    });
  });

  group('ToolchainOrchestrator', () {
    test('installOne：Linux Runtime 未就绪 → blocked', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      // 删除 proot → isLinuxReady false
      File('${f.temp.path}/proot').deleteSync();

      final result = await f.orchestrator.installOne(RuntimeTool.node, f.ctx);

      expect(result.success, isFalse);
      expect(result.phase, InstallPhase.blocked);
      expect(result.errorMessage, contains('Linux Runtime'));
    });

    test('installOne：依赖未安装（Node）→ codex blocked', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final result =
          await f.orchestrator.installOne(RuntimeTool.codexCli, f.ctx);

      expect(result.success, isFalse);
      expect(result.phase, InstallPhase.blocked);
      expect(result.errorMessage, contains('Node.js'));
    });

    test('无安装器 → 真正的 UNSUPPORTED', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      expect(f.orchestrator.hasInstallerFor(RuntimeTool.flutterSdk), isFalse);
      final result =
          await f.orchestrator.installOne(RuntimeTool.flutterSdk, f.ctx);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('暂不支持'));
    });

    test('installAll：依赖顺序 + 幂等（第二次全部 SKIP）', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final first = await f.orchestrator.installAll(f.ctx);
      expect(first.length, 5, reason: 'node/git/python/codex/mimo 共 5 个');
      for (final r in first) {
        expect(r.success, isTrue, reason: '${r.tool} 应安装成功');
      }
      // 第一次：全部 apt/npm 执行
      expect(f.adapter.log.where((l) => l.contains('apt-get install')).length, 3);
      expect(f.adapter.log.where((l) => l.contains('npm install')).length, 2);

      // 第二次：全部 SKIP，无任何 apt/npm install（仅 --version 查询）
      final aptBefore =
          f.adapter.log.where((l) => l.contains('apt-get install')).length;
      final npmBefore =
          f.adapter.log.where((l) => l.contains('npm install')).length;
      final second = await f.orchestrator.installAll(f.ctx);
      for (final r in second) {
        expect(r.success, isTrue);
        expect(r.version, contains('已安装'));
      }
      expect(f.adapter.log.where((l) => l.contains('apt-get install')).length,
          aptBefore,
          reason: '第二次不得重复 apt install');
      expect(f.adapter.log.where((l) => l.contains('npm install')).length,
          npmBefore,
          reason: '第二次不得重复 npm install');
    });

    test('部分失败恢复：首次 Node 失败 → 修复后重试全部成功', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.failAptInstall = true;

      // 第一次：node 失败 → git/python 尝试也失败（apt install 失败）
      // codex/mimo 依赖 node 失败 → blocked
      final first = await f.orchestrator.installAll(f.ctx);
      expect(first.firstWhere((r) => r.tool == RuntimeTool.node).success, isFalse);
      final codexFirst =
          first.firstWhere((r) => r.tool == RuntimeTool.codexCli);
      expect(codexFirst.success, isFalse);
      expect(codexFirst.phase, InstallPhase.blocked);

      // 修复 apt → 重试：全部成功（失败恢复）
      f.adapter.failAptInstall = false;
      final second = await f.orchestrator.installAll(f.ctx);
      for (final r in second) {
        expect(r.success, isTrue, reason: '${r.tool} 重试应成功');
      }
      expect(f.adapter.installedVersions['/usr/bin/codex'], '0.9.0');
      expect(f.adapter.installedVersions['/usr/bin/mimo2codex'], '1.2.0');
    });
  });

  group('错误模型', () {
    test('aptInstall 抛 DeployError 携带真实 exitCode/stderr', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.failAptInstall = true;

      try {
        await f.ctx.aptInstall(['nodejs']);
        fail('应抛出 DeployError');
      } on DeployError catch (e) {
        expect(e.code, DeployErrorCode.aptInstallFailed);
        expect(e.detail, contains('Unable to locate package'));
      }
    });
  });
}
