/// ====================================================================
/// ArtifactManager 幂等目录创建 + .deb 精确目标提取测试
///
/// 覆盖 2026-08 真机 ENOTDIR 根因（proot 统一 strip 布局冲突）：
///   `FileSystemException: Creation failed, path =
///   '.../runtime/ubuntu/bin/proot' (OS Error: Not a directory, errno = 20)`
///
/// 场景：
///   1. ensureDirectory 幂等（不存在 / 目录 / 文件 / 符号链接 /
///      父目录被错误创建为文件）
///   2. extractDebFileTargets 精确提取（复现 proot deb 真实路径结构：
///      data/data/com.termux/files/usr/... → bin/ 与 libexec/ 分离布局）
///   3. 旧版残留损坏状态（bin/proot 是文件）→ 修复后重部署成功
///   4. 并发提取到同一目标 → 结果一致（配合 InstallLock 并发防护）
///
/// 不依赖网络 / 真实 Termux / 系统 xz（使用 archive 包自编码自解码）。
/// ====================================================================
library;

import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:codex_mobile_pro/runtime/artifact_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造最小 ar 归档（.deb 外壳）。
///
/// [members]：成员名 → 内容。自动处理 60 字节头与偶数对齐。
List<int> buildArDeb(Map<String, List<int>> members) {
  final buf = BytesBuilder();
  buf.add(utf8.encode('!<arch>\n'));
  for (final e in members.entries) {
    final data = e.value;
    final header = StringBuffer()
      ..write(e.key.padRight(16)) // name
      ..write('0'.padRight(12)) // mtime
      ..write('0'.padRight(6)) // uid
      ..write('0'.padRight(6)) // gid
      ..write('100644'.padRight(8)) // mode
      ..write(data.length.toString().padLeft(10)) // size
      ..write('\x60\x0a'); // magic
    buf.add(utf8.encode(header.toString()));
    buf.add(data);
    if (data.length.isOdd) buf.addByte(0x0a);
  }
  return buf.toBytes();
}

/// 检查系统 xz 是否可用（构造 .deb 需要真实 xz 编码：
/// archive 3.6.1 的 XZEncoder 输出与自身 XZDecoder 不兼容，
/// 而生产环境 .deb 的 data.tar.xz 由 Termux 用真实 xz 生成）。
bool get _systemXzAvailable {
  try {
    final r = Process.runSync('xz', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// 构造 data.tar.xz（tar 内路径保留 `./data/...` 前缀，模拟 proot .deb）。
/// 使用系统 xz 生成真实 xz 流（与 XZDecoder 兼容）。
/// 系统无 xz 时返回 null（调用方应跳过用例）。
List<int>? buildDataTarXz(List<(String, List<int>, int)> files) {
  if (!_systemXzAvailable) return null;
  final archive = Archive();
  for (final (name, content, mode) in files) {
    final af = ArchiveFile(name, content.length, content);
    af.mode = mode;
    archive.addFile(af);
  }
  final tarBytes = TarEncoder().encode(archive);
  final tmpDir = Directory.systemTemp.createTempSync('artifact_xz_');
  try {
    final tarFile = File('${tmpDir.path}/data.tar');
    tarFile.writeAsBytesSync(tarBytes, flush: true);
    final r = Process.runSync('xz', ['-f', tarFile.path]);
    if (r.exitCode != 0) return null;
    final xzFile = File('${tmpDir.path}/data.tar.xz');
    return xzFile.readAsBytesSync();
  } catch (_) {
    return null;
  } finally {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// 模拟 proot .deb：data.tar.xz 内含 proot / loader / loader32，
/// 路径与 Termux 真实包一致（`./data/data/com.termux/files/usr/...`）。
/// 返回是否具备构造 .deb 的环境（系统 xz）；不具备时跳过端到端用例。
bool _prootDebAvailable() => _systemXzAvailable;

void writeProotDeb(File deb, {int extra = 0}) {
  // extra 仅在“失败后重部署”用例用于区分两次内容；
  // extra == 0 时保持基准内容（proot-binary），避免断言歧义。
  final String suffix = extra == 0 ? '' : '$extra';
  final tarXz = buildDataTarXz([
    (
      './data/data/com.termux/files/usr/bin/proot',
      utf8.encode('proot-binary$suffix'),
      0x1ED, // 755
    ),
    (
      './data/data/com.termux/files/usr/libexec/proot/loader',
      utf8.encode('loader-binary$suffix'),
      0x1ED,
    ),
    (
      './data/data/com.termux/files/usr/libexec/proot/loader32',
      utf8.encode('loader32-binary$suffix'),
      0x1ED,
    ),
  ]);
  final debBytes = buildArDeb({
    'debian-binary': utf8.encode('2.0\n'),
    'control.tar.xz': buildArDeb({}), // 占位（不会被解析）
    'data.tar.xz': tarXz!,
  });
  deb.writeAsBytesSync(debBytes, flush: true);
}

/// proot 精确目标映射（与 runtime_manifest.dart 的 fileTargets 一致）
Map<String, String> prootTargets(String ubuntuDir) => {
      'usr/bin/proot': '$ubuntuDir/bin/proot',
      'usr/libexec/proot/loader': '$ubuntuDir/libexec/proot/loader',
      'usr/libexec/proot/loader32': '$ubuntuDir/libexec/proot/loader32',
    };

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('artifact_manager_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ═══════════════════════════════════════════════════════════════
  // ensureDirectory 幂等
  // ═══════════════════════════════════════════════════════════════
  group('ArtifactManager.ensureDirectory — 幂等路径类型修复', () {
    test('目标不存在 → 创建目录成功', () async {
      final target = '${tmp.path}/runtime/ubuntu/bin';
      await ArtifactManager.ensureDirectory(target);
      expect(Directory(target).existsSync(), isTrue);
    });

    test('目标已是目录 → 保持不变（幂等）', () async {
      final target = '${tmp.path}/runtime/ubuntu/bin';
      Directory(target).createSync(recursive: true);
      await ArtifactManager.ensureDirectory(target);
      expect(Directory(target).existsSync(), isTrue);
    });

    test('目标本身是文件 → 删除后重建为目录', () async {
      final target = '${tmp.path}/runtime/ubuntu/bin';
      Directory('${tmp.path}/runtime/ubuntu').createSync(recursive: true);
      File(target).writeAsStringSync('i am a file, not a dir');
      await ArtifactManager.ensureDirectory(target);
      expect(File(target).existsSync(), isFalse,
          reason: '文件型目标必须被删除');
      expect(Directory(target).existsSync(), isTrue);
    });

    test('父目录被错误创建为文件（ubuntu 是文件）→ 逐层修复后成功', () async {
      final parent = '${tmp.path}/runtime/ubuntu';
      final child = '$parent/bin';
      Directory('${tmp.path}/runtime').createSync(recursive: true);
      File(parent).writeAsStringSync('fake file');
      await ArtifactManager.ensureDirectory(child);
      expect(Directory(child).existsSync(), isTrue);
      expect(File(parent).existsSync(), isFalse);
    });

    test('目标本身是符号链接 → 删除后重建为目录', () async {
      final target = '${tmp.path}/runtime/ubuntu/bin';
      Directory('${tmp.path}/runtime/ubuntu').createSync(recursive: true);
      Link(target).createSync('${tmp.path}/elsewhere');
      await ArtifactManager.ensureDirectory(target);
      expect(Directory(target).existsSync(), isTrue);
    });

    test('中间层是文件（ubuntu/bin 是文件，创建 bin/proot）→ 修复', () async {
      // 模拟旧版残留：ubuntu/bin 被写成普通文件
      Directory('${tmp.path}/runtime/ubuntu').createSync(recursive: true);
      final binAsFile = '${tmp.path}/runtime/ubuntu/bin';
      File(binAsFile).writeAsStringSync('corrupted');
      await ArtifactManager.ensureDirectory('$binAsFile/proot');
      expect(Directory(binAsFile).existsSync(), isTrue);
      expect(Directory('$binAsFile/proot').existsSync(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // extractDebFileTargets 精确提取（ENOTDIR 根因修复）
  // ═══════════════════════════════════════════════════════════════
  group('ArtifactManager.extractDebFileTargets — proot 精确布局', () {
    test('按 fileTargets 将 proot/loader/loader32 精确落到 bin 与 libexec',
        () async {
      if (!_prootDebAvailable()) {
        markTestSkipped('系统无 xz，无法构造真实 .deb');
      }
      final ubuntuDir = '${tmp.path}/runtime/ubuntu';
      Directory(ubuntuDir).createSync(recursive: true);
      final deb = File('${ubuntuDir}/.cache/proot.deb');
      Directory('${ubuntuDir}/.cache').createSync(recursive: true);
      writeProotDeb(deb);

      await ArtifactManager.extractDebFileTargets(
        debPath: deb.path,
        fileTargets: prootTargets(ubuntuDir),
      );

      // proot → bin/proot（不再被 loader 当作目录创建 → 无 ENOTDIR）
      final proot = File('$ubuntuDir/bin/proot');
      expect(proot.existsSync(), isTrue);
      expect(proot.readAsStringSync(), 'proot-binary');

      // loader → libexec/proot/loader
      final loader = File('$ubuntuDir/libexec/proot/loader');
      expect(loader.existsSync(), isTrue);
      expect(loader.readAsStringSync(), 'loader-binary');

      // loader32 → libexec/proot/loader32
      final loader32 = File('$ubuntuDir/libexec/proot/loader32');
      expect(loader32.existsSync(), isTrue);
      expect(loader32.readAsStringSync(), 'loader32-binary');
    });

    test('旧版残留：bin/proot 已是文件 → 提取仍成功且被覆盖（重部署幂等）',
        () async {
      if (!_prootDebAvailable()) {
        markTestSkipped('系统无 xz，无法构造真实 .deb');
      }
      final ubuntuDir = '${tmp.path}/runtime/ubuntu';
      Directory(ubuntuDir).createSync(recursive: true);
      // 制造旧版损坏状态：bin/proot 被写成文件
      File('$ubuntuDir/bin/proot').createSync(recursive: true);
      File('$ubuntuDir/bin/proot').writeAsStringSync('stale');
      final deb = File('${ubuntuDir}/.cache/proot.deb');
      Directory('${ubuntuDir}/.cache').createSync(recursive: true);
      writeProotDeb(deb);

      await ArtifactManager.extractDebFileTargets(
        debPath: deb.path,
        fileTargets: prootTargets(ubuntuDir),
      );

      expect(File('$ubuntuDir/bin/proot').readAsStringSync(), 'proot-binary');
      expect(File('$ubuntuDir/libexec/proot/loader').existsSync(), isTrue);
    });

    test('父目录是文件（ubuntu/bin 是文件）→ 提取前修复为目录并成功',
        () async {
      if (!_prootDebAvailable()) {
        markTestSkipped('系统无 xz，无法构造真实 .deb');
      }
      final ubuntuDir = '${tmp.path}/runtime/ubuntu';
      Directory(ubuntuDir).createSync(recursive: true);
      // 极端残留：ubuntu/bin 整个是普通文件（ENOTDIR 直接来源）
      File('$ubuntuDir/bin').writeAsStringSync('not a dir');
      final deb = File('${ubuntuDir}/.cache/proot.deb');
      Directory('${ubuntuDir}/.cache').createSync(recursive: true);
      writeProotDeb(deb);

      await ArtifactManager.extractDebFileTargets(
        debPath: deb.path,
        fileTargets: prootTargets(ubuntuDir),
      );

      expect(File('$ubuntuDir/bin/proot').existsSync(), isTrue);
      expect(File('$ubuntuDir/bin/proot').readAsStringSync(), 'proot-binary');
      expect(File('$ubuntuDir/libexec/proot/loader').existsSync(), isTrue);
    });

    test('失败后重部署：先损坏后修复，第二次提取结果一致', () async {
      if (!_prootDebAvailable()) {
        markTestSkipped('系统无 xz，无法构造真实 .deb');
      }
      final ubuntuDir = '${tmp.path}/runtime/ubuntu';
      Directory(ubuntuDir).createSync(recursive: true);
      final deb = File('${ubuntuDir}/.cache/proot.deb');
      Directory('${ubuntuDir}/.cache').createSync(recursive: true);
      writeProotDeb(deb, extra: 1);

      // 第一次：成功
      await ArtifactManager.extractDebFileTargets(
        debPath: deb.path,
        fileTargets: prootTargets(ubuntuDir),
      );

      // 人为破坏：bin/proot 改成目录、libexec 删掉
      final prootPath = '$ubuntuDir/bin/proot';
      File(prootPath).deleteSync();
      Directory(prootPath).createSync();
      Directory('$ubuntuDir/libexec').deleteSync(recursive: true);

      // 第二次（重新部署）：ensureDirectory + 提取 → 恢复一致
      await ArtifactManager.ensureDirectory('$ubuntuDir/bin');
      await ArtifactManager.extractDebFileTargets(
        debPath: deb.path,
        fileTargets: prootTargets(ubuntuDir),
      );

      expect(File('$ubuntuDir/bin/proot').readAsStringSync(), 'proot-binary1');
      expect(File('$ubuntuDir/libexec/proot/loader').readAsStringSync(),
          'loader-binary1');
      expect(File('$ubuntuDir/libexec/proot/loader32').existsSync(), isTrue);
    });

    test('并发提取同一 .deb 到同一目标 → 结果一致（配合 InstallLock）',
        () async {
      if (!_prootDebAvailable()) {
        markTestSkipped('系统无 xz，无法构造真实 .deb');
      }
      final ubuntuDir = '${tmp.path}/runtime/ubuntu';
      Directory(ubuntuDir).createSync(recursive: true);
      final deb = File('${ubuntuDir}/.cache/proot.deb');
      Directory('${ubuntuDir}/.cache').createSync(recursive: true);
      writeProotDeb(deb);

      await Future.wait([
        ArtifactManager.extractDebFileTargets(
          debPath: deb.path,
          fileTargets: prootTargets(ubuntuDir),
        ),
        ArtifactManager.extractDebFileTargets(
          debPath: deb.path,
          fileTargets: prootTargets(ubuntuDir),
        ),
      ]);

      expect(File('$ubuntuDir/bin/proot').readAsStringSync(), 'proot-binary');
      expect(File('$ubuntuDir/libexec/proot/loader').readAsStringSync(),
          'loader-binary');
      expect(File('$ubuntuDir/libexec/proot/loader32').existsSync(), isTrue);
    });
  });
}
