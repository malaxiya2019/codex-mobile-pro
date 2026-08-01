/// ====================================================================
/// NativeProot（jniLibs 交付的 proot + loader）可用性验证
///
/// 覆盖用户要求的最小自动检测：
///   1. nativeLibraryDir/libproot.so 是否存在
///   2. executable 是否可启动（execve 冒烟）
///   3. `proot --version` 是否成功
///   4. nativeLibraryDir/libloader.so 是否存在
///
/// 说明：
///   - 使用「伪 proot」shell 脚本（支持 --version），真实 execve 由
///     测试宿主执行，避免依赖 ARM64 proot 二进制（CI x86_64 无法
///     执行 ARM ELF）。
///   - nativeLibDirQueryOverride 注入 fake nativeLibraryDir。
/// ====================================================================
library;

import 'dart:io';

import 'package:codex_mobile_pro/runtime/native/native_proot.dart';
import 'package:flutter_test/flutter_test.dart';

/// 创建「伪 proot」脚本（--version 输出横幅并退出 0）
File createFakeProot(Directory dir, {bool executable = true}) {
  final script = File('${dir.path}/libproot.so');
  if (script.existsSync()) script.deleteSync();
  script.writeAsStringSync('#!/bin/sh\n'
      'if [ "\$1" = "--version" ]; then\n'
      '  echo "fake proot 5.1.107.89"\n'
      '  exit 0\n'
      'fi\n'
      'exit 1\n');
  if (executable) {
    final chmod = Process.runSync('chmod', ['+x', script.path]);
    expect(chmod.exitCode, 0, reason: 'chmod 伪 proot 应成功');
  } else {
    Process.runSync('chmod', ['000', script.path]);
  }
  return script;
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('native_proot_test_');
  });

  tearDown(() {
    NativeProot.nativeLibDirQueryOverride = null;
    NativeProot.resetCache();
    try {
      Process.runSync('chmod', ['-R', '755', tmp.path]);
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ensureInstalled — 最小自动检测', () {
    test('nativeLibraryDir 不可用（非 Android / override null）→ null', () async {
      NativeProot.nativeLibDirQueryOverride = () async => null;
      expect(await NativeProot.ensureInstalled(), isNull);
    });

    test('libproot.so 不存在 → null（检测点 1 失败）', () async {
      final dir = Directory('${tmp.path}/nativelib')..createSync();
      NativeProot.nativeLibDirQueryOverride = () async => dir.path;
      expect(await NativeProot.ensureInstalled(), isNull);
    });

    test('libloader.so 不存在 → null（检测点 4 失败）', () async {
      final dir = Directory('${tmp.path}/nativelib')..createSync();
      createFakeProot(dir);
      NativeProot.nativeLibDirQueryOverride = () async => dir.path;
      expect(await NativeProot.ensureInstalled(), isNull);
    });

    test('proot 不可启动（无执行权限）→ null（检测点 2/3 失败）', () async {
      final dir = Directory('${tmp.path}/nativelib')..createSync();
      createFakeProot(dir, executable: false);
      File('${dir.path}/libloader.so').writeAsStringSync('static-loader');
      NativeProot.nativeLibDirQueryOverride = () async => dir.path;
      expect(await NativeProot.ensureInstalled(), isNull);
    });

    test('全部就绪 → 返回 nativeLibraryDir 路径', () async {
      final dir = Directory('${tmp.path}/nativelib')..createSync();
      createFakeProot(dir);
      File('${dir.path}/libloader.so').writeAsStringSync('static-loader');
      NativeProot.nativeLibDirQueryOverride = () async => dir.path;

      final result = await NativeProot.ensureInstalled();
      expect(result, isNotNull);
      expect(result!.prootExecutable, '${dir.path}/libproot.so');
      expect(result.loaderPath, '${dir.path}/libloader.so');
      expect(result.nativeLibraryDir, dir.path);
    });

    test('--version 非零退出 → null（检测点 3 失败）', () async {
      final dir = Directory('${tmp.path}/nativelib')..createSync();
      final script = createFakeProot(dir);
      // 覆盖成 --version 失败的行为
      script.writeAsStringSync('#!/bin/sh\n'
          'if [ "\$1" = "--version" ]; then\n'
          '  echo "boom" >&2\n'
          '  exit 2\n'
          'fi\n'
          'exit 1\n');
      Process.runSync('chmod', ['+x', script.path]);
      File('${dir.path}/libloader.so').writeAsStringSync('static-loader');
      NativeProot.nativeLibDirQueryOverride = () async => dir.path;

      expect(await NativeProot.ensureInstalled(), isNull);
    });
  });
}
