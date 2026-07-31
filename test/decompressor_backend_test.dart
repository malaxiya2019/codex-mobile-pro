/// ====================================================================
/// DecompressorBackend 单元测试
///
/// 2026-08 止损重构：验证「Termux 优先 + 内置 BusyBox fallback」的
/// 解压后端选择与错误映射。
///
/// 覆盖：
///   1. Termux xz+tar 可用 → 选择 TermuxXzBackend
///   2. Termux busybox 可用 → TermuxBusyboxBackend
///   3. 全部不可用 → NoDecompressorBackend（分项状态）
///   4. busyboxOverride（测试注入）优先
///   5. TermuxXzBackend 真实解压小 tar.xz
///   6. BusyboxBackend 真实解压小 tar.xz
///   7. busybox 无执行权限（EACCES）→ permissionDenied
///   8. busybox 不存在（ENOENT）→ extractionFailed
///   9. 镜像不存在 / 不可读 → extractionFailed（结构化，不裸抛）
///   10. 正常进度上报
///
/// 说明：
///   - Termux 路径通过注入 prefix（fake 目录 + 委托脚本）模拟，
///     不依赖真实 Termux，也不硬编码 /data/data/com.termux/...。
///   - 系统无 xz/tar 时用 markTestSkipped 跳过端到端解压用例。
///   - 不依赖网络下载。
/// ====================================================================
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:codex_mobile_pro/runtime/decompressor/decompressor_backend.dart';
import 'package:codex_mobile_pro/runtime/deploy_error.dart';
import 'package:flutter_test/flutter_test.dart';

/// 检查系统工具是否存在（返回其绝对路径；不存在返回空串）
String systemTool(String name) {
  try {
    final r = Process.runSync('sh', ['-c', 'command -v $name']);
    if (r.exitCode == 0) return (r.stdout as String).trim();
  } catch (_) {}
  return '';
}

final systemXz = systemTool('xz');
final systemTar = systemTool('tar');
final toolsAvailable = systemXz.isNotEmpty && systemTar.isNotEmpty;

/// 创建「伪 busybox」脚本（xzcat/tar 委托给系统工具）
File createFakeBusybox(Directory tmp, {bool executable = true}) {
  final script = File('${tmp.path}/fake-busybox');
  if (script.existsSync()) {
    script.deleteSync();
  }
  script.writeAsStringSync('#!/bin/sh\n'
      'case "\$1" in\n'
      '  xzcat) shift; exec $systemXz -dc "\$@" ;;\n'
      '  tar) shift; exec $systemTar "\$@" ;;\n'
      '  --list) echo "ash xz xzcat tar true"; exit 0 ;;\n'
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

/// 在 fake prefix 下构造 Termux 风格的 bin 目录
///
/// [xz]/[tar]/[busybox] 分别控制是否创建对应可执行脚本；
/// xz/tar 脚本委托系统工具，busybox 脚本为伪 busybox。
Directory createFakePrefix(
  Directory tmp, {
  bool xz = true,
  bool tar = true,
  bool busybox = true,
}) {
  final prefix = '${tmp.path}/fake-prefix';
  final bin = Directory('$prefix/bin')..createSync(recursive: true);

  if (xz) {
    final f = File('${bin.path}/xz')
      ..writeAsStringSync('#!/bin/sh\nexec $systemXz "\$@"\n');
    Process.runSync('chmod', ['+x', f.path]);
  }
  if (tar) {
    final f = File('${bin.path}/tar')
      ..writeAsStringSync('#!/bin/sh\nexec $systemTar "\$@"\n');
    Process.runSync('chmod', ['+x', f.path]);
  }
  if (busybox) {
    final f = File('${bin.path}/busybox');
    f.writeAsStringSync('#!/bin/sh\n'
        'case "\$1" in\n'
        '  xzcat) shift; exec $systemXz -dc "\$@" ;;\n'
        '  tar) shift; exec $systemTar "\$@" ;;\n'
        '  --list) echo "ash xz xzcat tar true"; exit 0 ;;\n'
        '  *) exit 127 ;;\n'
        'esac\n');
    Process.runSync('chmod', ['+x', f.path]);
  }
  return Directory(prefix);
}

/// 生成一个含顶层 `ubuntu/` 前缀的最小 tar.xz（模拟 rootfs 格式）
File createTinyRootfsTarXz(Directory dir, {required bool systemXzCompress}) {
  final archive = Archive();
  archive.addFile(ArchiveFile('ubuntu/etc/os-release', 0,
      utf8.encode('PRETTY_NAME="Ubuntu 24.04 (noble)"\n')));
  archive.addFile(ArchiveFile('ubuntu/usr/bin/bash', 0,
      utf8.encode('#!/bin/sh\necho fake-bash\n')));
  final tarBytes = TarEncoder().encode(archive);
  final file = File('${dir.path}/tiny-rootfs.tar.xz');
  if (systemXzCompress) {
    final rawTar = File('${dir.path}/tiny-rootfs.tar')
      ..writeAsBytesSync(tarBytes);
    final xz = Process.runSync(systemXz, ['-c', rawTar.path],
        stdoutEncoding: null); // 二进制输出，禁止 UTF-8 解码
    expect(xz.exitCode, 0, reason: '系统 xz 压缩失败');
    file.writeAsBytesSync((xz.stdout as List<int>));
    try {
      rawTar.deleteSync();
    } catch (_) {}
  } else {
    file.writeAsBytesSync(XZEncoder().encode(tarBytes));
  }
  return file;
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('decompressor_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('DecompressorResolver — 自动选择', () {
    test('Termux xz+tar 可用 → 选择 TermuxXzBackend', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过');
        return;
      }
      final prefix = createFakePrefix(tmp);
      final backend = await DecompressorResolver.resolve(prefix: prefix.path);
      expect(backend, isA<TermuxXzBackend>());
      expect(backend.available, isTrue);
      expect(backend.kind, DecompressorKind.xzTar);
      expect(backend.source, DecompressorSource.termux);
      expect(backend.busyboxPath, isNull);
    });

    test('Termux xz 不可用但 busybox 可用 → TermuxBusyboxBackend', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过');
        return;
      }
      final prefix = createFakePrefix(tmp, xz: false);
      final backend = await DecompressorResolver.resolve(prefix: prefix.path);
      expect(backend, isA<TermuxBusyboxBackend>());
      expect(backend.available, isTrue);
      expect(backend.kind, DecompressorKind.busybox);
      expect(backend.source, DecompressorSource.termux);
      expect(backend.busyboxPath, isNotNull);
    });

    test('Termux 全部不可用 → 回退到内置 BusyBox（bundled）', () async {
      // fake prefix 无任何工具 → Termux 后端不可用。
      // 内置 BusyBox 在 flutter_test 中无法安装（path_provider 抛
      // MissingPluginException，系统临时目录 execve 冒烟失败）→
      // BundledBusyboxBackend 也失败 → NoDecompressorBackend。
      // 断言分项状态完整（3 个候选），不依赖具体平台可用性。
      final prefix = createFakePrefix(tmp, xz: false, tar: false, busybox: false);
      final backend = await DecompressorResolver.resolve(prefix: prefix.path);
      expect(backend, isA<NoDecompressorBackend>());
      expect(backend.available, isFalse);
      expect(backend.status.length, greaterThanOrEqualTo(3));
      final names = backend.status.map((s) => s.name).toList();
      expect(names, contains('Termux xz + tar'));
      expect(names, contains('Termux busybox'));
      expect(names, contains('App 内置 BusyBox'));
    });

    test('无 PREFIX（Termux 未运行）→ Termux 候选标记为未检测到', () async {
      final backend = await DecompressorResolver.resolve(prefix: '');
      expect(backend.available, isFalse);
      final termuxXz = backend.status
          .firstWhere((s) => s.name == 'Termux xz + tar');
      expect(termuxXz.available, isFalse);
      expect(termuxXz.reason, contains('PREFIX'));
    });

    test('busyboxOverride（测试注入）优先', () async {
      final bb = createFakeBusybox(tmp);
      final backend =
          await DecompressorResolver.resolve(busyboxOverride: bb.path);
      expect(backend, isA<BundledBusyboxBackend>());
      expect(backend.available, isTrue);
      expect(backend.busyboxPath, bb.path);
    });
  });

  group('解压（端到端，依赖系统 xz/tar）', () {
    test('TermuxXzBackend 流式解压成功 + 进度上报 + strip-components',
        () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final prefix = createFakePrefix(tmp);
      final backend =
          await DecompressorResolver.resolve(prefix: prefix.path);
      expect(backend, isA<TermuxXzBackend>());

      final tiny = createTinyRootfsTarXz(tmp, systemXzCompress: true);
      final out = '${tmp.path}/out';
      final piped = <int>[];
      await backend.extractTarXz(
        tarPath: tiny.path,
        targetDir: out,
        stripComponents: 1,
        expandedBytes: 9999,
        onProgress: piped.add,
      );
      expect(File('$out/etc/os-release').existsSync(), isTrue);
      expect(File('$out/usr/bin/bash').existsSync(), isTrue);
      // 至少一次中间上报 + 最终上报 expandedBytes
      expect(piped.length, greaterThanOrEqualTo(2));
      expect(piped.last, 9999);
    });

    test('BusyboxBackend（override）流式解压成功', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final bb = createFakeBusybox(tmp);
      final backend = BundledBusyboxBackend(path: bb.path);
      await backend.checkAvailable();
      expect(backend.available, isTrue);

      final tiny = createTinyRootfsTarXz(tmp, systemXzCompress: true);
      final out = '${tmp.path}/out-bb';
      await backend.extractTarXz(
        tarPath: tiny.path,
        targetDir: out,
        stripComponents: 1,
        expandedBytes: 0,
        onProgress: (_) {},
      );
      expect(File('$out/etc/os-release').existsSync(), isTrue);
    });

    test('BusyboxBackend 单命令（tar xf 内置 xz）解压成功 + 进度', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final bb = createFakeBusybox(tmp);
      final backend = BundledBusyboxBackend(path: bb.path);
      await backend.checkAvailable();
      expect(backend.available, isTrue);

      final tiny = createTinyRootfsTarXz(tmp, systemXzCompress: true);
      final out = '${tmp.path}/out-single';
      final piped = <int>[];
      // 单命令模式：busybox tar xf <tar.xz> -C <target>（busybox tar
      // 内置 xz 解压，不经过独立 xzcat 进程 —— 与 Operit 验证路径一致）
      await backend.extractTarXz(
        tarPath: tiny.path,
        targetDir: out,
        stripComponents: 1,
        expandedBytes: 9999,
        onProgress: piped.add,
      );
      expect(File('$out/etc/os-release').existsSync(), isTrue);
      expect(File('$out/usr/bin/bash').existsSync(), isTrue);
      // 最终上报 expandedBytes
      expect(piped, isNotEmpty);
      expect(piped.last, 9999);
    });

    test('镜像不存在 → extractionFailed，detail 含路径（不裸抛）', () async {
      if (!toolsAvailable) {
        markTestSkipped('系统无 xz/tar，跳过端到端解压测试');
        return;
      }
      final bb = createFakeBusybox(tmp);
      final backend = BundledBusyboxBackend(path: bb.path);
      await backend.checkAvailable();

      await expectLater(
        backend.extractTarXz(
          tarPath: '${tmp.path}/no-such/rootfs.tar.xz',
          targetDir: '${tmp.path}/out',
          stripComponents: 1,
          expandedBytes: 0,
          onProgress: (_) {},
        ),
        throwsA(isA<DeployError>().having(
          (e) => e.code,
          'code',
          DeployErrorCode.extractionFailed,
        )),
      );
    });
  });

  group('Busybox 验证 — 精确错误映射', () {
    test('无执行权限（EACCES）→ permissionDenied', () async {
      final broken = createFakeBusybox(tmp, executable: false);
      final backend = BundledBusyboxBackend(path: broken.path);
      await backend.checkAvailable();
      expect(backend.available, isFalse);
      expect(backend.failureCode, DeployErrorCode.permissionDenied);
      expect(backend.reason, contains(broken.path));
    });

    test('文件不存在（ENOENT）→ extractionFailed', () async {
      final backend =
          BundledBusyboxBackend(path: '${tmp.path}/no-busybox');
      await backend.checkAvailable();
      expect(backend.available, isFalse);
      expect(backend.failureCode, DeployErrorCode.extractionFailed);
    });

    test('busybox 可执行但缺少 xzcat/tar applet → dependencyMissing',
        () async {
      final f = File('${tmp.path}/bad-busybox')
        ..writeAsStringSync('#!/bin/sh\necho "ash only"\nexit 0\n');
      Process.runSync('chmod', ['+x', f.path]);
      final backend = BundledBusyboxBackend(path: f.path);
      await backend.checkAvailable();
      expect(backend.available, isFalse);
      expect(backend.failureCode, DeployErrorCode.dependencyMissing);
    });
  });

  group('extractTarXz — 不可用后端', () {
    test('NoDecompressorBackend 调用 → 结构化 DeployError', () async {
      final backend = NoDecompressorBackend(const [
        DecompressorStatus(
          name: 'Termux xz + tar',
          available: false,
          reason: '未检测到 PREFIX',
        ),
      ]);
      await expectLater(
        backend.extractTarXz(
          tarPath: '${tmp.path}/x.tar.xz',
          targetDir: '${tmp.path}/out',
          stripComponents: 1,
          expandedBytes: 0,
          onProgress: (_) {},
        ),
        throwsA(isA<DeployError>()
            .having((e) => e.code, 'code', DeployErrorCode.dependencyMissing)
            .having((e) => e.message, 'message 含「解压工具不可用」',
                contains('解压工具不可用'))),
      );
    });
  });
}
