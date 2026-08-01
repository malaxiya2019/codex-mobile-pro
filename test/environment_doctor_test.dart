/// ====================================================================
/// Phase 8 Environment Doctor 测试
///
/// 覆盖：
///   1. 干净环境 → 全部通过（proot / loader / rootfs / tmp / dpkg / apt）
///   2. proot 缺失 → 结构化失败
///   3. /tmp 缺失 → 自动创建
///   4. dpkg interrupted → dpkg --configure -a 被调用并修复
///   5. dpkg 修复失败 → 结构化失败（不删 lock）
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

  /// 干净环境预设：proot 冒烟 / dpkg / apt 全部成功
  void setUpHealthy() {
    fakeRunner.when('proot --version', const FakeCommandResult(
      exitCode: 0,
      stdout: 'proot version 5.4.0\n',
    ));
    fakeRunner.when('dpkg --audit', const FakeCommandResult(
      exitCode: 0,
      stdout: '',
    ));
    fakeRunner.when('apt-get update', const FakeCommandResult(
      exitCode: 0,
      stdout: '',
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
    test('全部检查通过', () async {
      setUpHealthy();

      final report = await doctor.runFullRepair();

      expect(report.allPassed, true, reason: report.summary);
      expect(report.hasUnresolved, false);
      expect(report.anyRepaired, false);
      // 检查项：proot/loader/rootfs/proot-smoke/tmp/dpkg/apt（共 7 项）
      expect(report.checks.length, greaterThanOrEqualTo(7));
      final names = report.checks.map((c) => c.name).toList();
      expect(names, contains('proot'));
      expect(names, contains('proot-smoke'));
      expect(names, contains('loader'));
      expect(names, contains('rootfs'));
      expect(names, contains('tmp'));
      expect(names, contains('dpkg'));
      expect(names, contains('apt'));
    });

    test('proot 冒烟走宿主上下文（不经过 rootfs 路径转换）', () async {
      setUpHealthy();

      await doctor.runFullRepair();

      // proot 冒烟请求必须是宿主路径 executable + --version
      final smoke = fakeRunner.executedRequests
          .where((r) => r.arguments.join(' ') == '--version')
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
      // proot 缺失 → 后续 dpkg/apt 不应执行
      final names = report.checks.map((c) => c.name).toList();
      expect(names, isNot(contains('dpkg')));
      expect(names, isNot(contains('apt')));
    });
  });

  group('EnvironmentDoctor — /tmp 缺失', () {
    test('自动创建 rootfs /tmp', () async {
      setUpHealthy();
      await Directory('${paths.rootfsDir}/tmp').delete(recursive: true);
      expect(Directory('${paths.rootfsDir}/tmp').existsSync(), false);

      final report = await doctor.runFullRepair();

      final tmp = report.checks.firstWhere((c) => c.name == 'tmp');
      expect(tmp.passed, true);
      expect(tmp.repaired, true);
      expect(Directory('${paths.rootfsDir}/tmp').existsSync(), true);
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
        FakeCommandResult(exitCode: 0, stdout: ''),
      ]);
      // dpkg --configure -a 修复成功
      fakeRunner.when('dpkg --configure -a', const FakeCommandResult(
        exitCode: 0,
        stdout: 'Setting up ... done',
      ));

      final report = await doctor.runFullRepair();

      final dpkg = report.checks.firstWhere((c) => c.name == 'dpkg');
      expect(dpkg.passed, true, reason: report.summary);
      // 断言 dpkg --configure -a 被执行
      final ranFix = fakeRunner.executedRequests.any(
        (r) => r.executable.endsWith('dpkg') &&
            r.arguments.join(' ') == '--configure -a',
      );
      expect(ranFix, true);
    });

    test('dpkg 修复失败 → 结构化失败（不删除 lock）', () async {
      setUpHealthy();
      // audit 报 interrupted
      fakeRunner.when('dpkg --audit', const FakeCommandResult(
        exitCode: 1,
        stderr: 'dpkg was interrupted',
      ));
      // configure -a 失败
      fakeRunner.when('dpkg --configure -a', const FakeCommandResult(
        exitCode: 1,
        stderr: 'dpkg: error: cannot open lock file',
      ));

      final report = await doctor.runFullRepair();

      final dpkg = report.checks.firstWhere((c) => c.name == 'dpkg');
      expect(dpkg.passed, false);
      expect(dpkg.detail, contains('--configure -a 失败'));
    });
  });
}
