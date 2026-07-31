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
///   6. SHA-256 校验：内容匹配 → true
///   7. SHA-256 校验：内容不匹配 → false
///   8. SHA-256 校验：文件不存在 → false
///
/// 说明：
///   - 使用「伪 busybox」shell 脚本（支持 true/xzcat/tar applet），
///     避免依赖 ARM64 busybox 二进制（CI x86_64 无法执行）。
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
}
