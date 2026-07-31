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
///   4. execve 冒烟验证：stat 权限位正确 ≠ 内核允许执行。安装/复用
///      后真实执行 `busybox true`，noexec mount、SELinux denial、
///      损坏 ELF（Exec format error）都会在此步暴露。
///   5. asset 解压后 SHA-256 校验（与期望 digest 比对，防止写入截断/
///      损坏的二进制被当作可用工具）。
/// ====================================================================
library;

import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart' show visibleForTesting;
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
  /// 优先复用已存在的「可执行 + 大小合理 + execve 冒烟通过」二进制
  /// （Kotlin PtyPlugin 或本模块安装的）；缺失 / 不可执行 / 损坏时
  /// 从 Flutter asset **原子安装**（写临时文件 → SHA-256 → chmod +x
  /// → execve 冒烟 → rename 覆盖），保证任何时刻 `files/bin/busybox`
  /// 要么是完整可用版本，要么不存在 —— 不会出现半写/截断文件被复用，
  /// 从而避免 `Process.start` 抛 EACCES / Exec format error。
  ///
  /// 返回 null 表示安装失败（调用方应转为结构化 DeployError）。
  static Future<String?> ensureInstalled() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final binDir = Directory('${supportDir.path}/bin');
      final busyboxFile = File('${binDir.path}/busybox');

      // ─── 复用已有文件：必须通过完整可用性验证（含 execve 冒烟）─
      if (busyboxFile.existsSync()) {
        final reused = await verifyUsable(busyboxFile);
        if (reused != null) {
          LogService.info('Busybox', '复用已安装的 busybox: ${busyboxFile.path}');
          return reused;
        }
        // 存在但不可执行 / 损坏 / 冒烟失败 → 原子重建
        LogService.warning(
          'Busybox',
          '已存在但不可复用，原子重建: ${busyboxFile.path}',
        );
        await _deleteBestEffort(busyboxFile);
      }

      // ─── 从 Flutter asset 原子安装 ───────────────────────────
      await binDir.create(recursive: true);
      final data = await rootBundle.load(assetName);
      return installFromBytes(
        binDir,
        busyboxFile,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        expectedSha: expectedSha256,
      );
    } catch (e) {
      LogService.error('Busybox', '安装 busybox 失败: $e');
      return null;
    }
  }

  /// 原子安装：把 [bytes] 写入同目录临时文件，依次完成
  /// SHA-256（可选）→ chmod +x → execve 冒烟，全部通过后
  /// rename 覆盖 [target]。
  ///
  /// 任何一步失败都会删除临时文件并返回 null，绝不留下半写文件。
  /// 与 Kotlin PtyPlugin 共用 `files/bin/busybox`：通过「临时文件 +
  /// rename」保证并发写入者最终都收敛到完整文件，避免旧实现的
  /// 非原子覆盖写（FileOutputStream 直写目标）造成截断/半写，
  /// 进而触发 `Process.start` EACCES / Exec format error。
  ///
  /// [expectedSha] 非空时校验内容 SHA-256；[minSize] 传递给
  /// [verifyUsable] 作为 execve 冒烟前的最小大小阈值（测试可传 0）。
  @visibleForTesting
  static Future<String?> installFromBytes(
    Directory binDir,
    File target,
    List<int> bytes, {
    String? expectedSha,
    int minSize = _minPlausibleSize,
  }) async {
    final tmp = File(
      '${binDir.path}/busybox.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);

      if (expectedSha != null) {
        final digest = await sha256Of(tmp);
        if (digest != expectedSha) {
          LogService.error(
            'Busybox',
            '临时文件 SHA-256 不匹配，丢弃: ${tmp.path}',
          );
          await _deleteBestEffort(tmp);
          return null;
        }
      }

      final chmodOk = await _makeExecutable(tmp.path);
      if (!chmodOk) {
        LogService.error(
          'Busybox',
          '临时文件 chmod +x 失败: ${tmp.path}（可能 SELinux 限制）',
        );
        await _deleteBestEffort(tmp);
        return null;
      }

      final verified = await verifyUsable(tmp, minSize: minSize);
      if (verified == null) {
        LogService.error(
          'Busybox',
          '临时文件 execve 冒烟失败，丢弃: ${tmp.path}',
        );
        await _deleteBestEffort(tmp);
        return null;
      }

      // 原子替换目标（先 best-effort 删除已存在目标，再 rename；
      // 并发写入者最终收敛到本完整版本）
      if (target.existsSync()) {
        await _deleteBestEffort(target);
      }
      await tmp.rename(target.path);
      LogService.info(
        'Busybox',
        'busybox 就绪: ${target.path} '
            '(${await target.length()} bytes)',
      );
      return target.path;
    } catch (e) {
      LogService.error('Busybox', '原子安装失败: $e');
      await _deleteBestEffort(tmp);
      return null;
    }
  }

  /// 完整可用性验证：存在 + 大小合理 + 可执行位 + 真实 execve 冒烟。
  ///
  /// 冒烟执行 `busybox true`：
  ///   - 无执行位 / SELinux denial / noexec mount → ProcessException
  ///     (EACCES)；
  ///   - 损坏 ELF / 非 ELF 文件 → ProcessException (Exec format error,
  ///     ENOEXEC)；
  ///   - 截断二进制 → 非零退出或异常。
  /// 全部通过返回路径，否则返回 null（调用方删除重建或报结构化错误）。
  @visibleForTesting
  static Future<String?> verifyUsable(
    File f, {
    int minSize = _minPlausibleSize,
  }) async {
    try {
      if (!await f.exists()) return null;
      final stat = await f.stat();
      final sizeOk = stat.size >= minSize;
      final execBit = (stat.mode & 0x40) != 0;
      if (!sizeOk || !execBit) {
        LogService.warning(
          'Busybox',
          '不可复用: sizeOk=$sizeOk execBit=$execBit '
              '${f.path} (${stat.size}B mode=${stat.mode.toRadixString(8)})',
        );
        return null;
      }

      // 真实 execve：stat 权限位正确 ≠ 内核允许执行
      final smoke = await Process.run(f.path, ['true']);
      if (smoke.exitCode != 0) {
        LogService.warning(
          'Busybox',
          '冒烟执行失败(exit=${smoke.exitCode}): ${f.path}\n'
              'stderr=${smoke.stderr}',
        );
        return null;
      }
      return f.path;
    } catch (e) {
      // ProcessException：EACCES / ENOENT / Exec format error 等
      LogService.warning('Busybox', '冒烟执行异常: ${f.path} → $e');
      return null;
    }
  }

  /// 计算文件的 SHA-256（十六进制小写）
  ///
  /// 同时被 [verifySha256] 与测试复用。
  @visibleForTesting
  static Future<String> sha256Of(File f) async {
    final bytes = await f.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// SHA-256 内容校验（与 [expected] 或内置 [expectedSha256] 比对）
  static Future<bool> verifySha256(File f, {String? expected}) async {
    try {
      final digest = await sha256Of(f);
      return digest == (expected ?? expectedSha256);
    } catch (e) {
      LogService.warning('Busybox', 'SHA-256 校验失败: $e');
      return false;
    }
  }

  static Future<void> _deleteBestEffort(File f) async {
    try {
      await f.delete();
    } catch (e) {
      LogService.warning('Busybox', '删除文件失败(忽略): ${f.path} → $e');
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
}
