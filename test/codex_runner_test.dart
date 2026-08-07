import 'dart:io';

import 'package:codex_mobile_pro/core/ai/codex_runner.dart';
import 'package:codex_mobile_pro/runtime/process/process_runner.dart';
import 'package:codex_mobile_pro/runtime/process/runner_models.dart';
import 'package:codex_mobile_pro/runtime/provider/linux_runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════
// 假执行器：不启动真实 PRoot/codex 进程，按配置输出假 JSONL 事件流
// （onStdoutChunk 回调必须手动调用，与真实 LocalProcessExecution 语义一致）
// ══════════════════════════════════════════════════════════════
class FakeLocalExecution extends LocalProcessExecution {
  final List<String> outputChunks;
  final int exitCode;
  final bool cancelledResult;

  /// 前 N 次 execute 返回「启动失败」（模拟 proot 路径失效 ENOENT）。
  final int failFirstCount;
  int executeCalls = 0;
  RuntimeProcessRequest? lastRequest;
  int cancelCalls = 0;

  FakeLocalExecution({
    this.outputChunks = const [],
    this.exitCode = 0,
    this.cancelledResult = false,
    this.failFirstCount = 0,
  });

  @override
  void requestCancel() {
    cancelCalls++;
    super.requestCancel();
  }

  @override
  Future<RuntimeProcessResult> execute(RuntimeProcessRequest request) async {
    executeCalls++;
    lastRequest = request;
    if (executeCalls <= failFirstCount) {
      return RuntimeProcessResult(
        exitCode: -1,
        error: '可执行文件不存在: ${request.executable}',
        request: request,
      );
    }
    for (final chunk in outputChunks) {
      request.onStdoutChunk?.call(chunk);
    }
    return RuntimeProcessResult(
      exitCode: exitCode,
      stdout: outputChunks.join(),
      cancelled: cancelledResult,
      request: request,
    );
  }
}

/// 收集事件的监听器
class RecordingListener implements CodexEventListener {
  final List<CodexEvent> events = [];
  int? exitCode;

  @override
  void onCodexEvent(CodexEvent event) => events.add(event);

  @override
  void onCodexExit(int code) => exitCode = code;
}

class FakeRootfs {
  final Directory rootfs;
  final bool hasCodex;
  final String? apiKey;

  FakeRootfs._(this.rootfs, {required this.hasCodex, this.apiKey});

  static Future<FakeRootfs> create({
    bool hasCodex = true,
    String? apiKey = 'test-key-123',
  }) async {
    final rootfs = await Directory.systemTemp.createTemp('codex-rootfs-test');
    if (hasCodex) {
      final codex = File('${rootfs.path}/usr/local/bin/codex');
      await codex.create(recursive: true);
    }
    if (apiKey != null) {
      final envFile = File('${rootfs.path}/root/.mimo2codex/.env');
      await envFile.create(recursive: true);
      await envFile.writeAsString('DS_API_KEY=$apiKey\n');
    }
    return FakeRootfs._(rootfs, hasCodex: hasCodex, apiKey: apiKey);
  }

  LinuxRuntimeProvider provider() => LinuxRuntimeProvider(
    paths: LinuxRuntimePaths(
      prootExecutable: '/fake/proot',
      rootfsDir: rootfs.path,
      loaderPath: '/fake/loader',
    ),
  );

  Future<void> dispose() async {
    if (rootfs.existsSync()) {
      await rootfs.delete(recursive: true);
    }
  }
}

void main() {
  group('CodexRunner.run', () {
    late FakeRootfs fakeRootfs;
    late Directory workspace;

    setUp(() async {
      fakeRootfs = await FakeRootfs.create();
      workspace = await Directory.systemTemp.createTemp('codex-ws-test');
    });

    tearDown(() async {
      await fakeRootfs.dispose();
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    });

    test('解析完整 JSONL 事件流并正确回调监听器', () async {
      const jsonl = '''
{"type":"thread.started","thread_id":"019fabc123"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"你好，"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"我是 Codex。"}}
{"type":"item.started","item":{"id":"item_2","type":"command_execution","command":"/bin/bash -lc ls","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/bash -lc ls","aggregated_output":"hello.txt\\n","exit_code":0,"status":"completed"}}
{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":5}}
''';

      final inner = FakeLocalExecution(outputChunks: [jsonl]);
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        inner: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: '列出目录',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(result.isSuccess, isTrue);
      expect(result.exitCode, 0);
      expect(result.threadId, '019fabc123');

      // 事件类型序列
      final types = listener.events.map((e) => e.runtimeType).toList();
      expect(
        types,
        containsAllInOrder([
          CodexThreadStarted,
          CodexTurnStarted,
          CodexAgentMessage,
          CodexAgentMessage,
          CodexCommandStarted,
          CodexCommandCompleted,
          CodexTurnCompleted,
        ]),
      );

      // agent 文本拼接
      final texts = listener.events
          .whereType<CodexAgentMessage>()
          .map((e) => e.text)
          .join();
      expect(texts, '你好，我是 Codex。');

      // command 事件字段
      final started = listener.events
          .whereType<CodexCommandStarted>()
          .single;
      expect(started.id, 'item_2');
      expect(started.command, contains('ls'));

      final completed = listener.events
          .whereType<CodexCommandCompleted>()
          .single;
      expect(completed.exitCode, 0);
      expect(completed.output, contains('hello.txt'));
    });

    test('跨 chunk 边界正确行缓冲（JSON 行被拆开）', () async {
      const line1 =
          '{"type":"thread.started","thread_id":"abc-1"}\n';
      // 单个 agent_message JSON 行，后面跟随真实换行
      const line2 =
          '{"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"跨chunk文本"}}';
      const line3 = '\n';
      const line4 =
          '{"type":"turn.completed"}\n';

      // 故意把 line2（一个完整 JSON 行）拆成两半，模拟 stdout 分段到达
      final inner = FakeLocalExecution(outputChunks: [
        line1 + line2.substring(0, 30),
        line2.substring(30) + line3 + line4,
      ]);
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        inner: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(result.isSuccess, isTrue);
      expect(listener.events.whereType<CodexThreadStarted>().single.threadId,
          'abc-1');
      final texts = listener.events
          .whereType<CodexAgentMessage>()
          .map((e) => e.text)
          .join();
      expect(texts, '跨chunk文本');
      expect(listener.events.whereType<CodexTurnCompleted>(), hasLength(1));
    });

    test('未安装 codex → 返回错误且不执行进程', () async {
      final noCodex = await FakeRootfs.create(hasCodex: false);
      addTearDown(noCodex.dispose);

      final inner = FakeLocalExecution(outputChunks: ['x']);
      final runner = CodexRunner(
        provider: noCodex.provider(),
        inner: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(result.exitCode, -1);
      expect(result.error, contains('Codex CLI 未安装'));
      // 未执行进程：没有 stdout 事件，且 execute 未被调用
      expect(listener.events, isEmpty);
    });

    test('API key 缺失 → 返回错误', () async {
      final noKey = await FakeRootfs.create(apiKey: null);
      addTearDown(noKey.dispose);

      final inner = FakeLocalExecution(outputChunks: ['x']);
      final runner = CodexRunner(
        provider: noKey.provider(),
        inner: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(result.exitCode, -1);
      expect(result.error, contains('DeepSeek API Key'));
    });

    test('自动创建宿主工作目录并绑定到 /workspace', () async {
      final nested = Directory(
        '${workspace.path}/a/b/c',
      );
      final inner = FakeLocalExecution();
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        inner: inner,
      );

      await runner.run(
        prompt: 'hi',
        hostWorkingDir: nested.path,
        listener: RecordingListener(),
      );

      expect(nested.existsSync(), isTrue);
      // 校验组装好的 proot 参数：绑定 host→/workspace，工作目录 /workspace
      final request = inner.lastRequest!;
      expect(request.executable, '/fake/proot');
      final args = request.arguments;
      expect(args, contains('-r'));
      expect(args[args.indexOf('-r') + 1], fakeRootfs.rootfs.path);
      // prootBindArguments 里已有 -b /proc -b /dev -b /sys，
      // 最后的绑定是 -b <host> /workspace；-w 后是 /workspace
      expect(args, contains('-b'));
      final wsIdx = args.indexOf('/workspace');
      expect(wsIdx, greaterThan(0));
      expect(args[wsIdx - 1], nested.path);
      expect(args, contains('-w'));
      expect(args[args.indexOf('-w') + 1], '/workspace');
      // 环境变量注入
      expect(request.environment?['DEEPSEEK_API_KEY'], 'test-key-123');
      expect(request.environment?['CODEX_PROMPT'], contains('hi'));
    });

    test('非零退出码传播', () async {
      final inner = FakeLocalExecution(
        outputChunks: ['{"type":"thread.started","thread_id":"t1"}\n'],
        exitCode: 2,
      );
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        inner: inner,
      );

      final result = await runner.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: RecordingListener(),
      );

      expect(result.exitCode, 2);
      expect(result.isSuccess, isFalse);
    });

    test('取消结果透传（cancelled=true）', () async {
      final inner = FakeLocalExecution(cancelledResult: true);
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        inner: inner,
      );

      final result = await runner.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: RecordingListener(),
      );

      expect(result.cancelled, isTrue);
    });

    test('stop() 转发到内部执行器取消', () async {
      final inner = FakeLocalExecution();
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        inner: inner,
      );

      runner.stop();
      runner.stop();

      // 每次 stop() 都转发到内部执行器的 requestCancel（幂等，Completer 只 complete 一次）
      expect(inner.cancelCalls, 2);
    });

    test('proot 启动失败（路径失效）→ 刷新路径缓存后自动重试一次成功', () async {
      const jsonl = '''
{"type":"thread.started","thread_id":"019fretry"}
{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}
''';
      final inner = FakeLocalExecution(
        outputChunks: [jsonl],
        failFirstCount: 1,
      );
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        inner: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: '重试',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(inner.executeCalls, 2, reason: '首次启动失败后应自动重试一次');
      expect(result.isSuccess, isTrue);
      expect(listener.events, isNotEmpty);
    });

    test('proot 启动失败且重试仍失败 → 如实返回启动失败（不无限重试）', () async {
      final inner = FakeLocalExecution(failFirstCount: 5);
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        inner: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: '重试仍失败',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(inner.executeCalls, 2, reason: '只重试一次，不再无限重试');
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('启动 codex 失败'));
    });
  });
}
