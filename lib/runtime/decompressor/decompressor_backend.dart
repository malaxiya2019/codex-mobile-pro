/// ====================================================================
/// Decompressor Backend（解压器后端）
///
/// 2026-08 止损重构：不再把「App 内置 BusyBox」作为 Linux Runtime 的
/// 硬依赖。rootfs 解压只依赖 [DecompressorBackend]，按优先级自动选择
/// 真正可用的后端：
///
///   1. TermuxXzBackend       — Termux 的 xz + tar（优先，真实可用）
///   2. TermuxBusyboxBackend  — Termux 的 busybox（xzcat + tar applet）
///   3. BundledBusyboxBackend — App 内置 BusyBox（fallback，保留回退）
///   4. NoDecompressorBackend — 全部不可用 → FAIL
///
/// 发现方式：
///   - Termux 路径通过 `$PREFIX` 环境变量发现（Termux 标准前缀），
///     禁止硬编码 /data/data/com.termux/...。
///   - 每个后端都必须「真实执行」验证（--version / --list），
///     禁止假设工具存在。
///
/// 解压方式（流式管道，不把 rootfs 读入内存）：
///   xzcat rootfs.tar.xz | tar -xf - -C `<target>` --strip-components=N
/// ====================================================================
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/logger/log_service.dart';
import '../deploy_error.dart';
import '../native/busybox_provider.dart';

/// 解压器来源
enum DecompressorSource {
  /// Termux 环境（通过 `$PREFIX` 发现）
  termux,

  /// App 内置（bundled asset / 测试注入）
  bundled,

  /// 无可用后端
  none,
}

/// 解压器类型
enum DecompressorKind {
  /// xz + tar 独立二进制
  xzTar,

  /// busybox（xzcat + tar applet）
  busybox,

  /// 无
  none,
}

/// 单个候选后端的探测状态（用于 UI 分项展示 / 诊断日志）
class DecompressorStatus {
  final String name;
  final bool available;
  final String? reason;
  const DecompressorStatus({
    required this.name,
    required this.available,
    this.reason,
  });
}

/// busybox 验证结果（结构化失败原因 → 精确错误码）
class BusyboxVerifyResult {
  final bool ok;
  final DeployErrorCode? failureCode;
  final String? reason;
  const BusyboxVerifyResult({required this.ok, this.failureCode, this.reason});
}

/// ====================================================================
/// DecompressorBackend（抽象）
/// ====================================================================
abstract class DecompressorBackend {
  String get name;
  DecompressorSource get source;
  DecompressorKind get kind;

  /// xz 可执行路径（非 xzTar 后端为 null）
  String? get xzPath;

  /// tar 可执行路径（非 xzTar 后端为 null）
  String? get tarPath;

  /// busybox 可执行路径（非 busybox 后端为 null）
  String? get busyboxPath;

  /// 是否可用（必须经过真实验证）
  bool get available;

  /// 不可用原因（验证失败点）
  String? get reason;

  /// 不可用时的精确错误码（默认 dependencyMissing）
  DeployErrorCode get failureCode => DeployErrorCode.dependencyMissing;

  /// 候选后端探测状态（含不可用候选），用于「Decompressor 分项展示」
  List<DecompressorStatus> get status;

  /// xzcat 命令的可执行路径
  String get xzcatExecutable;

  /// xzcat 命令参数（不含可执行路径）
  List<String> xzcatArgs(String tarPath);

  /// tar 命令的可执行路径
  String get tarExecutable;

  /// tar 命令参数（不含可执行路径）
  List<String> tarArgs(String targetDir, int stripComponents);

  /// 流式解压 tar.xz（公共管道实现）
  ///
  /// 内存峰值 = 单次管道块（≤ 64KB），不把 rootfs 读入内存。
  /// 设备节点无法创建（"can't create node"）按警告处理（rootfs 的
  /// /dev 由 proot 虚拟化），不视为失败。
  Future<void> extractTarXz({
    required String tarPath,
    required String targetDir,
    required int stripComponents,
    required int expandedBytes,
    required void Function(int pipedBytes) onProgress,
  }) async {
    if (!available) {
      throw DeployError(
        code: failureCode,
        message: '解压工具不可用（$name）',
        detail: reason,
        userSuggestion: '点击「重新初始化」将重新探测可用解压工具'
            '（Termux xz / Termux busybox / 内置 BusyBox）',
      );
    }

    await Directory(targetDir).create(recursive: true);

    // ─── 启动前诊断日志（Permission denied 排查用） ──────────────
    final diag = await _diagnoseImage(tarPath);
    LogService.info(
      'Decompressor',
      '解压启动前诊断: backend=$name | xzcat=$xzcatExecutable | '
          'tar=$tarExecutable | image=$tarPath | imageExists=${diag.imageExists} | '
          'imageSize=${diag.imageSize} | imageReadable=${diag.imageReadable} | '
          'parentExists=${diag.parentExists} | parent=${diag.parentDir}',
    );

    // ─── 管道：xzcat rootfs.tar.xz | tar -xf - -C <target> ──────
    Process xzcat;
    Process tar;
    try {
      xzcat = await Process.start(xzcatExecutable, xzcatArgs(tarPath));
      tar = await Process.start(tarExecutable, tarArgs(targetDir, stripComponents));
    } on ProcessException catch (e) {
      throw _processStartDeployError(
        e.message,
        e.errorCode,
        tarPath: tarPath,
        imageExists: diag.imageExists,
        imageSize: diag.imageSize,
        imageReadable: diag.imageReadable,
        parentExists: diag.parentExists,
      );
    } on PathAccessException catch (e) {
      throw _processStartDeployError(
        e.message,
        e.osError?.errorCode,
        tarPath: tarPath,
        imageExists: diag.imageExists,
        imageSize: diag.imageSize,
        imageReadable: diag.imageReadable,
        parentExists: diag.parentExists,
      );
    }

    final stderrBuf = StringBuffer();
    final xzcatErrDone = xzcat.stderr
        .transform(const SystemEncoding().decoder)
        .listen((d) => stderrBuf.write(d))
        .asFuture<void>();
    final tarErrDone = tar.stderr
        .transform(const SystemEncoding().decoder)
        .listen((d) => stderrBuf.write(d))
        .asFuture<void>();

    int piped = 0;

    // 带背压的流式管道 + 字节计数（addStream 保证不无限缓冲）
    final counting = xzcat.stdout.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          piped += chunk.length;
          onProgress(piped);
          sink.add(chunk);
        },
      ),
    );

    // 整体超时保护：解压卡死时终止，避免 UI 永久「正在部署」
    final timeoutCompleter = Completer<void>();
    final timeoutTimer = Timer(kDecompressorExtractionTimeout, () {
      if (!timeoutCompleter.isCompleted) timeoutCompleter.complete();
    });

    try {
      await Future.any([
        (() async {
          await tar.stdin.addStream(counting);
          // dart:io IOSink.addStream 完成时不会自动关闭 sink；
          // 不显式 close 会让 tar 永远等待 EOF → exitCode 挂起。
          await tar.stdin.close();
        })(),
        timeoutCompleter.future,
      ]);
      if (timeoutCompleter.isCompleted) {
        throw TimeoutException(
          'rootfs 解压超时（超过 ${kDecompressorExtractionTimeout.inMinutes} 分钟）',
        );
      }
    } on Object catch (e) {
      try {
        xzcat.kill();
        tar.kill();
      } catch (_) {}
      if (e is DeployError) rethrow;
      rethrow;
    } finally {
      timeoutTimer.cancel();
    }

    final xzcatExit = await xzcat.exitCode;
    final tarExit = await tar.exitCode;
    await xzcatErrDone;
    await tarErrDone;

    final stderrText = stderrBuf.toString().trim();
    LogService.info(
      'Decompressor',
      '解压进程结束: backend=$name | xzcat exit=$xzcatExit | '
          'tar exit=$tarExit | piped=$piped bytes | '
          'stderr=${stderrText.isEmpty ? '(空)' : stderrText}',
    );
    // 允许设备节点无法创建的警告（rootfs 的 /dev 由 proot 虚拟化）
    final deviceNodeOnly = stderrText.contains("can't create node") ||
        stderrText.contains('Operation not permitted');

    if (tarExit != 0 && !deviceNodeOnly) {
      throw DeployError(
        code: DeployErrorCode.extractionFailed,
        message: 'rootfs 解压失败',
        detail: 'backend=$name tar exit=$tarExit, xzcat exit=$xzcatExit\n'
            'stderr:\n${stderrText.isEmpty ? '(空)' : stderrText}',
        userSuggestion:
            '解压中断。已保留完整压缩包缓存，点击「重新初始化」将直接重新解压，无需再次下载',
      );
    }
    if (xzcatExit != 0) {
      throw DeployError(
        code: DeployErrorCode.extractionFailed,
        message: 'rootfs 解压失败（xzcat exit=$xzcatExit）',
        detail: 'backend=$name\n${stderrText.isEmpty ? '(空)' : stderrText}',
        userSuggestion: DeployErrorSuggestions.forCode(DeployErrorCode.extractionFailed),
      );
    }

    onProgress(expandedBytes);
  }

  /// 解压工具启动失败（ProcessException / PathAccessException）统一
  /// 转换为结构化 [DeployError]，避免裸异常一路抛到 UI。
  ///
  /// - errno 13（EACCES）/ 消息含 "Permission" → permissionDenied
  /// - errno 2（ENOENT）/ 消息含 "No such" → extractionFailed（附提示）
  DeployError _processStartDeployError(
    String message,
    int? errno, {
    required String tarPath,
    required bool imageExists,
    required int imageSize,
    required bool imageReadable,
    required bool parentExists,
  }) {
    final isPermission = errno == 13 || message.contains('ermission');
    final isNoEnt = errno == 2 || message.contains('No such');
    return DeployError(
      code: isPermission
          ? DeployErrorCode.permissionDenied
          : DeployErrorCode.extractionFailed,
      message: isPermission ? '解压工具启动失败（权限被拒绝）' : '解压工具启动失败（$message）',
      detail: 'backend=$name\n'
          'xzcat=$xzcatExecutable tar=$tarExecutable\n'
          'error=$message (errno=$errno)\n'
          'image=$tarPath exists=$imageExists size=$imageSize '
          'readable=$imageReadable '
          'parentExists=$parentExists\n'
          '${isNoEnt ? '解压工具不存在或路径错误。' : ''}'
          '${isPermission ? '若为可执行权限问题，点击「重新初始化」将重新安装/探测解压工具。' : ''}',
      userSuggestion: isPermission
          ? '点击「重新初始化」重试（将重新探测 Termux xz / busybox 并重建内置解压工具）；'
              '若反复失败请清理应用数据后重新部署'
          : '点击「重新初始化」重试；若反复失败请清理应用数据后重新部署',
    );
  }

}

/// 解压前镜像诊断结果（Permission denied 排查用）
class _ImageDiagnostics {
  final bool imageExists;
  final int imageSize;
  final bool imageReadable;
  final bool parentExists;
  final String parentDir;
  const _ImageDiagnostics({
    required this.imageExists,
    required this.imageSize,
    required this.imageReadable,
    required this.parentExists,
    required this.parentDir,
  });
}

/// 解压启动前镜像诊断：文件存在性 / 大小 / 可读性 / 父目录可访问性。
/// 所有失败只记日志不抛出，避免诊断本身干扰解压。
Future<_ImageDiagnostics> _diagnoseImage(String tarPath) async {
  final imageFile = File(tarPath);
  final parentDir = Directory(path.dirname(tarPath));
  var imageExists = false;
  var imageSize = -1;
  var imageReadable = false;
  try {
    imageExists = await imageFile.exists();
    if (imageExists) {
      imageSize = await imageFile.length();
      final stat = await imageFile.stat();
      imageReadable = (stat.mode & 0x04) != 0;
      if (imageReadable) {
        try {
          final raf = await imageFile.open();
          await raf.readByte();
          await raf.close();
        } catch (_) {
          imageReadable = false;
        }
      }
    }
  } catch (e) {
    LogService.warning('Decompressor', '镜像诊断失败(忽略): $e');
  }
  return _ImageDiagnostics(
    imageExists: imageExists,
    imageSize: imageSize,
    imageReadable: imageReadable,
    parentExists: await parentDir.exists(),
    parentDir: parentDir.path,
  );
}

/// 递归统计目录内普通文件字节数（busybox 单命令模式的真实进度来源）。
/// 失败/权限不足时返回 0，不抛出。
Future<int> _countDirBytes(Directory dir) async {
  var total = 0;
  try {
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

/// 流式解压整体超时（防止卡死导致 UI 永久「正在部署」）
const Duration kDecompressorExtractionTimeout = Duration(minutes: 20);

/// 探测命令超时
const Duration kDecompressorProbeTimeout = Duration(seconds: 10);

/// ====================================================================
/// TermuxXzBackend — Termux 的 xz + tar（优先）
/// ====================================================================
class TermuxXzBackend extends DecompressorBackend {
  TermuxXzBackend({required String xzPath, required String tarPath})
      : _xz = xzPath,
        _tar = tarPath;

  final String _xz;
  final String _tar;
  bool _available = false;
  String? _reason;

  @override
  String get name => 'Termux xz + tar';
  @override
  DecompressorSource get source => DecompressorSource.termux;
  @override
  DecompressorKind get kind => DecompressorKind.xzTar;
  @override
  String? get xzPath => _xz;
  @override
  String? get tarPath => _tar;
  @override
  String? get busyboxPath => null;
  @override
  bool get available => _available;
  @override
  String? get reason => _reason;
  @override
  List<DecompressorStatus> get status => [
        DecompressorStatus(
          name: name,
          available: _available,
          reason: _reason,
        ),
      ];

  @override
  String get xzcatExecutable => _xz;
  @override
  List<String> xzcatArgs(String tarPath) => ['-dc', tarPath];
  @override
  String get tarExecutable => _tar;
  @override
  List<String> tarArgs(String targetDir, int stripComponents) => [
        '-xf',
        '-',
        '-C',
        targetDir,
        if (stripComponents > 0) '--strip-components=$stripComponents',
      ];

  /// 真实执行 `xz --version` / `tar --version` 验证可用性
  Future<void> checkAvailable() async {
    final xzOk = await _probe(_xz, ['--version']);
    final tarOk = await _probe(_tar, ['--version']);
    _available = xzOk && tarOk;
    if (!_available) {
      final parts = <String>[
        if (!xzOk) 'xz 不可用: $_xz',
        if (!tarOk) 'tar 不可用: $_tar',
      ];
      _reason = parts.join('; ');
    }
  }

  static Future<bool> _probe(String exec, List<String> args) async {
    final f = File(exec);
    if (!await f.exists()) return false;
    try {
      final r = await Process.run(exec, args)
          .timeout(
        kDecompressorProbeTimeout,
        onTimeout: () => ProcessResult(0, -1, '', 'timeout'),
      );
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// ====================================================================
/// busybox 型后端公共基类（TermuxBusyboxBackend / BundledBusyboxBackend）
/// ====================================================================
abstract class BusyboxBackendBase extends DecompressorBackend {
  String? get busyboxPathValue;

  @override
  String get xzcatExecutable => busyboxPathValue!;
  @override
  List<String> xzcatArgs(String tarPath) => ['xzcat', tarPath];
  @override
  String get tarExecutable => busyboxPathValue!;
  @override
  List<String> tarArgs(String targetDir, int stripComponents) => [
        'tar',
        '-xf',
        '-',
        '-C',
        targetDir,
        if (stripComponents > 0) '--strip-components=$stripComponents',
      ];

  /// 单命令流式解压：`busybox tar xf <tar.xz> -C <target>`。
  ///
  /// busybox tar 内置 xz 解压（与 Operit 验证过的路径一致），
  /// 不经过独立 xzcat 进程，避免「xzcat 可执行但 pipe 阶段失败」
  /// 的双进程耦合问题。进度通过轮询目标目录累计字节数上报
  /// （每 1.5s，真实数据），避免 UI 假进度。
  @override
  Future<void> extractTarXz({
    required String tarPath,
    required String targetDir,
    required int stripComponents,
    required int expandedBytes,
    required void Function(int pipedBytes) onProgress,
  }) async {
    if (!available) {
      throw DeployError(
        code: failureCode,
        message: '解压工具不可用（$name）',
        detail: reason,
        userSuggestion: '点击「重新初始化」将重新探测可用解压工具'
            '（Termux xz / Termux busybox / 内置 BusyBox）',
      );
    }

    await Directory(targetDir).create(recursive: true);

    final diag = await _diagnoseImage(tarPath);
    final exec = busyboxPathValue;
    LogService.info(
      'Decompressor',
      '解压启动前诊断(单命令): backend=$name | busybox=$exec | '
          'image=$tarPath | imageExists=${diag.imageExists} | '
          'imageSize=${diag.imageSize} | imageReadable=${diag.imageReadable} | '
          'parentExists=${diag.parentExists} | parent=${diag.parentDir}',
    );

    final args = [
      'tar',
      'xf',
      tarPath,
      '-C',
      targetDir,
      if (stripComponents > 0) '--strip-components=$stripComponents',
    ];

    Process proc;
    try {
      proc = await Process.start(exec!, args);
    } on ProcessException catch (e) {
      throw _processStartDeployError(
        e.message,
        e.errorCode,
        tarPath: tarPath,
        imageExists: diag.imageExists,
        imageSize: diag.imageSize,
        imageReadable: diag.imageReadable,
        parentExists: diag.parentExists,
      );
    } on PathAccessException catch (e) {
      throw _processStartDeployError(
        e.message,
        e.osError?.errorCode,
        tarPath: tarPath,
        imageExists: diag.imageExists,
        imageSize: diag.imageSize,
        imageReadable: diag.imageReadable,
        parentExists: diag.parentExists,
      );
    }

    final stderrBuf = StringBuffer();
    final errDone = proc.stderr
        .transform(const SystemEncoding().decoder)
        .listen((d) => stderrBuf.write(d))
        .asFuture<void>();

    // 真实进度：轮询目标目录累计字节数（expandedBytes>0 时 clamp）
    var lastReported = 0;
    final progressTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) async {
        final bytes = await _countDirBytes(Directory(targetDir));
        if (bytes > lastReported) {
          lastReported = bytes;
          onProgress(
            expandedBytes > 0 ? bytes.clamp(0, expandedBytes) : bytes,
          );
        }
      },
    );

    // 整体超时保护：解压卡死时终止，避免 UI 永久「正在部署」
    final timeoutCompleter = Completer<void>();
    final timeoutTimer = Timer(kDecompressorExtractionTimeout, () {
      if (!timeoutCompleter.isCompleted) timeoutCompleter.complete();
    });

    try {
      await Future.any([proc.exitCode, timeoutCompleter.future]);
      if (timeoutCompleter.isCompleted) {
        throw TimeoutException(
          'rootfs 解压超时（超过 ${kDecompressorExtractionTimeout.inMinutes} 分钟）',
        );
      }
    } on Object catch (e) {
      try {
        proc.kill();
      } catch (_) {}
      if (e is DeployError) rethrow;
      rethrow;
    } finally {
      timeoutTimer.cancel();
      progressTimer.cancel();
    }

    final exit = await proc.exitCode;
    await errDone;

    final stderrText = stderrBuf.toString().trim();
    LogService.info(
      'Decompressor',
      '解压进程结束(单命令): backend=$name | busybox tar exit=$exit | '
          'lastReported=$lastReported bytes | '
          'stderr=${stderrText.isEmpty ? '(空)' : stderrText}',
    );
    // 允许设备节点无法创建的警告（rootfs 的 /dev 由 proot 虚拟化）
    final deviceNodeOnly = stderrText.contains("can't create node") ||
        stderrText.contains('Operation not permitted');

    if (exit != 0 && !deviceNodeOnly) {
      throw DeployError(
        code: DeployErrorCode.extractionFailed,
        message: 'rootfs 解压失败',
        detail: 'backend=$name busybox tar exit=$exit\n'
            'stderr:\n${stderrText.isEmpty ? '(空)' : stderrText}',
        userSuggestion:
            '解压中断。已保留完整压缩包缓存，点击「重新初始化」将直接重新解压，无需再次下载',
      );
    }

    onProgress(expandedBytes);
  }

  /// 验证 busybox 可执行且含 xzcat / tar applet。
  ///
  /// 返回结构化结果：
  ///   - 文件不存在 → extractionFailed（兼容旧语义：ENOENT）
  ///   - 无执行权限（EACCES）→ permissionDenied
  ///   - 可执行但 --list 失败 / 缺 applet → dependencyMissing
  Future<BusyboxVerifyResult> verifyBusybox(String exec) async {
    final f = File(exec);
    if (!await f.exists()) {
      return BusyboxVerifyResult(
        ok: false,
        failureCode: DeployErrorCode.extractionFailed,
        reason: '文件不存在: $exec',
      );
    }
    try {
      final r = await Process.run(exec, ['--list'])
          .timeout(
        kDecompressorProbeTimeout,
        onTimeout: () => ProcessResult(0, -1, '', 'timeout'),
      );
      if (r.exitCode != 0) {
        return BusyboxVerifyResult(
          ok: false,
          failureCode: DeployErrorCode.dependencyMissing,
          reason: 'busybox --list 退出码 ${r.exitCode}: ${r.stderr}',
        );
      }
      final out = '${r.stdout}';
      if (!out.contains('xzcat') || !out.contains('tar')) {
        return BusyboxVerifyResult(
          ok: false,
          failureCode: DeployErrorCode.dependencyMissing,
          reason: 'busybox 缺少 xzcat/tar applet: $exec',
        );
      }
      return const BusyboxVerifyResult(ok: true);
    } on ProcessException catch (e) {
      final isPermission = e.errorCode == 13 || e.message.contains('ermission');
      if (isPermission) {
        return BusyboxVerifyResult(
          ok: false,
          failureCode: DeployErrorCode.permissionDenied,
          reason: '无执行权限（EACCES）: $exec\n${e.message}',
        );
      }
      return BusyboxVerifyResult(
        ok: false,
        failureCode: DeployErrorCode.extractionFailed,
        reason: '启动失败: $exec\n${e.message}',
      );
    } on PathAccessException catch (e) {
      final isPermission = e.osError?.errorCode == 13 ||
          e.message.contains('ermission');
      return BusyboxVerifyResult(
        ok: false,
        failureCode: isPermission
            ? DeployErrorCode.permissionDenied
            : DeployErrorCode.extractionFailed,
        reason: '访问失败: $exec\n${e.message}',
      );
    } on TimeoutException {
      return const BusyboxVerifyResult(
        ok: false,
        failureCode: DeployErrorCode.dependencyMissing,
        reason: 'busybox --list 超时',
      );
    }
  }
}

/// ====================================================================
/// TermuxBusyboxBackend — Termux 的 busybox
/// ====================================================================
class TermuxBusyboxBackend extends BusyboxBackendBase {
  TermuxBusyboxBackend({required String busyboxPath}) : _path = busyboxPath;

  final String _path;
  bool _available = false;
  String? _reason;

  @override
  String get name => 'Termux busybox';
  @override
  DecompressorSource get source => DecompressorSource.termux;
  @override
  DecompressorKind get kind => DecompressorKind.busybox;
  @override
  String? get xzPath => null;
  @override
  String? get tarPath => null;
  @override
  String? get busyboxPath => _path;
  @override
  String? get busyboxPathValue => _path;
  @override
  bool get available => _available;
  @override
  String? get reason => _reason;
  @override
  DeployErrorCode get failureCode => _failureCode;
  DeployErrorCode _failureCode = DeployErrorCode.dependencyMissing;
  @override
  List<DecompressorStatus> get status => [
        DecompressorStatus(
          name: name,
          available: _available,
          reason: _reason,
        ),
      ];

  Future<void> checkAvailable() async {
    final v = await verifyBusybox(_path);
    _available = v.ok;
    _reason = v.reason;
    _failureCode = v.failureCode ?? DeployErrorCode.dependencyMissing;
  }
}

/// ====================================================================
/// BundledBusyboxBackend — App 内置 BusyBox（fallback）
///
/// [path] 非空时为测试注入 / 显式指定路径（跳过 NativeBusybox 安装，
/// 直接验证该文件）；为空时走 [NativeBusybox.ensureInstalledDetailed]
/// （App 内置 asset → 私有目录原子安装 + 完整健康检查）。
/// ====================================================================
class BundledBusyboxBackend extends BusyboxBackendBase {
  BundledBusyboxBackend({String? path}) : _path = path;

  /// 显式指定路径（测试注入）；null = App 内置 asset
  final String? _path;

  String? _resolvedPath;
  bool _available = false;
  String? _reason;
  DeployErrorCode _failureCode = DeployErrorCode.dependencyMissing;

  @override
  String get name => 'App 内置 BusyBox';
  @override
  DecompressorSource get source => DecompressorSource.bundled;
  @override
  DecompressorKind get kind => DecompressorKind.busybox;
  @override
  String? get xzPath => null;
  @override
  String? get tarPath => null;
  @override
  String? get busyboxPath => _resolvedPath;
  @override
  String? get busyboxPathValue => _resolvedPath;
  @override
  bool get available => _available;
  @override
  String? get reason => _reason;
  @override
  DeployErrorCode get failureCode => _failureCode;
  @override
  List<DecompressorStatus> get status => [
        DecompressorStatus(
          name: name,
          available: _available,
          reason: _reason,
        ),
      ];

  Future<void> checkAvailable() async {
    final explicit = _path;
    if (explicit != null && explicit.trim().isNotEmpty) {
      // 测试注入 / 显式指定路径：直接验证
      final resolved = explicit.trim();
      _resolvedPath = resolved;
      final v = await verifyBusybox(resolved);
      _available = v.ok;
      _reason = v.reason;
      _failureCode = v.failureCode ?? DeployErrorCode.dependencyMissing;
      return;
    }
    // App 内置 asset：完整安装 + 健康检查
    final r = await NativeBusybox.ensureInstalledDetailed();
    if (r.success && r.path != null) {
      _resolvedPath = r.path;
      _available = true;
      _reason = null;
    } else {
      _available = false;
      _reason = '内置 BusyBox 安装失败: ${r.error.name}${r.detail != null ? '\n${r.detail}' : ''}';
      _failureCode = _mapBusyboxError(r.error);
    }
  }

  static DeployErrorCode _mapBusyboxError(BusyboxErrorCode code) {
    switch (code) {
      case BusyboxErrorCode.notFound:
        return DeployErrorCode.extractionFailed;
      case BusyboxErrorCode.permissionDenied:
        return DeployErrorCode.permissionDenied;
      case BusyboxErrorCode.corrupted:
      case BusyboxErrorCode.execFailed:
      case BusyboxErrorCode.xzcatUnavailable:
      case BusyboxErrorCode.installFailed:
        return DeployErrorCode.toolInstallationFailed;
      case BusyboxErrorCode.abiMismatch:
        return DeployErrorCode.archNotSupported;
      case BusyboxErrorCode.none:
        return DeployErrorCode.dependencyMissing;
    }
  }
}

/// ====================================================================
/// NoDecompressorBackend — 全部候选均不可用
/// ====================================================================
class NoDecompressorBackend extends DecompressorBackend {
  NoDecompressorBackend(this.status);

  @override
  final List<DecompressorStatus> status;

  @override
  String get name => '无可用解压器';
  @override
  DecompressorSource get source => DecompressorSource.none;
  @override
  DecompressorKind get kind => DecompressorKind.none;
  @override
  String? get xzPath => null;
  @override
  String? get tarPath => null;
  @override
  String? get busyboxPath => null;
  @override
  bool get available => false;
  @override
  String? get reason =>
      status.where((s) => !s.available).map((s) => s.reason).whereType<String>().join('; ');

  @override
  String get xzcatExecutable => '';
  @override
  List<String> xzcatArgs(String tarPath) => const [];
  @override
  String get tarExecutable => '';
  @override
  List<String> tarArgs(String targetDir, int stripComponents) => const [];
}

/// ====================================================================
/// DecompressorResolver — 按优先级自动选择可用后端
/// ====================================================================
class DecompressorResolver {
  DecompressorResolver._();

  /// 按优先级自动选择可用解压后端。
  ///
  /// [busyboxOverride] 非空时把该路径直接作为 busybox 使用
  /// （测试注入 / 回退），不再探测 Termux。
  /// [prefix] 为 Termux 前缀的测试注入点；不传时使用
  /// `Platform.environment['PREFIX']`（生产发现方式，禁止硬编码
  /// /data/data/com.termux/...）。
  ///
  /// 优先级：Termux xz+tar → Termux busybox → App 内置 BusyBox → none。
  static Future<DecompressorBackend> resolve({
    String? busyboxOverride,
    String? prefix,
  }) async {
    if (busyboxOverride != null && busyboxOverride.trim().isNotEmpty) {
      final b = BundledBusyboxBackend(path: busyboxOverride.trim());
      await b.checkAvailable();
      return b;
    }

    final statuses = <DecompressorStatus>[];
    final effectivePrefix = (prefix ?? Platform.environment['PREFIX'])
        ?.trim();

    if (effectivePrefix != null && effectivePrefix.isNotEmpty) {
      // ─── 1. Termux xz + tar ────────────────────────────────
      final termuxXz = TermuxXzBackend(
        xzPath: '$effectivePrefix/bin/xz',
        tarPath: '$effectivePrefix/bin/tar',
      );
      await termuxXz.checkAvailable();
      statuses.addAll(termuxXz.status);
      LogService.info(
        'Decompressor',
        'Termux xz 后端: available=${termuxXz.available} '
            '(${termuxXz.reason ?? 'ok'})',
      );
      if (termuxXz.available) return termuxXz;

      // ─── 2. Termux busybox ─────────────────────────────────
      final termuxBb = TermuxBusyboxBackend(busyboxPath: '$effectivePrefix/bin/busybox');
      await termuxBb.checkAvailable();
      statuses.addAll(termuxBb.status);
      LogService.info(
        'Decompressor',
        'Termux busybox 后端: available=${termuxBb.available} '
            '(${termuxBb.reason ?? 'ok'})',
      );
      if (termuxBb.available) return termuxBb;
    } else {
      statuses.add(const DecompressorStatus(
        name: 'Termux xz + tar',
        available: false,
        reason: '未检测到 \$PREFIX（Termux 未安装 / 未运行）',
      ));
      statuses.add(const DecompressorStatus(
        name: 'Termux busybox',
        available: false,
        reason: '未检测到 \$PREFIX（Termux 未安装 / 未运行）',
      ));
    }

    // ─── 3. App 内置 BusyBox（fallback） ─────────────────────
    final bundled = BundledBusyboxBackend();
    await bundled.checkAvailable();
    statuses.addAll(bundled.status);
    LogService.info(
      'Decompressor',
      'App 内置 BusyBox 后端: available=${bundled.available} '
          '(${bundled.reason ?? 'ok'})',
    );
    if (bundled.available) return bundled;

    // ─── 4. 全部不可用 ───────────────────────────────────────
    return NoDecompressorBackend(statuses);
  }
}
