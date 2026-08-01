/// ====================================================================
/// LinuxExecutionAdapter 诊断与启动失败测试
///
/// 覆盖（Phase 9 — exit=-1 空输出根因回归）：
///   1. proot 缺失 → 错误包含关键文件状态（proot/loader/bash）
///   2. proot 存在但无执行位 / bash 缺失 → 未就绪错误可诊断
///   3. 完整就绪 + inner 启动失败 → error 保留原始 ProcessException
///      原因并追加 [诊断] 文件状态
///
/// 全部使用注入的 LinuxRuntimePaths + 临时目录，不依赖真实 Termux。
/// ====================================================================
library;

import 'dart:io';

import 'package:codex_mobile_pro/runtime/process/linux_execution.dart';
import 'package:codex_mobile_pro/runtime/process/runner_models.dart';
import 'package:codex_mobile_pro/runtime/provider/linux_runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在临时目录构建最小 Linux Runtime 路径结构
LinuxRuntimePaths fakePaths(Directory root) {
  final runtimeDir = Directory('${root.path}/runtime');
  final rootfsDir = Directory('${runtimeDir.path}/ubuntu/rootfs');
  final binDir = Directory('${runtimeDir.path}/ubuntu/bin');
  final libexecDir = Directory('${runtimeDir.path}/ubuntu/libexec');
  runtimeDir.createSync(recursive: true);
  rootfsDir.createSync(recursive: true);
  binDir.createSync(recursive: true);
  libexecDir.createSync(recursive: true);
  // loader 父目录（libexec/proot）也必须存在，否则写 loader 文件时
  // PathNotFoundException (errno=2)
  Directory('${libexecDir.path}/proot').createSync(recursive: true);

  return LinuxRuntimePaths(
    prootExecutable: '${binDir.path}/proot',
    rootfsDir: rootfsDir.path,
    loaderPath: '${libexecDir.path}/proot/loader',
  );
}

/// 模拟 inner 执行失败（等价于 Process.start 抛 ProcessException）
class _FailingAdapter implements IExecutionAdapter {
  final String message;

  _FailingAdapter(this.message);

  @override
  String get id => 'failing';

  @override
  bool supports(RuntimeProcessRequest request) => true;

  @override
  Future<RuntimeProcessResult> execute(RuntimeProcessRequest request) async =>
      RuntimeProcessResult(exitCode: -1, error: message, request: request);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('linux_exec_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('LinuxExecutionAdapter 未就绪诊断', () {
    test('proot 缺失 → 错误包含 proot/loader/bash 状态', () async {
      final paths = fakePaths(tmp);
      final adapter = LinuxExecutionAdapter(
        LinuxRuntimeProvider(paths: paths),
      );

      final result = await adapter.execute(
        const RuntimeProcessRequest(
          runtimeId: 'linux',
          executable: '/usr/bin/apt-get',
          arguments: ['update'],
        ),
      );

      expect(result.exitCode, -1);
      expect(result.failedToStart, isTrue);
      expect(result.error, contains('Linux Runtime 未初始化'));
      expect(result.error, contains('[proot] null'));
      expect(result.error, contains('[loader] null'));
      expect(result.error, contains('[bash] 缺失'));
    });

    test('proot 存在但 bash 缺失 → 未就绪且给出文件状态', () async {
      final paths = fakePaths(tmp);
      File(paths.prootExecutable).writeAsStringSync('fake-proot');
      final adapter = LinuxExecutionAdapter(
        LinuxRuntimeProvider(paths: paths),
      );

      final result = await adapter.execute(
        const RuntimeProcessRequest(
          runtimeId: 'linux',
          executable: '/usr/bin/apt-get',
        ),
      );

      expect(result.failedToStart, isTrue);
      // proot 文件已存在（状态包含 exec 位信息），bash 缺失
      expect(result.error, contains('[proot] type=file'));
      expect(result.error, contains('[bash] 缺失'));
    });
  });

  group('LinuxExecutionAdapter 启动失败诊断', () {
    test('inner 启动失败 → 保留原始原因并追加 [诊断] 文件状态', () async {
      final paths = fakePaths(tmp);
      // 完整就绪：proot + loader + rootfs bash
      File(paths.prootExecutable).writeAsStringSync('proot');
      File(paths.loaderPath).writeAsStringSync('loader');
      final bashDir = Directory('${paths.rootfsDir}/usr/bin');
      bashDir.createSync(recursive: true);
      File('${bashDir.path}/bash').writeAsStringSync('bash');

      final adapter = LinuxExecutionAdapter(
        LinuxRuntimeProvider(paths: paths),
        inner: _FailingAdapter('权限不足: ${paths.prootExecutable} (errno=13)'),
      );

      final result = await adapter.execute(
        const RuntimeProcessRequest(
          runtimeId: 'linux',
          executable: '/usr/bin/apt-get',
          arguments: ['update'],
        ),
      );

      expect(result.exitCode, -1);
      // 原始 ProcessException 原因必须保留（不能被吞）
      expect(result.error, contains('权限不足'));
      expect(result.error, contains('errno=13'));
      // 诊断文件状态必须存在
      expect(result.error, contains('[诊断] proot='));
      expect(result.error, contains('[诊断] loader='));
      expect(result.error, contains('[诊断] bash='));
    });
  });
  group('LinuxExecutionAdapter 宿主端临时目录（PROOT_TMP_DIR）', () {
    test('PRoot 进程环境包含 PROOT_TMP_DIR=<rootfs>/tmp 且 rootfs/tmp 被创建', () async {
      final paths = readyPaths(tmp);
      // 明确删除 rootfs/tmp，验证 execute 会自动重建
      final rootfsTmp = Directory('${paths.rootfsDir}/tmp');
      if (rootfsTmp.existsSync()) rootfsTmp.deleteSync(recursive: true);

      final capture = _CaptureAdapter();
      final adapter = LinuxExecutionAdapter(
        LinuxRuntimeProvider(paths: paths),
        inner: capture,
      );

      final result = await adapter.execute(
        const RuntimeProcessRequest(
          runtimeId: 'linux',
          executable: '/usr/bin/node',
          arguments: ['--version'],
        ),
      );

      expect(result.exitCode, 0);
      final env = capture.lastRequest!.environment!;
      // 宿主端 PRoot 专用临时目录：必须指向真实存在的 rootfs/tmp
      expect(env['PROOT_TMP_DIR'], '${paths.rootfsDir}/tmp');
      expect(Directory(env['PROOT_TMP_DIR']!).existsSync(), isTrue,
          reason: 'PROOT_TMP_DIR 指向的目录必须真实存在');
      // guest 内 TMPDIR 保持 /tmp（不改变 Ubuntu 内 apt/dpkg/npm 行为）
      expect(env['TMPDIR'], '/tmp');
      // PRoot 自身 argv 不含 PROOT_TMP_DIR（那是宿主进程环境变量）
      final args = capture.lastRequest!.arguments.join(' ');
      expect(args, isNot(contains('PROOT_TMP_DIR')));
    });
  });
}

/// 捕获 wrapped request（验证 PROOT_TMP_DIR 等环境注入）
class _CaptureAdapter implements IExecutionAdapter {
  RuntimeProcessRequest? lastRequest;

  @override
  String get id => 'capture';

  @override
  bool supports(RuntimeProcessRequest request) => true;

  @override
  Future<RuntimeProcessResult> execute(RuntimeProcessRequest request) async {
    lastRequest = request;
    return RuntimeProcessResult(exitCode: 0, stdout: 'ok', request: request);
  }
}

/// 完整就绪的最小 Linux Runtime（proot + loader + rootfs bash + rootfs/tmp）
LinuxRuntimePaths readyPaths(Directory root) {
  final paths = fakePaths(root);
  File(paths.prootExecutable).writeAsStringSync('proot');
  File(paths.loaderPath).writeAsStringSync('loader');
  final bashDir = Directory('${paths.rootfsDir}/usr/bin');
  bashDir.createSync(recursive: true);
  File('${bashDir.path}/bash').writeAsStringSync('bash');
  return paths;
}
