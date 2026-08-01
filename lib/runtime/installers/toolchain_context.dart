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
import 'apt_source_manager.dart';

/// 工具链安装上下文
class ToolchainContext {
  final RuntimeProcessRunner _runner;
  final LinuxRuntimeProvider? _linux;
  final LinuxRuntimePaths? _injectedPaths;

  /// 同一轮安装中 `apt-get update` 是否已成功执行（幂等）
  bool aptUpdated = false;

  /// 同一轮安装中 `dpkg` 是否已确认健康（幂等）
  bool dpkgHealthy = false;

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

  /// 确保 dpkg 状态健康（幂等：同轮已确认则不重复执行）。
  ///
  /// 真机曾出现 dpkg interrupted（apt 安装中断遗留），此时 apt-get
  /// install 会直接报 `dpkg was interrupted` 而失败。修复方式：
  ///   dpkg --audit → 发现 interrupted → dpkg --configure -a → 复验。
  /// 禁止删除 /var/lib/dpkg/lock 等危险方式绕过。
  ///
  /// 失败抛 DeployError(aptInstallFailed)（与安装同错误族），
  /// 保留真实 exit/stdout/stderr 便于诊断。
  Future<void> ensureDpkgHealthy() async {
    if (dpkgHealthy) return;

    // 1. 审计
    final audit = await runInRootfs(
      '/usr/bin/dpkg',
      arguments: const ['--audit'],
      timeout: const Duration(seconds: 60),
      label: 'dpkg:audit',
    );
    final auditText = '${audit.stderr}\n${audit.stdout}';
    final interrupted = audit.exitCode != 0 ||
        auditText.toLowerCase().contains('interrupted') ||
        auditText.toLowerCase().contains('in a mess') ||
        auditText.toLowerCase().contains('serious problems') ||
        auditText.toLowerCase().contains('requires manual intervention');

    if (!interrupted) {
      dpkgHealthy = true;
      return;
    }

    // 2. 修复
    LogService.warning(
      'Toolchain',
      'dpkg interrupted 检测到，执行 dpkg --configure -a',
    );
    final fix = await runInRootfs(
      '/usr/bin/dpkg',
      arguments: const ['--configure', '-a'],
      timeout: const Duration(minutes: 5),
      label: 'dpkg:configure-a',
    );
    if (!fix.isSuccess) {
      throw DeployError(
        code: DeployErrorCode.aptInstallFailed,
        message: 'dpkg 修复失败（interrupted 状态无法恢复）',
        detail: 'exit=${fix.exitCode}\n'
            'stdout: ${fix.stdout.trim()}\n'
            'stderr: ${fix.stderr.trim()}',
        userSuggestion: '尝试重新初始化 Linux Runtime 后重试',
        context: {'command': 'dpkg --configure -a'},
      );
    }

    // 3. 复验
    final reAudit = await runInRootfs(
      '/usr/bin/dpkg',
      arguments: const ['--audit'],
      timeout: const Duration(seconds: 60),
      label: 'dpkg:reaudit',
    );
    final reText = '${reAudit.stderr}\n${reAudit.stdout}';
    final stillInterrupted = reAudit.exitCode != 0 ||
        reText.toLowerCase().contains('interrupted') ||
        reText.toLowerCase().contains('in a mess');
    if (stillInterrupted) {
      throw DeployError(
        code: DeployErrorCode.aptInstallFailed,
        message: 'dpkg 修复后仍存在 interrupted 状态',
        detail: reText,
        userSuggestion: '尝试重新初始化 Linux Runtime 后重试',
        context: {'command': 'dpkg --audit'},
      );
    }

    LogService.info('Toolchain', 'dpkg interrupted 已修复');
    dpkgHealthy = true;
  }

  /// 执行 `apt-get update`（幂等：同轮已成功则不重复执行）。
  ///
  /// 失败时若判定为网络获取失败（TCP/HTTP 无法连接镜像），自动按
  /// fallback 链切换 apt 源重试；全部失败抛 DeployError(aptUpdateFailed)。
  Future<void> ensureAptUpdated() async {
    if (aptUpdated) return;
    await _runWithAptSourceFallback(
      arguments: const ['update'],
      label: 'apt:update',
      failureCode: DeployErrorCode.aptUpdateFailed,
      failureMessage: 'Ubuntu apt 源更新失败',
      failureSuggestion: '请检查网络后重试；若持续失败可切换 Ubuntu 镜像源',
      timeout: const Duration(minutes: 10),
      context: {'command': 'apt-get update'},
    );
    aptUpdated = true;
  }

  /// 执行 apt-get install -y packages（rootfs 内）。
  ///
  /// 失败抛 DeployError(aptInstallFailed)，保留 exitCode/stdout/stderr。
  /// 若下载阶段网络失败（如 `E: Failed to fetch ... exit=100`），
  /// 自动切换备用 apt 源重试（每个源独立执行 update + install 验证）。
  Future<void> aptInstall(
    List<String> packages, {
    Duration? timeout,
  }) async {
    await ensureDpkgHealthy();
    await ensureAptUpdated();
    await _runWithAptSourceFallback(
      arguments: ['install', '-y', ...packages],
      label: 'apt:install:${packages.join(",")}',
      failureCode: DeployErrorCode.aptInstallFailed,
      failureMessage: 'Ubuntu 包安装失败: ${packages.join(', ')}',
      failureSuggestion: '可尝试重新初始化后重试，或检查 apt 源是否可用',
      timeout: timeout ?? const Duration(minutes: 15),
      context: {
        'packages': packages,
        'command': 'apt-get install -y ${packages.join(' ')}',
      },
    );
  }

  /// 带 apt 源 fallback 的命令执行（apt-get update / install 共用）。
  ///
  /// 流程：
  ///   1. 用当前 rootfs 内源直接执行；成功即返回（不改写 rootfs）。
  ///   2. 失败且判定为网络获取失败 → 依次切换 fallback 源：
  ///      writeSource → apt-get update（独立验证 TCP/HTTPS + 索引）
  ///      → 重试原命令（独立验证 .deb 下载/安装）。
  ///   3. 全部失败 → 抛 DeployError，message 使用
  ///      「APT 下载失败 / 无法连接 Ubuntu 镜像」真实网络分类。
  Future<void> _runWithAptSourceFallback({
    required List<String> arguments,
    required String label,
    required DeployErrorCode failureCode,
    required String failureMessage,
    String? failureSuggestion,
    required Duration timeout,
    required Map<String, dynamic> context,
  }) async {
    final paths = await resolvePaths();
    final aptSource = AptSourceManager(paths.rootfsDir);
    final command = 'apt-get ${arguments.join(' ')}';

    var result = await runInRootfs(
      '/usr/bin/apt-get',
      arguments: arguments,
      timeout: timeout,
      label: label,
    );
    if (result.isSuccess) return;

    // 非网络获取失败（keyring/依赖冲突/包不存在等）→ 不切换源，直接报错
    if (!isAptFetchFailure(result)) {
      throw _aptFailure(
        code: failureCode,
        message: failureMessage,
        result: result,
        command: command,
        context: context,
        suggestion: failureSuggestion,
      );
    }

    // 网络获取失败 → 备用源逐一尝试
    final currentUri = await aptSource.readCurrentUri();
    final chain = aptSource.buildFallbackChain(currentUri: currentUri);
    LogService.info(
      'Toolchain',
      'apt 网络获取失败，尝试备用源(${chain.length} 个): '
          '${chain.map((e) => e.name).join(', ')}',
    );

    final attempted = <String>[];
    const updateTimeout = Duration(minutes: 3);
    const attemptTimeout = Duration(minutes: 5);
    for (final src in chain) {
      try {
        await aptSource.writeSource(src);
      } catch (e) {
        LogService.warning('Toolchain', '写入 apt 源失败(尝试下一个): $e');
        continue;
      }
      attempted.add('${src.name}(${src.baseUri})');

      // 每个源独立验证：先 update（TCP/HTTPS + 索引下载）
      final update = await runInRootfs(
        '/usr/bin/apt-get',
        arguments: const ['update'],
        timeout: updateTimeout,
        label: 'apt:update:${src.name}',
      );
      if (!update.isSuccess) {
        result = update;
        continue;
      }

      // 再执行原命令（.deb 下载 + 安装）
      result = await runInRootfs(
        '/usr/bin/apt-get',
        arguments: arguments,
        timeout: attemptTimeout,
        label: '$label:${src.name}',
      );
      if (result.isSuccess) {
        LogService.info(
          'Toolchain',
          'apt 备用源 ${src.name} 执行成功（rootfs 源已切换）',
        );
        return;
      }
      // 该源可用但命令仍失败：
      //   - 再次网络失败 → 尝试下一个源
      //   - 其他错误（如包冲突）→ 立即上报，避免在错误的源上反复重试
      if (!isAptFetchFailure(result)) {
        break;
      }
    }

    throw _aptFailure(
      code: failureCode,
      message: failureMessage,
      result: result,
      command: command,
      context: context,
      network: true,
      attemptedSources: attempted,
    );
  }

  /// 构建 apt 失败 DeployError（含真实网络分类文案）。
  DeployError _aptFailure({
    required DeployErrorCode code,
    required String message,
    required RuntimeProcessResult result,
    required String command,
    required Map<String, dynamic> context,
    String? suggestion,
    bool network = false,
    List<String> attemptedSources = const [],
  }) {
    final buf = StringBuffer()
      ..writeln('exit=${result.exitCode}')
      ..writeln('command: $command');
    if (result.error != null && result.error!.isNotEmpty) {
      buf.writeln('启动错误: ${result.error}');
    }
    if (result.stdout.trim().isNotEmpty) {
      buf.writeln('stdout: ${result.stdout.trim()}');
    }
    if (result.stderr.trim().isNotEmpty) {
      buf.writeln('stderr: ${result.stderr.trim()}');
    }
    if (attemptedSources.isNotEmpty) {
      buf.writeln('已尝试源: ${attemptedSources.join(' → ')}');
    }
    final fullContext = Map<String, dynamic>.from(context)
      ..['aptSourceFallback'] = attemptedSources;
    return DeployError(
      code: code,
      message: network ? kAptNetworkFailure : message,
      detail: buf.toString(),
      userSuggestion: network
          ? kAptNetworkSuggestion
          : (suggestion ?? DeployErrorSuggestions.forCode(code)),
      context: fullContext,
    );
  }

  /// 判断 apt 失败是否为网络获取失败（无法连接镜像 / 索引或包下载失败）。
  ///
  /// 只在 stderr/stdout 中出现真实网络症状时返回 true，避免把
  /// keyring、依赖冲突、包不存在等本地错误误判为网络问题。
  static bool isAptFetchFailure(RuntimeProcessResult result) {
    final text = '${result.stderr}\n${result.stdout}'.toLowerCase();
    const patterns = [
      'failed to fetch',
      'unable to fetch some archives',
      'unable to connect',
      'could not resolve',
      'temporary failure resolving',
      'name or service not known',
      'connection timed out',
      'connection refused',
      'connection reset',
      'connection closed',
      'network is unreachable',
      'no route to host',
      'could not connect',
      'failed to connect',
    ];
    return patterns.any(text.contains);
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
