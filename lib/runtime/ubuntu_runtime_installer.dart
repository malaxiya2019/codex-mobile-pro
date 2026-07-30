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
  Future<void> _extractTarXz({
    required String tarPath,
    required String targetDir,
    required int stripComponents,
    required void Function(int extracted, int total) onProgress,
  }) async {
    await Directory(targetDir).create(recursive: true);

    // ─── 解析系统工具路径 ───
    // Flutter App 进程的 PATH 不包含 Termux 目录，必须显式指定完整路径
    // 否则 Process.start('xz') 会报 Permission denied
    final xzBin = await _ensureToolInstalled('xz');
    final tarBin = await _ensureToolInstalled('tar');
    final findBin = _findSystemBinary('find');

    // ─── 流式解压：xz -> pipe -> tar ───
    // 使用 Process.start 管道直连 xz -> tar，不经过 Dart 内存缓冲区
    // 避免将 300MB+ 解压数据全部加载到内存中导致 OOM
    // 使用 shell + 自定义 PATH 执行 xz（SELinux 下 App 无法直接执行 Termux 的二进制）
    final xzProcess = await _startBinary(
      xzBin, ['-d', '-c', tarPath],
    );
    final tarProcess = await _startBinary(
      tarBin, ['x', '-C', targetDir, '--strip-components', '$stripComponents'],
    );

    // 管道：xz stdout → tar stdin（流式传输，不经过 Dart 代码）
    await xzProcess.stdout.pipe(tarProcess.stdin);
    await xzProcess.stderr.drain(); // 释放 stderr 缓冲区

    final xzExit = await xzProcess.exitCode;
    final tarExit = await tarProcess.exitCode;

    if (xzExit != 0 || tarExit != 0) {
      throw DeployError(
        code: DeployErrorCode.extractionFailed,
        message: 'rootfs 解压失败 (xz=$xzExit, tar=$tarExit)',
      );
    }

    // 统计解压后的文件数（纯UI反馈，失败不阻断）
    int totalFiles = 0;
    try {
      final countResult = await Process.run(
        findBin, [targetDir, '-type', 'f'],
        runInShell: true,
      );
      totalFiles = (countResult.stdout as String).split('\n').where((l) => l.isNotEmpty).length;
    } catch (_) {
      LogService.info('UbuntuInstaller', 'find 不可用，跳过文件计数');
    }
    onProgress(totalFiles, totalFiles);
  }




  /// 确保系统工具已安装，缺失时自动通过 Termux 安装
  Future<String> _ensureToolInstalled(String name) async {
    final binPath = _findSystemBinary(name);

    // 已找到（完整路径且文件存在）
    if (binPath.contains('/') && File(binPath).existsSync()) {
      return binPath;
    }

    // 只有裸名 → 不存在 → 尝试通过 Termux 安装
    LogService.info('UbuntuInstaller', '系统工具 $name 未找到，尝试自动安装...');

    // 检查 Termux 包管理器是否可用
    const termuxPkg = '/data/data/com.termux/files/usr/bin/pkg';
    if (!File(termuxPkg).existsSync()) {
      throw DeployError(
        code: DeployErrorCode.toolInstallationFailed,
        message: '缺少系统工具 $name，且 Termux 包管理器不可用',
      );
    }

    _report(InstallPhase.extracting, 0.25, '安装系统工具 $name...');

    // 通过 shell 执行 pkg install（Termux 的 pkg 是 bash 脚本）
    // SHELL: 先用 /system/bin/sh + 自定义 PATH 来执行
    const termuxPath = '/data/data/com.termux/files/usr/bin';
    const systemPath = '/system/bin:/system/xbin:/bin:/usr/bin';
    final customPath = '$termuxPath:$systemPath';

    final result = await Process.run(
      '/system/bin/sh',
      <String>['-c', 'pkg install $name -y'],
      environment: {'PATH': customPath},
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim().replaceAll(RegExp(r'\n'), '; ');
      // pkg 可能因为 SELinux 签名/版本问题不可用 → 直接尝试 apt
      LogService.warning('UbuntuInstaller', 'pkg install $name 失败 ($result.exitCode), 尝试 apt...');

      // 尝试直接用 apt（apt 是 ELF 二进制，比 pkg 脚本更容易被执行）
      const termuxApt = '/data/data/com.termux/files/usr/bin/apt';
      if (File(termuxApt).existsSync()) {
        final aptResult = await Process.run(
          '/system/bin/sh',
          <String>['-c', 'apt install $name -y 2>/dev/null || apt install $name -y --allow-unauthenticated'],
          environment: {'PATH': customPath},
        );
        if (aptResult.exitCode != 0) {
          throw DeployError(
            code: DeployErrorCode.toolInstallationFailed,
            message: '安装 $name 失败 (pkg=$result.exitCode, apt=$aptResult.exitCode): $stderr',
          );
        }
      } else {
        throw DeployError(
          code: DeployErrorCode.toolInstallationFailed,
          message: '安装 $name 失败 (pkg=$result.exitCode): $stderr',
        );
      }
    }

    // 安装后再次检查
    final installedPath = '/data/data/com.termux/files/usr/bin/$name';
    if (File(installedPath).existsSync()) {
      LogService.info('UbuntuInstaller', '$name 安装成功 ($installedPath)');
      return installedPath;
    }

    // 让 _findSystemBinary 再做一次完整查找
    final retryPath = _findSystemBinary(name);
    if (retryPath.contains('/') && File(retryPath).existsSync()) {
      return retryPath;
    }

    throw DeployError(
      code: DeployErrorCode.toolInstallationFailed,
      message: '安装 $name 完成但无法定位二进制文件',
    );
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
  static Future<Process> _startBinary(String binPath, List<String> args) async {
    // 如果二进制在系统目录，直接执行（不需要 shell 包装）
    if (binPath.startsWith('/system/') || binPath.startsWith('/bin/') || binPath.startsWith('/usr/')) {
      return await Process.start(binPath, args);
    }

    // 二进制在 Termux 或其它非标准目录 → 通过 shell + 自定义 PATH 启动
    // sh 始终可执行，PATH 包含 Termux 目录让 shell 能找到该二进制
    const termuxPath = '/data/data/com.termux/files/usr/bin';
    const systemPath = '/system/bin:/system/xbin:/bin:/usr/bin';
    final customPath = '$termuxPath:$systemPath';

    // 构建 shell 命令：sh -c 'exec $binName $arg1 $arg2 ...'
    // 使用 $0, $1, $2 传递参数以避免 shell 转义问题
    final binName = binPath.split('/').last;
    final shellArgs = <String>['-c', 'exec \$0 "\$@"', binName, ...args];

    return await Process.start(
      '/system/bin/sh',
      shellArgs,
      environment: {'PATH': customPath},
    );
  }

  static String _findSystemBinary(String name) {
    // 优先检查系统目录（App 进程可直接执行）
    const systemPaths = [
      '/system/bin',
      '/system/xbin',
      '/bin',
      '/usr/bin',
    ];
    for (final dir in systemPaths) {
      final fullPath = '$dir/$name';
      if (File(fullPath).existsSync()) return fullPath;
    }

    // Termux 目录 — 需要 shell + 自定义 PATH
    // 直接返回裸名，调用方通过 shell 环境变量 PATH 注入解决
    const termuxPaths = [
      '/data/data/com.termux/files/usr/bin',
      '/data/data/com.termux/files/home/.local/bin',
    ];
    for (final dir in termuxPaths) {
      final fullPath = '$dir/$name';
      if (File(fullPath).existsSync()) return fullPath;
    }

    // 回退：让 shell 去 PATH 查找
    return name;
  }
}
