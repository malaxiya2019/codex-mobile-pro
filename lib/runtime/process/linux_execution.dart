/// ====================================================================
/// LinuxExecutionAdapter
///
/// 将 runtimeId='linux' 的请求包装为 PRoot 执行：
///   `proot -r rootfs -w cwd /bin/bash -lc '<command>'`
///
/// 职责：
///   1. 识别 runtimeId == 'linux' 的请求
///   2. 统一生成 PRoot 参数（禁止调用点拼接）
///   3. 将 rootfs 绝对路径转换为 rootfs 内路径（/usr/bin/node）
///   4. 委托 LocalProcessExecution 实际执行
///   5. Runtime 未就绪时返回结构化错误
///
/// 不依赖 Termux。PRoot 路径由 LinuxRuntimeProvider 统一提供。
/// ====================================================================
library;

import 'dart:io';

import '../../core/logger/log_service.dart';
import '../provider/linux_runtime_provider.dart';
import 'process_runner.dart';
import 'runner_models.dart';

/// Linux 执行适配器
class LinuxExecutionAdapter implements IExecutionAdapter {
  final LinuxRuntimeProvider _provider;
  final IExecutionAdapter _inner;

  LinuxExecutionAdapter(this._provider, {IExecutionAdapter? inner})
    : _inner = inner ?? LocalProcessExecution();

  @override
  String get id => 'linux';

  @override
  bool supports(RuntimeProcessRequest request) =>
      request.runtimeId == 'linux';

  @override
  Future<RuntimeProcessResult> execute(RuntimeProcessRequest request) async {
    // 修复 rootfs DNS（127.0.0.53 stub → 公共 DNS）与 apt IPv4 配置，
    // 否则 apt-get update 会因域名解析失败而报「Ubuntu apt 源更新失败」。
    await _provider.ensureResolvConf();
    await _provider.ensureAptIpv4Only();

    final paths = await _provider.resolvePaths();

    // ─── 关键文件状态（诊断用，不依赖 existsSync 猜测）──────────
    final prootStat = _statInfo(paths.prootExecutable);
    final loaderStat = _statInfo(paths.loaderPath);
    final bashPath = _firstExisting([
      '${paths.rootfsDir}/usr/bin/bash',
      '${paths.rootfsDir}/bin/bash',
    ]);
    final bashStat = bashPath != null ? _statInfo(bashPath) : '缺失';

    // ─── Runtime 未就绪 → 结构化错误（附真实文件状态）──────────
    final prootReady = prootStat != null;
    final loaderReady = loaderStat != null;
    final bashReady = bashPath != null;
    if (!prootReady || !bashReady || !loaderReady) {
      return RuntimeProcessResult(
        exitCode: -1,
        error: 'Linux Runtime 未初始化\n'
            '[proot] $prootStat\n'
            '[loader] $loaderStat\n'
            '[bash] $bashStat',
        request: request,
      );
    }

    // ─── 转换 rootfs 内路径 ────────────────────────────────────
    final innerExecutable = _toRootfsPath(paths.rootfsDir, request.executable);
    final command = [innerExecutable, ...request.arguments].join(' ');

    // ─── 统一生成 PRoot 参数 ───────────────────────────────────
    final arguments = <String>[
      '-r',
      paths.rootfsDir,
      ...LinuxRuntimeProvider.prootBindArguments(),
      if (request.workingDirectory != null) ...[
        '-w',
        request.workingDirectory!,
      ],
      '/bin/bash',
      '-lc',
      command,
    ];

    // ─── 环境合并：Linux 基础环境 + 请求覆盖 ───────────────────
    final environment = _provider.buildEnvironment(paths);
    if (request.environment != null) {
      environment.addAll(request.environment!);
    }

    final wrapped = RuntimeProcessRequest(
      executable: paths.prootExecutable,
      arguments: arguments,
      environment: environment,
      workingDirectory: request.workingDirectory,
      timeout: request.timeout,
      label: 'proot:${request.label ?? request.executable}',
    );

    final result = await _inner.execute(wrapped);

    // ─── 启动失败 → 记录完整诊断，避免真实原因被吞 ──────────────
    if (result.failedToStart) {
      LogService.error(
        'LinuxExec',
        'PRoot 启动失败: ${result.error}\n'
        'argv=${wrapped.executable} ${wrapped.arguments.join(' ')}\n'
        '[proot] $prootStat\n'
        '[loader] $loaderStat\n'
        '[bash] $bashStat',
      );
      return RuntimeProcessResult(
        exitCode: result.exitCode,
        error: '${result.error}\n'
            '[诊断] proot=$prootStat\n'
            '[诊断] loader=$loaderStat\n'
            '[诊断] bash=$bashStat',
        stdout: result.stdout,
        stderr: result.stderr,
        duration: result.duration,
        timedOut: result.timedOut,
        cancelled: result.cancelled,
        cleanupTimedOut: result.cleanupTimedOut,
        request: request,
      );
    }
    return result;
  }

  /// 返回文件状态摘要（type/size/mode/exec 位）；不存在返回 null
  static String? _statInfo(String p) {
    try {
      final stat = FileStat.statSync(p);
      if (stat.type == FileSystemEntityType.notFound) return null;
      final mode = stat.mode;
      final exec = (mode & 0x49) != 0; // owner/group/other exec 任一
      return 'type=${stat.type} size=${stat.size} '
          'mode=${mode.toRadixString(8)} exec=$exec';
    } catch (e) {
      return 'stat失败: $e';
    }
  }

  /// 返回第一个存在的路径（按顺序）
  static String? _firstExisting(List<String> candidates) {
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// 将 rootfs 绝对路径转换为 proot 内部路径
  ///
  /// 例：rootfs/usr/bin/node → /usr/bin/node
  /// 非 rootfs 前缀的路径原样保留（如 /bin/bash）。
  static String _toRootfsPath(String rootfsDir, String executable) {
    if (executable.startsWith(rootfsDir)) {
      final rel = executable.substring(rootfsDir.length);
      if (rel.isEmpty) return executable;
      return rel.startsWith('/') ? rel : '/$rel';
    }
    return executable;
  }
}
