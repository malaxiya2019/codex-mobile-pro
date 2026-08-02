/// ====================================================================
/// Phase 8 Environment Doctor 测试
///
/// 覆盖（收敛修复后）：
///   1. 干净环境 → 全部通过（proot / loader / rootfs / tmp / tmp-env /
///      dpkg / apt / node / npm / git / python3）
///   2. proot 缺失 → 结构化失败且安全中断
///   3. /tmp 缺失 → 自动创建 + TMPDIR/TMP/TEMP 环境变量验证
///   4. dpkg interrupted → dpkg --configure -a 被调用并修复
///   5. dpkg 修复失败 → 安全中断：不执行 apt/install/verify
///   6. 幂等：重复 runFullRepair 无副作用（configure -a 只执行一次）
///   7. npm 补装：node 已装 npm 缺 → 仅 apt install npm，不重装 nodejs
///   8. Capability 独立映射：npm 补装失败不影响 Node.js = installed
///   9. apt 失败 → 跳过 npm 补装（防止错误扩大）
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
  }

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('env-doctor-test');
    fakeRunner = FakeProcessRunner();
    paths = await createFakePaths(tmpRoot);
    doctor = EnvironmentDoctor(
      runner: fakeRunner,
      injectedPaths: paths,
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
      //         node/npm/git/python3（共 12 项）
      expect(report.checks.length, greaterThanOrEqualTo(12));
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
          'apt-get install -y npm',
          const FakeCommandResult(
            stdout: 'Setting up npm ... done',
          ));

      final report = await doctor.runFullRepair();

      // 触发 npm 补装：apt install npm 出现
      final ranNpmInstall = fakeRunner.executedRequests.any(
        (r) => r.arguments.join(' ') == 'install -y npm',
      );
      expect(ranNpmInstall, true, reason: '必须执行 apt install npm');
      // 不得重装 nodejs
      final ranFullNodeInstall = fakeRunner.executedRequests.any(
        (r) => r.arguments.join(' ') == 'install -y nodejs npm',
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
        (r) => r.arguments.join(' ') == 'install -y npm',
      );
      expect(ranNpmInstall, false);
      final npmCheck = report.checks.firstWhere((c) => c.name == 'npm');
      expect(npmCheck.passed, false);
      expect(npmCheck.detail, contains('跳过 npm 补装'));
      // 只读验证仍执行：node/git/python3 独立 capability 不受 apt 影响
      final nodeCheck = report.checks.firstWhere((c) => c.name == 'node');
      expect(nodeCheck.passed, true);
    });
  });
}
