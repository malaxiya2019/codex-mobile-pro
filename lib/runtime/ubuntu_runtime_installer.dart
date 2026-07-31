/// ====================================================================
/// Ubuntu Runtime 安装器
///
/// 负责下载、验证、解压 Ubuntu rootfs + proot-loader 到 App 私有目录。
///
/// 安装流程：
///   rootfs tar.xz → SHA256 → 磁盘预检 → 流式解压（busybox xzcat 管道 tar）
///   → 原子替换 → fake sysdata → proot .deb → 健康检查 → 完成标记
///
/// 关键设计（2026-07 修复「解压 50% 闪退」）：
///   1. 流式解压：busybox xzcat rootfs.tar.xz | busybox tar -xf -
///      不再将 315MB tar 流 / Archive 对象全量读入内存（原实现峰值
///      700MB+ → OOM → Android signal 9 静默杀进程）。
///   2. 真实进度：解压进度 = 已管道字节 / expandedBytes，
///      不再使用「50%」魔数假进度。
///   3. 原子安装：先解压到 rootfs.tmp-时间戳，成功后再 rename 替换，
///      失败自动清理半成品并回滚旧目录。
///   4. 完成标记：.codex_install_complete，防止半解压 rootfs 被误判
///      为已安装。
///   5. 缓存复用：已验证的 rootfs.tar.xz 保留在 .cache，下次跳过下载。
///   6. 磁盘预检：解压前检查可用空间，避免用户等到 50% 才遇到 ENOSPC。
///   7. 错误结构化：任何失败都转为 DeployError（code/detail/suggestion），
///      UI 可展示「阶段 + 原因 + 建议」，不再黑盒消失。
///
/// 依赖：
///   - 内置 BusyBox（assets/busybox-arm64，meefik 1.34.1 静态构建）
///   - 不依赖 Termux xz / 系统 tar / pkg / apt / dpkg
///
/// 2026-08 修复「ProcessException: Permission denied」（busybox xzcat）：
///   1. Process.start(busybox) 抛 EACCES（可执行位缺失/二进制损坏）时，
///      不再裸抛，转为结构化 DeployError（permissionDenied/extractionFailed），
///      携带 busybox 路径 + 镜像路径 + 存在性/大小/父目录/可读性诊断。
///   2. busybox 复用/重建逻辑（NativeBusybox）在启动前校验可执行位。
///   3. 解压启动前输出完整诊断日志（cacheDir/imagePath/exists/size/...）。
///   4. 安装前清理历史 rootfs.tmp-* / rootfs.old-*，防止旧权限异常缓存残留。
/// ====================================================================
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as path;

import '../core/logger/log_service.dart';
import 'artifact_manager.dart';
import 'deploy_error.dart';
import 'install_models.dart';
import 'native/busybox_provider.dart';
import 'runtime_dependency.dart';
import 'runtime_environment.dart';
import 'runtime_manifest.dart';
import 'sysdata_setup.dart';

/// Ubuntu Runtime 安装器
class UbuntuRuntimeInstaller {
  final RuntimeEnvironment _env;
  final InstallProgressCallback? _onProgress;

  /// 测试注入的 busybox 路径（非空时优先使用，跳过 NativeBusybox）
  final String? _busyboxOverride;

  /// 解压所需的空间余量（压缩包缓存 + 解压 + 临时文件 / proot / sysdata）
  static const int _spaceMarginBytes = 192 * 1024 * 1024;

  /// 流式解压整体超时（防止卡死导致 UI 永久「正在部署」）
  static const Duration _extractionTimeout = Duration(minutes: 20);

  UbuntuRuntimeInstaller(this._env, [this._onProgress, this._busyboxOverride]);

  /// 安装 Ubuntu Runtime（rootfs + proot + sysdata）
  Future<InstallResult> install() async {
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

      // 0. 磁盘空间预检（在下载前就给出明确提示）
      await _preCheckDiskSpace(manifest);

      // 1. 下载（或复用缓存）并流式解压 rootfs（原子替换）
      await _installRootfs(manifest);

      // 2. 下载并解压 proot
      await _installProot(manifest);

      // 3. 创建 fake sysdata
      await _setupSysdata();

      // 4. 健康检查
      final healthOk = await _healthCheck();
      if (!healthOk) {
        throw const DeployError(
          code: DeployErrorCode.healthCheckFailed,
          message: 'Ubuntu Runtime 健康检查失败',
          userSuggestion: '安装已回滚，请点击「重新初始化」重试',
        );
      }

      // 5. 写入安装完成标记（唯一判定「已安装」的依据）
      await _writeInstallCompleteMarker();

      _report(InstallPhase.completed, 1.0, 'Ubuntu Runtime 安装完成');
      return const InstallResult(
        tool: RuntimeTool.ubuntu,
        success: true,
        version: '24.04',
      );
    } on DeployError catch (e) {
      LogService.error(
        'UbuntuInstaller',
        '安装失败 [${e.code}]: ${e.message} ${e.detail ?? ''}',
      );
      _report(InstallPhase.failed, 0, e.message);
      return InstallResult(
        tool: RuntimeTool.ubuntu,
        success: false,
        errorMessage: e.userFriendly,
        phase: InstallPhase.failed,
      );
    } catch (e) {
      LogService.error('UbuntuInstaller', '安装失败: $e');
      _report(InstallPhase.failed, 0, '安装失败: $e');
      return InstallResult(
        tool: RuntimeTool.ubuntu,
        success: false,
        errorMessage: '部署失败: $e',
        phase: InstallPhase.failed,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 磁盘空间预检
  // ═══════════════════════════════════════════════════════════════

  /// 解压前磁盘空间预检
  ///
  /// 需要 = 压缩包缓存 + 预计解压大小 + 空间余量。
  /// 空间查询失败（未知）时跳过，不阻塞部署。
  Future<void> _preCheckDiskSpace(RuntimeManifest manifest) async {
    final rootfsArtifact = manifest.artifacts[0];
    final required =
        rootfsArtifact.size + rootfsArtifact.expandedBytes + _spaceMarginBytes;

    final free = await _freeDiskSpaceBytes(_env.ubuntuDir);
    if (free >= 0 && free < required) {
      throw DeployError(
        code: DeployErrorCode.diskFull,
        message: '存储空间不足，无法解压 Ubuntu Runtime',
        detail: '需要约 ${_formatSize(required)}，可用 ${_formatSize(free)}',
        userSuggestion: '请释放至少 ${_formatSize(required)} 空间后重试',
      );
    }
  }

  /// 获取指定路径所在文件系统的可用空间（字节）
  ///
  /// 使用 `df -Pk`（Android toybox 自带，不依赖 Termux）。
  /// 失败返回 -1（表示未知，调用方应跳过预检）。
  Future<int> _freeDiskSpaceBytes(String targetPath) async {
    try {
      final result = await Process.run('df', ['-Pk', targetPath]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        if (lines.length >= 2) {
          // df -Pk 列：Filesystem 1024-blocks Used Available Capacity Mounted-on
          final parts = lines[1].split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final availableKb = int.tryParse(parts[3]);
            if (availableKb != null) return availableKb * 1024;
          }
        }
      }
    } catch (_) {}
    return -1;
  }

  // ═══════════════════════════════════════════════════════════════
  // rootfs 安装（下载 → 校验 → 流式解压 → 原子替换）
  // ═══════════════════════════════════════════════════════════════

  Future<void> _installRootfs(RuntimeManifest manifest) async {
    final rootfsArtifact = manifest.artifacts[0]; // rootfs
    final rootfsDir = _env.ubuntuRootfsDir;
    final cacheDir = path.join(_env.ubuntuDir, '.cache');
    await Directory(cacheDir).create(recursive: true);

    // 清理历史半成品/隔离目录（权限异常或中断遗留的 rootfs.tmp-* /
    // rootfs.old-*），避免旧文件影响本次安装与磁盘空间。
    await _cleanupStaleInstallDirs();

    final ext = rootfsArtifact.url.endsWith('.xz') ? '.tar.xz' : '.tar.gz';
    final cachePath = path.join(cacheDir, '${rootfsArtifact.name}$ext');

    // ─── 缓存复用：已下载且 SHA256 一致 → 跳过下载 ──────────────
    final rootfsPath = cachePath;
    var needDownload = true;
    if (await File(cachePath).exists()) {
      _report(InstallPhase.verifying, 0.40, '验证已缓存的 rootfs...');
      final cachedSha = await _sha256Of(cachePath);
      if (cachedSha == rootfsArtifact.sha256) {
        needDownload = false;
        LogService.info('UbuntuInstaller', '复用已校验的 rootfs 缓存: $cachePath');
      } else {
        LogService.warning('UbuntuInstaller', 'rootfs 缓存校验失败，重新下载');
        try {
          await File(cachePath).delete();
        } catch (_) {}
      }
    }

    // ─── 下载（真实进度 5% → 40%）───────────────────────────────
    if (needDownload) {
      _report(InstallPhase.downloading, 0.05, '下载 Ubuntu rootfs...');
      await ArtifactManager.downloadFile(
        artifact: rootfsArtifact,
        destPath: rootfsPath,
        expectedSize: rootfsArtifact.size,
        expectedSha256: rootfsArtifact.sha256,
        onProgress: (downloaded, total) {
          final ratio = total > 0 ? downloaded / total : 0.0;
          _report(
            InstallPhase.downloading,
            0.05 + ratio * 0.35,
            '下载 Ubuntu rootfs (${_formatSize(downloaded)}/${_formatSize(total)})...',
          );
        },
      );
    }

    // ─── SHA256 校验（下载源已校验，这里对缓存/落盘再做一次） ──
    _report(InstallPhase.verifying, 0.42, '校验 rootfs 完整性...');
    final actualSha = await _sha256Of(rootfsPath);
    if (actualSha != rootfsArtifact.sha256) {
      throw DeployError(
        code: DeployErrorCode.sha256Mismatch,
        message: 'rootfs 完整性校验失败',
        detail: '期望 ${rootfsArtifact.sha256}\n实际 $actualSha',
        userSuggestion:
            DeployErrorSuggestions.forCode(DeployErrorCode.sha256Mismatch),
      );
    }

    // ─── 解压前磁盘预检（防止 50% 时 ENOSPC） ──────────────────
    final required = rootfsArtifact.expandedBytes + _spaceMarginBytes;
    final free = await _freeDiskSpaceBytes(_env.ubuntuDir);
    if (free >= 0 && free < required) {
      throw DeployError(
        code: DeployErrorCode.diskFull,
        message: '存储空间不足，无法解压 Ubuntu Runtime',
        detail: '需要约 ${_formatSize(required)}，可用 ${_formatSize(free)}',
        userSuggestion: '请释放至少 ${_formatSize(required)} 空间后重试',
      );
    }

    // ─── 流式解压到临时目录 → 原子替换 ──────────────────────────
    final tmpRootfsDir =
        '${_env.ubuntuDir}/rootfs.tmp-${DateTime.now().millisecondsSinceEpoch}';
    _report(InstallPhase.extracting, 0.50, '准备解压 Ubuntu rootfs...');

    try {
      await extractTarXzStreaming(
        tarPath: rootfsPath,
        targetDir: tmpRootfsDir,
        stripComponents: rootfsArtifact.stripComponents,
        expandedBytes: rootfsArtifact.expandedBytes,
        onProgress: (pipedBytes) {
          final ratio = rootfsArtifact.expandedBytes > 0
              ? (pipedBytes / rootfsArtifact.expandedBytes).clamp(0.0, 1.0)
              : 0.0;
          _report(
            InstallPhase.extracting,
            0.50 + ratio * 0.30,
            '解压 Ubuntu rootfs... ${(ratio * 100).toInt()}%',
          );
        },
      );

      // 解压后结构验证（只检查目录/文件，不执行 Ubuntu 内部命令）
      _verifyRootfsStructure(tmpRootfsDir);
      _report(InstallPhase.extracting, 0.82, 'rootfs 解压完成，正在安装...');

      // 原子替换：旧 rootfs → .old-*，新 rootfs → 正式目录
      await _atomicReplaceRootfs(tmpRootfsDir, rootfsDir);
    } catch (e) {
      // 失败清理：删除半成品（保留已验证的 .tar.xz 缓存供下次续用）
      await _deleteDirBestEffort(tmpRootfsDir);
      rethrow;
    }

    // 保留 rootfs 缓存（下次跳过下载）
  }

  /// 清理历史 rootfs 半成品/隔离目录
  ///
  /// 匹配 `<ubuntuDir>/rootfs.tmp-*` 与 `<ubuntuDir>/rootfs.old-*`，
  /// 尽力删除（失败仅记日志）。确保「重新初始化」真正清理旧的
  /// 损坏/权限异常缓存，而不是只清 UI 状态。
  Future<void> _cleanupStaleInstallDirs() async {
    try {
      final ubuntuDir = Directory(_env.ubuntuDir);
      if (!await ubuntuDir.exists()) return;
      await for (final entry in ubuntuDir.list()) {
        final name = path.basename(entry.path);
        if ((name.startsWith('rootfs.tmp-') ||
                name.startsWith('rootfs.old-')) &&
            entry is Directory) {
          LogService.info('UbuntuInstaller', '清理历史 rootfs 目录: ${entry.path}');
          await _deleteDirBestEffort(entry.path);
        }
      }
    } catch (e) {
      LogService.warning('UbuntuInstaller', '清理历史 rootfs 目录失败(忽略): $e');
    }
  }

  /// 原子替换 rootfs 目录
  ///
  /// 1. 旧目录存在 → rename 为 rootfs.old-时间戳（隔离损坏的半成品）
  /// 2. 新临时目录 → rename 为正式 rootfsDir
  /// 3. 第二步失败 → 回滚旧目录
  /// 4. 旧目录后台异步删除（失败仅记日志，不阻塞安装）
  Future<void> _atomicReplaceRootfs(String tmpDir, String finalDir) async {
    String? oldDir;
    if (await Directory(finalDir).exists()) {
      oldDir =
          '${_env.ubuntuDir}/rootfs.old-${DateTime.now().millisecondsSinceEpoch}';
      await Directory(finalDir).rename(oldDir);
    }

    try {
      await Directory(tmpDir).rename(finalDir);
    } catch (e) {
      // 回滚旧目录
      if (oldDir != null) {
        try {
          await Directory(oldDir).rename(finalDir);
        } catch (_) {}
      }
      rethrow;
    }

    if (oldDir != null) {
      unawaited(_deleteDirBestEffort(oldDir));
    }
  }

  /// 解析解压器可执行文件路径
  ///
  /// 优先级：
  ///   1. [_busyboxOverride]（测试 / 回退注入）
  ///   2. [NativeBusybox.ensureInstalled]（App 内置 busybox，含
  ///      可执行位校验 / 损坏重建）
  /// 返回 null 表示没有任何可用解压器。
  @visibleForTesting
  Future<String?> resolveBusybox() async {
    final override = _busyboxOverride;
    if (override != null && override.trim().isNotEmpty) {
      LogService.info('UbuntuInstaller', '使用注入的 busybox: $override');
      return override;
    }
    return NativeBusybox.ensureInstalled();
  }

  /// 流式解压 tar.xz（busybox xzcat | busybox tar）
  ///
  /// 不再使用 archive 包全量解码：
  ///   - 内存峰值 = 单次管道块（≤ 64KB），而不是 700MB+
  ///   - symlink / device 节点由 busybox tar 完整还原
  ///   - 进度 = 已管道字节 / expandedBytes（真实进度）
  ///
  /// busybox tar 在 Android 上无法创建设备节点时会在 stderr 输出
  /// "can't create node" / "Operation not permitted" 并返回 exit=1，
  /// 此属预期（rootfs 的 /dev 由 proot 虚拟化），按警告处理而不是失败。
  ///
  /// 2026-08 增强（修复「ProcessException: Permission denied」）：
  ///   - Process.start 抛 ProcessException（EACCES/ENOENT/Exec format
  ///     error）时转为结构化 DeployError，携带 busybox + 镜像诊断，
  ///     不再把裸异常抛给 UI。
  ///   - 启动前输出诊断日志（busybox / 镜像路径 / 存在性 / 大小 /
  ///     父目录 / 可读性）。
  ///   - 支持 [_busyboxOverride] 注入（测试 / 回退用）。
  @visibleForTesting
  Future<void> extractTarXzStreaming({
    required String tarPath,
    required String targetDir,
    required int stripComponents,
    required int expandedBytes,
    required void Function(int pipedBytes) onProgress,
  }) async {
    final busyboxPath = await resolveBusybox();
    if (busyboxPath == null) {
      throw const DeployError(
        code: DeployErrorCode.dependencyMissing,
        message: '内置解压工具（BusyBox）不可用',
        userSuggestion: '请点击「重新初始化」（会重新安装内置解压工具）；'
            '若仍失败请清理应用数据后重新部署',
      );
    }

    await Directory(targetDir).create(recursive: true);

    // ─── 启动前诊断日志（Permission denied 排查用） ────────────
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
      LogService.warning('UbuntuInstaller', '镜像诊断失败(忽略): $e');
    }
    LogService.info(
      'UbuntuInstaller',
      'xzcat 启动前诊断: busybox=$busyboxPath | image=$tarPath | '
          'imageExists=$imageExists | imageSize=$imageSize | '
          'imageReadable=$imageReadable | '
          'parentExists=${await parentDir.exists()} | parent=$parentDir',
    );

    // 管道：busybox xzcat rootfs.tar.xz | busybox tar -xf - -C <target> --strip-components=N
    Process xzcat;
    Process tar;
    try {
      xzcat = await Process.start(busyboxPath, ['xzcat', tarPath]);
      tar = await Process.start(busyboxPath, [
        'tar',
        '-xf',
        '-',
        '-C',
        targetDir,
        if (stripComponents > 0) '--strip-components=$stripComponents',
      ]);
    } on ProcessException catch (e) {
      // 核心修复：exec 失败（EACCES=13 / ENOENT=2 / Exec format error）
      // 转结构化 DeployError，而不是让裸异常一路抛到 UI。
      final errno = e.errorCode;
      final isPermission = errno == 13 || e.message.contains('ermission');
      final isNoEnt = errno == 2 || e.message.contains('No such');
      throw DeployError(
        code: isPermission
            ? DeployErrorCode.permissionDenied
            : DeployErrorCode.extractionFailed,
        message: isPermission ? '解压工具启动失败（权限被拒绝）' : '解压工具启动失败（${e.message}）',
        detail: 'busybox=$busyboxPath\n'
            'error=${e.message} (errno=$errno)\n'
            'image=$tarPath exists=$imageExists size=$imageSize '
            'readable=$imageReadable '
            'parentExists=${await parentDir.exists()}\n'
            '${isNoEnt ? '解压工具不存在或路径错误。' : ''}'
            '若为可执行权限问题，点击「重新初始化」将重新安装内置解压工具',
        userSuggestion: '点击「重新初始化」重试（将重新安装内置解压工具）；'
            '若反复失败请清理应用数据后重新部署',
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
    final timeoutTimer = Timer(_extractionTimeout, () {
      if (!timeoutCompleter.isCompleted) timeoutCompleter.complete();
    });

    try {
      await Future.any([
        tar.stdin.addStream(counting),
        timeoutCompleter.future,
      ]);
      if (timeoutCompleter.isCompleted) {
        throw TimeoutException(
          'rootfs 解压超时（超过 ${_extractionTimeout.inMinutes} 分钟）',
        );
      }
    } on Object catch (e) {
      // 终止子进程，避免残留
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
      'UbuntuInstaller',
      '解压进程结束: busybox=$busyboxPath | xzcat exit=$xzcatExit | '
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
        detail: 'tar exit=$tarExit, xzcat exit=$xzcatExit\n'
            'stderr:\n${stderrText.isEmpty ? '(空)' : stderrText}',
        userSuggestion: '解压中断。已保留完整压缩包缓存，点击「重新初始化」将直接重新解压，无需再次下载',
      );
    }
    if (xzcatExit != 0) {
      throw DeployError(
        code: DeployErrorCode.extractionFailed,
        message: 'rootfs 解压失败（xzcat exit=$xzcatExit）',
        detail: stderrText.isEmpty ? '(空)' : stderrText,
        userSuggestion:
            DeployErrorSuggestions.forCode(DeployErrorCode.extractionFailed),
      );
    }

    onProgress(expandedBytes);
  }

  /// 解压后 rootfs 结构验证（只检查目录/文件存在性）
  ///
  /// 注意：不执行 Ubuntu 内部命令（解压阶段禁止运行 rootfs 内程序）。
  void _verifyRootfsStructure(String rootfsDir) {
    final required = <String>[
      'etc',
      'usr',
      'bin',
      'lib',
      'bin/bash',
      'usr/bin/bash',
      'usr/bin/apt',
      'etc/os-release',
    ];
    final missing = required.where((p) {
      final entityPath = '$rootfsDir/$p';
      return FileSystemEntity.typeSync(entityPath) ==
          FileSystemEntityType.notFound;
    }).toList();

    if (missing.isNotEmpty) {
      throw DeployError(
        code: DeployErrorCode.extractionFailed,
        message: 'rootfs 解压后结构不完整',
        detail: '缺少: ${missing.join(", ")}',
        userSuggestion: '压缩包可能损坏。已保留缓存，点击「重新初始化」将重新解压',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // proot 安装
  // ═══════════════════════════════════════════════════════════════

  Future<void> _installProot(RuntimeManifest manifest) async {
    final prootArtifact = manifest.artifacts[1]; // proot
    final prootDir = _env.ubuntuBinDir;

    _report(InstallPhase.downloading, 0.84, '下载 proot...');

    // 复用 ArtifactManager 的 .deb 下载和提取能力（.deb 仅 95KB，内存安全）
    await ArtifactManager.downloadAndExtract(
      artifact: prootArtifact,
      targetDir: prootDir,
      onProgress: (downloaded, total, message) {
        _report(
          InstallPhase.downloading,
          0.84 + (total > 0 ? (downloaded / total) : 0.0) * 0.05,
          message,
        );
      },
    );

    // 确保 proot binary 有可执行权限（校验 chmod 结果，避免同类 EACCES）
    final prootBin = File(path.join(prootDir, 'proot'));
    if (await prootBin.exists()) {
      final chmod = await Process.run('chmod', ['+x', prootBin.path]);
      if (chmod.exitCode != 0) {
        LogService.warning(
          'UbuntuInstaller',
          'proot chmod +x 失败: exit=${chmod.exitCode} stderr=${chmod.stderr}',
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // fake sysdata
  // ═══════════════════════════════════════════════════════════════

  Future<void> _setupSysdata() async {
    _report(InstallPhase.configuring, 0.92, '创建系统数据文件...');
    await SysDataSetup.setup(_env.ubuntuRootfsDir);
  }

  // ═══════════════════════════════════════════════════════════════
  // 健康检查
  // ═══════════════════════════════════════════════════════════════

  Future<bool> _healthCheck() async {
    _report(InstallPhase.verifying, 0.95, '验证 Ubuntu Runtime...');

    // 检查 key 文件是否存在
    final bashFile =
        File(path.join(_env.ubuntuRootfsDir, 'usr', 'bin', 'bash'));
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

    final loaderFile =
        File(path.join(_env.ubuntuLibexecDir, 'proot', 'loader'));
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

  /// 写入安装完成标记（唯一判定「已安装」的依据）
  Future<void> _writeInstallCompleteMarker() async {
    final marker = File(_env.installCompleteMarker);
    await marker.writeAsString(
      'installed_at=${DateTime.now().toIso8601String()}\n'
      'version=24.04\n',
      flush: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════════════

  void _report(InstallPhase phase, double progress, String message) {
    _onProgress?.call(RuntimeTool.ubuntu, phase, progress, message);
    LogService.info('UbuntuInstaller', message);
  }

  /// 下载 artifact 文件（不通过 .deb）—— 仅用于 rootfs 预下载
  ///
  /// 保留此方法供未来多 rootfs 下载复用；当前 rootfs 下载直接在
  /// _installRootfs 内完成（含缓存复用）。
  Future<String> _downloadArtifact({
    required RuntimeArtifact artifact,
    required void Function(int downloaded, int total) onProgress,
  }) async {
    final cacheDir = path.join(_env.ubuntuDir, '.cache');
    await Directory(cacheDir).create(recursive: true);

    final ext = artifact.url.endsWith('.xz') ? '.tar.xz' : '.tar.gz';
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

  /// 计算文件 SHA256（流式，避免大文件入内存）
  static Future<String> _sha256Of(String filePath) async {
    final file = File(filePath);
    final chunks = file.openRead();
    final digest = await sha256.bind(chunks).first;
    return digest.toString();
  }

  /// 尽力删除目录（失败仅记日志，不阻塞）
  static Future<void> _deleteDirBestEffort(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      LogService.warning('UbuntuInstaller', '清理目录失败(忽略): $dirPath — $e');
    }
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
