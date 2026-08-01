/// ====================================================================
/// Coding Runtime 工具链安装上下文
///
/// 统一承载工具链安装所需的执行通道与状态：
///   1. 所有命令经 RuntimeProcessRunner + LinuxExecutionAdapter
///      （runtimeId='linux' → PRoot → Ubuntu rootfs），不依赖 Termux
///   2. `apt-get update` 在同一轮安装中只执行一次（aptUpdated 幂等）
///   3. 可注入 LinuxRuntimePaths / FakeAdapter 便于单元测试
///
/// 执行约定：
///   - [executable] 使用 rootfs 内路径（如 /usr/bin/apt-get），
///     由 LinuxExecutionAdapter 统一生成 PRoot 参数
///   - 禁止在业务层拼接 PRoot 参数
/// ====================================================================
library;

import 'dart:io';

import '../../core/logger/log_service.dart';
import '../deploy_error.dart';
import '../process/process_runner.dart';
import '../process/runner_models.dart';
import '../provider/linux_runtime_provider.dart';

/// 工具链安装上下文
class ToolchainContext {
  final RuntimeProcessRunner _runner;
  final LinuxRuntimeProvider? _linux;
  final LinuxRuntimePaths? _injectedPaths;

  /// 同一轮安装中 `apt-get update` 是否已成功执行（幂等）
  bool aptUpdated = false;

  ToolchainContext({
    required RuntimeProcessRunner runner,
    LinuxRuntimeProvider? linux,
    LinuxRuntimePaths? injectedPaths,
  })  : _runner = runner,
        _linux = linux,
        _injectedPaths = injectedPaths;

  /// 解析 Linux Runtime 路径（懒加载）
  Future<LinuxRuntimePaths> resolvePaths() async {
    if (_injectedPaths != null) return _injectedPaths;
    final linux = _linux;
    if (linux == null) {
      throw StateError('ToolchainContext: 无 LinuxRuntimeProvider');
    }
    return linux.resolvePaths();
  }

  /// Linux Runtime 是否就绪（proot + rootfs bash 均存在）
  Future<bool> isLinuxReady() async {
    try {
      final paths = await resolvePaths();
      final prootOk = File(paths.prootExecutable).existsSync();
      final bashOk = File('${paths.rootfsDir}/usr/bin/bash').existsSync() ||
          File('${paths.rootfsDir}/bin/bash').existsSync();
      return prootOk && bashOk;
    } catch (_) {
      return false;
    }
  }

  /// 在 Ubuntu rootfs 内执行命令（经 PRoot）
  ///
  /// [executable] 为 rootfs 内路径（/usr/bin/apt-get 等）。
  Future<RuntimeProcessResult> runInRootfs(
    String executable, {
    List<String> arguments = const [],
    Duration? timeout,
    String? label,
  }) async {
    await resolvePaths();
    return _runner.run(
      RuntimeProcessRequest(
        runtimeId: 'linux',
        executable: executable,
        arguments: arguments,
        timeout: timeout,
        label: label ?? executable,
      ),
    );
  }

  /// 查询 rootfs 内工具的版本（执行 executable 的 --version）
  ///
  /// 成功返回版本字符串（trim），失败返回 null。
  Future<String?> versionOf(
    String executable, {
    Duration? timeout,
  }) async {
    final result = await runInRootfs(
      executable,
      arguments: ['--version'],
      timeout: timeout ?? const Duration(seconds: 30),
      label: 'version:$executable',
    );
    if (result.isSuccess) {
      final out = result.stdout.trim();
      return out.isEmpty ? 'OK' : out;
    }
    LogService.debug(
      'Toolchain',
      'versionOf $executable 失败: '
      'exit=${result.exitCode} stderr=${result.stderr.trim()}',
    );
    return null;
  }

  /// 执行 `apt-get update`（幂等：同轮已成功则不重复执行）
  ///
  /// 失败抛 DeployError(aptUpdateFailed)。
  Future<void> ensureAptUpdated() async {
    if (aptUpdated) return;
    final result = await runInRootfs(
      '/usr/bin/apt-get',
      arguments: ['update'],
      timeout: const Duration(minutes: 10),
      label: 'apt:update',
    );
    if (!result.isSuccess) {
      throw DeployError(
        code: DeployErrorCode.aptUpdateFailed,
        message: 'Ubuntu apt 源更新失败',
        detail: 'exit=${result.exitCode}\n'
            '${result.error != null ? "启动错误: ${result.error}\n" : ""}'
            'stdout: ${result.stdout.trim()}\n'
            'stderr: ${result.stderr.trim()}',
        userSuggestion: '请检查网络后重试；若持续失败可切换 Ubuntu 镜像源',
        context: {'command': 'apt-get update'},
      );
    }
    aptUpdated = true;
  }

  /// 执行 apt-get install -y packages（rootfs 内）
  ///
  /// 失败抛 DeployError(aptInstallFailed)，保留 exitCode/stdout/stderr。
  Future<void> aptInstall(
    List<String> packages, {
    Duration? timeout,
  }) async {
    await ensureAptUpdated();
    final result = await runInRootfs(
      '/usr/bin/apt-get',
      arguments: ['install', '-y', ...packages],
      timeout: timeout ?? const Duration(minutes: 15),
      label: 'apt:install:${packages.join(",")}',
    );
    if (!result.isSuccess) {
      throw DeployError(
        code: DeployErrorCode.aptInstallFailed,
        message: 'Ubuntu 包安装失败: ${packages.join(', ')}',
        detail: 'exit=${result.exitCode}\n'
            '${result.error != null ? "启动错误: ${result.error}\n" : ""}'
            'stdout: ${result.stdout.trim()}\n'
            'stderr: ${result.stderr.trim()}',
        userSuggestion: '可尝试重新初始化后重试，或检查 apt 源是否可用',
        context: {
          'packages': packages,
          'command': 'apt-get install -y ${packages.join(' ')}',
        },
      );
    }
  }

  /// 执行 npm 全局安装（rootfs 内）：npm install -g packages...
  ///
  /// 失败抛 DeployError(npmInstallFailed)，保留 exitCode/stdout/stderr。
  Future<void> npmInstallGlobal(
    List<String> packages, {
    Duration? timeout,
  }) async {
    final result = await runInRootfs(
      '/usr/bin/npm',
      arguments: ['install', '-g', '--no-fund', '--no-audit', ...packages],
      timeout: timeout ?? const Duration(minutes: 15),
      label: 'npm:install:${packages.join(",")}',
    );
    if (!result.isSuccess) {
      throw DeployError(
        code: DeployErrorCode.npmInstallFailed,
        message: 'npm 全局安装失败: ${packages.join(', ')}',
        detail: 'exit=${result.exitCode}\n'
            '${result.error != null ? "启动错误: ${result.error}\n" : ""}'
            'stdout: ${result.stdout.trim()}\n'
            'stderr: ${result.stderr.trim()}',
        userSuggestion: '请检查网络后重试',
        context: {
          'packages': packages,
          'command': 'npm install -g ${packages.join(' ')}',
        },
      );
    }
  }
}
