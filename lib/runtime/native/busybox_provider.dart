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
///
/// 2026-08 修复「ProcessException: Permission denied」（busybox xzcat）：
///   1. chmod +x 后必须检查 exitCode，静默失败会留下无执行权限的
///      二进制，导致后续 Process.start 抛 EACCES。
///   2. 复用已有 busybox 前校验「可执行位 + 合理大小」，对损坏/不可
///      执行文件删除重建，不再静默复用旧版本遗留文件。
///   3. 返回前强制验证可执行位，不满足则返回 null（调用方给出结构化
///      错误，而不是裸抛 ProcessException）。
/// ====================================================================
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../core/logger/log_service.dart';

/// Native BusyBox 提供者
class NativeBusybox {
  NativeBusybox._();

  /// Flutter asset 中的 busybox 文件名
  static const String assetName = 'assets/busybox-arm64';

  /// 期望的 SHA256（构建期验证，防止 asset 被替换成不可信二进制）
  static const String expectedSha256 =
      '6b23c93ba7ac1c2db0d3a4e5a691a86c50113d4f6bae21b40ed6e0c9d0edccfa';

  /// 复用合法性的最小大小阈值。
  ///
  /// meefik busybox arm64 实际约 1.5MB。明显更小的文件多半是
  /// 截断/损坏/占位文件，即使有执行位也不该复用（否则 xzcat 启动
  /// 后立即以非零码退出，或直接 Exec format error）。
  static const int _minPlausibleSize = 500 * 1024;

  /// 确保 busybox 已安装到 `files/bin/busybox`，返回完整路径
  ///
  /// 优先复用已存在的「可执行 + 大小合理」二进制（Kotlin PtyPlugin
  /// 或本模块解压的），缺失 / 不可执行 / 损坏时从 Flutter asset 解压
  /// 并设置可执行权限。
  /// 返回 null 表示安装失败（调用方应转为结构化 DeployError）。
  static Future<String?> ensureInstalled() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final binDir = Directory('${supportDir.path}/bin');
      final busyboxFile = File('${binDir.path}/busybox');

      // ─── 复用已有文件：必须同时满足「存在 + 可执行 + 大小合理」─
      if (busyboxFile.existsSync()) {
        final stat = await busyboxFile.stat();
        final executable = (stat.mode & 0x40) != 0;
        final sizeOk = stat.size >= _minPlausibleSize;

        if (executable && sizeOk) {
          LogService.info(
            'Busybox',
            '复用已安装的 busybox: ${busyboxFile.path} '
                '(${stat.size} bytes, mode=${stat.mode.toRadixString(8)})',
          );
          return busyboxFile.path;
        }

        // 存在但不可执行 / 疑似损坏 → 删除重建
        LogService.warning(
          'Busybox',
          '已存在但不可复用，删除重建: ${busyboxFile.path} '
              '(mode=${stat.mode.toRadixString(8)}, size=${stat.size}, '
              'executable=$executable, sizeOk=$sizeOk)',
        );
        try {
          await busyboxFile.delete();
        } catch (e) {
          LogService.warning('Busybox', '删除不可复用的 busybox 失败: $e');
        }
      }

      // ─── 从 Flutter asset 解压 ────────────────────────────────
      await binDir.create(recursive: true);
      final data = await rootBundle.load(assetName);
      await busyboxFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      // ─── 设置可执行权限（chmod +x），必须验证结果 ─────────────
      final chmodOk = await _makeExecutable(busyboxFile.path);
      if (!chmodOk) {
        LogService.error(
          'Busybox',
          'chmod +x 失败: ${busyboxFile.path}（可能 SELinux 限制）',
        );
        return null;
      }

      // ─── 最终强制验证 ─────────────────────────────────────────
      if (!await _isExecutable(busyboxFile)) {
        LogService.error(
          'Busybox',
          '解压后仍不可执行: ${busyboxFile.path}',
        );
        return null;
      }

      LogService.info(
        'Busybox',
        'busybox 就绪: ${busyboxFile.path} '
            '(${await busyboxFile.length()} bytes)',
      );
      return busyboxFile.path;
    } catch (e) {
      LogService.error('Busybox', '安装 busybox 失败: $e');
      return null;
    }
  }

  /// 设置可执行位并验证 chmod 结果
  ///
  /// 依次尝试：
  ///   1. `chmod`（PATH 解析）
  ///   2. `/system/bin/chmod`（Android 系统路径，toybox）
  ///   3. `/system/bin/toybox chmod`（部分设备无独立 chmod）
  /// 全部失败返回 false。
  static Future<bool> _makeExecutable(String path) async {
    final attempts = <List<String>>[
      ['chmod', '+x', path],
      ['/system/bin/chmod', '+x', path],
      ['/system/bin/toybox', 'chmod', '+x', path],
    ];

    for (final args in attempts) {
      try {
        final result = await Process.run(args.first, args.sublist(1));
        if (result.exitCode == 0) return true;
        LogService.warning(
          'Busybox',
          '${args.first} ${args.sublist(1).join(" ")} → exit=${result.exitCode} '
              'stderr=${result.stderr}',
        );
      } catch (e) {
        LogService.warning('Busybox', '执行 ${args.first} 失败: $e');
      }
    }
    return false;
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
