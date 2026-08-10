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

  /// 启动失败时使用的错误信息（默认模拟 ENOENT；可注入「Linux Runtime
  /// 未初始化」验证明确提示映射）。
  String? failWithMessage;

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
        error: failWithMessage ?? '可执行文件不存在: ${request.executable}',
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

  /// proot/loader 可执行文件路径。与 rootfs 同处系统临时目录 —— 此前
  /// 写死 `/fake/proot` 在文件系统根创建，CI runner 非 root 无法写 `/`，
  /// 导致 setUp 抛 PathAccessException、全部用例失败。
  final String prootExecutable;
  final String loaderPath;

  /// 是否模拟「Runtime 已就绪」（proot/loader/bash 文件齐全）。
  ///
  /// true（默认）时 LinuxExecutionAdapter 的就绪检查通过，请求会
  /// 委托到内层执行器（FakeLocalExecution）；false 时这三个关键
  /// 文件缺失，适配器直接返回「Linux Runtime 未初始化」——用于验证
  /// 「Coding Runtime 未就绪」明确提示（新架构：适配器先做就绪检查，
  /// 未就绪不会走到内层执行器）。
  final bool runtimeReady;

  FakeRootfs._(
    this.rootfs, {
    required this.hasCodex,
    this.apiKey,
    required this.runtimeReady,
    required this.prootExecutable,
    required this.loaderPath,
  });

  static Future<FakeRootfs> create({
    bool hasCodex = true,
    String? apiKey = 'test-key-123',
    bool runtimeReady = true,
  }) async {
    final rootfs = await Directory.systemTemp.createTemp('codex-rootfs-test');
    // 与 rootfs 同处临时目录（CI runner 非 root，不能写文件系统根 /）
    final prootExecutable = '${rootfs.path}/proot';
    final loaderPath = '${rootfs.path}/loader';
    if (hasCodex) {
      final codex = File('${rootfs.path}/usr/local/bin/codex');
      await codex.create(recursive: true);
    }
    if (apiKey != null) {
      final envFile = File('${rootfs.path}/root/.mimo2codex/.env');
      await envFile.create(recursive: true);
      await envFile.writeAsString('DS_API_KEY=$apiKey\n');
    }
    if (runtimeReady) {
      // LinuxExecutionAdapter 就绪检查要求 proot/loader/bash 三个关键
      // 文件存在，否则请求不会委托到内层执行器（也就无法模拟 codex
      // JSONL 输出/启动失败/取消等执行期行为）。
      await File(prootExecutable).create(recursive: true);
      await File(loaderPath).create(recursive: true);
      await File('${rootfs.path}/usr/bin/bash').create(recursive: true);
    }
    return FakeRootfs._(
      rootfs,
      hasCodex: hasCodex,
      apiKey: apiKey,
      runtimeReady: runtimeReady,
      prootExecutable: prootExecutable,
      loaderPath: loaderPath,
    );
  }

  LinuxRuntimeProvider provider() => LinuxRuntimeProvider(
    paths: LinuxRuntimePaths(
      prootExecutable: prootExecutable,
      rootfsDir: rootfs.path,
      loaderPath: loaderPath,
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
        processExecution: inner,
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
        processExecution: inner,
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
        processExecution: inner,
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
        processExecution: inner,
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

    test('自动创建宿主工作目录，经统一 runner 绑定到 /workspace', () async {
      final nested = Directory(
        '${workspace.path}/a/b/c',
      );
      final inner = FakeLocalExecution();
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        processExecution: inner,
      );

      await runner.run(
        prompt: 'hi',
        hostWorkingDir: nested.path,
        listener: RecordingListener(),
      );

      expect(nested.existsSync(), isTrue);
      // wrapped 请求 = LinuxExecutionAdapter 生成的完整 PRoot argv
      final request = inner.lastRequest!;
      expect(request.executable, fakeRootfs.prootExecutable);
      final args = request.arguments;
      // rootfs
      expect(args, contains('-r'));
      expect(args[args.indexOf('-r') + 1], fakeRootfs.rootfs.path);
      // 修正后的 bind 格式：-b <host>:/workspace（单参数，冒号分隔）
      expect(args, contains('${nested.path}:/workspace'));
      // -w /workspace（guest 工作目录）
      expect(args, contains('-w'));
      expect(args[args.indexOf('-w') + 1], '/workspace');
      // 宿主端 cwd 守卫：/workspace 在宿主不存在 → 不透传给 Process.start
      expect(request.workingDirectory, isNull);
      // 内层 bash 命令：exec 前缀 + codex exec --json + $CODEX_PROMPT + </dev/null
      final lcIdx = args.indexOf('-lc');
      final innerCommand = args[lcIdx + 1];
      expect(innerCommand, startsWith('exec /usr/local/bin/codex exec --json'));
      expect(innerCommand, contains('--skip-git-repo-check'));
      expect(innerCommand, contains('--dangerously-bypass-approvals-and-sandbox'));
      expect(innerCommand, contains('"\$CODEX_PROMPT"'));
      expect(innerCommand, endsWith('</dev/null'));
      // 环境变量注入
      expect(request.environment?['DEEPSEEK_API_KEY'], 'test-key-123');
      expect(request.environment?['CODEX_PROMPT'], contains('hi'));
      // 宿主端 PRoot 临时目录（适配器统一注入）
      expect(request.environment?['PROOT_TMP_DIR'],
          '${fakeRootfs.rootfs.path}/tmp');
    });

    test('Runtime 未就绪 → 明确提示 Coding Runtime 未就绪（替代 ENOENT）', () async {
      // proot/loader/bash 三个关键文件缺失 → 适配器直接返回未就绪，
      // 不会走到内层执行器（executeCalls 恒为 0）。
      final noRuntime = await FakeRootfs.create(runtimeReady: false);
      addTearDown(noRuntime.dispose);

      final inner = FakeLocalExecution();
      final runner = CodexRunner(
        provider: noRuntime.provider(),
        processExecution: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(result.exitCode, -1);
      expect(result.error, contains('Coding Runtime 未就绪'));
      expect(result.error, contains('请先部署 Linux Runtime'));
      // 不再出现误导性的 /system/bin/sh 或裸 ENOENT
      expect(result.error, isNot(contains('/system/bin/sh')));
      // 未就绪 → 未启动任何进程（不伪造成功，也不调用内层执行器）
      expect(inner.executeCalls, 0);
    });


    test('workspace .codex 含宿主绝对路径 → 自动遮蔽为干净阴影', () async {
      // 模拟 codex 0.147 的 project config 污染：工作区 .codex/config.toml
      // 的 model_catalog_json 指向 Android 宿主绝对路径（PRoot 内 ENOENT）
      final codexDir = Directory('${workspace.path}/.codex');
      await codexDir.create(recursive: true);
      await File('${codexDir.path}/config.toml').writeAsString(
        'model_catalog_json = '
        '"/data/user/0/com.codexmobile.app/app_flutter/.codex/deepseek-models.json"\n',
      );

      final inner = FakeLocalExecution();
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        processExecution: inner,
      );

      final result = await runner.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: RecordingListener(),
      );

      expect(result.isSuccess, isTrue);
      final request = inner.lastRequest!;
      final args = request.arguments;
      // 原始 workspace bind 仍在
      expect(args, contains('${workspace.path}:/workspace'));
      // 追加 .codex 阴影 bind（-b <shadowDir>:/workspace/.codex）
      final shadowBinds = args.where((a) => a.endsWith(':/workspace/.codex'));
      expect(shadowBinds, hasLength(1));
      final shadow = shadowBinds.first;
      final shadowHost = shadow.split(':').first;
      // 阴影目录真实存在（rootfs tmp 内）
      expect(Directory(shadowHost).existsSync(), isTrue);
      // 阴影目录为空（无 config.toml → 空 project layer，不读宿主路径）
      expect(File('$shadowHost/config.toml').existsSync(), isFalse);
    });

    test('workspace .codex 干净或不存在 → 不遮蔽', () async {
      // 场景 1：无 .codex
      final inner = FakeLocalExecution();
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        processExecution: inner,
      );

      await runner.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: RecordingListener(),
      );

      var args = inner.lastRequest!.arguments;
      expect(args.where((a) => a.endsWith(':/workspace/.codex')), isEmpty);
      expect(args, contains('${workspace.path}:/workspace'));

      // 场景 2：.codex/config.toml 干净（无宿主绝对路径）
      final codexDir = Directory('${workspace.path}/.codex');
      await codexDir.create(recursive: true);
      await File('${codexDir.path}/config.toml').writeAsString(
        'model = "deepseek-chat"\n'
        '[model_providers.deepseek]\n'
        'base_url = "https://api.deepseek.com"\n',
      );

      final inner2 = FakeLocalExecution();
      final runner2 = CodexRunner(
        provider: fakeRootfs.provider(),
        processExecution: inner2,
      );

      await runner2.run(
        prompt: 'hi',
        hostWorkingDir: workspace.path,
        listener: RecordingListener(),
      );

      args = inner2.lastRequest!.arguments;
      expect(args.where((a) => a.endsWith(':/workspace/.codex')), isEmpty);
    });

    test('非零退出码传播', () async {
      final inner = FakeLocalExecution(
        outputChunks: ['{"type":"thread.started","thread_id":"t1"}\n'],
        exitCode: 2,
      );
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        processExecution: inner,
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
        processExecution: inner,
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
        processExecution: inner,
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
        processExecution: inner,
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
        processExecution: inner,
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
  group('真实 codex 0.147 JSONL 解析（repro 捕获的真实 stdout）', () {
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
    test('真实「只回复 OK」stdout → 提取 agent_message text = OK', () async {
      // 数据来源：~/repro/audit_stdout.jsonl（真实 PRoot + Ubuntu noble + codex-cli
      // 0.147.0 执行「只回复 OK」的 stdout，逐行原样拷贝，含无害 fallback error 事件）
      const realStdout = r'''
{"type":"thread.started","thread_id":"019febf6-5b13-7931-a9e8-b122e5b52336"}
{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Ignored unsupported project-local config keys in /workspace/.codex/config.toml: model_provider, model_providers. If you want these settings to apply, manually set them in your user-level config.toml."}}
{"type":"item.completed","item":{"id":"item_1","type":"error","message":"Ignored unsupported project-local config keys in /workspace/.codex/config.toml: model_provider, model_providers. If you want these settings to apply, manually set them in your user-level config.toml."}}
{"type":"item.completed","item":{"id":"item_2","type":"error","message":"Model metadata for `deepseek-chat` not found. Defaulting to fallback metadata; this can degrade performance and cause issues."}}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"OK"}}
{"type":"turn.completed","usage":{"input_tokens":10012,"cached_input_tokens":9856,"cache_write_input_tokens":0,"output_tokens":27,"reasoning_output_tokens":25}}
''';

      final inner = FakeLocalExecution(outputChunks: [realStdout]);
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        processExecution: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: '只回复 OK',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(result.isSuccess, isTrue);
      expect(result.exitCode, 0);
      final agents = listener.events.whereType<CodexAgentMessage>().toList();
      expect(agents, hasLength(1), reason: '真实 stdout 只含一个 agent_message');
      expect(agents.single.text, 'OK');
    });

    test('真实「介绍一下自己」stdout → 提取完整自我介绍（多行 \n 不丢失）', () async {
      // 数据来源：~/repro/audit_appsim_stdout.jsonl（App 文档目录模拟 + 完整 systemPrompt
      // + 用户 prompt「介绍一下自己」的真实 stdout；agent_message 含 \n\n 与 markdown 反引号）
      const realStdout = r'''
{"type":"thread.started","thread_id":"019febf9-9912-7171-9d09-9310ff079c46"}
{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Model metadata for `deepseek-chat` not found. Defaulting to fallback metadata; this can degrade performance and cause issues."}}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"你好!我是 Codex,一个运行在终端里的 AI 编程助手,可以直接在命令行环境中帮你处理各种编码任务。\n\n**我能做什么**\n- 读取、搜索和修改项目文件,支持多种编程语言\n- 运行命令、构建项目、执行测试来验证代码\n- 调试问题、修复 bug、重构代码\n- 解释代码逻辑、撰写文档、生成测试用例\n- 处理 Git 操作(除非你明确要求,否则我不会擅自提交)\n\n**我的工作方式**\n- 先理解你的需求,必要时制定分步计划\n- 逐步操作并随时汇报进展,保持透明\n- 尽量做到精准、不过度修改,尊重现有代码风格\n- 完成后用简洁的中文总结改动,并给出可点击的文件路径\n\n当前工作目录是 `/workspace`,你可以直接让我在这个目录里干活。有什么想让我帮忙的吗?比如看看项目结构、修个 bug,或者从零开始写点什么?"}}
{"type":"turn.completed","usage":{"input_tokens":10053,"cached_input_tokens":9984,"cache_write_input_tokens":0,"output_tokens":227,"reasoning_output_tokens":26}}
''';

      final inner = FakeLocalExecution(outputChunks: [realStdout]);
      final runner = CodexRunner(
        provider: fakeRootfs.provider(),
        processExecution: inner,
      );
      final listener = RecordingListener();

      final result = await runner.run(
        prompt: '介绍一下自己',
        hostWorkingDir: workspace.path,
        listener: listener,
      );

      expect(result.isSuccess, isTrue);
      final agents = listener.events.whereType<CodexAgentMessage>().toList();
      expect(agents, hasLength(1));
      final text = agents.single.text;
      expect(text, startsWith('你好!我是 Codex'));
      expect(text, contains('\n\n**我能做什么**'), reason: 'JSON 内的 \\n 应被解码为真实换行');
      expect(text, contains('当前工作目录是 `/workspace`'));
    });
  });
}

