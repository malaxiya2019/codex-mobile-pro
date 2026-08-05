/// ====================================================================
/// Phase 8 Environment Doctor 测试
///
/// 覆盖（收敛修复后）：
///   1. 干净环境 → 全部通过（proot / loader / rootfs / tmp / tmp-env /
///      dpkg / apt / node / npm / git / python3 / codex）
///   2. proot 缺失 → 结构化失败且安全中断
///   3. /tmp 缺失 → 自动创建 + TMPDIR/TMP/TEMP 环境变量验证
///   4. dpkg interrupted → dpkg --configure -a 被调用并修复
///   5. dpkg 修复失败 → 安全中断：不执行 apt/install/verify
///   6. 幂等：重复 runFullRepair 无副作用（configure -a 只执行一次）
///   7. npm 补装：node 已装 npm 缺 → 仅 apt install npm，不重装 nodejs
///   8. Capability 独立映射：npm 补装失败不影响 Node.js = installed
///   9. apt 失败 → 跳过 npm 补装（防止错误扩大）
///  10. 修复环境自愈：node 缺失+apt 可用 → 补装 nodejs+npm
///  11. git 缺失+apt 可用 → 补装 git
///  12. codex 缺失+npm 可用 → npm 全局补装 @openai/codex
///  13. apt 失败 → node/git/codex 一律只读不补装
/// ====================================================================
library;

import 'dart:io';

import 'package:codex_mobile_pro/runtime/environment_doctor.dart';
import 'package:codex_mobile_pro/runtime/provider/linux_runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capability/fake_runner.dart';

/// 创建最小可用的 Linux Runtime 目录 + 注入路径
Future<LinuxRuntimePaths> createFakePaths(Directory root) async {
  final rootfs = Directory('${root.path}/rootfs');
  final bin = Directory('${root.path}/bin');
  await rootfs.create(recursive: true);
  await bin.create(recursive: true);
  await Directory('${rootfs.path}/usr/bin').create(recursive: true);
  await Directory('${rootfs.path}/tmp').create(recursive: true);
  await File('${bin.path}/proot').writeAsString('proot');
  await File('${bin.path}/loader').writeAsString('loader');
  await File('${rootfs.path}/usr/bin/bash').writeAsString('bash');
  return LinuxRuntimePaths(
    prootExecutable: '${bin.path}/proot',
    rootfsDir: rootfs.path,
    loaderPath: '${bin.path}/loader',
    fromNativeLibrary: true,
  );
}

void main() {
  late Directory tmpRoot;
  late FakeProcessRunner fakeRunner;
  late EnvironmentDoctor doctor;
  late LinuxRuntimePaths paths;

  /// 干净环境预设：proot 冒烟 / dpkg / apt / 工具链全部成功
  void setUpHealthy() {
    fakeRunner.when(
        'proot --version',
        const FakeCommandResult(
          stdout: 'proot version 5.4.0\n',
        ));
    fakeRunner.when('dpkg --audit', const FakeCommandResult());
    fakeRunner.when('apt-get update', const FakeCommandResult());
    fakeRunner.when(
        'node --version',
        const FakeCommandResult(
          stdout: 'v18.19.1\n',
        ));
    fakeRunner.when(
        'npm --version',
        const FakeCommandResult(
          stdout: '9.2.0\n',
        ));
    fakeRunner.when(
        'git --version',
        const FakeCommandResult(
          stdout: 'git version 2.43.0\n',
        ));
    fakeRunner.when(
        'python3 --version',
        const FakeCommandResult(
          stdout: 'Python 3.12.3\n',
        ));
    fakeRunner.when(
        'codex --version',
        const FakeCommandResult(
          stdout: '0.50.0\n',
        ));
  }

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('env-doctor-test');
    fakeRunner = FakeProcessRunner();
    paths = await createFakePaths(tmpRoot);
    doctor = EnvironmentDoctor(
      runner: fakeRunner,
      injectedPaths: paths,
      // 全部不可达：preselect 测速不写源、不发真实 HTTP（测试隔离）
      aptSourceProbe: (_) async => null,
    );
  });

  tearDown(() async {
    if (await tmpRoot.exists()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  group('EnvironmentDoctor — 干净环境', () {
    test('全部检查通过（PRoot/tmp/dpkg/apt/工具链）', () async {
      setUpHealthy();

      final report = await doctor.runFullRepair();

      expect(report.allPassed, true, reason: report.summary);
      expect(report.hasUnresolved, false);
      expect(report.anyRepaired, false);
      // 检查项：proot/loader/rootfs/proot-smoke/tmp/tmp-env/dpkg/apt/
      //         node/npm/git/python3/codex（共 13 项）
      expect(report.checks.length, greaterThanOrEqualTo(13));
      final names = report.checks.map((c) => c.name).toList();
      for (final n in [
        'proot',
        'loader',
        'rootfs',
        'proot-smoke',
        'tmp',
        'tmp-env',
        'dpkg',
        'apt',
        'node',
        'npm',
        'git',
        'python3',
        'codex',
      ]) {
        expect(names, contains(n), reason: '缺少检查项 $n: $names');
      }
      // 幂等：全绿环境下不触发任何修复动作
      expect(
        fakeRunner.executedRequests
            .where((r) => r.arguments.join(' ').contains('install'))
            .toList(),
        isEmpty,
      );
    });

    test('proot 冒烟走宿主上下文（不经过 rootfs 路径转换）', () async {
      setUpHealthy();

      await doctor.runFullRepair();

      // proot 冒烟请求必须是宿主路径 executable + --version
      final smoke = fakeRunner.executedRequests
          .where((r) =>
              r.arguments.join(' ') == '--version' &&
              r.executable.endsWith('/bin/proot'))
          .toList();
      expect(smoke, isNotEmpty);
      final req = smoke.first;
      expect(req.executable, endsWith('/bin/proot'));
      // 环境必须携带 PROOT_LOADER（宿主直接执行 proot 需要 loader）
      expect(req.environment?['PROOT_LOADER'], endsWith('/bin/loader'));
    });
  });

  group('EnvironmentDoctor — proot 缺失', () {
    test('结构化失败且跳过后续 rootfs 操作', () async {
      // 删除 proot 文件 → proot 检查失败
      await File(paths.prootExecutable).delete();

      final report = await doctor.runFullRepair();

      final proot = report.checks.firstWhere((c) => c.name == 'proot');
      expect(proot.passed, false);
      expect(proot.detail, contains('不存在'));
      expect(report.allPassed, false);
      // proot 缺失 → 后续 dpkg/apt/工具链均不应执行（安全中断）
      final names = report.checks.map((c) => c.name).toList();
      expect(names, isNot(contains('dpkg')));
      expect(names, isNot(contains('apt')));
      expect(names, isNot(contains('node')));
      expect(names, isNot(contains('npm')));
    });
  });

  group('EnvironmentDoctor — /tmp 与 TMPDIR/TMP/TEMP', () {
    test('自动创建 rootfs /tmp，TMPDIR/TMP/TEMP 指向 Ubuntu /tmp', () async {
      setUpHealthy();
      await Directory('${paths.rootfsDir}/tmp').delete(recursive: true);
      expect(Directory('${paths.rootfsDir}/tmp').existsSync(), false);

      final report = await doctor.runFullRepair();

      final tmp = report.checks.firstWhere((c) => c.name == 'tmp');
      expect(tmp.passed, true);
      expect(tmp.repaired, true);
      expect(Directory('${paths.rootfsDir}/tmp').existsSync(), true);

      // guest 内 TMPDIR/TMP/TEMP 必须一致且指向 Ubuntu /tmp，
      // 与宿主侧 PROOT_TMP_DIR（linux_execution 注入）解耦
      final tmpEnv = report.checks.firstWhere((c) => c.name == 'tmp-env');
      expect(tmpEnv.passed, true, reason: tmpEnv.detail);
      expect(tmpEnv.detail, contains('TMPDIR/TMP/TEMP=/tmp'));
    });
  });

  group('EnvironmentDoctor — dpkg interrupted recovery', () {
    test('发现 interrupted → 执行 dpkg --configure -a → 复验通过', () async {
      setUpHealthy();
      // 第一次 audit 报 interrupted；复验 audit 干净
      fakeRunner.whenSequence('dpkg --audit', const [
        FakeCommandResult(
          exitCode: 1,
          stderr: 'dpkg: error: dpkg status database is locked by another '
              "process\nError: couldn't find any packages",
        ),
        FakeCommandResult(),
      ]);
      // dpkg --configure -a 修复成功
      fakeRunner.when(
          'dpkg --configure -a',
          const FakeCommandResult(
            stdout: 'Setting up ... done',
          ));

      final report = await doctor.runFullRepair();

      final dpkg = report.checks.firstWhere((c) => c.name == 'dpkg');
      expect(dpkg.passed, true, reason: report.summary);
      expect(dpkg.repaired, true);
      // 断言 dpkg --configure -a 被执行
      final ranFix = fakeRunner.executedRequests.any(
        (r) =>
            r.executable.endsWith('dpkg') &&
            r.arguments.join(' ') == '--configure -a',
      );
      expect(ranFix, true);
      // 修复后工具链照常验证
      expect(report.allPassed, true, reason: report.summary);
    });

    test('dpkg 修复失败 → 安全中断：不执行 apt/install/verify', () async {
      setUpHealthy();
      // audit 报 interrupted
      fakeRunner.when(
          'dpkg --audit',
          const FakeCommandResult(
            exitCode: 1,
            stderr: 'dpkg was interrupted',
          ));
      // configure -a 失败
      fakeRunner.when(
          'dpkg --configure -a',
          const FakeCommandResult(
            exitCode: 1,
            stderr: 'dpkg: error: cannot open lock file',
          ));

      final report = await doctor.runFullRepair();

      final dpkg = report.checks.firstWhere((c) => c.name == 'dpkg');
      expect(dpkg.passed, false);
      expect(dpkg.detail, contains('--configure -a 失败'));
      // 安全中断：后续 apt update / install / 工具链验证一律不执行
      final names = report.checks.map((c) => c.name).toList();
      expect(names, isNot(contains('apt')));
      expect(names, isNot(contains('node')));
      expect(names, isNot(contains('npm')));
      expect(names, isNot(contains('git')));
      expect(names, isNot(contains('python3')));
      final ranAptUpdate = fakeRunner.executedRequests.any(
        (r) =>
            r.executable.endsWith('apt-get') &&
            r.arguments.isNotEmpty &&
            r.arguments.first == 'update',
      );
      expect(ranAptUpdate, false, reason: 'dpkg 未恢复不得继续 apt');
      // 不删除 lock 文件（无 rm /var/lib/dpkg 相关命令）
      final rmLock = fakeRunner.executedRequests.any(
        (r) =>
            r.arguments.join(' ').contains('rm') &&
            r.arguments.join(' ').contains('lock'),
      );
      expect(rmLock, false);
    });

    test('幂等：两次 runFullRepair，configure -a 只执行一次', () async {
      setUpHealthy();
      // 第一次 audit interrupted；之后（复验 + 第二次完整流程）干净
      fakeRunner.whenSequence('dpkg --audit', const [
        FakeCommandResult(
          exitCode: 1,
          stderr: 'dpkg was interrupted',
        ),
        FakeCommandResult(),
      ]);
      fakeRunner.when(
          'dpkg --configure -a',
          const FakeCommandResult(
            stdout: 'Setting up ... done',
          ));

      final first = await doctor.runFullRepair();
      final second = await doctor.runFullRepair();

      expect(first.allPassed, true, reason: first.summary);
      expect(second.allPassed, true, reason: second.summary);
      // 第二次不应再触发修复
      expect(second.anyRepaired, false);
      // configure -a 只执行一次
      final fixCount = fakeRunner.executedRequests
          .where((r) => r.arguments.join(' ') == '--configure -a')
          .length;
      expect(fixCount, 1, reason: '幂等要求修复动作只执行一次');
      // 两次报告结构一致
      expect(second.checks.length, first.checks.length);
    });

    test('重复执行不破坏环境：/tmp 仍可写、无安装动作', () async {
      setUpHealthy();
      // 模拟上次执行遗留的探针文件
      await File('${paths.rootfsDir}/tmp/.codex_doctor_probe')
          .writeAsString('stale');
      final first = await doctor.runFullRepair();
      final second = await doctor.runFullRepair();

      expect(first.allPassed, true, reason: first.summary);
      expect(second.allPassed, true, reason: second.summary);
      // /tmp 仍可写：探针写入删除成功（tmp check passed）
      final tmpCheck = second.checks.firstWhere((c) => c.name == 'tmp');
      expect(tmpCheck.passed, true, reason: tmpCheck.detail);
      expect(tmpCheck.repaired, false);
      // 无任何 install 动作（不污染环境）
      final installs = fakeRunner.executedRequests
          .where((r) => r.arguments.contains('install'))
          .toList();
      expect(installs, isEmpty);
    });
  });

  test('缺 list/md5sums 控制文件 → 检测到 → 重装损坏包 → audit 干净', () async {
    setUpHealthy();
    const brokenText = 'The following packages are missing the list control '
        'file in the database, they need to be reinstalled:\n'
        ' dpkg-dev             Debian package development tools\n'
        'The following packages are missing the md5sums control file in '
        'the database, they need to be reinstalled:\n'
        ' dpkg-dev             Debian package development tools\n';
    // audit：损坏 → configure -a 后复验仍损坏 → 重装后最终复验干净
    fakeRunner.whenSequence('dpkg --audit', [
      const FakeCommandResult(stdout: brokenText),
      const FakeCommandResult(stdout: brokenText),
      const FakeCommandResult(),
    ]);
    fakeRunner.when('dpkg --configure -a', const FakeCommandResult());
    fakeRunner.when('apt-get update', const FakeCommandResult());
    fakeRunner.when('apt-get install --reinstall -y dpkg-dev',
        const FakeCommandResult(stdout: 'Setting up dpkg-dev ...'));

    final report = await doctor.runFullRepair();

    final dpkg = report.checks.firstWhere((c) => c.name == 'dpkg');
    expect(dpkg.passed, true, reason: report.summary);
    expect(dpkg.repaired, true);
    expect(dpkg.detail, contains('重装损坏包'));
    // apt-get install --reinstall -y dpkg-dev 确实被执行
    final ranReinstall = fakeRunner.executedRequests.any(
      (r) =>
          r.executable.endsWith('apt-get') &&
          r.arguments.join(' ') == 'install --reinstall -y dpkg-dev',
    );
    expect(ranReinstall, true);
    expect(report.allPassed, true, reason: report.summary);
  });

  test('重装损坏包失败 → dpkg 未恢复，安全中断后续流程', () async {
    setUpHealthy();
    const brokenText = 'The following packages are missing the list control '
        'file in the database, they need to be reinstalled:\n'
        ' dpkg-dev             Debian package development tools\n';
    fakeRunner.whenSequence('dpkg --audit', [
      const FakeCommandResult(stdout: brokenText),
      const FakeCommandResult(stdout: brokenText),
    ]);
    fakeRunner.when('dpkg --configure -a', const FakeCommandResult());
    fakeRunner.when('apt-get update', const FakeCommandResult());
    fakeRunner.when(
        'apt-get install --reinstall -y dpkg-dev',
        const FakeCommandResult(
          exitCode: 1,
          stderr: 'E: dpkg was interrupted, you must manually run '
              "'dpkg --configure -a' to correct the problem.",
        ));

    final report = await doctor.runFullRepair();

    final dpkg = report.checks.firstWhere((c) => c.name == 'dpkg');
    expect(dpkg.passed, false);
    expect(dpkg.detail, contains('重装损坏包失败'));
    // 安全中断：后续 apt / node / npm / git / python3 一律不出现
    final names = report.checks.map((c) => c.name).toList();
    expect(names, isNot(contains('apt')));
    expect(names, isNot(contains('node')));
    expect(names, isNot(contains('npm')));
    expect(names, isNot(contains('git')));
    expect(names, isNot(contains('python3')));
  });

  test('重装后 audit 仍异常 → dpkg 失败（不误判成功）', () async {
    setUpHealthy();
    const brokenText = 'The following packages are missing the list control '
        'file in the database, they need to be reinstalled:\n'
        ' dpkg-dev             Debian package development tools\n';
    // 三次 audit 全部报损坏（重装未能恢复）
    fakeRunner.whenSequence('dpkg --audit', [
      const FakeCommandResult(stdout: brokenText),
      const FakeCommandResult(stdout: brokenText),
      const FakeCommandResult(stdout: brokenText),
    ]);
    fakeRunner.when('dpkg --configure -a', const FakeCommandResult());
    fakeRunner.when('apt-get update', const FakeCommandResult());
    fakeRunner.when('apt-get install --reinstall -y dpkg-dev',
        const FakeCommandResult(stdout: 'Setting up dpkg-dev ...'));

    final report = await doctor.runFullRepair();

    final dpkg = report.checks.firstWhere((c) => c.name == 'dpkg');
    expect(dpkg.passed, false);
    expect(dpkg.detail, contains('dpkg 重装后仍异常'));
    expect(report.allPassed, false);
  });

  group('EnvironmentDoctor — npm 补装与 Capability 独立映射', () {
    test('node 已装、npm 缺失 → 仅补装 npm，不重装 nodejs', () async {
      setUpHealthy();
      // 真机复刻：node 18.19.1 可用，npm --version exit=127（broken）
      fakeRunner.when(
          'npm --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: npm',
          ));
      // apt install npm 成功（fake 无法模拟安装后状态，
      // npm --version 保持失败 → npm check 判为未恢复，Node 仍独立通过）
      fakeRunner.when(
          'apt-get install -y --no-install-recommends npm',
          const FakeCommandResult(
            stdout: 'Setting up npm ... done',
          ));

      final report = await doctor.runFullRepair();

      // 触发 npm 补装：apt install npm 出现
      final ranNpmInstall = fakeRunner.executedRequests.any(
        (r) =>
            r.arguments.join(' ') == 'install -y --no-install-recommends npm',
      );
      expect(ranNpmInstall, true, reason: '必须执行 apt install npm');
      // 不得重装 nodejs
      final ranFullNodeInstall = fakeRunner.executedRequests.any(
        (r) =>
            r.arguments.join(' ') ==
            'install -y --no-install-recommends nodejs npm',
      );
      expect(ranFullNodeInstall, false, reason: 'node 已装不得重装 nodejs');

      // Capability 独立映射：npm 失败不影响 Node.js = installed
      final nodeCheck = report.checks.firstWhere((c) => c.name == 'node');
      expect(nodeCheck.passed, true, reason: nodeCheck.detail);
      expect(nodeCheck.detail, contains('v18.19.1'));
      final npmCheck = report.checks.firstWhere((c) => c.name == 'npm');
      expect(npmCheck.passed, false, reason: 'fake 下 npm 未恢复');
      expect(npmCheck.repaired, true);
      // Git / Python3 独立通过
      final gitCheck = report.checks.firstWhere((c) => c.name == 'git');
      expect(gitCheck.passed, true);
      final pyCheck = report.checks.firstWhere((c) => c.name == 'python3');
      expect(pyCheck.passed, true);
    });

    test('npm 可用 → 不触发任何安装（无副作用）', () async {
      setUpHealthy();

      final report = await doctor.runFullRepair();

      expect(report.allPassed, true, reason: report.summary);
      expect(report.anyRepaired, false);
      final installs = fakeRunner.executedRequests
          .where((r) => r.arguments.contains('install'))
          .toList();
      expect(installs, isEmpty);
      final npmCheck = report.checks.firstWhere((c) => c.name == 'npm');
      expect(npmCheck.passed, true);
      expect(npmCheck.repaired, false);
    });

    test('apt 失败 → 跳过 npm 补装（防止错误扩大）', () async {
      setUpHealthy();
      fakeRunner.when(
          'npm --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: npm',
          ));
      fakeRunner.when(
          'apt-get update',
          const FakeCommandResult(
            exitCode: 100,
            stderr: 'E: Failed to fetch http://ports.ubuntu.com/... '
                'Unable to connect',
          ));

      final report = await doctor.runFullRepair();

      final apt = report.checks.firstWhere((c) => c.name == 'apt');
      expect(apt.passed, false);
      // apt 不可用 → 不得尝试 apt install npm
      final ranNpmInstall = fakeRunner.executedRequests.any(
        (r) =>
            r.arguments.join(' ') == 'install -y --no-install-recommends npm',
      );
      expect(ranNpmInstall, false);
      final npmCheck = report.checks.firstWhere((c) => c.name == 'npm');
      expect(npmCheck.passed, false);
      expect(npmCheck.detail, contains('跳过 npm 补装'));
      // 只读验证仍执行：node/git/python3 独立 capability 不受 apt 影响
      final nodeCheck = report.checks.firstWhere((c) => c.name == 'node');
      expect(nodeCheck.passed, true);
    });

    test('node 未安装 → 全量补装 nodejs+npm，不单独触发 npm 补装', () async {
      setUpHealthy();
      // 真机极端场景：node 与 npm 均不可用
      fakeRunner.when(
          'node --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: node',
          ));
      fakeRunner.when(
          'npm --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: npm',
          ));
      // apt 安装成功（fake 无法模拟安装后状态，node --version 仍失败）
      fakeRunner.when(
          'apt-get install -y --no-install-recommends nodejs npm',
          const FakeCommandResult(
            stdout: 'Setting up nodejs ... done',
          ));

      final report = await doctor.runFullRepair();

      // node 缺失 → NodeJsInstaller 全量补装 nodejs+npm
      final ranFull = fakeRunner.executedRequests.any(
        (r) =>
            r.arguments.join(' ') ==
            'install -y --no-install-recommends nodejs npm',
      );
      expect(ranFull, true, reason: 'node 缺失时必须执行 apt install nodejs npm');
      // 不单独触发 npm 补装（已包含在全量安装里）
      final ranNpmOnly = fakeRunner.executedRequests.any(
        (r) =>
            r.arguments.join(' ') == 'install -y --no-install-recommends npm',
      );
      expect(ranNpmOnly, false);
      // Node 独立 check：fake 下安装后仍未恢复 → 失败但标记 repaired
      final nodeCheck = report.checks.firstWhere((c) => c.name == 'node');
      expect(nodeCheck.passed, false);
      expect(nodeCheck.repaired, true);
      // npm 分支明确「node 未安装，跳过 npm 补装」（独立补装分支）
      final npmCheck = report.checks.firstWhere((c) => c.name == 'npm');
      expect(npmCheck.passed, false);
      expect(npmCheck.repaired, false);
      expect(npmCheck.detail, contains('node 未安装'));
      // git/python3/codex 独立 capability 不受影响
      final gitCheck = report.checks.firstWhere((c) => c.name == 'git');
      expect(gitCheck.passed, true);
      expect(report.allPassed, false, reason: 'node 缺失时整体不应判定通过');
    });
  });

  group('EnvironmentDoctor — 工具链补装（修复环境自愈）', () {
    bool ranAptInstall(FakeProcessRunner runner, String packages) =>
        runner.executedRequests.any((r) =>
            r.executable.endsWith('apt-get') &&
            r.arguments.join(' ') ==
                'install -y --no-install-recommends $packages');

    bool ranNpmGlobalInstall(FakeProcessRunner runner) =>
        runner.executedRequests.any((r) =>
            r.executable.endsWith('npm') &&
            r.arguments.isNotEmpty &&
            r.arguments.first == 'install');

    test('node 缺失 + apt 可用 → 补装 nodejs+npm', () async {
      setUpHealthy();
      fakeRunner.when(
          'node --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: node',
          ));
      fakeRunner.when(
          'apt-get install -y --no-install-recommends nodejs npm',
          const FakeCommandResult(
            stdout: 'Setting up nodejs ... done',
          ));

      final report = await doctor.runFullRepair();

      expect(ranAptInstall(fakeRunner, 'nodejs npm'), isTrue,
          reason: 'node 缺失时必须触发 apt install nodejs npm');
      final nodeCheck = report.checks.firstWhere((c) => c.name == 'node');
      expect(nodeCheck.passed, isFalse, reason: 'fake 下 node 未恢复');
      expect(nodeCheck.repaired, isTrue);
      // npm 独立 capability：npm 本身可用 → passed（不受 node 补装影响）
      final npmCheck = report.checks.firstWhere((c) => c.name == 'npm');
      expect(npmCheck.passed, isTrue, reason: npmCheck.detail);
    });

    test('git 缺失 + apt 可用 → 补装 git', () async {
      setUpHealthy();
      fakeRunner.when(
          'git --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: git',
          ));
      fakeRunner.when(
          'apt-get install -y --no-install-recommends git',
          const FakeCommandResult(
            stdout: 'Setting up git ... done',
          ));

      final report = await doctor.runFullRepair();

      expect(ranAptInstall(fakeRunner, 'git'), isTrue,
          reason: 'git 缺失时必须触发 apt install git');
      final gitCheck = report.checks.firstWhere((c) => c.name == 'git');
      expect(gitCheck.passed, isFalse, reason: 'fake 下 git 未恢复');
      expect(gitCheck.repaired, isTrue);
    });

    test('codex 缺失 + npm 可用 → npm 全局补装 @openai/codex', () async {
      setUpHealthy();
      fakeRunner.when(
          'codex --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: codex',
          ));
      fakeRunner.when('npm install -g --no-fund --no-audit @openai/codex',
          const FakeCommandResult(stdout: 'added 1 package'));

      final report = await doctor.runFullRepair();

      expect(ranNpmGlobalInstall(fakeRunner), isTrue,
          reason: 'codex 缺失且 npm 可用时必须触发 npm 全局安装');
      final codexCheck = report.checks.firstWhere((c) => c.name == 'codex');
      expect(codexCheck.passed, isFalse, reason: 'fake 下 codex 未恢复');
      expect(codexCheck.repaired, isTrue);
      // 其它工具链不受影响
      expect(report.checks.firstWhere((c) => c.name == 'node').passed, isTrue);
      expect(report.checks.firstWhere((c) => c.name == 'npm').passed, isTrue);
      expect(report.checks.firstWhere((c) => c.name == 'git').passed, isTrue);
    });

    test('apt 失败 → node/git 不补装；codex 走 npm 独立补装', () async {
      setUpHealthy();
      fakeRunner.when(
          'node --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: node',
          ));
      fakeRunner.when(
          'git --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: git',
          ));
      fakeRunner.when(
          'codex --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: codex',
          ));
      fakeRunner.when(
          'apt-get update',
          const FakeCommandResult(
            exitCode: 100,
            stderr: 'E: Failed to fetch http://ports.ubuntu.com/... '
                'Unable to connect',
          ));
      fakeRunner.when('npm install -g --no-fund --no-audit @openai/codex',
          const FakeCommandResult(stdout: 'added 1 package'));

      final report = await doctor.runFullRepair();

      // apt 类安装被禁止（node/git 依赖 apt）
      expect(ranAptInstall(fakeRunner, 'nodejs npm'), isFalse);
      expect(ranAptInstall(fakeRunner, 'git'), isFalse);
      // codex 补装仅依赖 npm（registry 与 apt 源独立），npm 可用时仍自愈
      expect(ranNpmGlobalInstall(fakeRunner), isTrue,
          reason: 'codex 补装走 npm，不依赖 apt 可用性');
      // 只读验证仍给出独立结果
      final nodeCheck = report.checks.firstWhere((c) => c.name == 'node');
      expect(nodeCheck.passed, isFalse);
      expect(nodeCheck.repaired, isFalse);
      final gitCheck = report.checks.firstWhere((c) => c.name == 'git');
      expect(gitCheck.passed, isFalse);
      expect(gitCheck.repaired, isFalse);
      final codexCheck = report.checks.firstWhere((c) => c.name == 'codex');
      expect(codexCheck.passed, isFalse);
      expect(codexCheck.repaired, isTrue, reason: 'fake 下 codex 未恢复，但补装已触发');
    });

    test('codex 缺失但 npm 不可用 → 不触发 npm 全局补装', () async {
      setUpHealthy();
      fakeRunner.when(
          'codex --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: codex',
          ));
      fakeRunner.when(
          'npm --version',
          const FakeCommandResult(
            exitCode: 127,
            stderr: 'command not found: npm',
          ));
      // npm 缺失 → NodeJsInstaller 走 apt 补装 npm（与 npm 全局安装无关）
      fakeRunner.when(
          'apt-get install -y --no-install-recommends npm',
          const FakeCommandResult(
            stdout: 'Setting up npm ... done',
          ));

      final report = await doctor.runFullRepair();

      expect(ranNpmGlobalInstall(fakeRunner), isFalse,
          reason: 'npm 不可用时 codex 不得触发全局安装');
      final codexCheck = report.checks.firstWhere((c) => c.name == 'codex');
      expect(codexCheck.passed, isFalse);
      expect(codexCheck.repaired, isFalse);
    });
  });
}
