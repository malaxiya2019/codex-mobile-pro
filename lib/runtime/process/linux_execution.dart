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
    // 内层命令：默认拼接 executable + arguments；设置 innerCommand 时
    // 原样使用（支持 exec 进程替换 / shell 重定向等特殊命令，如 codex）。
    final innerExecutable = _toRootfsPath(paths.rootfsDir, request.executable);
    final command =
        request.innerCommand ?? [innerExecutable, ...request.arguments].join(' ');

    // ─── 额外 bind：宿主目录映射进 guest（git 工作区等）────────
    //
    // request.extraBinds（格式 `hostPath[:guestPath]`）由业务层生成，
    // 用于把 Android 宿主目录挂载进 PRoot guest。目录型 bind 会
    // best-effort 在 rootfs 中创建 guest 目标，避免 PRoot 因目标
    // 不存在而回退（如 git clone 到 /sdcard/... 之前先建 /sdcard）。
    final extraBinds = request.extraBinds ?? const [];
    for (final bind in extraBinds) {
      final hostPath = bind.split(':').first;
      if (Directory(hostPath).existsSync()) {
        final guest = _guestPathOfBind(bind);
        try {
          Directory('${paths.rootfsDir}$guest').createSync(recursive: true);
        } catch (e) {
          LogService.debug('LinuxExec', '创建 bind guest 目录失败: $guest ($e)');
        }
      }
    }

    // ─── 统一生成 PRoot 参数 ───────────────────────────────────
    final arguments = <String>[
      '-r',
      paths.rootfsDir,
      ...LinuxRuntimeProvider.prootBindArguments(),
      for (final bind in extraBinds) ...[
        '-b',
        bind,
      ],
      if (request.workingDirectory != null) ...[
        '-w',
        request.workingDirectory!,
      ],
      '/bin/bash',
      '-lc',
      command,
    ];

    // ─── 环境合并：Linux 基础环境 + 请求覆盖 ───────────────────
    //
    // PRoot 宿主端临时目录修复：
    //   - buildEnvironment 中 TMPDIR=/tmp 是 guest（Ubuntu）内路径，正确。
    //   - 但宿主（Android）不存在 /tmp，PRoot 进程自身启动时会在 TMPDIR
    //     创建 f2fs bug probe / unix socket，导致
    //     `Unable to create temp directory for f2fs bug probe` warning。
    //   - 解决方案：为 PRoot 进程设置 PROOT_TMP_DIR=<rootfs>/tmp（宿主
    //     绝对路径，真实存在），PRoot 专用变量只影响 PRoot 自身，不传给
    //     guest，apt/dpkg/npm 在 Ubuntu 内仍使用 TMPDIR=/tmp。
    final hostTmpDir = '${paths.rootfsDir}/tmp';
    try {
      await Directory(hostTmpDir).create(recursive: true);
    } catch (e) {
      LogService.warning('LinuxExec', 'rootfs /tmp 创建失败: $e');
    }
    final environment = _provider.buildEnvironment(paths);
    environment['PROOT_TMP_DIR'] = hostTmpDir;
    if (request.environment != null) {
      environment.addAll(request.environment!);
    }

    // ─── 宿主端 cwd 守卫 ───────────────────────────────────────
    // request.workingDirectory 是 guest 路径（-w 已用），但 wrapped 请求
    // 会把它原样传给宿主 Process.start。若该路径在 Android 宿主不存在
    // （如 codex 的 /workspace 或 git 的 /sdcard/xxx 尚未创建），
    // Process.start 会抛 ENOENT，被误报为「可执行文件不存在」。
    // → 宿主端仅当目录真实存在时才透传；否则省略（PRoot -w 仍生效）。
    final hostCwd = (request.workingDirectory != null &&
            Directory(request.workingDirectory!).existsSync())
        ? request.workingDirectory
        : null;
    final wrapped = RuntimeProcessRequest(
      executable: paths.prootExecutable,
      arguments: arguments,
      environment: environment,
      workingDirectory: hostCwd,
      timeout: request.timeout,
      label: 'proot:${request.label ?? request.executable}',
      onStdoutChunk: request.onStdoutChunk,
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

  /// 提取 bind 串（`host[:guest]`）的 guest 路径。
  ///
  /// 无 `:` 时 guest 与 host 同路径；有 `:` 时取冒号后部分。
  static String _guestPathOfBind(String bind) {
    final idx = bind.lastIndexOf(':');
    if (idx == -1) return bind;
    return bind.substring(idx + 1);
  }
}
