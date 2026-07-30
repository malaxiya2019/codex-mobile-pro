/// ====================================================================
/// Ubuntu Runtime 安装器
///
/// 负责下载、验证、解压 Ubuntu rootfs + proot-loader 到 App 私有目录。
///
/// 安装流程：
///   rootfs tar.xz → SHA256 → 解压 (stripComponents=1) → fake sysdata → proot .deb
///   → SHA256 → 解压 → proot binary → loader → 健康检查
///
/// 与当前 .deb 单包安装器 (RuntimeInstaller) 共存，不删除后者。
/// ====================================================================

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as path;

import '../core/logger/log_service.dart';
import 'artifact_manager.dart';
import 'runtime_dependency.dart';
import 'runtime_environment.dart';
import 'runtime_installer.dart'; // 复用 InstallPhase, InstallResult, InstallErrorCode
import 'runtime_manifest.dart';
import 'sysdata_setup.dart';

/// Ubuntu Runtime 安装器
class UbuntuRuntimeInstaller {
  final RuntimeEnvironment _env;
  final InstallProgressCallback? _onProgress;

  UbuntuRuntimeInstaller(this._env, [this._onProgress]);

  /// 安装 Ubuntu Runtime（rootfs + proot + sysdata）
  Future<InstallResult> install() async {
    _report(InstallPhase.downloading, 0.0, '准备安装 Ubuntu Runtime...');

    try {
      // 检查架构
      if (!_isSupportedArch()) {
        return InstallResult(
          tool: RuntimeTool.ubuntu,
          success: false,
          errorMessage: '当前设备架构不支持 Ubuntu Runtime（仅 arm64-v8a）',
          phase: InstallPhase.failed,
        );
      }

      // 获取 manifest
      final manifest = RuntimeManifest.forTool(RuntimeTool.ubuntu);
      if (manifest == null) {
        return InstallResult(
          tool: RuntimeTool.ubuntu,
          success: false,
          errorMessage: 'Ubuntu Runtime 清单未定义',
          phase: InstallPhase.failed,
        );
      }

      final ubuntuDir = _env.ubuntuDir;
      await Directory(ubuntuDir).create(recursive: true);

      // 1. 下载并解压 rootfs
      await _installRootfs(manifest);

      // 2. 下载并解压 proot
      await _installProot(manifest);

      // 3. 创建 fake sysdata
      await _setupSysdata();

      // 4. 健康检查
      final healthOk = await _healthCheck();
      if (!healthOk) {
        return InstallResult(
          tool: RuntimeTool.ubuntu,
          success: false,
          errorMessage: 'Ubuntu Runtime 健康检查失败',
          phase: InstallPhase.failed,
        );
      }

      _report(InstallPhase.completed, 1.0, 'Ubuntu Runtime 安装完成');
      return InstallResult(
        tool: RuntimeTool.ubuntu,
        success: true,
        version: '24.04',
        phase: InstallPhase.completed,
      );
    } on InstallException catch (e) {
      _report(InstallPhase.failed, 0, e.message);
      return InstallResult(
        tool: RuntimeTool.ubuntu,
        success: false,
        errorMessage: e.message,
        phase: InstallPhase.failed,
      );
    } catch (e) {
      _report(InstallPhase.failed, 0, '安装失败: $e');
      return InstallResult(
        tool: RuntimeTool.ubuntu,
        success: false,
        errorMessage: e.toString(),
        phase: InstallPhase.failed,
      );
    }
  }

  /// ─── rootfs 安装 ─────────────────────────────────────────────

  Future<void> _installRootfs(RuntimeManifest manifest) async {
    final rootfsArtifact = manifest.artifacts[0]; // rootfs
    final rootfsDir = _env.ubuntuRootfsDir;

    _report(InstallPhase.downloading, 0.15, '下载 Ubuntu rootfs...');

    // 下载 rootfs
    final rootfsPath = await _downloadArtifact(
      artifact: rootfsArtifact,
      onProgress: (downloaded, total) {
        _report(
          InstallPhase.downloading,
          0.15 + (downloaded / total) * 0.3,
          '下载 Ubuntu rootfs (${_formatSize(downloaded)}/${_formatSize(total)})...',
        );
      },
    );

    _report(InstallPhase.extracting, 0.5, '解压 Ubuntu rootfs...');

    // 解压 tar.xz (stripComponents=1)
    await _extractTarXz(
      tarPath: rootfsPath,
      targetDir: rootfsDir,
      stripComponents: rootfsArtifact.stripComponents,
      onProgress: (extracted, total) {
        _report(
          InstallPhase.extracting,
          0.5 + (extracted / total) * 0.2,
          '解压 rootfs ($extracted/$total)...',
        );
      },
    );

    // 清理下载缓存
    try {
      await File(rootfsPath).delete();
    } catch (_) {}
  }

  /// ─── proot 安装 ──────────────────────────────────────────────

  Future<void> _installProot(RuntimeManifest manifest) async {
    final prootArtifact = manifest.artifacts[1]; // proot
    final prootDir = _env.ubuntuBinDir;

    _report(InstallPhase.downloading, 0.72, '下载 proot...');

    // 复用 ArtifactManager 的 .deb 下载和提取能力
    await ArtifactManager.downloadAndExtract(
      artifact: prootArtifact,
      targetDir: prootDir,
      onProgress: (downloaded, total, message) {
        _report(
          InstallPhase.downloading,
          0.72 + (downloaded / total) * 0.15,
          message,
        );
      },
    );

    // 确保 proot binary 有可执行权限
    final prootBin = File(path.join(prootDir, 'proot'));
    if (await prootBin.exists()) {
      await Process.run('chmod', ['+x', prootBin.path]);
    }
  }

  /// ─── fake sysdata ────────────────────────────────────────────

  Future<void> _setupSysdata() async {
    _report(InstallPhase.configuring, 0.9, '创建系统数据文件...');
    await SysDataSetup.setup(_env.ubuntuRootfsDir);
  }

  /// ─── 健康检查 ────────────────────────────────────────────────

  Future<bool> _healthCheck() async {
    _report(InstallPhase.verifying, 0.95, '验证 Ubuntu Runtime...');

    // 检查 key 文件是否存在
    final bashFile = File(path.join(_env.ubuntuRootfsDir, 'usr', 'bin', 'bash'));
    if (!await bashFile.exists()) {
      LogService.error('UbuntuInstaller', 'bash 不存在于 rootfs');
      return false;
    }

    final aptFile = File(path.join(_env.ubuntuRootfsDir, 'usr', 'bin', 'apt'));
    if (!await aptFile.exists()) {
      LogService.error('UbuntuInstaller', 'apt 不存在于 rootfs');
      return false;
    }

    final prootFile = File(path.join(_env.ubuntuBinDir, 'proot'));
    if (!await prootFile.exists()) {
      LogService.error('UbuntuInstaller', 'proot 二进制不存在');
      return false;
    }

    final loaderFile = File(path.join(_env.ubuntuLibexecDir, 'proot', 'loader'));
    if (!await loaderFile.exists()) {
      LogService.error('UbuntuInstaller', 'proot loader 不存在');
      return false;
    }

    // 检查 sysdata
    if (!SysDataSetup.isSetupComplete(_env.ubuntuRootfsDir)) {
      LogService.error('UbuntuInstaller', 'fake sysdata 未完整创建');
      return false;
    }

    LogService.info('UbuntuInstaller', 'Ubuntu Runtime 健康检查通过');
    return true;
  }

  /// ─── 工具方法 ────────────────────────────────────────────────

  void _report(InstallPhase phase, double progress, String message) {
    _onProgress?.call(RuntimeTool.ubuntu, phase, progress, message);
    LogService.info('UbuntuInstaller', message);
  }

  /// 下载 artifact 文件（不通过 .deb）
  Future<String> _downloadArtifact({
    required RuntimeArtifact artifact,
    required void Function(int downloaded, int total) onProgress,
  }) async {
    final cacheDir = path.join(_env.ubuntuDir, '.cache');
    await Directory(cacheDir).create(recursive: true);

    final ext = artifact.url.endsWith('.xz')
        ? '.tar.xz'
        : '.tar.gz';
    final destPath = path.join(cacheDir, '${artifact.name}$ext');
    final partPath = '$destPath.part';

    // 带重试的下载
    int attempt = 0;
    const maxRetries = 3;
    while (true) {
      attempt++;
      try {
        await _doDownload(
          url: artifact.url,
          destPath: destPath,
          partPath: partPath,
          expectedSize: artifact.size,
          onProgress: onProgress,
        );
        break;
      } catch (e) {
        try { await File(partPath).delete(); } catch (_) {}
        if (attempt >= maxRetries) rethrow;
        final delay = Duration(seconds: 2 << (attempt - 1));
        await Future.delayed(delay);
      }
    }

    // SHA256 验证
    onProgress(artifact.size, artifact.size);
    final actualSha256 = await _computeSha256(destPath);
    if (actualSha256 != artifact.sha256) {
      await File(destPath).delete();
      throw InstallException(
        InstallErrorCode.sha256Mismatch,
        '${artifact.name} SHA256 校验失败\n'
        '期望: ${artifact.sha256}\n'
        '实际: $actualSha256',
      );
    }

    return destPath;
  }

  Future<void> _doDownload({
    required String url,
    required String destPath,
    required String partPath,
    required int expectedSize,
    required void Function(int, int) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw InstallException(
          InstallErrorCode.downloadFailed,
          '下载失败: HTTP ${response.statusCode} — $url',
        );
      }

      final file = File(partPath);
      final sink = file.openWrite();
      int bytesDownloaded = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        bytesDownloaded += chunk.length;
        onProgress(bytesDownloaded, expectedSize);
      }

      await sink.flush();
      await sink.close();

      // 验证大小
      final actualSize = await file.length();
      if (actualSize != expectedSize) {
        await file.delete();
        throw InstallException(
          InstallErrorCode.downloadFailed,
          '文件大小不匹配: 期望 $expectedSize, 实际 $actualSize',
        );
      }

      await file.rename(destPath);
    } finally {
      client.close();
    }
  }

  /// 解压 tar.xz 到目标目录
  Future<void> _extractTarXz({
    required String tarPath,
    required String targetDir,
    required int stripComponents,
    required void Function(int extracted, int total) onProgress,
  }) async {
    await Directory(targetDir).create(recursive: true);

    final bytes = await File(tarPath).readAsBytes();

    // 解压 xz
    List<int> tarBytes;
    if (tarPath.endsWith('.xz')) {
      tarBytes = XZDecoder().decodeBytes(bytes);
    } else if (tarPath.endsWith('.gz')) {
      tarBytes = GZipDecoder().decodeBytes(bytes);
    } else {
      tarBytes = bytes;
    }

    // 解压 tar
    final decoder = TarDecoder();
    final archive = decoder.decodeBytes(tarBytes);

    int extracted = 0;
    final total = archive.length;

    for (final entry in archive) {
      if (entry.isFile) {
        final strippedPath = _stripPathComponents(entry.name, stripComponents);
        if (strippedPath == null || strippedPath.isEmpty) continue;

        final destPath = path.join(targetDir, strippedPath);
        final destDir = path.dirname(destPath);
        await Directory(destDir).create(recursive: true);

        await File(destPath).writeAsBytes(entry.content as List<int>);

        // 设置执行权限
        if ((entry.mode & 0x40) != 0) {
          try {
            await Process.run('chmod', ['+x', destPath]);
          } catch (_) {}
        }

        extracted++;
        if (extracted % 1000 == 0) {
          onProgress(extracted, total);
        }
      }
    }

    onProgress(total, total);
  }

  /// 去掉路径的前 N 个组件
  static String? _stripPathComponents(String filePath, int count) {
    final parts = path.split(filePath);
    final cleaned = parts.where((p) => p.isNotEmpty && p != '.').toList();
    if (cleaned.length <= count) return null;
    return path.joinAll(cleaned.sublist(count));
  }

  /// 计算 SHA256
  static Future<String> _computeSha256(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// 架构检查
  static bool _isSupportedArch() {
    try {
      final result = Process.runSync('getprop', ['ro.product.cpu.abi']);
      if (result.exitCode == 0) {
        final abi = (result.stdout as String).trim();
        return abi == 'arm64-v8a' || abi == 'aarch64';
      }
    } catch (_) {}
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        final arch = (result.stdout as String).trim();
        return arch == 'aarch64' || arch == 'arm64';
      }
    } catch (_) {}
    return true; // 默认允许
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 带错误码的安装异常（复用现有定义）
class InstallException implements Exception {
  final InstallErrorCode code;
  final String message;
  final String? detail;

  const InstallException(this.code, this.message, {this.detail});

  @override
  String toString() => 'InstallException[$code]: $message';
}
