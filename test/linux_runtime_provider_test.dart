/// ====================================================================
/// LinuxRuntimeProvider 单元测试
///
/// 覆盖：
///   1. 路径解析（LinuxRuntimePaths）
///   2. detect() — 未初始化 / 部分就绪 / 就绪
///   3. buildEnvironment() — 统一 Linux 环境
///   4. resolveExecutable() — rootfs 内解析
///   5. buildShellSpec() / buildCommandSpec() — 结构化 PRoot 参数
///   6. capabilities — 真实检测
///   7. healthCheck()
///
/// 全部使用注入的 LinuxRuntimePaths + 临时目录，不依赖真实 Termux。
/// ====================================================================
library;

import 'dart:io';

import 'package:codex_mobile_pro/runtime/provider/linux_runtime_provider.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_capability.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在临时目录构建一个最小 Linux Runtime 结构
LinuxRuntimePaths createFakePaths(Directory root) {
  final runtimeDir = Directory('${root.path}/runtime');
  final rootfsDir = Directory('${runtimeDir.path}/ubuntu/rootfs');
  final binDir = Directory('${runtimeDir.path}/ubuntu/bin');
  final libexecDir = Directory('${runtimeDir.path}/ubuntu/libexec');
  runtimeDir.createSync(recursive: true);
  rootfsDir.createSync(recursive: true);
  binDir.createSync(recursive: true);
  libexecDir.createSync(recursive: true);

  return LinuxRuntimePaths(
    prootExecutable: '${binDir.path}/proot',
    rootfsDir: rootfsDir.path,
    loaderPath: '${libexecDir.path}/proot/loader',
  );
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('linux_provider_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('LinuxRuntimePaths', () {
    test('默认 home/tmp', () {
      const paths = LinuxRuntimePaths(
        prootExecutable: '/x/proot',
        rootfsDir: '/x/rootfs',
        loaderPath: '/x/loader',
      );
      expect(paths.homeDir, '/root');
      expect(paths.tmpDir, '/tmp');
    });
  });

  group('LinuxRuntimeProvider — detect', () {
    test('未初始化 → unavailable', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);

      final info = await provider.detect();
      expect(info.status, ProviderStatus.unavailable);
      expect(info.capabilities, isNotEmpty);
      expect(info.health?.healthy, false);
    });

    test('proot 存在但 rootfs 缺失 → degraded', () async {
      final paths = createFakePaths(tmp);
      File(paths.prootExecutable).createSync(recursive: true);

      final provider = LinuxRuntimeProvider(paths: paths);
      final info = await provider.detect();
      expect(info.status, ProviderStatus.degraded);
    });

    test('proot + rootfs bash → available', () async {
      final paths = createFakePaths(tmp);
      File(paths.prootExecutable).createSync(recursive: true);
      final bash = File('${paths.rootfsDir}/usr/bin/bash');
      bash.createSync(recursive: true);
      File(paths.loaderPath).createSync(recursive: true);
      // os-release 版本信息
      final osRelease = File('${paths.rootfsDir}/etc/os-release');
      osRelease.createSync(recursive: true);
      osRelease.writeAsStringSync('PRETTY_NAME="Ubuntu 24.04.1 LTS"\nVERSION_ID="24.04"\n');

      final provider = LinuxRuntimeProvider(paths: paths);
      final info = await provider.detect();
      expect(info.status, ProviderStatus.available);
      expect(info.health?.healthy, true);
      expect(info.version, contains('24.04'));
      // rootfs 能力应报告可用
      final rootfsCap = info.capabilities
          .where((c) => c.type == CapabilityType.ubuntu)
          .firstOrNull;
      expect(rootfsCap, isNotNull);
      expect(rootfsCap!.available, true);
    });
  });

  group('LinuxRuntimeProvider — environment', () {
    test('buildEnvironment 返回统一 Linux 环境', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);
      final env = provider.buildEnvironment(paths);

      expect(env['HOME'], '/root');
      expect(env['SHELL'], '/bin/bash');
      expect(env['TMPDIR'], '/tmp');
      expect(
        env['PATH'],
        '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      );
      expect(env['PROOT_LOADER'], paths.loaderPath);
      expect(env['PROOT_ROOTFS'], paths.rootfsDir);
      expect(env['TERM'], 'xterm-256color');
    });

    test('getEnvironment 返回相同内容', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);
      final env = await provider.getEnvironment();
      expect(env['HOME'], '/root');
    });
  });

  group('LinuxRuntimeProvider — resolveExecutable', () {
    test('rootfs 内存在 → 返回绝对路径', () async {
      final paths = createFakePaths(tmp);
      final node = File('${paths.rootfsDir}/usr/bin/node');
      node.createSync(recursive: true);

      final provider = LinuxRuntimeProvider(paths: paths);
      final resolved = await provider.resolveExecutable('node');
      expect(resolved, '${paths.rootfsDir}/usr/bin/node');
    });

    test('rootfs 内不存在 → null', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);
      final resolved = await provider.resolveExecutable('node');
      expect(resolved, isNull);
    });
  });

  group('LinuxRuntimeProvider — process spec', () {
    test('buildShellSpec 返回结构化 PRoot 参数', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);

      final spec = await provider.buildShellSpec();
      expect(spec.executable, paths.prootExecutable);
      expect(spec.arguments, [
        '-r',
        paths.rootfsDir,
        '-b', '/proc',
        '-b', '/dev',
        '-b', '/sys',
        '/bin/bash',
        '-l',
      ]);
      expect(spec.environment['SHELL'], '/bin/bash');
      expect(spec.environment['DEBIAN_FRONTEND'], 'noninteractive');
      expect(spec.toProcessRequest().runtimeId, 'linux');
    });

    test('buildCommandSpec 包装为 bash -lc', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);

      final spec = await provider.buildCommandSpec(['node', '--version']);
      expect(spec.executable, paths.prootExecutable);
      expect(spec.arguments, [
        '-r',
        paths.rootfsDir,
        '-b', '/proc',
        '-b', '/dev',
        '-b', '/sys',
        '/bin/bash',
        '-lc',
        'node --version',
      ]);
    });

    test('workingDirectory 传递 -w', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);

      final spec = await provider.buildShellSpec(workingDirectory: '/root/proj');
      expect(spec.arguments, [
        '-r',
        paths.rootfsDir,
        '-b', '/proc',
        '-b', '/dev',
        '-b', '/sys',
        '-w',
        '/root/proj',
        '/bin/bash',
        '-l',
      ]);
    });
  });

  group('LinuxRuntimeProvider — capabilities', () {
    test('未就绪时只报告 rootfs 能力', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);
      final info = await provider.detect();

      final types = info.capabilities.map((c) => c.type).toSet();
      expect(types, {CapabilityType.ubuntu});
    });

    test('就绪时真实检测工具', () async {
      final paths = createFakePaths(tmp);
      File(paths.prootExecutable).createSync(recursive: true);
      File('${paths.rootfsDir}/usr/bin/bash').createSync(recursive: true);
      File('${paths.rootfsDir}/usr/bin/node').createSync(recursive: true);
      File('${paths.rootfsDir}/usr/bin/git').createSync(recursive: true);

      final provider = LinuxRuntimeProvider(paths: paths);
      final info = await provider.detect();

      final nodeCap = info.capabilities
          .where((c) => c.type == CapabilityType.node)
          .firstOrNull;
      expect(nodeCap, isNotNull);
      expect(nodeCap!.available, true);
      expect(nodeCap.executable, '${paths.rootfsDir}/usr/bin/node');

      // 未安装的工具报告不可用
      final npmCap = info.capabilities
          .where((c) => c.type == CapabilityType.npm)
          .firstOrNull;
      expect(npmCap, isNotNull);
      expect(npmCap!.available, false);
    });
  });

  group('LinuxRuntimeProvider — healthCheck', () {
    test('健康检查反映 proot/rootfs 状态', () async {
      final paths = createFakePaths(tmp);
      File(paths.prootExecutable).createSync(recursive: true);
      File('${paths.rootfsDir}/usr/bin/bash').createSync(recursive: true);

      final provider = LinuxRuntimeProvider(paths: paths);
      final health = await provider.healthCheck();
      expect(health.healthy, true);
      expect(health.checks.length, greaterThanOrEqualTo(2));
    });

    test('未安装 → 不健康', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);
      final health = await provider.healthCheck();
      expect(health.healthy, false);
    });
  });

  group('LinuxRuntimeProvider — rootfs DNS 修复', () {
    test('resolv.conf 缺失 → 写入公共 DNS', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);
      final ok = await provider.ensureResolvConf();
      final content = File('${paths.rootfsDir}/etc/resolv.conf').readAsStringSync();
      expect(ok, true);
      expect(content, contains('nameserver 8.8.8.8'));
      expect(content, contains('nameserver 1.1.1.1'));
    });

    test('resolv.conf 指向 127.0.0.53 stub → 覆盖为公共 DNS', () async {
      final paths = createFakePaths(tmp);
      final resolv = File('${paths.rootfsDir}/etc/resolv.conf')
        ..createSync(recursive: true)
        ..writeAsStringSync('nameserver 127.0.0.53\noptions edns0\n');

      final provider = LinuxRuntimeProvider(paths: paths);
      final ok = await provider.ensureResolvConf();
      expect(ok, true);
      final content = resolv.readAsStringSync();
      expect(content, contains('nameserver 8.8.8.8'));
      expect(content, isNot(contains('127.0.0.53')));
    });

    test('resolv.conf 已可用（公共 DNS）→ 幂等不重写', () async {
      final paths = createFakePaths(tmp);
      final resolv = File('${paths.rootfsDir}/etc/resolv.conf')
        ..createSync(recursive: true)
        ..writeAsStringSync('nameserver 8.8.8.8\n');

      final provider = LinuxRuntimeProvider(paths: paths);
      final ok = await provider.ensureResolvConf();
      expect(ok, true);
      expect(resolv.readAsStringSync(), 'nameserver 8.8.8.8\n');
    });

    test('apt ForceIPv4 配置写入', () async {
      final paths = createFakePaths(tmp);
      final provider = LinuxRuntimeProvider(paths: paths);
      await provider.ensureAptIpv4Only();
      final conf = File(
        '${paths.rootfsDir}/etc/apt/apt.conf.d/99codex-force-ipv4',
      );
      expect(conf.existsSync(), true);
      expect(conf.readAsStringSync(), contains('Acquire::ForceIPv4 "true";'));
    });

    test('apt ForceIPv4 幂等（已存在不重写）', () async {
      final paths = createFakePaths(tmp);
      final conf = File('${paths.rootfsDir}/etc/apt/apt.conf.d/99codex-force-ipv4')
        ..createSync(recursive: true)
        ..writeAsStringSync('Acquire::ForceIPv4 "true";\n');

      final provider = LinuxRuntimeProvider(paths: paths);
      await provider.ensureAptIpv4Only();
      expect(conf.readAsStringSync(), 'Acquire::ForceIPv4 "true";\n');
    });
  });
}
