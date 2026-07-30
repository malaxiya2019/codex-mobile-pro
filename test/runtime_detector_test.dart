import 'package:codex_mobile_pro/core/detector/detection_result.dart';
import 'package:codex_mobile_pro/runtime/runtime_detector.dart';
import 'package:flutter_test/flutter_test.dart';

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
          makeResult(id: 'node', name: 'Node.js', status: DetectionStatus.installed),
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
          makeResult(id: 'node', name: 'Node.js', status: DetectionStatus.installed),
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
          makeResult(id: 'codex', name: 'Codex CLI', status: DetectionStatus.unsupported),
          makeResult(id: 'mimo2codex', name: 'mimo2codex', status: DetectionStatus.unsupported),
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
          makeResult(id: 'node', name: 'Node.js', status: DetectionStatus.installed),
          makeResult(id: 'codex', name: 'Codex CLI', status: DetectionStatus.unsupported),
        ],
        all: [],
        isComplete: true,
      );

      expect(result.codingReady, isTrue);
    });

    test('codingReady — 混合 installed + missing + unsupported 为 false', () {
      final result = RuntimeDetectionResult(
        coding: [
          makeResult(id: 'node', name: 'Node.js', status: DetectionStatus.installed),
          makeResult(id: 'git', name: 'Git', status: DetectionStatus.missing),
          makeResult(id: 'codex', name: 'Codex CLI', status: DetectionStatus.unsupported),
        ],
        all: [],
        isComplete: true,
      );

      expect(result.codingReady, isFalse,
          reason: '还有 missing 工具未安装');
    });

    test('codingInstalled 只统计 installed', () {
      final result = RuntimeDetectionResult(
        coding: [
          makeResult(id: 'node', name: 'Node.js', status: DetectionStatus.installed),
          makeResult(id: 'git', name: 'Git', status: DetectionStatus.missing),
          makeResult(id: 'codex', name: 'Codex CLI', status: DetectionStatus.unsupported),
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
          makeResult(id: 'termux', name: 'Termux', status: DetectionStatus.installed),
        ],
        coding: [
          makeResult(id: 'node', name: 'Node.js', status: DetectionStatus.installed),
        ],
        ai: [
          makeResult(id: 'deepseek_key', name: 'DeepSeek', status: DetectionStatus.missing),
        ],
        development: [
          makeResult(id: 'flutter', name: 'Flutter', status: DetectionStatus.missing),
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
}
