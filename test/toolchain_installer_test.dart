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
///   7. npm 缺失 → Codex CLI 安装失败（npm 缺失），不再误判依赖 Node.js blocked
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
import 'package:codex_mobile_pro/runtime/installers/apt_source_manager.dart';
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

  /// 前 N 次 apt-get update 模拟「网络获取失败」（Failed to fetch → exit=100），
  /// 用于验证自动切换备用 apt 源后成功。
  int failAptUpdateAttempts = 0;
  int _aptUpdateCalls = 0;

  /// 前 N 次 apt-get install 模拟「下载 .deb 失败」（Failed to fetch → exit=100）。
  int failAptInstallAttempts = 0;
  int _aptInstallCalls = 0;

  /// apt-get update 模拟「进程启动失败」（ProcessException → exit=-1 空输出）
  bool failAptUpdateStart = false;
  bool failAptInstall = false;
  bool failNpmInstall = false;

  /// 模拟 dpkg interrupted（dpkg --audit 报错，--configure -a 修复后恢复）
  bool dpkgInterrupted = false;

  /// 模拟 apt-get install 的耗时（验证安装期间心跳动态上报）
  Duration? installDelay;

  /// 模拟 dpkg --configure -a 永远失败（不可恢复场景）
  bool dpkgConfigureAlwaysFails = false;
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

    // dpkg 健康（Phase 8：aptInstall 前置 dpkg --audit 检查）
    if (exe == '/usr/bin/dpkg') {
      if (args.contains('--audit')) {
        if (dpkgInterrupted) {
          return RuntimeProcessResult(
            exitCode: 1,
            stderr: 'dpkg: error: dpkg was interrupted, you must manually '
                "run 'dpkg --configure -a' to correct the problem.",
            request: request,
          );
        }
        return _ok(request);
      }
      if (args.contains('--configure')) {
        if (dpkgConfigureAlwaysFails) {
          return RuntimeProcessResult(
            exitCode: 1,
            stderr: 'dpkg: error: cannot open lock file - open (13: '
                'Permission denied)',
            request: request,
          );
        }
        dpkgInterrupted = false; // 修复完成
        return _ok(request);
      }
      return _ok(request);
    }

    if (exe == '/usr/bin/apt-get') {
      if (args.contains('update')) {
        if (failAptUpdateStart) {
          // 模拟 Process.start 抛 ProcessException（PRoot 无法启动）
          return RuntimeProcessResult(
            exitCode: -1,
            error: '权限不足: /tmp/proot (errno=13)',
            request: request,
          );
        }
        _aptUpdateCalls++;
        if (failAptUpdate || _aptUpdateCalls <= failAptUpdateAttempts) {
          // 真实根因复刻：TCP 无法连接 ports.ubuntu.com:80 → exit=100
          return RuntimeProcessResult(
            exitCode: 100,
            stderr:
                'Err:1 http://ports.ubuntu.com/ubuntu-ports noble InRelease\n'
                '  Unable to connect to ports.ubuntu.com:http: '
                '[IP: 91.189.92.19 80]\n'
                'E: Failed to fetch '
                'http://ports.ubuntu.com/ubuntu-ports/dists/noble/InRelease '
                'Unable to connect to ports.ubuntu.com:http: [IP: 91.189.92.19 80]\n'
                'E: Unable to fetch some archives',
            request: request,
          );
        }
        return _ok(request);
      }
      if (args.contains('install')) {
        _aptInstallCalls++;
        if (failAptInstallAttempts > 0 &&
            _aptInstallCalls <= failAptInstallAttempts) {
          // 下载 .deb 阶段网络失败（与 update 已成功并不矛盾：同主机间歇性 TCP）
          return RuntimeProcessResult(
            exitCode: 100,
            stderr: 'E: Failed to fetch '
                'http://ports.ubuntu.com/ubuntu-ports/pool/main/n/nodejs/'
                'nodejs_18.19.1+dfsg-6ubuntu4_arm64.deb '
                'Unable to connect to ports.ubuntu.com:http: [IP: 91.189.92.19 80]\n'
                'E: Unable to fetch some archives, maybe run apt-get update '
                'or try with --fix-missing?',
            request: request,
          );
        }
        if (failAptInstall) {
          return RuntimeProcessResult(
            exitCode: 100,
            stderr: 'E: Unable to locate package nodejs',
            request: request,
          );
        }
        if (installDelay != null) {
          await Future.delayed(installDelay!);
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
              installedVersions['/usr/bin/pip3'] =
                  'pip 24.0 from /usr/lib/python3/dist-packages (python 3.12)';
            case 'python3-pip':
              installedVersions['/usr/bin/pip3'] =
                  'pip 24.0 from /usr/lib/python3/dist-packages (python 3.12)';
          }
        }
        return _ok(request);
      }
      return _ok(request);
    }

    if (exe == '/usr/bin/npm') {
      if (args.contains('install')) {
        if (installDelay != null) {
          await Future.delayed(installDelay!);
        }
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
      return v != null
          ? _ok(request, v)
          : RuntimeProcessResult(exitCode: 127, request: request);
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

  ToolchainFixture({AptSourceProbe? probe}) {
    temp = Directory.systemTemp.createTempSync('toolchain_test_');
    // 满足 isLinuxReady：proot + rootfs bash 真实存在
    File('${temp.path}/proot').createSync(recursive: true);
    final bashDir = Directory('${temp.path}/rootfs/usr/bin');
    bashDir.createSync(recursive: true);
    File('${bashDir.path}/bash').createSync();
    // 出厂 apt 源（与 App 部署的 noble rootfs tarball 一致）
    final aptDir = Directory('${temp.path}/rootfs/etc/apt');
    aptDir.createSync(recursive: true);
    File('${aptDir.path}/sources.list').writeAsStringSync(
      'deb [signed-by="/usr/share/keyrings/ubuntu-archive-keyring.gpg"] '
      'http://ports.ubuntu.com/ubuntu-ports noble main universe multiverse\n',
    );

    adapter = FakeToolchainAdapter();
    runner = RuntimeProcessRunner(adapters: [adapter]);
    ctx = ToolchainContext(
      runner: runner,
      injectedPaths: LinuxRuntimePaths(
        prootExecutable: '${temp.path}/proot',
        rootfsDir: '${temp.path}/rootfs',
        loaderPath: '${temp.path}/loader',
      ),
      // 默认注入「全部不可达」探针：测速不写源、不发真实 HTTP；
      // preselect 专项测试再注入特定延迟。
      aptSourceProbe: probe ?? (_) async => null,
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

    test('node 已装但 npm 缺失/broken → 仅 apt install npm 修复', () async {
      // 真机根因复刻：nodejs 已安装但 /usr/bin/npm 是 broken symlink
      // （目标 /usr/share/nodejs/npm/bin/npm-cli.js 缺失）→ npm --version exit=127
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      // npm 未设置 → FakeAdapter 对 npm --version 返回 exit 127

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      // 必须只补装 npm，不重装 nodejs
      expect(f.adapter.log,
          contains('/usr/bin/apt-get install -y --no-install-recommends npm'));
      expect(
        f.adapter.log.where(
            (l) => l.contains('apt-get install') && l.contains('nodejs')),
        isEmpty,
        reason: 'node 已装时不得重新安装 nodejs',
      );
      expect(f.adapter.installedVersions['/usr/bin/node'], 'v18.19.1');
      expect(f.adapter.installedVersions['/usr/bin/npm'], '9.2.0');
      expect(result.version, contains('node'));
    });

    test('缺失 → apt install → 验证 → INSTALLED', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(f.adapter.log, contains('/usr/bin/apt-get update'));
      expect(
          f.adapter.log,
          contains(
              '/usr/bin/apt-get install -y --no-install-recommends nodejs npm'));
      expect(f.adapter.installedVersions['/usr/bin/node'], 'v18.19.1');
      expect(f.adapter.installedVersions['/usr/bin/npm'], '9.2.0');
      expect(result.version, contains('node'));
    });

    test('apt-get update 网络失败 → 备用源全部失败 → FAILED（APT 下载失败分类）', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.failAptUpdate = true; // 所有源均返回 Failed to fetch

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isFalse);
      expect(result.phase, InstallPhase.failed);
      // 部署中心必须显示真实网络分类，而不是「权限不足」
      expect(result.errorMessage, contains('APT 下载失败'));
      expect(result.errorMessage, contains('无法连接 Ubuntu 镜像'));
      expect(result.errorMessage, isNot(contains('权限不足')));
      // detail 必须保留已尝试的备用源与真实 stderr
      expect(result.errorMessage, contains('已尝试源'));
      expect(result.errorMessage, contains('official-https'));
      expect(result.errorMessage, contains('tuna'));
      expect(result.errorMessage, contains('aliyun'));
      expect(result.errorMessage, contains('Failed to fetch'));
    });

    test('apt-get update 网络失败 → 自动切换备用源 → 安装成功', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      // 第一次 update 失败（TCP 无法连接官方 HTTP），后续备用源成功
      f.adapter.failAptUpdateAttempts = 1;

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(result.version, contains('node'));
      // 必须真实发生源切换：rootfs /etc/apt/sources.list 被覆盖为备用源
      final sources =
          File('${f.temp.path}/rootfs/etc/apt/sources.list').readAsStringSync();
      expect(sources, contains('https://ports.ubuntu.com/ubuntu-ports'));
      expect(sources, contains('noble'));
      // 原始出厂配置已备份
      expect(
        File('${f.temp.path}/rootfs/etc/apt/sources.list.orig').existsSync(),
        isTrue,
      );
      // update 被调用至少 2 次（首次失败 + 备用源成功）
      final updateCalls = f.adapter.log
          .where((l) => l.contains('/usr/bin/apt-get update'))
          .length;
      expect(updateCalls, greaterThanOrEqualTo(2));
    });

    test('apt-get update 启动失败(exit=-1) → detail 暴露真实启动错误', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.failAptUpdateStart = true;

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isFalse);
      expect(result.phase, InstallPhase.failed);
      // 回归：ProcessException 真实原因（result.error）必须可见，
      // 不能只剩无信息量的 exit=-1 stdout="" stderr=""
      expect(result.errorMessage, contains('apt'));
      expect(result.errorMessage, contains('权限不足'));
      expect(result.errorMessage, contains('errno=13'));
    });

    test('apt install 失败 → FAILED（aptInstallFailed，非“暂不支持”）', () async {
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

    test('apt install 下载 .deb 网络失败 → 自动切换备用源 → 安装成功', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      // update 成功，但第一次 install 下载 nodejs .deb 时 TCP 失败
      f.adapter.failAptInstallAttempts = 1;

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(result.version, contains('node'));
      // 已切换为官方 HTTPS 备用源
      final sources =
          File('${f.temp.path}/rootfs/etc/apt/sources.list').readAsStringSync();
      expect(sources, contains('https://ports.ubuntu.com/ubuntu-ports'));
      // install 至少重试 2 次（首次失败 + 备用源成功）
      final installCalls = f.adapter.log
          .where((l) => l.contains('/usr/bin/apt-get install'))
          .length;
      expect(installCalls, greaterThanOrEqualTo(2));
    });

    test('apt install 前置 dpkg interrupted → 自动 dpkg --configure -a → 安装成功',
        () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.dpkgInterrupted = true; // 真机遗留状态：dpkg interrupted

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue, reason: '${result.errorMessage}');
      // 修复动作必须真实执行（不删除 lock）
      final fixCalls = f.adapter.log
          .where((l) => l.contains('/usr/bin/dpkg --configure -a'))
          .length;
      expect(fixCalls, greaterThanOrEqualTo(1));
      expect(f.adapter.dpkgInterrupted, isFalse, reason: '修复后应恢复健康');
    });

    test('apt install 前置 dpkg interrupted 且修复失败 → 结构化错误', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.dpkgInterrupted = true;
      // configure -a 永远失败（模拟 lock 无法获取等不可恢复场景）
      f.adapter.dpkgConfigureAlwaysFails = true;

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isFalse);
      expect(result.phase, InstallPhase.failed);
      expect(result.errorMessage, contains('dpkg'));
    });

    test('apt install 非网络失败（unable to locate）→ 不切换源、不误报网络分类', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.failAptInstall =
          true; // stderr: Unable to locate package nodejs

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('失败'));
      expect(result.errorMessage, isNot(contains('APT 下载失败')));
      // 非网络失败不应改写 rootfs apt 源（保持出厂 ports.ubuntu.com）
      final sources =
          File('${f.temp.path}/rootfs/etc/apt/sources.list').readAsStringSync();
      expect(sources, contains('http://ports.ubuntu.com/ubuntu-ports'));
      expect(sources, isNot(contains('mirrors.')));
      expect(
        File('${f.temp.path}/rootfs/etc/apt/sources.list.orig').existsSync(),
        isFalse,
      );
    });
  });

  group('apt 自动测速选源（自动检测网络 → 智能切换）', () {
    test('部署前镜像最快 → sources.list 切换为镜像，出厂源备份 .orig', () async {
      final f = ToolchainFixture(probe: (url) async {
        if (url.contains('tuna')) return const Duration(milliseconds: 100);
        if (url.contains('ports.ubuntu.com')) {
          return const Duration(seconds: 2);
        }
        return const Duration(seconds: 3);
      });
      addTearDown(f.dispose);

      final installer = NodeJsInstaller();
      final result = await installer.install(f.ctx);
      expect(result.success, isTrue);

      final sources =
          File('${f.temp.path}/rootfs/etc/apt/sources.list').readAsStringSync();
      expect(sources, contains('mirrors.tuna.tsinghua.edu.cn'),
          reason: '测速最快源应写入初始 sources.list');
      expect(sources, isNot(contains('http://ports.ubuntu.com/ubuntu-ports')),
          reason: '出厂 HTTP 源被覆盖');
      expect(
          File('${f.temp.path}/rootfs/etc/apt/sources.list.orig').existsSync(),
          isTrue,
          reason: '切换前必须备份出厂配置');
    });

    test('官方可达且差距 <= 300ms → 仍选官方（稳定优先）', () async {
      final f = ToolchainFixture(probe: (url) async {
        if (url.contains('ports.ubuntu.com')) {
          return const Duration(milliseconds: 400);
        }
        if (url.contains('tuna')) return const Duration(milliseconds: 300);
        return const Duration(milliseconds: 350);
      });
      addTearDown(f.dispose);

      final installer = NodeJsInstaller();
      await installer.install(f.ctx);

      final sources =
          File('${f.temp.path}/rootfs/etc/apt/sources.list').readAsStringSync();
      expect(sources, contains('https://ports.ubuntu.com/ubuntu-ports'),
          reason: '官方 HTTPS 可达时优先官方');
    });

    test('测速全部不可达 → 保持出厂源（不写镜像，由 fallback 兜底）', () async {
      final f = ToolchainFixture(probe: (_) async => null);
      addTearDown(f.dispose);

      final installer = NodeJsInstaller();
      await installer.install(f.ctx);

      final sources =
          File('${f.temp.path}/rootfs/etc/apt/sources.list').readAsStringSync();
      expect(sources, contains('http://ports.ubuntu.com/ubuntu-ports'),
          reason: '测速失败必须保持当前源');
      expect(sources, isNot(contains('tuna')));
    });
  });

  group('Git / Python 安装器', () {
    test('Git 缺失 → apt install → 验证', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final installer = GitInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(f.adapter.log,
          contains('/usr/bin/apt-get install -y --no-install-recommends git'));
      expect(f.adapter.installedVersions['/usr/bin/git'], '2.43.0');
    });

    test('Git 已安装 → SKIP', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/git'] = '2.43.0';

      final result = await GitInstaller().install(f.ctx);

      expect(result.success, isTrue);
      expect(
          f.adapter.log.where((l) => l.contains('apt-get install')), isEmpty);
    });

    test('Python 缺失 → apt install python3+python3-pip → 验证 pip3', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);

      final installer = PythonInstaller();
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(
          f.adapter.log,
          contains(
              '/usr/bin/apt-get install -y --no-install-recommends python3 python3-pip'));
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
      expect(
          f.adapter.log,
          contains(
              '/usr/bin/npm install -g --no-fund --no-audit @openai/codex'));
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

    test('Codex CLI 安装成功 → 注入 Shell 快捷命令到 rootfs /root/.bashrc', () async {
      // 真机根因复刻：App 一键部署只 npm install，从不追加
      // config/bashrc-additions.sh → cyo/cy/cs command not found。
      // 修复：验证 codex 后把 asset 内容幂等追加到 /root/.bashrc。
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      f.adapter.installedVersions['/usr/bin/npm'] = '9.2.0';

      const sample = '# Codex Mobile Pro — Shell 快捷命令\n'
          'cy() { echo cy; }\n'
          'cyo() { echo cyo; }\n';
      final installer =
          CodexCliInstaller(loadShellAdditions: () async => sample);
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      final bashrc = File('${f.temp.path}/rootfs/root/.bashrc');
      expect(bashrc.existsSync(), isTrue);
      final content = bashrc.readAsStringSync();
      expect(content, contains('# Codex Mobile Pro'));
      expect(content, contains('cyo()'));
    });

    test('Shell 快捷命令已注入 → 不重复追加（幂等）', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      f.adapter.installedVersions['/usr/bin/npm'] = '9.2.0';
      final bashrc = File('${f.temp.path}/rootfs/root/.bashrc');
      bashrc.createSync(recursive: true);
      bashrc
          .writeAsStringSync('# Codex Mobile Pro — 已存在\ncyo() { echo old; }\n');

      var loadCalls = 0;
      final installer = CodexCliInstaller(loadShellAdditions: () async {
        loadCalls++;
        return '# Codex Mobile Pro — NEW\ncyo() { echo new; }\n';
      });
      final result = await installer.install(f.ctx);

      expect(result.success, isTrue);
      expect(loadCalls, 0, reason: '已注入时不得读取/追加');
      expect(bashrc.readAsStringSync(), isNot(contains('NEW')));
    });

    test('Shell 快捷命令注入失败 → 不阻断 Codex 安装', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      f.adapter.installedVersions['/usr/bin/npm'] = '9.2.0';

      final installer = CodexCliInstaller(loadShellAdditions: () async {
        throw StateError('asset 加载失败');
      });
      final result = await installer.install(f.ctx);

      // 快捷命令为增强步骤：注入失败仅 warning，Codex 安装仍成功
      expect(result.success, isTrue);
      expect(result.version, contains('0.9.0'));
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

    test('installOne：node 本体可用但 npm 缺失 → codex 不被 blocked（真实 npm 错误）',
        () async {
      // 真机状态复刻：node 18.19.1 可用（--version 成功），npm 未配置（exit=127）。
      // 依赖检查只看 node 本体 → PASS；npm 真实缺失由 CodexCliInstaller 暴露。
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';

      final result =
          await f.orchestrator.installOne(RuntimeTool.codexCli, f.ctx);

      // 不得误判「依赖 Node.js 未安装」而 blocked
      expect(result.phase, isNot(InstallPhase.blocked));
      expect(result.errorMessage, isNot(contains('Node.js 未安装')));
      // CodexCliInstaller 给出真实的 npm 缺失错误
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('npm'));
    });

    test('installOne：node 完全缺失 → codex blocked（依赖真实未安装）', () async {
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
      expect(
          f.adapter.log.where((l) => l.contains('apt-get install')).length, 3);
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
      expect(
          first.firstWhere((r) => r.tool == RuntimeTool.node).success, isFalse);
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

  group('安装心跳（进度动态变化，不再卡静态 30%）', () {
    test('apt install 阻塞期间 onProgress 被持续调用且单调递增', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      // 模拟 apt 安装耗时 > 2 个心跳周期（心跳间隔 2s）
      f.adapter.installDelay = const Duration(milliseconds: 4600);

      final progressValues = <double>[];
      final messages = <String>[];
      await f.ctx.aptInstall(
        ['git'],
        onProgress: (p, m) {
          progressValues.add(p);
          messages.add(m);
        },
      );

      expect(progressValues.length, greaterThanOrEqualTo(2),
          reason: '安装阻塞期间应持续上报心跳进度');
      expect(progressValues.first, greaterThan(0.3));
      expect(progressValues.last, greaterThan(progressValues.first),
          reason: '心跳进度应单调递增（不卡在静态 30%）');
      expect(progressValues.last, lessThan(0.9),
          reason: '心跳封顶 0.89，避免与 verifying 的 0.9 混淆');
      expect(messages.first, contains('已运行'), reason: '心跳消息应附带已运行秒数');
      // 安装完成后 Timer 被取消（finally），进度停留在验证阶段的值
      expect(f.adapter.installedVersions['/usr/bin/git'], '2.43.0');
    });

    test('npm install 阻塞期间同样上报心跳', () async {
      final f = ToolchainFixture();
      addTearDown(f.dispose);
      f.adapter.installDelay = const Duration(milliseconds: 4600);
      // npm 前置：node/npm 已装
      f.adapter.installedVersions['/usr/bin/node'] = 'v18.19.1';
      f.adapter.installedVersions['/usr/bin/npm'] = '9.2.0';

      final progressValues = <double>[];
      await f.ctx.npmInstallGlobal(
        ['@openai/codex'],
        onProgress: (p, m) => progressValues.add(p),
      );

      expect(progressValues.length, greaterThanOrEqualTo(2));
      expect(progressValues.first, greaterThan(0.3));
      expect(progressValues.last, lessThan(0.9));
    });
  });
}
