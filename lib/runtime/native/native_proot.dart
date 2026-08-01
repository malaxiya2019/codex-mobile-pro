/// ====================================================================
/// Native PRoot Provider（Android jniLibs 交付机制）
///
/// proot + loader 作为 jniLibs（libproot.so / libloader.so）随 APK
/// 安装，Android 系统解压到 nativeLibraryDir（/data/app/`<pkg>`/lib/
/// arm64，系统保证可执行，不受 filesDir noexec / SELinux 限制）。
///
/// 与 busybox（libbusybox.so）同源交付方案：
///   - useLegacyPackaging=true 已配置，安装时 .so 真实解压；
///   - jniLibs 命名约束要求 `lib*.so` 前缀，因此可执行文件实际为
///     nativeLibraryDir/libproot.so（proot 不依赖 argv[0]，直接
///     execve 即可，无需 symlink 改名）；
///   - loader（全静态）经 PROOT_LOADER 环境变量指向
///     nativeLibraryDir/libloader.so。
///
/// 最小自动检测（用户要求）：
///   1. nativeLibraryDir/libproot.so 是否存在
///   2. executable 是否可启动（execve 冒烟）
///   3. `proot --version` 是否成功
///   4. nativeLibraryDir/libloader.so 是否存在
///
/// 全部通过才返回结果；任一失败返回 null，由调用方回退 rootfs 内
/// proot（现有安装流程产物），不影响旧链路。
/// ====================================================================
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;
import 'package:meta/meta.dart' show visibleForTesting;

import '../../core/logger/log_service.dart';

/// nativeLibraryDir 内 proot + loader 的就绪结果
class NativeProotInstallResult {
  /// nativeLibraryDir/libproot.so（可直接 execve）
  final String prootExecutable;

  /// nativeLibraryDir/libloader.so（PROOT_LOADER 目标）
  final String loaderPath;

  /// Android nativeLibraryDir（jniLibs 解压区）
  final String nativeLibraryDir;

  const NativeProotInstallResult({
    required this.prootExecutable,
    required this.loaderPath,
    required this.nativeLibraryDir,
  });
}

/// Native PRoot Provider
class NativeProot {
  NativeProot._();

  /// PtyPlugin MethodChannel（与 Kotlin PtyPlugin.kt 对应）
  static const MethodChannel _nativeChannel =
      MethodChannel('com.codexmobile.app/terminal/native');

  /// 冒烟超时（防挂起）
  static const Duration _smokeTimeout = Duration(seconds: 15);

  /// nativeLibraryDir 查询的测试注入点（同 NativeBusybox）
  @visibleForTesting
  static Future<String?> Function()? nativeLibDirQueryOverride;

  static NativeProotInstallResult? _cached;

  /// 重置进程内缓存（测试用）。
  ///
  /// nativeLibraryDir 由系统在安装时固定，生产环境无需重置；
  /// 单测通过 nativeLibDirQueryOverride 注入不同目录时需要清理。
  @visibleForTesting
  static void resetCache() {
    _cached = null;
  }

  /// 查询 nativeLibraryDir（Android jniLibs 解压区）。
  ///
  /// 失败（非 Android / MissingPlugin / Kotlin 报错）返回 null，
  /// 调用方回退到 rootfs 内 proot。
  static Future<String?> _queryNativeLibDir() async {
    final override = nativeLibDirQueryOverride;
    if (override != null) {
      try {
        return await override();
      } catch (_) {
        return null;
      }
    }
    try {
      final r = await _nativeChannel
          .invokeMethod<Map<Object?, Object?>>('getNativeLibDir');
      final dir = r?['nativeLibDir'];
      return dir is String && dir.isNotEmpty ? dir : null;
    } on MissingPluginException {
      return null;
    } catch (e) {
      LogService.warning('NativeProot', '查询 nativeLibraryDir 失败(忽略): $e');
      return null;
    }
  }

  /// 确保 native proot + loader 就绪。
  ///
  /// 返回 null 表示不可用（非 Android / 文件缺失 / --version 冒烟
  /// 失败），调用方回退现有 rootfs 内 proot。
  ///
  /// 结果进程内缓存：nativeLibraryDir 由系统在安装时固定，重复
  /// 查询无意义；--version 冒烟只执行一次。
  static Future<NativeProotInstallResult?> ensureInstalled() async {
    if (_cached != null) return _cached;

    final dir = await _queryNativeLibDir();
    if (dir == null || dir.isEmpty) return null;

    final prootSo = File('$dir/libproot.so');
    final loaderSo = File('$dir/libloader.so');

    // 1. nativeLibraryDir/proot 是否存在
    if (!await prootSo.exists()) {
      LogService.warning('NativeProot', 'nativeLibraryDir 无 libproot.so: $dir');
      return null;
    }

    // 4. loader 是否存在
    if (!await loaderSo.exists()) {
      LogService.warning('NativeProot', 'nativeLibraryDir 无 libloader.so: $dir');
      return null;
    }

    // 2 + 3. executable 可启动 + `proot --version` 成功
    final version = await _runVersion(prootSo.path);
    if (version == null) {
      LogService.warning('NativeProot', 'proot --version 冒烟失败: ${prootSo.path}');
      return null;
    }

    final result = NativeProotInstallResult(
      prootExecutable: prootSo.path,
      loaderPath: loaderSo.path,
      nativeLibraryDir: dir,
    );
    _cached = result;
    LogService.info(
      'NativeProot',
      'native proot 就绪: ${prootSo.path} '
          '(${version.trim().split('\n').first})',
    );
    return result;
  }

  /// 带超时的 `proot --version` 冒烟。
  ///
  /// 成功返回 stdout 内容；启动异常（EACCES / ENOEXEC / ENOENT）、
  /// 超时、非零退出统一返回 null。
  static Future<String?> _runVersion(String executable) async {
    try {
      final p = await Process.start(executable, ['--version']);
      final code = await p.exitCode.timeout(_smokeTimeout);
      if (code != 0) {
        try {
          p.kill();
        } catch (_) {}
        LogService.warning('NativeProot', 'proot --version exit=$code');
        return null;
      }
      final out = await p.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(_smokeTimeout);
      return out;
    } on TimeoutException {
      LogService.warning('NativeProot', 'proot --version 超时（>15s）');
      return null;
    } on ProcessException catch (e) {
      LogService.warning(
        'NativeProot',
        'proot --version ProcessException: ${e.message} (errno=${e.errorCode})',
      );
      return null;
    } on Object catch (e) {
      LogService.warning('NativeProot', 'proot --version 异常: $e');
      return null;
    }
  }
}
