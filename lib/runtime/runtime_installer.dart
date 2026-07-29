import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/logger/log_service.dart';
import 'artifact_manager.dart';
import 'runtime_dependency.dart';
import 'runtime_environment.dart';
import 'runtime_manifest.dart';

/// ====================================================================
/// Runtime 安装器
///
/// 负责在 App 私有目录下安装 Node.js / Git / Python / Codex CLI / mimo2codex。
///
/// 所有安装在 App 私有目录中进行，不修改系统目录。
///
/// 安装流程：
///   RuntimeManifest → ArtifactManager.downloadAndExtract() → HealthCheck
/// ====================================================================

/// 安装阶段
enum InstallPhase {
  pending,
  downloading,
  extracting,
  configuring,
  verifying,
  completed,
  failed,
}

/// 安装结果
class InstallResult {
  final RuntimeTool tool;
  final bool success;
  final String? errorMessage;
  final String? version;
  final InstallPhase phase;

  const InstallResult({
    required this.tool,
    required this.success,
    this.errorMessage,
    this.version,
    this.phase = InstallPhase.completed,
  });
}

/// 安装进度回调
typedef InstallProgressCallback = void Function(
  RuntimeTool tool,
  InstallPhase phase,
  double progress,
  String message,
);

/// 详细安装错误码
enum InstallErrorCode {
  none,
  archNotSupported,
  downloadFailed,
  sha256Mismatch,
  extractionFailed,
  healthCheckFailed,
  npmMissing,
  storageInsufficient,
  permissionDenied,
  unknown,
}

/// 带错误码的安装异常
class InstallException implements Exception {
  final InstallErrorCode code;
  final String message;
  final String? detail;

  const InstallException(this.code, this.message, {this.detail});

  @override
  String toString() => 'InstallException[$code]: $message';
}

/// Runtime 安装器
class RuntimeInstaller {
  final RuntimeEnvironment _env;
  final InstallProgressCallback? _onProgress;

  RuntimeInstaller(this._env, [this._onProgress]);

  /// 安装单个工具
  Future<InstallResult> install(RuntimeTool tool) async {
    _report(tool, InstallPhase.pending, 0, '准备安装...');

    try {
      // 检查架构支持
      if (!ArtifactManager.isSupportedArchitecture()) {
        final arch = ArtifactManager.getArchitectureName();
        throw InstallException(
          InstallErrorCode.archNotSupported,
          '当前设备架构 ($arch) 暂不支持',
          detail: 'Node.js Runtime 仅支持 arm64-v8a / aarch64',
        );
      }

      // 检查清单
      final manifest = RuntimeManifest.forTool(tool);
      if (manifest == null) {
        return InstallResult(
          tool: tool,
          success: false,
          errorMessage: '暂不支持自动安装',
          phase: InstallPhase.failed,
        );
      }

      switch (tool) {
        case RuntimeTool.node:
          return await _installNode(manifest);
        default:
          return InstallResult(
            tool: tool,
            success: false,
            errorMessage: '暂不支持自动安装',
            phase: InstallPhase.failed,
          );
      }
    } on InstallException catch (e) {
      _report(tool, InstallPhase.failed, 0, e.message);
      return InstallResult(
        tool: tool,
        success: false,
        errorMessage: e.message,
        phase: InstallPhase.failed,
      );
    } catch (e) {
      _report(tool, InstallPhase.failed, 0, '安装失败: $e');
      return InstallResult(
        tool: tool,
        success: false,
        errorMessage: e.toString(),
        phase: InstallPhase.failed,
      );
    }
  }

  /// 一键安装所有 Coding Runtime（按依赖顺序）
  Future<List<InstallResult>> installCodingRuntime() async {
    final order = RuntimeDependency.installOrder();
    final results = <InstallResult>[];

    for (final tool in order) {
      final dep = RuntimeDependency.forTool(tool);
      if (dep == null || dep.category != RuntimeCategory.coding) continue;
      if (dep.optional) continue;

      // 跳过已安装的
      if (_env.isToolInstalled(tool)) {
        results.add(InstallResult(
          tool: tool,
          success: true,
          version: '已安装',
        ));
        continue;
      }

      // 检查依赖是否满足
      final missingDep = dep.dependencies
          .where((d) => !_env.isToolInstalled(d))
          .toList();
      if (missingDep.isNotEmpty) {
        results.add(InstallResult(
          tool: tool,
          success: false,
          errorMessage: '⛔ 需要先安装: ${missingDep.map((d) => d.name).join(", ")}',
          phase: InstallPhase.failed,
        ));
        break;
      }

      final result = await install(tool);
      results.add(result);
      if (!result.success) break;
    }

    return results;
  }

  /// ─── Node.js 安装 ──────────────────────────────────────────────

  Future<InstallResult> _installNode(RuntimeManifest manifest) async {
    final targetDir = _env.nodeDir;

    // 确保目标目录存在
    await Directory(targetDir).create(recursive: true);

    // 下载并提取每个 artifact
    int completed = 0;
    final total = manifest.artifacts.length;

    for (final artifact in manifest.artifacts) {
      _report(
        RuntimeTool.node,
        InstallPhase.downloading,
        completed / total,
        '下载 ${artifact.name} ($completed/$total)...',
      );

      await ArtifactManager.downloadAndExtract(
        artifact: artifact,
        targetDir: targetDir,
        onProgress: (downloaded, totalSize, message) {
          final artifactProgress = downloaded / totalSize;
          final overallProgress =
              (completed + artifactProgress) / total;
          _report(
            RuntimeTool.node,
            InstallPhase.downloading,
            overallProgress,
            message,
          );
        },
      );

      completed++;
    }

    // ─── 健康检查 ───
    _report(RuntimeTool.node, InstallPhase.verifying, 0.9, '验证 Node.js...');

    // 设置 LD_LIBRARY_PATH 进行验证
    final nodeBin = '${_env.nodeBinDir}/node';
    final libDir = '${_env.nodeDir}/lib';
    final env = Map<String, String>.from(Platform.environment)..['LD_LIBRARY_PATH'] = libDir;

    final healthResult = await _healthCheck(nodeBin, env);

    if (healthResult.success) {
      _report(
        RuntimeTool.node,
        InstallPhase.completed,
        1.0,
        'Node.js ${healthResult.version} 安装完成',
      );
      return InstallResult(
        tool: RuntimeTool.node,
        success: true,
        version: healthResult.version,
      );
    } else {
      _report(
        RuntimeTool.node,
        InstallPhase.failed,
        0,
        healthResult.error ?? 'Node.js 验证失败',
      );
      return InstallResult(
        tool: RuntimeTool.node,
        success: false,
        errorMessage: healthResult.error ?? '健康检查失败',
        phase: InstallPhase.failed,
      );
    }
  }

  /// ─── 健康检查 ─────────────────────────────────────────────────

  /// 执行 node/npm 健康检查
  Future<NodeHealthResult> _healthCheck(
    String nodeBin,
    Map<String, String> env,
  ) async {
    try {
      // 1. 检查 node 文件是否存在
      final nodeFile = File(nodeBin);
      if (!nodeFile.existsSync()) {
        return NodeHealthResult(
          success: false,
          error: 'Node.js 二进制文件不存在',
        );
      }

      // 2. 检查 node --version
      final versionResult = await Process.run(
        nodeBin,
        ['--version'],
        environment: env,
      );

      if (versionResult.exitCode != 0) {
        return NodeHealthResult(
          success: false,
          error: 'node --version 执行失败: ${versionResult.stderr}',
        );
      }

      final version = (versionResult.stdout as String).trim();

      // 3. 检查 process.arch
      final archResult = await Process.run(
        nodeBin,
        ['-e', "console.log(process.arch)"],
        environment: env,
      );

      final arch = archResult.exitCode == 0
          ? (archResult.stdout as String).trim()
          : 'unknown';

      // 4. 检查 process.platform
      final platformResult = await Process.run(
        nodeBin,
        ['-e', "console.log(process.platform)"],
        environment: env,
      );

      final platform = platformResult.exitCode == 0
          ? (platformResult.stdout as String).trim()
          : 'unknown';

      // 5. 检查 npm --version
      final npmBin = path.join(path.dirname(nodeBin), 'npm');
      String? npmVersion;

      if (File(npmBin).existsSync()) {
        final npmResult = await Process.run(
          npmBin,
          ['--version'],
          environment: env,
        );
        if (npmResult.exitCode == 0) {
          npmVersion = (npmResult.stdout as String).trim();
        }
      }

      // 记录检测信息
      LogService.info('RuntimeInstaller', 'Node.js 健康检查结果:');
      LogService.info('RuntimeInstaller', '  version: $version');
      LogService.info('RuntimeInstaller', '  arch: $arch');
      LogService.info('RuntimeInstaller', '  platform: $platform');
      LogService.info('RuntimeInstaller', '  npm: ${npmVersion ?? "未找到"}');

      return NodeHealthResult(
        success: true,
        version: version,
        arch: arch,
        platform: platform,
        npmVersion: npmVersion,
      );
    } catch (e) {
      return NodeHealthResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// ─── 工具方法 ──────────────────────────────────────────────────

  void _report(RuntimeTool tool, InstallPhase phase, double progress,
      String message) {
    _onProgress?.call(tool, phase, progress, message);
    LogService.info('RuntimeInstaller', '[$tool] $message');
  }
}

/// Node.js 健康检查结果
class NodeHealthResult {
  final bool success;
  final String? version;
  final String? arch;
  final String? platform;
  final String? npmVersion;
  final String? error;

  const NodeHealthResult({
    required this.success,
    this.version,
    this.arch,
    this.platform,
    this.npmVersion,
    this.error,
  });
}
