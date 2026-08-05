import 'dart:io';

import 'package:codex_mobile_pro/core/detector/detection_result.dart';
import 'package:codex_mobile_pro/runtime/capability/capability_resolver.dart';
import 'package:codex_mobile_pro/runtime/runtime_detector.dart';
import 'package:codex_mobile_pro/runtime/runtime_environment.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capability/fake_runner.dart';

void main() {
  group('RuntimeDetectionResult', () {
    /// 创建一个模拟的检测结果
    DetectionResult makeResult({
      required String id,
      required String name,
      required DetectionStatus status,
    }) {
      return DetectionResult(
        id: id,
        name: name,
        icon: '🟢',
        status: status,
      );
    }

    test('codingReady — 全部 installed 为 true', () {
      final result = RuntimeDetectionResult(
        coding: [
          makeResult(
              id: 'node', name: 'Node.js', status: DetectionStatus.installed),
          makeResult(id: 'git', name: 'Git', status: DetectionStatus.installed),
        ],
        all: [],
        isComplete: true,
      );

      expect(result.codingReady, isTrue);
    });

    test('codingReady — 有 missing 为 false', () {
      final result = RuntimeDetectionResult(
        coding: [
          makeResult(
              id: 'node', name: 'Node.js', status: DetectionStatus.installed),
          makeResult(id: 'git', name: 'Git', status: DetectionStatus.missing),
        ],
        all: [],
        isComplete: true,
      );

      expect(result.codingReady, isFalse);
    });

    test('codingReady — 全部 unsupported 为 true（无可安装项）', () {
      final result = RuntimeDetectionResult(
        coding: [
          makeResult(
              id: 'codex',
              name: 'Codex CLI',
              status: DetectionStatus.unsupported),
          makeResult(
              id: 'mimo2codex',
              name: 'mimo2codex',
              status: DetectionStatus.unsupported),
        ],
        all: [],
        isComplete: true,
      );

      expect(result.codingReady, isTrue,
          reason: '所有工具都是 unsupported 时，coding 视为就绪');
    });

    test('codingReady — 混合 installed + unsupported 为 true', () {
      final result = RuntimeDetectionResult(
        coding: [
          makeResult(
              id: 'node', name: 'Node.js', status: DetectionStatus.installed),
          makeResult(
              id: 'codex',
              name: 'Codex CLI',
              status: DetectionStatus.unsupported),
        ],
        all: [],
        isComplete: true,
      );

      expect(result.codingReady, isTrue);
    });

    test('codingReady — 混合 installed + missing + unsupported 为 false', () {
      final result = RuntimeDetectionResult(
        coding: [
          makeResult(
              id: 'node', name: 'Node.js', status: DetectionStatus.installed),
          makeResult(id: 'git', name: 'Git', status: DetectionStatus.missing),
          makeResult(
              id: 'codex',
              name: 'Codex CLI',
              status: DetectionStatus.unsupported),
        ],
        all: [],
        isComplete: true,
      );

      expect(result.codingReady, isFalse, reason: '还有 missing 工具未安装');
    });

    test('codingInstalled 只统计 installed', () {
      final result = RuntimeDetectionResult(
        coding: [
          makeResult(
              id: 'node', name: 'Node.js', status: DetectionStatus.installed),
          makeResult(id: 'git', name: 'Git', status: DetectionStatus.missing),
          makeResult(
              id: 'codex',
              name: 'Codex CLI',
              status: DetectionStatus.unsupported),
        ],
        all: [],
        isComplete: true,
      );

      expect(result.codingInstalled, 1);
      expect(result.codingTotal, 3);
      expect(result.codingUnsupported, 1);
    });

    test('summary 包含基础/编码/AI/开发信息', () {
      final result = RuntimeDetectionResult(
        basic: [
          makeResult(
              id: 'linux', name: 'Linux', status: DetectionStatus.installed),
        ],
        coding: [
          makeResult(
              id: 'node', name: 'Node.js', status: DetectionStatus.installed),
        ],
        ai: [
          makeResult(
              id: 'deepseek_key',
              name: 'DeepSeek',
              status: DetectionStatus.missing),
        ],
        development: [
          makeResult(
              id: 'flutter', name: 'Flutter', status: DetectionStatus.missing),
        ],
        all: [],
        isComplete: true,
      );

      final summary = result.summary;
      expect(summary, contains('基础'));
      expect(summary, contains('编码'));
      expect(summary, contains('AI'));
      expect(summary, contains('开发'));
    });
  });

  group('reGroupResults — Codex CLI 分组', () {
    final detector = RuntimeDetector(runner: FakeProcessRunner());

    DetectionResult makeResult({
      required String id,
      required DetectionStatus status,
    }) {
      return DetectionResult(
        id: id,
        name: id,
        icon: '🤖',
        status: status,
      );
    }

    test('A. codex 归入 coding 分组，mimo2codex 留在 advanced', () {
      final results = [
        makeResult(id: 'node', status: DetectionStatus.installed),
        makeResult(id: 'npm', status: DetectionStatus.installed),
        makeResult(id: 'git', status: DetectionStatus.installed),
        makeResult(id: 'python', status: DetectionStatus.installed),
        makeResult(id: 'codex', status: DetectionStatus.missing),
        makeResult(id: 'mimo2codex', status: DetectionStatus.missing),
      ];
      final grouped = detector.reGroupResults(results);

      final codingIds = grouped.coding.map((r) => r.id).toList();
      final advancedIds = grouped.advanced.map((r) => r.id).toList();

      expect(codingIds, containsAll(['node', 'npm', 'git', 'python', 'codex']));
      expect(codingIds, isNot(contains('mimo2codex')));
      expect(advancedIds, contains('mimo2codex'));
      expect(advancedIds, isNot(contains('codex')));
    });

    test('B. codex missing → codingMissing > 0（一键部署按钮条件）', () {
      // 复刻 deploy_page._buildActionButtons 的 codingMissing 计算：
      //   final codingMissing = detection.coding
      //       .where((r) => r.status == DetectionStatus.missing).length;
      final results = [
        makeResult(id: 'node', status: DetectionStatus.installed),
        makeResult(id: 'npm', status: DetectionStatus.installed),
        makeResult(id: 'git', status: DetectionStatus.installed),
        makeResult(id: 'python', status: DetectionStatus.installed),
        makeResult(id: 'codex', status: DetectionStatus.missing),
      ];
      final grouped = detector.reGroupResults(results);

      final codingMissing = grouped.coding
          .where((r) => r.status == DetectionStatus.missing)
          .length;

      expect(grouped.coding.map((r) => r.id), contains('codex'));
      expect(codingMissing, greaterThan(0));
      expect(grouped.codingReady, isFalse);
    });

    test('C. codex installed → codingReady 正确计算（total/installed 含 codex）', () {
      final results = [
        makeResult(id: 'node', status: DetectionStatus.installed),
        makeResult(id: 'npm', status: DetectionStatus.installed),
        makeResult(id: 'git', status: DetectionStatus.installed),
        makeResult(id: 'python', status: DetectionStatus.installed),
        makeResult(id: 'codex', status: DetectionStatus.installed),
      ];
      final grouped = detector.reGroupResults(results);

      expect(grouped.codingTotal, 5);
      expect(grouped.codingInstalled, 5);
      expect(grouped.codingReady, isTrue);
    });

    test('C2. codex missing → codingTotal 含 codex、codingReady false', () {
      final results = [
        makeResult(id: 'node', status: DetectionStatus.installed),
        makeResult(id: 'npm', status: DetectionStatus.installed),
        makeResult(id: 'git', status: DetectionStatus.installed),
        makeResult(id: 'python', status: DetectionStatus.installed),
        makeResult(id: 'codex', status: DetectionStatus.missing),
      ];
      final grouped = detector.reGroupResults(results);

      expect(grouped.codingTotal, 5);
      expect(grouped.codingInstalled, 4);
      expect(grouped.codingReady, isFalse);
    });

    test('D. verifyCodingEnvironment Linux 分支能检测 codex', () async {
      final temp = await Directory.systemTemp.createTemp('rtd-verify-');
      addTearDown(() => temp.delete(recursive: true));

      final env = RuntimeEnvironment.forTest(temp.path);

      // 构造 Linux Runtime 已安装假象（isUbuntuInstalled 三要素）
      File('${env.ubuntuBinDir}/proot').createSync(recursive: true);
      File('${env.ubuntuRootfsDir}/usr/bin/bash').createSync(recursive: true);
      File(env.installCompleteMarker).createSync(recursive: true);

      // rootfs /usr/bin 下放置 node/git/python3/codex 可执行文件
      final ubuntuBin = '${env.ubuntuRootfsDir}/usr/bin';
      for (final tool in ['node', 'git', 'python3', 'codex']) {
        File('$ubuntuBin/$tool').createSync(recursive: true);
      }

      // 预设版本检测成功
      final runner = FakeProcessRunner();
      runner.whenVersion('node', '18.19.1');
      runner.whenVersion('git', '2.43.0');
      runner.whenVersion('python3', '3.12.3');
      runner.whenVersion('codex', '0.9.0');

      final detector = RuntimeDetector(runner: runner);
      final results = await detector.verifyCodingEnvironment(environment: env);

      final codex = results.firstWhere((r) => r.tool == 'codex');
      expect(codex.success, isTrue, reason: 'codex --version 应验证成功');
      expect(codex.output, contains('0.9.0'));

      // 回归：原有 node/git/python3 仍可验证
      for (final tool in ['node', 'git', 'python3']) {
        final r = results.firstWhere((r) => r.tool == tool);
        expect(r.success, isTrue, reason: '$tool 验证应成功');
      }
    });

    test(
        'D2. verifyCodingEnvironment：rootfs 内 broken（exit=127）→ 报 exit 而非「未安装」',
        () async {
      final temp = await Directory.systemTemp.createTemp('rtd-verify-127-');
      addTearDown(() => temp.delete(recursive: true));
      final env = RuntimeEnvironment.forTest(temp.path);

      // 构造 Linux Runtime 已安装假象（isUbuntuInstalled 三要素）
      File('${env.ubuntuBinDir}/proot').createSync(recursive: true);
      File('${env.ubuntuRootfsDir}/usr/bin/bash').createSync(recursive: true);
      File(env.installCompleteMarker).createSync(recursive: true);

      final runner = FakeProcessRunner();
      runner.whenVersion('node', '18.19.1');
      runner.whenVersion('git', '2.43.0');
      runner.whenVersion('python3', '3.12.3');
      // rootfs 内 broken symlink：命令存在但执行失败（无 stderr 输出）
      runner.when('codex --version', const FakeCommandResult(exitCode: 127));

      final detector = RuntimeDetector(runner: runner);
      final results = await detector.verifyCodingEnvironment(environment: env);

      final codex = results.firstWhere((r) => r.tool == 'codex');
      expect(codex.success, isFalse);
      expect(codex.error, isNotNull);
      expect(codex.error, isNot(contains('未安装')),
          reason: 'broken 与未安装必须区分（避免误导用户）');
      expect(codex.error, contains('127'));
      // 回归：node/git/python3 正常
      for (final tool in ['node', 'git', 'python3']) {
        final r = results.firstWhere((r) => r.tool == tool);
        expect(r.success, isTrue, reason: '$tool 验证应成功');
      }
    });

    test('D3. verifyCodingEnvironment：版本检测走 PRoot 上下文（runtimeId=linux）',
        () async {
      final temp = await Directory.systemTemp.createTemp('rtd-verify-rid-');
      addTearDown(() => temp.delete(recursive: true));
      final env = RuntimeEnvironment.forTest(temp.path);

      // 构造 Linux Runtime 已安装假象（isUbuntuInstalled 三要素）
      File('${env.ubuntuBinDir}/proot').createSync(recursive: true);
      File('${env.ubuntuRootfsDir}/usr/bin/bash').createSync(recursive: true);
      File(env.installCompleteMarker).createSync(recursive: true);

      final runner = FakeProcessRunner();
      runner.whenVersion('node', '18.19.1');
      runner.whenVersion('git', '2.43.0');
      runner.whenVersion('python3', '3.12.3');
      runner.whenVersion('codex', '0.9.0');

      final detector = RuntimeDetector(runner: runner);
      await detector.verifyCodingEnvironment(environment: env);

      // 全部走 runtimeId='linux'（PRoot → rootfs），不落在宿主侧
      for (final tool in ['node', 'git', 'python3', 'codex']) {
        final calls = runner.executedRequests
            .where((r) =>
                r.executable == tool && r.arguments.join(' ') == '--version')
            .toList();
        expect(calls, isNotEmpty, reason: '$tool 应发出版本检测请求');
        expect(calls.first.runtimeId, 'linux',
            reason: '$tool 必须走 PRoot 上下文（rootfs 内真实检测）');
      }
    });
  });

  group('Linux Runtime 未就绪 → Coding 工具 missing（APK-238 回归）', () {
    test('E. Linux 未就绪时 detectOne(node) 为 missing + 依赖提示，不误报 exit=127',
        () async {
      final temp = await Directory.systemTemp.createTemp('rtd-238-');
      addTearDown(() => temp.delete(recursive: true));
      final env = RuntimeEnvironment.forTest(temp.path);

      // 即使预设了版本成功（模拟宿主 shell 能找到），未就绪时也应短路，
      // 不执行任何版本检测命令。
      final runner = FakeProcessRunner();
      runner.whenVersion('node', '18.19.1');

      final detector = RuntimeDetector(
        runner: runner,
        capabilityResolver: CapabilityResolver(runner: runner),
      );
      final result = await detector.detectOne('node', environment: env);

      expect(result, isNotNull);
      expect(result!.id, 'node');
      expect(result.status, DetectionStatus.missing,
          reason: 'Linux 未就绪时 node 必须为 missing（可安装），而非 error');
      expect(result.status, isNot(DetectionStatus.error));
      expect(result.missingHint, contains('Linux Runtime'),
          reason: '应引导用户先完成一键部署');
      expect(result.errorMessage, isNull, reason: '不应再出现 exit=127 类错误误报');
      // 未就绪时不应发出任何 node 相关执行请求
      final nodeCalls = runner.executedRequests
          .where((r) => r.executable.contains('node'))
          .length;
      expect(nodeCalls, 0, reason: 'Linux 未就绪时应完全跳过 resolver 检测');
    });

    test('F. Linux 未就绪时全部 rootfs 工具均为 missing', () async {
      final temp = await Directory.systemTemp.createTemp('rtd-238-all-');
      addTearDown(() => temp.delete(recursive: true));
      final env = RuntimeEnvironment.forTest(temp.path);

      final detector = RuntimeDetector(
        runner: FakeProcessRunner(),
        capabilityResolver: CapabilityResolver(runner: FakeProcessRunner()),
      );

      for (final id in [
        'node',
        'npm',
        'git',
        'python',
        'codex',
        'mimo2codex',
        'flutter',
      ]) {
        final result = await detector.detectOne(id, environment: env);
        expect(result, isNotNull, reason: '$id 应返回检测结果');
        expect(result!.status, DetectionStatus.missing,
            reason: '$id 在 Linux 未就绪时应为 missing');
        expect(result.missingHint, contains('Linux Runtime'),
            reason: '$id 应提示依赖 Linux Runtime');
      }
    });

    test('G. Linux 就绪后 detectOne(node) 正常走 resolver（回归保护）', () async {
      final temp = await Directory.systemTemp.createTemp('rtd-238-ready-');
      addTearDown(() => temp.delete(recursive: true));
      final env = RuntimeEnvironment.forTest(temp.path);

      // 构造 Linux Runtime 已安装假象（isUbuntuInstalled 三要素）
      File('${env.ubuntuBinDir}/proot').createSync(recursive: true);
      File('${env.ubuntuRootfsDir}/usr/bin/bash').createSync(recursive: true);
      File(env.installCompleteMarker).createSync(recursive: true);

      final runner = FakeProcessRunner();
      runner.whenWhich('node', '${env.ubuntuRootfsDir}/usr/bin/node');
      runner.whenVersion('node', '18.19.1');

      final detector = RuntimeDetector(
        runner: runner,
        capabilityResolver: CapabilityResolver(runner: runner),
      );
      final result = await detector.detectOne('node', environment: env);

      expect(result, isNotNull);
      expect(result!.status, DetectionStatus.installed,
          reason: 'Linux 就绪后应正常检测 node');
      expect(result.version, contains('18.19.1'));
    });
  });
}
