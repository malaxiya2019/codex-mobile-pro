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
///   6. 结构化健康检查 [healthCheck]：exists → size → 可执行位 →
///      ELF ABI（e_machine）→ execve 冒烟（带超时）→ xzcat applet
///      （`busybox --list`），每个失败点给出精确错误码
///      [BusyboxErrorCode]，不再把「文件不存在 / 权限拒绝 / ABI
///      不匹配 / 文件损坏 / applet 缺失」统一显示成「BusyBox 不可用」。
///   7. 路径 fallback：filesDir 不可用时依次尝试 cacheDir →
///      系统临时目录；外部存储（sdcard FUSE，通常 noexec）不参与。
/// ====================================================================
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../../core/logger/log_service.dart';

/// BusyBox 安装/验证错误码（精确到失败点）
enum BusyboxErrorCode {
  /// 完全可用（不存在错误）
  none,

  /// 文件不存在
  notFound,

  /// 文件损坏（大小异常 / 非 ELF / 截断）
  corrupted,

  /// 无执行权限（缺执行位 / execve EACCES，如 noexec / SELinux）
  permissionDenied,

  /// ELF 架构与设备不匹配（如 asset 被替换成 x86_64）
  abiMismatch,

  /// execve 启动失败（ENOEXEC / 超时 / 其他）
  execFailed,

  /// busybox 可执行但缺少 xzcat applet（无法解压 rootfs）
  xzcatUnavailable,

  /// 安装流程异常（目录创建 / 写文件 / 读取 asset 失败）
  installFailed,
}

/// BusyBox 健康检查结果（每个检查项 + 精确错误码）
class BusyboxHealth {
  final String path;

  /// 文件是否存在
  final bool exists;

  /// 文件大小（字节；不存在为 -1）
  final int size;

  /// 大小是否合理（≥ minSize）
  final bool sizeOk;

  /// 是否设置了 owner 执行位
  final bool execBit;

  /// ELF e_machine 值（非 ELF 为 null；AArch64=183, ARM=40,
  /// x86_64=62, i386=3）
  final int? elfMachine;

  /// 架构是否匹配（ELF 且为 AArch64）
  final bool abiOk;

  /// execve 冒烟（busybox true）是否通过
  final bool execSmokeOk;

  /// xzcat applet 是否可用
  final bool xzcatOk;

  /// 失败点错误码（全部通过为 none）
  final BusyboxErrorCode error;

  /// 失败详情（stderr / errno 等）
  final String? detail;

  const BusyboxHealth({
    required this.path,
    required this.exists,
    required this.size,
    required this.sizeOk,
    required this.execBit,
    required this.elfMachine,
    required this.abiOk,
    required this.execSmokeOk,
    required this.xzcatOk,
    required this.error,
    this.detail,
  });

  bool get usable => error == BusyboxErrorCode.none;

  /// 可读摘要（供日志与 UI 诊断）
  String get summary {
    final parts = <String>[
      'exists=$exists',
      'size=$size',
      'sizeOk=$sizeOk',
      'execBit=$execBit',
      'abi=${elfMachine == null ? "非ELF" : "e_machine=$elfMachine"}',
      'abiOk=$abiOk',
      'execSmokeOk=$execSmokeOk',
      'xzcatOk=$xzcatOk',
    ];
    return 'BusyboxHealth[$error] ${parts.join(" | ")}'
        '${detail == null ? "" : " | detail=$detail"}';
  }
}

/// 安装/复用结果（path + 精确错误码）
class BusyboxInstallResult {
  /// 可用 busybox 的完整路径（失败为 null）
  final String? path;

  /// 失败点错误码（成功为 none）
  final BusyboxErrorCode error;

  /// 失败详情
  final String? detail;

  const BusyboxInstallResult({this.path, this.error = BusyboxErrorCode.none, this.detail});

  bool get success => path != null;
}

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

  /// ELF e_machine 常量
  static const int _emAArch64 = 183;
  static const int _emArm = 40;

  /// execve 冒烟超时（防挂起）
  static const Duration _smokeTimeout = Duration(seconds: 10);

  /// 确保 busybox 已安装，返回完整路径（失败返回 null）
  ///
  /// 兼容旧调用方；失败详情见 [ensureInstalledDetailed]。
  static Future<String?> ensureInstalled() async {
    final result = await ensureInstalledDetailed();
    return result.path;
  }

  /// 确保 busybox 已安装（结构化结果）
  ///
  /// 依次尝试候选目录（filesDir → cacheDir → 系统临时目录）：
  ///   1. 复用已有文件：必须通过完整健康检查（含 execve 冒烟 +
  ///      xzcat applet），否则删除重建；
  ///   2. 从 Flutter asset 原子安装（写临时文件 → SHA-256 → chmod +x
  ///      → execve 冒烟 → xzcat 验证 → rename 覆盖）；
  ///   3. 任一候选目录成功后立即返回，全部失败返回精确错误码。
  ///
  /// 任何时刻 `bin/busybox` 要么是完整可用版本，要么不存在 ——
  /// 不会出现半写/截断文件被复用，从而避免 `Process.start` 抛
  /// EACCES / Exec format error。
  ///
  /// 注意：外部存储（sdcard FUSE）通常以 noexec 挂载，不能作为
  /// 可执行文件存放位置，因此不参与候选。
  static Future<BusyboxInstallResult> ensureInstalledDetailed() async {
    // ─── 候选目录：App 私有内部存储（/data 分区，可执行） ──────
    final candidates = <String>{};
    try {
      candidates.add((await getApplicationSupportDirectory()).path);
    } catch (e) {
      LogService.warning('Busybox', 'getApplicationSupportDirectory 失败: $e');
    }
    try {
      candidates.add((await getTemporaryDirectory()).path);
    } catch (e) {
      LogService.warning('Busybox', 'getTemporaryDirectory 失败: $e');
    }
    candidates.add(Directory.systemTemp.path);

    BusyboxErrorCode lastError = BusyboxErrorCode.installFailed;
    String? lastDetail;

    for (final base in candidates) {
      final binDir = Directory('$base/bin');
      final busyboxFile = File('${binDir.path}/busybox');

      // ─── 复用已有文件：必须通过完整健康检查 ──────────────
      if (busyboxFile.existsSync()) {
        final health = await healthCheck(busyboxFile);
        if (health.usable) {
          LogService.info(
            'Busybox',
            '复用已安装的 busybox: ${busyboxFile.path}',
          );
          return BusyboxInstallResult(path: busyboxFile.path);
        }
        lastError = health.error;
        lastDetail = health.summary;
        LogService.warning(
          'Busybox',
          '已存在但不可复用（$lastError），原子重建: ${busyboxFile.path}\n$lastDetail',
        );
        await _deleteBestEffort(busyboxFile);
      }

      // ─── 从 Flutter asset 原子安装 ────────────────────────
      try {
        await binDir.create(recursive: true);
        final data = await rootBundle.load(assetName);
        final installed = await installFromBytes(
          binDir,
          busyboxFile,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          expectedSha: expectedSha256,
        );
        if (installed != null) {
          return BusyboxInstallResult(path: installed);
        }
        lastError = BusyboxErrorCode.installFailed;
        lastDetail = '原子安装失败（SHA-256 / chmod / execve / xzcat 校验未通过）';
      } catch (e) {
        lastError = BusyboxErrorCode.installFailed;
        lastDetail = e.toString();
        LogService.error('Busybox', '候选目录安装失败 ($base): $e');
      }
    }

    LogService.error(
      'Busybox',
      '所有候选目录均无法安装 busybox: error=$lastError detail=$lastDetail',
    );
    return BusyboxInstallResult(error: lastError, detail: lastDetail);
  }

  /// 原子安装：把 [bytes] 写入同目录临时文件，依次完成
  /// SHA-256（可选）→ chmod +x → 健康检查（execve 冒烟 + xzcat）
  /// → rename 覆盖 [target]。
  ///
  /// 任何一步失败都会删除临时文件并返回 null，绝不留下半写文件。
  /// 与 Kotlin PtyPlugin 共用 `bin/busybox`：通过「临时文件 +
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
          '临时文件健康检查失败，丢弃: ${tmp.path}',
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

  /// 完整可用性验证：存在 + 大小合理 + 可执行位 + ABI + execve
  /// 冒烟 + xzcat applet。全部通过返回路径，否则返回 null。
  ///
  /// 等价于 [healthCheck].usable；保留此签名兼容现有调用方/测试。
  @visibleForTesting
  static Future<String?> verifyUsable(
    File f, {
    int minSize = _minPlausibleSize,
  }) async {
    final health = await healthCheck(f, minSize: minSize);
    return health.usable ? f.path : null;
  }

  /// BusyBox 独立健康检查（用户要求：exists / size / exec-bit /
  /// ABI / 可启动 / xzcat applet 逐项验证）
  ///
  /// 检查链（任一失败即返回，error 精确到失败点）：
  ///   1. exists — 不存在 → notFound
  ///   2. size ≥ minSize — 过小 → corrupted
  ///   3. ELF magic + e_machine — 是 ELF 但架构非 AArch64 → abiMismatch
  ///      （非 ELF 不判 ABI，交给 execve 冒烟：shell 脚本类夹具可过，
  ///       真机 asset 若被替换成非 ELF 会以 execFailed 暴露）
  ///   4. exec bit — 无执行位 → permissionDenied
  ///   5. execve 冒烟 `busybox true`（带超时）：
  ///      - ProcessException EACCES(13) → permissionDenied
  ///        （noexec mount / SELinux denial）
  ///      - 其他 ProcessException（ENOEXEC=8 / ENOENT=2 等）/ 超时
  ///        / 非零退出 → execFailed
  ///   6. xzcat applet：`busybox --list` 包含 xzcat → 否则
  ///      xzcatUnavailable
  @visibleForTesting
  static Future<BusyboxHealth> healthCheck(
    File f, {
    int minSize = _minPlausibleSize,
  }) async {
    final path = f.path;

    // 1. exists
    bool exists;
    try {
      exists = await f.exists();
    } catch (e) {
      return BusyboxHealth(
        path: path,
        exists: false,
        size: -1,
        sizeOk: false,
        execBit: false,
        elfMachine: null,
        abiOk: false,
        execSmokeOk: false,
        xzcatOk: false,
        error: BusyboxErrorCode.notFound,
        detail: 'exists() 异常: $e',
      );
    }
    if (!exists) {
      return BusyboxHealth(
        path: path,
        exists: false,
        size: -1,
        sizeOk: false,
        execBit: false,
        elfMachine: null,
        abiOk: false,
        execSmokeOk: false,
        xzcatOk: false,
        error: BusyboxErrorCode.notFound,
      );
    }

    // 2. size
    var size = -1;
    var sizeOk = false;
    try {
      final stat = await f.stat();
      size = stat.size;
      sizeOk = size >= minSize;
    } catch (e) {
      LogService.warning('Busybox', 'stat 失败: $path → $e');
    }

    // 3. exec bit
    var execBit = false;
    try {
      final stat = await f.stat();
      execBit = (stat.mode & 0x40) != 0;
    } catch (_) {}

    // 4. ELF ABI
    final elfMachine = elfMachineOf(f);
    var abiOk = false;
    if (elfMachine != null) {
      abiOk = elfMachine == _emAArch64 || elfMachine == _emArm;
    }
    if (elfMachine != null && !abiOk) {
      return BusyboxHealth(
        path: path,
        exists: exists,
        size: size,
        sizeOk: sizeOk,
        execBit: execBit,
        elfMachine: elfMachine,
        abiOk: false,
        execSmokeOk: false,
        xzcatOk: false,
        error: BusyboxErrorCode.abiMismatch,
        detail: 'ELF e_machine=$elfMachine，期望 AArch64(183) 或 ARM(40)',
      );
    }

    if (!sizeOk) {
      return BusyboxHealth(
        path: path,
        exists: exists,
        size: size,
        sizeOk: false,
        execBit: execBit,
        elfMachine: elfMachine,
        abiOk: abiOk,
        execSmokeOk: false,
        xzcatOk: false,
        error: BusyboxErrorCode.corrupted,
        detail: 'size=$size < minSize=$minSize（文件疑似截断/占位）',
      );
    }

    if (!execBit) {
      return BusyboxHealth(
        path: path,
        exists: exists,
        size: size,
        sizeOk: sizeOk,
        execBit: false,
        elfMachine: elfMachine,
        abiOk: abiOk,
        execSmokeOk: false,
        xzcatOk: false,
        error: BusyboxErrorCode.permissionDenied,
        detail: '未设置执行位（mode=${_modeString(f)}）',
      );
    }

    // 5. execve 冒烟（真实 exec：stat 权限位正确 ≠ 内核允许执行）
    final smokeExit = await _execExitCode(f.path, ['true']);
    if (smokeExit == null) {
      return BusyboxHealth(
        path: path,
        exists: exists,
        size: size,
        sizeOk: sizeOk,
        execBit: execBit,
        elfMachine: elfMachine,
        abiOk: abiOk,
        execSmokeOk: false,
        xzcatOk: false,
        error: _lastExecError,
        detail: 'execve 冒烟失败: $_lastExecErrorDetail'
            '${elfMachine == null ? "（非 ELF 文件）" : ""}',
      );
    }
    if (smokeExit != 0) {
      return BusyboxHealth(
        path: path,
        exists: exists,
        size: size,
        sizeOk: sizeOk,
        execBit: execBit,
        elfMachine: elfMachine,
        abiOk: abiOk,
        execSmokeOk: false,
        xzcatOk: false,
        error: BusyboxErrorCode.execFailed,
        detail: 'busybox true exit=$smokeExit',
      );
    }

    // 6. xzcat applet 验证
    final xzcatOk = await _hasXzcatApplet(f);
    if (!xzcatOk) {
      return BusyboxHealth(
        path: path,
        exists: exists,
        size: size,
        sizeOk: sizeOk,
        execBit: execBit,
        elfMachine: elfMachine,
        abiOk: abiOk,
        execSmokeOk: true,
        xzcatOk: false,
        error: BusyboxErrorCode.xzcatUnavailable,
        detail: 'busybox --list 未包含 xzcat',
      );
    }

    return BusyboxHealth(
      path: path,
      exists: exists,
      size: size,
      sizeOk: sizeOk,
      execBit: execBit,
      elfMachine: elfMachine,
      abiOk: abiOk,
      execSmokeOk: true,
      xzcatOk: true,
      error: BusyboxErrorCode.none,
    );
  }

  /// 上一次 execve 冒烟失败的精确错误（供 healthCheck 使用）
  static BusyboxErrorCode _lastExecError = BusyboxErrorCode.execFailed;
  static String? _lastExecErrorDetail;

  /// 带超时的 execve 冒烟
  ///
  /// 返回 exitCode；ProcessException（EACCES/ENOEXEC/ENOENT 等）、
  /// 超时、启动异常统一返回 null，并通过 [_lastExecError] /
  /// [_lastExecErrorDetail] 记录精确原因。
  static Future<int?> _execExitCode(
    String executable,
    List<String> args,
  ) async {
    try {
      final p = await Process.start(executable, args);
      try {
        final code = await p.exitCode.timeout(_smokeTimeout);
        _lastExecError = BusyboxErrorCode.execFailed;
        _lastExecErrorDetail = null;
        return code;
      } on TimeoutException {
        try {
          p.kill();
        } catch (_) {}
        _lastExecError = BusyboxErrorCode.execFailed;
        _lastExecErrorDetail = 'execve 冒烟超时（>${_smokeTimeout.inSeconds}s）';
        return null;
      }
    } on ProcessException catch (e) {
      // errno 13 = EACCES（noexec / SELinux / 无执行权限）
      final isEacces = e.errorCode == 13 || e.message.contains('ermission');
      _lastExecError = isEacces
          ? BusyboxErrorCode.permissionDenied
          : BusyboxErrorCode.execFailed;
      _lastExecErrorDetail =
          'ProcessException: ${e.message} (errno=${e.errorCode})';
      return null;
    } on Object catch (e) {
      _lastExecError = BusyboxErrorCode.execFailed;
      _lastExecErrorDetail = '$e';
      return null;
    }
  }

  /// 验证 xzcat applet 可用（`busybox --list` 输出包含 xzcat）
  static Future<bool> _hasXzcatApplet(File f) async {
    try {
      final p = await Process.start(f.path, ['--list']);
      final code = await p.exitCode.timeout(_smokeTimeout);
      if (code != 0) {
        p.kill();
        return false;
      }
      final out = await p.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(_smokeTimeout);
      final tokens = out.split(RegExp(r'[\s,]+'));
      return tokens.contains('xzcat');
    } on Object catch (e) {
      LogService.warning('Busybox', 'xzcat applet 验证异常: $e');
      return false;
    }
  }

  /// 解析 ELF e_machine（offset 18，2 字节小端）；非 ELF 返回 null
  ///
  /// 测试通过 [elfMachineOf] 直接构造 ELF header 验证 ABI 检测。
  @visibleForTesting
  static int? elfMachineOf(File f) {
    try {
      final raf = f.openSync();
      final header = raf.readSync(20);
      raf.closeSync();
      if (header.length < 20) return null;
      // ELF magic: 0x7F 'E' 'L' 'F'
      if (header[0] != 0x7F ||
          header[1] != 0x45 ||
          header[2] != 0x4C ||
          header[3] != 0x46) {
        return null;
      }
      return header[18] | (header[19] << 8);
    } catch (_) {
      return null;
    }
  }

  /// 读取文件 mode 的八进制表示（诊断用）
  static String _modeString(File f) {
    try {
      final stat = f.statSync();
      return stat.mode.toRadixString(8);
    } catch (_) {
      return '(未知)';
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
