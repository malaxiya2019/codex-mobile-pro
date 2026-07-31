/// ====================================================================
/// NativeBusybox 可用性验证单元测试
///
/// 覆盖（2026-08「解压工具启动失败（权限被拒绝）」回归）：
///   1. executable 不存在 → verifyUsable 返回 null
///   2. executable 无执行权限 → null（权限位缺失，即使文件存在）
///   3. executable 位于不可访问父目录（父目录 chmod 000）→ null
///   4. executable 损坏（非 ELF/脚本，有执行位）→ null（Exec format
///      error 被捕获）
///   5. 正常可执行文件 → 返回路径（execve 冒烟通过）
///   6. SHA-256 校验：内容匹配 / 不匹配 / 文件不存在
///   7. healthCheck 逐项精确错误码：notFound / permissionDenied /
///      execFailed（损坏）/ abiMismatch（伪造 x86_64 ELF）/ execFailed
///      （伪造 AArch64 ELF 但不可执行）/ none（伪脚本含 xzcat applet）
///   8. elfMachineOf：AArch64(183) / ARM(40) / x86_64(62) / 非 ELF /
///      不足 20 字节
///   9. installFromBytes 原子安装：正常 / 损坏目标替换 / SHA-256
///      不匹配 / execve 冒烟失败（无残留临时文件）
///
/// 说明：
///   - 使用「伪 busybox」shell 脚本（支持 true/xzcat/tar/--list
///     applet），避免依赖 ARM64 busybox 二进制（CI x86_64 无法执行）。
///   - 不依赖真实 Termux / Flutter 插件。
/// ====================================================================
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:codex_mobile_pro/runtime/native/busybox_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 创建「伪 busybox」脚本（true/xzcat/tar applet 委托系统工具）
File createFakeBusybox(Directory tmp, {bool executable = true}) {
  final script = File('${tmp.path}/fake-busybox');
  if (script.existsSync()) {
    // 旧文件可能被 chmod 000，先删除重建
    script.deleteSync();
  }
  script.writeAsStringSync('#!/bin/sh\n'
      'case "\$1" in\n'
      '  true) exit 0 ;;\n'
      '  xzcat) shift; exec xz -dc "\$@" ;;\n'
      '  tar) shift; exec tar "\$@" ;;\n'
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

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('busybox_provider_test_');
  });

  tearDown(() {
    try {
      // 恢复被 chmod 000 的目录权限，确保可递归删除
      Process.runSync('chmod', ['-R', '755', tmp.path]);
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('verifyUsable — execve 冒烟验证', () {
    test('executable 不存在 → null', () async {
      final ghost = File('${tmp.path}/no-such-busybox');
      expect(await NativeBusybox.verifyUsable(ghost), isNull);
    });

    test('executable 无执行权限 → null（权限位缺失）', () async {
      final broken = createFakeBusybox(tmp, executable: false);
      expect(await NativeBusybox.verifyUsable(broken, minSize: 0), isNull);
    });

    test('executable 位于不可访问父目录 → null（Process EACCES）', () async {
      final sub = Directory('${tmp.path}/locked')..createSync(recursive: true);
      final busybox = createFakeBusybox(sub);
      // 父目录去掉所有权限：Process.start 打开文件时 EACCES
      final chmod = Process.runSync('chmod', ['000', sub.path]);
      expect(chmod.exitCode, 0);
      expect(await NativeBusybox.verifyUsable(busybox, minSize: 0), isNull);
      Process.runSync('chmod', ['755', sub.path]);
    });

    test('executable 损坏（非 ELF，有执行位）→ null（Exec format error）', () async {
      final corrupt = File('${tmp.path}/corrupt-busybox');
      // 随机字节 + 执行位：execve 应抛 Exec format error
      corrupt.writeAsBytesSync(
        List<int>.generate(1024, (i) => i % 251),
        flush: true,
      );
      Process.runSync('chmod', ['+x', corrupt.path]);
      expect(await NativeBusybox.verifyUsable(corrupt, minSize: 0), isNull);
    });

    test('正常可执行文件 → 返回路径（冒烟通过）', () async {
      final good = createFakeBusybox(tmp);
      expect(await NativeBusybox.verifyUsable(good, minSize: 0), good.path);
    });
  });

  group('verifySha256 — 内容完整性校验', () {
    test('内容匹配期望 digest → true', () async {
      final f = File('${tmp.path}/data')
        ..writeAsBytesSync(utf8.encode('hello world'));
      final digest = await NativeBusybox.sha256Of(f);
      expect(await NativeBusybox.verifySha256(f, expected: digest), isTrue);
    });

    test('内容不匹配 → false', () async {
      final f = File('${tmp.path}/data')
        ..writeAsBytesSync(utf8.encode('hello world'));
      final other = File('${tmp.path}/other')
        ..writeAsBytesSync(utf8.encode('hello world!'));
      final otherDigest = await NativeBusybox.sha256Of(other);
      expect(
        await NativeBusybox.verifySha256(f, expected: otherDigest),
        isFalse,
      );
    });

    test('文件不存在 → false', () async {
      final ghost = File('${tmp.path}/no-such-file');
      expect(await NativeBusybox.verifySha256(ghost), isFalse);
    });
  });
  group('installFromBytes - atomic install (tmp + rename)', () {
    test(
        'normal install: target exists, executable, content matches, no tmp leftover',
        () async {
      final binDir = Directory('${tmp.path}/bin')..createSync(recursive: true);
      final target = File('${binDir.path}/busybox');
      final fake = createFakeBusybox(tmp);
      final bytes = fake.readAsBytesSync();
      final digest = await NativeBusybox.sha256Of(fake);

      final result = await NativeBusybox.installFromBytes(
        binDir,
        target,
        bytes,
        expectedSha: digest,
        minSize: 0,
      );

      expect(result, target.path);
      expect(target.existsSync(), isTrue);
      expect(target.readAsBytesSync(), bytes);
      final stat = await target.stat();
      expect(stat.mode & 0x40, isNot(0), reason: 'should have owner exec bit');
      // installed result must pass verifyUsable (minSize=0)
      expect(await NativeBusybox.verifyUsable(target, minSize: 0), target.path);
      // no temp file leftover
      final leftovers = binDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.tmp.'));
      expect(leftovers, isEmpty);
    });

    test('corrupt target is atomically replaced with full bytes', () async {
      final binDir = Directory('${tmp.path}/bin')..createSync(recursive: true);
      final target = File('${binDir.path}/busybox');
      // simulate legacy broken file (half-written/truncated, exec bit set)
      target.writeAsBytesSync(List<int>.generate(128, (i) => i % 251));
      Process.runSync('chmod', ['+x', target.path]);

      final fake = createFakeBusybox(tmp);
      final bytes = fake.readAsBytesSync();
      final digest = await NativeBusybox.sha256Of(fake);

      final result = await NativeBusybox.installFromBytes(
        binDir,
        target,
        bytes,
        expectedSha: digest,
        minSize: 0,
      );

      expect(result, target.path);
      expect(target.readAsBytesSync(), bytes, reason: 'corrupt file replaced');
    });

    test('sha256 mismatch -> null, no target, no tmp leftover', () async {
      final binDir = Directory('${tmp.path}/bin')..createSync(recursive: true);
      final target = File('${binDir.path}/busybox');
      final fake = createFakeBusybox(tmp);
      final bytes = fake.readAsBytesSync();
      final otherFile = File('${tmp.path}/other')
        ..writeAsBytesSync(utf8.encode('different content'));

      final result = await NativeBusybox.installFromBytes(
        binDir,
        target,
        bytes,
        expectedSha: await NativeBusybox.sha256Of(otherFile),
        minSize: 0,
      );

      expect(result, isNull);
      expect(target.existsSync(), isFalse,
          reason: 'no target on failed install');
      expect(
        binDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('.tmp.')),
        isEmpty,
        reason: 'no tmp leftover on failed install',
      );
    });

    test('execve smoke failure (non-ELF random bytes) -> null, no leftover',
        () async {
      final binDir = Directory('${tmp.path}/bin')..createSync(recursive: true);
      final target = File('${binDir.path}/busybox');
      final bytes = List<int>.generate(1024, (i) => i % 251);

      final result = await NativeBusybox.installFromBytes(
        binDir,
        target,
        bytes,
        // expectedSha omitted: skip sha256, focus on smoke failure path
        minSize: 0,
      );

      expect(result, isNull);
      expect(target.existsSync(), isFalse,
          reason: 'no target when smoke fails');
      expect(
        binDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('.tmp.')),
        isEmpty,
        reason: 'no tmp leftover when smoke fails',
      );
    });
  });

  group('healthCheck — 逐项失败点精确错误码', () {
    test('文件不存在 → notFound', () async {
      final ghost = File('${tmp.path}/no-such-busybox');
      final h = await NativeBusybox.healthCheck(ghost);
      expect(h.error, BusyboxErrorCode.notFound);
      expect(h.exists, isFalse);
    });

    test('无执行位 → permissionDenied', () async {
      final broken = createFakeBusybox(tmp, executable: false);
      final h = await NativeBusybox.healthCheck(broken, minSize: 0);
      expect(h.error, BusyboxErrorCode.permissionDenied);
      expect(h.execBit, isFalse);
    });

    test('损坏（非 ELF 随机字节，有执行位）→ execFailed（execve ENOEXEC）',
        () async {
      final corrupt = File('${tmp.path}/corrupt-busybox');
      corrupt.writeAsBytesSync(
        List<int>.generate(1024, (i) => i % 251),
        flush: true,
      );
      Process.runSync('chmod', ['+x', corrupt.path]);
      final h = await NativeBusybox.healthCheck(corrupt, minSize: 0);
      expect(h.error, BusyboxErrorCode.execFailed);
      expect(h.elfMachine, isNull, reason: '非 ELF 不判 ABI');
    });

    test('伪造 ELF e_machine=62（x86_64）→ abiMismatch', () async {
      final wrong = File('${tmp.path}/x86-busybox');
      wrong.writeAsBytesSync(_elfHeader(62), flush: true);
      Process.runSync('chmod', ['+x', wrong.path]);
      final h = await NativeBusybox.healthCheck(wrong, minSize: 0);
      expect(h.error, BusyboxErrorCode.abiMismatch);
      expect(h.elfMachine, 62);
    });

    test('伪造 ELF e_machine=183（AArch64）但内容不可执行 → execFailed', () async {
      final fakeArm = File('${tmp.path}/fake-arm-busybox');
      fakeArm.writeAsBytesSync(
        [..._elfHeader(183), ...List<int>.generate(64, (i) => i % 251)],
        flush: true,
      );
      Process.runSync('chmod', ['+x', fakeArm.path]);
      final h = await NativeBusybox.healthCheck(fakeArm, minSize: 0);
      expect(h.abiOk, isTrue, reason: 'ABI 检测通过');
      expect(h.error, BusyboxErrorCode.execFailed, reason: '内容非真实 ELF');
    });

    test('正常伪脚本（含 xzcat applet）→ none（完全可用）', () async {
      final good = createFakeBusybox(tmp);
      final h = await NativeBusybox.healthCheck(good, minSize: 0);
      expect(h.error, BusyboxErrorCode.none);
      expect(h.usable, isTrue);
      expect(h.execSmokeOk, isTrue);
      expect(h.xzcatOk, isTrue);
    });
  });

  group('elfMachineOf — ELF e_machine 解析', () {
    test('AArch64 (183) 识别', () async {
      final f = File('${tmp.path}/arm64')
        ..writeAsBytesSync(_elfHeader(183), flush: true);
      expect(NativeBusybox.elfMachineOf(f), 183);
    });

    test('ARM (40) 识别', () async {
      final f = File('${tmp.path}/arm')
        ..writeAsBytesSync(_elfHeader(40), flush: true);
      expect(NativeBusybox.elfMachineOf(f), 40);
    });

    test('x86_64 (62) 识别', () async {
      final f = File('${tmp.path}/x86')
        ..writeAsBytesSync(_elfHeader(62), flush: true);
      expect(NativeBusybox.elfMachineOf(f), 62);
    });

    test('非 ELF（无 magic）→ null', () async {
      final f = File('${tmp.path}/not-elf')
        ..writeAsBytesSync(List<int>.generate(20, (i) => i), flush: true);
      expect(NativeBusybox.elfMachineOf(f), isNull);
    });

    test('不足 20 字节 → null', () async {
      final f = File('${tmp.path}/short')
        ..writeAsBytesSync(List<int>.generate(12, (i) => i), flush: true);
      expect(NativeBusybox.elfMachineOf(f), isNull);
    });
  });

  group('nativeLibraryDir 优先（jniLibs 解压区，系统保证可执行）', () {
    test('nativeLibraryDir 中存在可用 libbusybox.so → 直接复用该路径',
        () async {
      final real = _findRealBusybox();
      if (real == null) {
        markTestSkipped('当前平台无可用真实 busybox ELF，跳过');
        return;
      }
      final nativeDir =
          Directory('${tmp.path}/native-lib')..createSync(recursive: true);
      final so = File('${nativeDir.path}/libbusybox.so');
      File(real).copySync(so.path);

      final r = await NativeBusybox.ensureInstalledDetailed(
        nativeLibraryDir: nativeDir.path,
      );
      expect(r.success, isTrue);
      expect(
        r.path,
        so.path,
        reason: '应优先复用 nativeLibraryDir 中的 libbusybox.so，'
            '而不是复制到 filesDir',
      );
    });

    test('nativeLibraryDir 不存在 libbusybox.so → 正常回退（不裸抛）',
        () async {
      final nativeDir =
          Directory('${tmp.path}/empty-native')..createSync(recursive: true);
      final r = await NativeBusybox.ensureInstalledDetailed(
        nativeLibraryDir: nativeDir.path,
      );
      // 回退到 assets 复制流程；CI（x86）上 arm64 busybox 不可执行 → 返回
      // 失败结果。平台无关断言：绝不裸抛异常，返回结构化结果。
      expect(r, isA<BusyboxInstallResult>());
    });

    test('nativeLibDirQueryOverride 生效（不传参时走注入查询）', () async {
      NativeBusybox.nativeLibDirQueryOverride =
          () async => '${tmp.path}/no-such-dir';
      addTearDown(() => NativeBusybox.nativeLibDirQueryOverride = null);
      final r = await NativeBusybox.ensureInstalledDetailed();
      expect(r, isA<BusyboxInstallResult>());
    });
  });
}

/// 查找当前平台可执行的真实 busybox（Termux/Android 环境；CI 通常没有）。
String? _findRealBusybox() {
  try {
    final r = Process.runSync('sh', ['-c', 'command -v busybox']);
    if (r.exitCode == 0) {
      final p = (r.stdout as String).trim();
      if (p.isNotEmpty && File(p).existsSync()) return p;
    }
  } catch (_) {}
  return null;
}

/// 构造最小 ELF header（前 20 字节），offset 18-19 为小端 e_machine。
List<int> _elfHeader(int eMachine) => [
      0x7F, 0x45, 0x4C, 0x46, // ELF magic
      2, // ELFCLASS64
      1, // EI_DATA=LSB
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 填充
      eMachine & 0xFF, (eMachine >> 8) & 0xFF, // e_machine
    ];

