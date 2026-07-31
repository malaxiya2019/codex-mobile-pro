/// ====================================================================
/// Ubuntu Runtime 清单测试
///
/// 守护 Phase「rootfs 流式解压」的关键清单数据：
///   - expandedBytes：解压进度计算基准（错误会导致进度失真）
///   - stripComponents：rootfs 目录层级（错误会导致解压路径错乱）
///   - sha256 / size：下载完整性校验
///
/// 纯常量断言，不依赖平台 / 插件 / 真实文件系统。
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/runtime_dependency.dart';
import 'package:codex_mobile_pro/runtime/runtime_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeArtifact.expandedBytes', () {
    test('默认值为 0（非 rootfs artifact 不需要）', () {
      const artifact = RuntimeArtifact(
        name: 'x',
        type: ArtifactType.deb,
        url: 'https://example.com/x.deb',
        sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        size: 100,
      );
      expect(artifact.expandedBytes, 0);
    });
  });

  group('Ubuntu Runtime manifest', () {
    test('manifest 存在且包含 rootfs + proot 两个 artifact', () {
      final manifest = RuntimeManifest.forTool(RuntimeTool.ubuntu);
      expect(manifest, isNotNull);
      expect(manifest!.artifacts.length, 2);
      expect(manifest.artifacts[0].type, ArtifactType.rootfs);
      expect(manifest.artifacts[1].type, ArtifactType.proot);
    });

    test('rootfs artifact 具备流式解压所需字段', () {
      final manifest = RuntimeManifest.forTool(RuntimeTool.ubuntu)!;
      final rootfs = manifest.artifacts[0];

      expect(rootfs.expandedBytes, greaterThan(0),
          reason: 'expandedBytes 用于真实解压进度，必须 > 0');
      // 与实测 tar 流大小一致（64MB xz → 314,982,400 字节）
      expect(rootfs.expandedBytes, 314982400);
      // rootfs tar 顶层为发行版目录，strip 1 层
      expect(rootfs.stripComponents, 1);
      expect(rootfs.size, 64133552);
      expect(rootfs.sha256.length, 64);
    });

    test('proot artifact 使用 Termux .deb 结构（strip 6 层）', () {
      final manifest = RuntimeManifest.forTool(RuntimeTool.ubuntu)!;
      final proot = manifest.artifacts[1];
      expect(proot.stripComponents, 6);
      expect(proot.includeFiles, isNotNull);
      expect(proot.includeFiles, contains('usr/bin/proot'));
      expect(proot.includeFiles, contains('usr/libexec/proot/loader'));
    });
  });
}
