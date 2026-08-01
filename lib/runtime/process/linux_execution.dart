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

    // ─── Runtime 未就绪 → 结构化错误 ───────────────────────────
    final prootReady = File(paths.prootExecutable).existsSync();
    final bashReady = File(
      '${paths.rootfsDir}/usr/bin/bash',
    ).existsSync() ||
        File('${paths.rootfsDir}/bin/bash').existsSync();
    if (!prootReady || !bashReady) {
      return RuntimeProcessResult(
        exitCode: -1,
        error: 'Linux Runtime 未初始化（proot=$prootReady, rootfs=$bashReady）',
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

    return _inner.execute(wrapped);
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
