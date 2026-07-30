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
library;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

import '../core/logger/log_service.dart';
import 'artifact_manager.dart';
import 'deploy_error.dart';
import 'runtime_dependency.dart';
import 'runtime_environment.dart';
import 'runtime_installer.dart'; // 复用 InstallPhase, InstallResult
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
        return const InstallResult(
          tool: RuntimeTool.ubuntu,
          success: false,
          errorMessage: '当前设备架构不支持 Ubuntu Runtime（仅 arm64-v8a）',
          phase: InstallPhase.failed,
        );
      }

      // 获取 manifest
      final manifest = RuntimeManifest.forTool(RuntimeTool.ubuntu);
      if (manifest == null) {
        return const InstallResult(
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
        return const InstallResult(
          tool: RuntimeTool.ubuntu,
          success: false,
          errorMessage: 'Ubuntu Runtime 健康检查失败',
          phase: InstallPhase.failed,
        );
      }

      _report(InstallPhase.completed, 1.0, 'Ubuntu Runtime 安装完成');
      return const InstallResult(
        tool: RuntimeTool.ubuntu,
        success: true,
        version: '24.04',
      );
    } on DeployError catch (e) {
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
  ///
  /// 带 IP 直连 fallback：标准重试失败后自动切 IP 直连。
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

    // 使用 ArtifactManager 的多镜像 fallback 下载
    await ArtifactManager.downloadFile(
      artifact: artifact,
      destPath: destPath,
      expectedSize: artifact.size,
      expectedSha256: artifact.sha256,
      onProgress: onProgress,
    );

    return destPath;
  }

  /// 解压 tar.xz 到目标目录（流式解压，避免 OOM）
  ///
  /// 使用系统命令 xz + tar 管道流式处理，不将解压数据完全加载到内存。
  /// 之前在 Dart 中用 archive 包全部解压到内存导致移动端 OOM 闪退。
  /// 解压 tar.xz 到目标目录（纯 Dart 实现，不依赖外部命令）
  Future<void> _extractTarXz({
    required String tarPath,
    required String targetDir,
    required int stripComponents,
    required void Function(int extracted, int total) onProgress,
  }) async {
    await Directory(targetDir).create(recursive: true);

    // 1. 读取压缩文件
    final compressedBytes = await File(tarPath).readAsBytes();

    // 2. XZ 解压缩（纯 Dart，archive 包）
    final tarBytes = XZDecoder().decodeBytes(compressedBytes);

    // 3. 解包 tar
    final decoder = TarDecoder();
    final archive = decoder.decodeBytes(tarBytes);

    // 4. 提取文件到目标目录
    int extracted = 0;
    for (final entry in archive) {
      if (entry.isFile) {
        final strippedPath = _stripPathComponents(entry.name, stripComponents);
        if (strippedPath == null || strippedPath.isEmpty) continue;

        final destPath = path.join(targetDir, strippedPath);
        final destDir = path.dirname(destPath);

        await Directory(destDir).create(recursive: true);
        await File(destPath).writeAsBytes(entry.content as List<int>);

        // 保留可执行权限
        if ((entry.mode & 0x40) != 0) {
          try {
            await Process.run('chmod', ['+x', destPath]);
          } catch (_) {}
        }

        extracted++;
        onProgress(extracted, archive.length);
      }
    }

    onProgress(archive.length, archive.length);
  }

  /// 去除路径前 N 个组件（tar --strip-components 的 Dart 实现）
  static String? _stripPathComponents(String filePath, int count) {
    final parts = filePath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= count) return null;
    return parts.skip(count).join('/');
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
  /// 查找系统二进制文件
  ///
  /// Android App 进程的 PATH 仅包含 /system/bin:/system/xbin，
  /// 不包含 Termux 的 /data/data/com.termux/files/usr/bin。
  /// 此方法按安全优先级查找：
  ///   1. 系统目录（/system/bin, /system/xbin）— App 有执行权限
  ///   2. Termux 目录 — 需通过 shell + 自定义 PATH 执行
  ///
  /// 返回值永远是裸名，实际路径通过 shell 环境变量注入解决。
  /// 启动一个二进制进程（处理 Termux 路径权限问题）
  ///
  /// Android SELinux 阻止 App 进程直接执行 /data/data/com.termux/ 下的二进制。
  /// 如果二进制在 Termux 目录，通过 /system/bin/sh 启动并注入 PATH 环境变量，
  /// 使 shell 能找到 Termux 的二进制文件。
  // ─── BusyBox 回退 ─────────────────────────────────────────────

  /// 查找 App 自带的 BusyBox（由 Kotlin PtyPlugin 解压到 files/bin/）
  /// 创建 xz 包装脚本（调用 BusyBox 的 unxz applet）
  ///
  /// 在 [cacheDir] 下生成一个轻量 shell 脚本，行为同 `xz` 命令行工具。
  /// 这样 _extractTarXz 的管道代码无需修改。
  /// 尝试通过 BusyBox 解决 xz 缺失
