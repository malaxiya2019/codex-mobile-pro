/// ====================================================================
/// Native BusyBox Provider（Native 适配层）
///
/// 提供 App 内置的静态 BusyBox（含 xz / tar / xzcat applet），
/// 用于 rootfs 的流式解压（busybox xzcat | busybox tar）。
///
/// 来源（可信 Artifact）：
///   https://github.com/meefik/busybox/releases/tag/1.34.1
///   arm64/bin/busybox
///   SHA256: 6b23c93ba7ac1c2db0d3a4e5a691a86c50113d4f6bae21b40ed6e0c9d0edccfa
///
/// 说明：
///   - 静态链接（bionic），可在 Android App 私有目录直接执行
///   - 含 xz / unxz / xzcat / tar / ash 等 applet
///   - 与 Kotlin PtyPlugin 共用 `files/bin/busybox`（同一路径，先到先用）
///   - 不依赖 Termux / 系统 xz
/// ====================================================================
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Native BusyBox 提供者
class NativeBusybox {
  NativeBusybox._();

  /// Flutter asset 中的 busybox 文件名
  static const String assetName = 'assets/busybox-arm64';

  /// 期望的 SHA256（构建期验证，防止 asset 被替换成不可信二进制）
  static const String expectedSha256 =
      '6b23c93ba7ac1c2db0d3a4e5a691a86c50113d4f6bae21b40ed6e0c9d0edccfa';

  /// 确保 busybox 已安装到 `files/bin/busybox`，返回完整路径
  ///
  /// 优先复用已存在的二进制（Kotlin PtyPlugin 或本模块解压的），
  /// 缺失时从 Flutter asset 解压并设置可执行权限。
  /// 返回 null 表示安装失败（调用方应回退到系统 xz/tar）。
  static Future<String?> ensureInstalled() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final binDir = Directory('${supportDir.path}/bin');
      final busyboxFile = File('${binDir.path}/busybox');

      if (busyboxFile.existsSync() && await _isExecutable(busyboxFile)) {
        return busyboxFile.path;
      }

      await binDir.create(recursive: true);

      // 从 Flutter asset 解压
      final data = await rootBundle.load(assetName);
      await busyboxFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await Process.run('chmod', ['+x', busyboxFile.path]);
      await busyboxFile.setExecutable(true, false);

      return busyboxFile.path;
    } catch (e) {
      return null;
    }
  }

  /// 检查文件是否可执行
  static Future<bool> _isExecutable(File f) async {
    try {
      final stat = await f.stat();
      // Unix 权限：owner execute bit (0x40)
      return (stat.mode & 0x40) != 0;
    } catch (_) {
      return false;
    }
  }
}
