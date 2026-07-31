/// ====================================================================
/// UbuntuRuntimeInstaller 解压链路单元测试
///
/// 覆盖（2026-08「ProcessException: Permission denied」回归）：
///   1. 正常镜像读取 + 流式解压成功（strip-components、进度）
///   2. 缓存不存在 → 结构化 DeployError（xzcat 非零退出）
///   3. 缓存文件不可读 → 结构化 DeployError
///   4. 父目录不存在 → 结构化 DeployError
///   5. busybox 不可执行（EACCES）→ 转为 DeployError.permissionDenied，
///      而不是裸抛 ProcessException（核心修复）
///   6. busybox 不存在（ENOENT）→ DeployError.extractionFailed
///   7. 无任何解压器 → DeployError.dependencyMissing
///   8. 重新初始化后缓存恢复：坏 busybox 失败 → 好 busybox 续用同一
///      缓存直接解压成功
///   9. resolveBusybox 注入优先级
///
/// 说明：
///   - 使用「伪 busybox」shell 脚本（xzcat → 系统 xz -dc，tar → 系统
///     tar），避免依赖 ARM64 busybox 二进制（CI x86_64 无法执行）。
///   - 系统无 xz/tar 时用 markTestSkipped 跳过端到端用例，不伪造成功。
///   - 不依赖真实 Termux / 网络下载。
/// ====================================================================
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:codex_mobile_pro/runtime/deploy_error.dart';
import 'package:codex_mobile_pro/runtime/runtime_environment.dart';
import 'package:codex_mobile_pro/runtime/ubuntu_runtime_installer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 检查系统工具是否存在（返回其绝对路径；不存在返回空串）
String systemTool(String name) {
  try {
    final r = Process.runSync('sh', ['-c', 'command -v $name']);
    if (r.exitCode == 0) return (r.stdout as String).trim();
  } catch (_) {}
  return '';
}

/// 创建「伪 busybox」脚本（xzcat/tar 委托给系统工具）
File createFakeBusybox(Directory tmp, {bool executable = true}) {
  final script = File('${tmp.path}/fake-busybox');
  // 同一测试内多次调用时，旧文件可能被 chmod 000（无写权限），
  // 直接覆盖写会抛 PathAccessException，先删除重建。
  if (script.existsSync()) {
    script.deleteSync();
  }
  script.writeAsStringSync('#!/bin/sh\n'
      'case "\$1" in\n'
      '  xzcat) shift; exec xz -dc "\$@" ;;\n'
      '  tar) shift; exec tar "\$@" ;;\n'
      '  *) exit 127 ;;\n'
      'esac\n');
  if (executable) {
    final chmod = Process.runSync('chmod', ['+x', script.path]);
    expect(chmod.exitCode, 0, reason: 'chmod 伪 busybox 应成功');
  } else {
    Process.runSync('chmod', ['000', script.path]);
  }
  return script;
}

/// 生成一个含顶层 `ubuntu/` 前缀的最小 tar.xz（模拟 proot-distro rootfs）。
///
/// [systemXz] 为 true 时用系统 xz 生成（真实镜像格式，系统 xz 可解压）；
/// 否则回退 dart archive XZEncoder（仅用于 EACCES/ENOENT 等不需要
/// 成功解压的用例）。archive 3.6.1 的 XZEncoder 输出与系统 xz 不兼容
/// （系统 xz 报 "Compressed data is corrupt"），不能用于正常解压用例。
File createTinyRootfsTarXz(Directory cacheDir, {required bool systemXz}) {
  final archive = Archive();
  archive.addFile(ArchiveFile('ubuntu/etc/os-release', 0,
      utf8.encode('PRETTY_NAME="Ubuntu 24.04 (noble)"\n')));
  archive.addFile(ArchiveFile(
      'ubuntu/usr/bin/bash', 0, utf8.encode('#!/bin/sh\necho fake-bash\n')));
  archive.addFile(ArchiveFile('ubuntu/bin/true', 0, utf8.encode('')));
  final tarBytes = TarEncoder().encode(archive);
  if (systemXz) {
    final tarFile = File('${cacheDir.path}/ubuntu-rootfs.tar');
    tarFile.writeAsBytesSync(tarBytes, flush: true);
    final r = Process.runSync('xz', ['-f', tarFile.path]);
    if (r.exitCode == 0) {
      // xz -f 生成 ubuntu-rootfs.tar.xz 并删除原 tar 文件
      return File('${cacheDir.path}/ubuntu-rootfs.tar.xz');
    }
  }
  final xzBytes = XZEncoder().encode(tarBytes);
  final file = File('${cacheDir.path}/ubuntu-rootfs.tar.xz');
  file.writeAsBytesSync(xzBytes, flush: true);
  return file;
}

void main() {
  late Directory tmp;
  late String xzPath;
  late String tarPath;
  late bool toolsAvailable;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ubuntu_installer_test_');
    xzPath = systemTool('xz');
    tarPath = systemTool('tar');
    toolsAvailable = xzPath.isNotEmpty && tarPath.isNotEmpty;
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('resolveBusybox — 注入优先级', () {
    test('优先使用注入的 busybox 路径', () async {
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final installer = UbuntuRuntimeInstaller(env, null, '/fake/busybox');
      expect(await installer.resolveBusybox(), '/fake/busybox');
    });

    test('注入为空时走 NativeBusybox（测试环境无插件 → 返回 null）', () async {
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final installer = UbuntuRuntimeInstaller(env, null, '   ');
      // path_provider 在 flutter_test 无 mock 时抛 MissingPluginException，
      // ensureInstalled 捕获后返回 null —— 验证「无解压器」路径不裸抛。
      expect(await installer.resolveBusybox(), isNull);
    });
  });

  group('extractTarXzStreaming', () {
    UbuntuRuntimeInstaller newInstaller(
      RuntimeEnvironment env, {
      String? busyboxOverride,
      void Function(int piped)? onPiped,
    }) {
      return UbuntuRuntimeInstaller(
        env,
        (tool, phase, progress, message) {
          onPiped?.call((progress * 10000).round());
        },
        busyboxOverride,
      );
    }

    Future<void> extract(
      UbuntuRuntimeInstaller installer, {
      required String tarPath,
      required String targetDir,
      int expandedBytes = 0,
      void Function(int piped)? onPiped,
    }) {
      return installer.extractTarXzStreaming(
        tarPath: tarPath,
        targetDir: targetDir,
        stripComponents: 1,
        expandedBytes: expandedBytes,
        onProgress: onPiped ?? (_) {},
      );
    }

    test('正常镜像读取 → 解压成功、strip-components、进度推进', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final cacheDir = Directory('${env.ubuntuDir}/.cache')
        ..createSync(recursive: true);
      final rootfs = createTinyRootfsTarXz(cacheDir, systemXz: true);

      final targetDir = '${tmp.path}/rootfs-out';
      final tarBytes = TarEncoder().encode(
        Archive()..addFile(ArchiveFile('ubuntu/x', 0, utf8.encode('y'))),
      );
      final piped = <int>[];

      final installer = newInstaller(
        env,
        busyboxOverride: createFakeBusybox(tmp).path,
        onPiped: piped.add,
      );
      await extract(
        installer,
        tarPath: rootfs.path,
        targetDir: targetDir,
        expandedBytes: tarBytes.length,
        onPiped: piped.add,
      );

      // strip-components=1：ubuntu/ 前缀被去掉
      expect(File('$targetDir/etc/os-release').existsSync(), isTrue);
      expect(File('$targetDir/usr/bin/bash').existsSync(), isTrue);
      // 进度：至少有一次中间上报 + 最终上报 expandedBytes
      expect(piped.length, greaterThanOrEqualTo(2));
      expect(piped.last, tarBytes.length);
    });

    test('缓存不存在 → 结构化 DeployError(extractionFailed)，detail 含路径', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final installer = newInstaller(
        env,
        busyboxOverride: createFakeBusybox(tmp).path,
      );
      final missingPath = '${env.ubuntuDir}/.cache/not-exist.tar.xz';

      await expectLater(
        extract(
          installer,
          tarPath: missingPath,
          targetDir: '${tmp.path}/out',
        ),
        throwsA(isA<DeployError>()
            .having((e) => e.code, 'code', DeployErrorCode.extractionFailed)
            .having((e) => e.detail ?? '', 'detail 含镜像路径',
                contains('not-exist.tar.xz'))),
      );
    });

    test('缓存文件不可读（chmod 000）→ 结构化 DeployError', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final cacheDir = Directory('${env.ubuntuDir}/.cache')
        ..createSync(recursive: true);
      final rootfs = createTinyRootfsTarXz(cacheDir, systemXz: true);
      Process.runSync('chmod', ['000', rootfs.path]);

      final installer = newInstaller(
        env,
        busyboxOverride: createFakeBusybox(tmp).path,
      );
      await expectLater(
        extract(
          installer,
          tarPath: rootfs.path,
          targetDir: '${tmp.path}/out',
        ),
        throwsA(isA<DeployError>()
            .having((e) => e.code, 'code', DeployErrorCode.extractionFailed)),
      );
    });

    test('父目录不存在 → 结构化 DeployError', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final installer = newInstaller(
        env,
        busyboxOverride: createFakeBusybox(tmp).path,
      );
      final ghostPath = '${tmp.path}/no-such-parent/rootfs.tar.xz';

      await expectLater(
        extract(
          installer,
          tarPath: ghostPath,
          targetDir: '${tmp.path}/out',
        ),
        throwsA(isA<DeployError>()
            .having((e) => e.code, 'code', DeployErrorCode.extractionFailed)),
      );
    });

    test('busybox 不可执行（EACCES）→ 转为 permissionDenied，不裸抛 ProcessException',
        () async {
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final cacheDir = Directory('${env.ubuntuDir}/.cache')
        ..createSync(recursive: true);
      final rootfs = createTinyRootfsTarXz(cacheDir, systemXz: false);
      // 伪 busybox 存在但无执行位 → Process.start 抛 EACCES
      final broken = createFakeBusybox(tmp, executable: false);

      final installer = newInstaller(env, busyboxOverride: broken.path);
      await expectLater(
        extract(
          installer,
          tarPath: rootfs.path,
          targetDir: '${tmp.path}/out',
        ),
        throwsA(isA<DeployError>()
            .having((e) => e.code, 'code', DeployErrorCode.permissionDenied)
            .having((e) => e.detail ?? '', 'detail 含 busybox 路径',
                contains(broken.path))),
      );
    });

    test('busybox 不存在（ENOENT）→ extractionFailed，不裸抛', () async {
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final cacheDir = Directory('${env.ubuntuDir}/.cache')
        ..createSync(recursive: true);
      final rootfs = createTinyRootfsTarXz(cacheDir, systemXz: false);

      final installer =
          newInstaller(env, busyboxOverride: '${tmp.path}/no-busybox');
      await expectLater(
        extract(
          installer,
          tarPath: rootfs.path,
          targetDir: '${tmp.path}/out',
        ),
        throwsA(isA<DeployError>()
            .having((e) => e.code, 'code', DeployErrorCode.extractionFailed)),
      );
    });

    test('无任何解压器 → dependencyMissing（不崩溃）', () async {
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final installer = newInstaller(env, busyboxOverride: '');
      await expectLater(
        extract(
          installer,
          tarPath: '${tmp.path}/x.tar.xz',
          targetDir: '${tmp.path}/out',
        ),
        throwsA(isA<DeployError>()
            .having((e) => e.code, 'code', DeployErrorCode.dependencyMissing)),
      );
    });

    test('重新初始化后缓存恢复：坏 busybox 失败 → 好 busybox 续用同一缓存成功', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final env = RuntimeEnvironment.forTest('${tmp.path}/app');
      final cacheDir = Directory('${env.ubuntuDir}/.cache')
        ..createSync(recursive: true);
      final rootfs = createTinyRootfsTarXz(cacheDir, systemXz: true);
      final targetDir = '${tmp.path}/rootfs-out';

      // 第一次：坏 busybox → 结构化失败（模拟「重新初始化前」状态）
      final broken = createFakeBusybox(tmp, executable: false);
      final failInstaller = newInstaller(env, busyboxOverride: broken.path);
      await expectLater(
        extract(
          failInstaller,
          tarPath: rootfs.path,
          targetDir: targetDir,
        ),
        throwsA(isA<DeployError>()
            .having((e) => e.code, 'code', DeployErrorCode.permissionDenied)),
      );

      // 第二次（重新初始化）：好 busybox + 同一缓存 → 直接成功
      final good = createFakeBusybox(tmp);
      final okInstaller = newInstaller(env, busyboxOverride: good.path);
      await extract(
        okInstaller,
        tarPath: rootfs.path,
        targetDir: targetDir,
      );
      expect(File('$targetDir/etc/os-release').existsSync(), isTrue);
    });
  });
}
