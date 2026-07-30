import 'package:codex_mobile_pro/core/detector/detection_result.dart';
import 'package:codex_mobile_pro/core/detector/detector.dart';
import 'package:codex_mobile_pro/core/detector/detector_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟检测器 — 已安装（Runtime）
class MockInstalledRuntimeDetector extends Detector {
  @override
  String get id => 'mock_runtime_installed';
  @override
  String get name => 'Mock Runtime';
  @override
  String get icon => '🧪';
  @override
  DetectorCategory get category => DetectorCategory.runtime;

  @override
  Future<DetectionResult> detect() async {
    return DetectionResult(
      id: id, name: name, icon: icon,
      status: DetectionStatus.installed,
      version: '1.0.0',
      path: '/usr/bin/mock',
      durationMs: 10,
      category: category,
    );
  }
}

/// 模拟检测器 — 已安装（Development）
class MockInstalledDevDetector extends Detector {
  @override
  String get id => 'mock_dev_installed';
  @override
  String get name => 'Mock Dev';
  @override
  String get icon => '🛠';
  @override
  DetectorCategory get category => DetectorCategory.development;
  @override
  String? get missingHint => 'Mock Dev（可选，用于开发）';

  @override
  Future<DetectionResult> detect() async {
    return DetectionResult(
      id: id, name: name, icon: icon,
      status: DetectionStatus.installed,
      version: '2.0.0',
      path: '/opt/mock',
      durationMs: 10,
      category: category,
      missingHint: missingHint,
    );
  }
}

/// 模拟检测器 — 未安装
class MockMissingDetector extends Detector {
  @override
  String get id => 'mock_missing';
  @override
  String get name => 'Mock Missing';
  @override
  String get icon => '🧪';
  @override
  DetectorCategory get category => DetectorCategory.runtime;

  @override
  Future<DetectionResult> detect() async {
    return DetectionResult(
      id: id, name: name, icon: icon,
      status: DetectionStatus.missing,
      errorMessage: '未安装',
      durationMs: 5,
      category: category,
    );
  }
}

/// 模拟检测器 — 检测出错
class MockErrorDetector extends Detector {
  @override
  String get id => 'mock_error';
  @override
  String get name => 'Mock Error';
  @override
  String get icon => '🧪';
  @override
  DetectorCategory get category => DetectorCategory.development;

  @override
  Future<DetectionResult> detect() async {
    return DetectionResult(
      id: id, name: name, icon: icon,
      status: DetectionStatus.error,
      errorMessage: '检测异常',
      category: category,
    );
  }
}

void main() {
  group('DetectionResult', () {
    test('installed 状态正确', () {
      const result = DetectionResult(
        id: 'test', name: 'Test', icon: '🧪',
        status: DetectionStatus.installed,
        version: '1.0.0',
        path: '/usr/bin/test',
      );
      expect(result.statusIcon, '✅');
      expect(result.status, DetectionStatus.installed);
      expect(result.category, DetectorCategory.runtime);
    });

    test('missing 状态正确', () {
      const result = DetectionResult(
        id: 'test', name: 'Test', icon: '🧪',
        status: DetectionStatus.missing,
      );
      expect(result.statusIcon, '⬜');
    });

    test('copyWith 工作正常', () {
      const result = DetectionResult(
        id: 'test', name: 'Test', icon: '🧪',
        status: DetectionStatus.missing,
        category: DetectorCategory.development,
      );
      final updated = result.copyWith(
        status: DetectionStatus.installed,
        version: '2.0',
        category: DetectorCategory.runtime,
      );
      expect(updated.status, DetectionStatus.installed);
      expect(updated.version, '2.0');
      expect(updated.category, DetectorCategory.runtime);
      // 原始对象不变
      expect(result.status, DetectionStatus.missing);
    });

    test('toString 包含版本和路径', () {
      const result = DetectionResult(
        id: 'git', name: 'Git', icon: '🔀',
        status: DetectionStatus.installed,
        version: '2.47.1',
        path: '/usr/bin/git',
      );
      final str = result.toString();
      expect(str, contains('✅'));
      expect(str, contains('Git'));
      expect(str, contains('2.47.1'));
      expect(str, contains('/usr/bin/git'));
    });

    test('statusColor 返回正确颜色值', () {
      const installed = DetectionResult(
        id: 't', name: 'T', icon: '🧪',
        status: DetectionStatus.installed,
      );
      const missing = DetectionResult(
        id: 't', name: 'T', icon: '🧪',
        status: DetectionStatus.missing,
      );
      expect(installed.statusColor, 0xFF4CAF50);
      expect(missing.statusColor, 0xFFFF9800);
    });

    test('failed 状态正确', () {
      const result = DetectionResult(
        id: 'test', name: 'Test', icon: '🧪',
        status: DetectionStatus.failed,
      );
      expect(result.statusIcon, '❌');
      expect(result.statusColor, 0xFFF44336);
    });

    test('blocked 状态正确', () {
      const result = DetectionResult(
        id: 'test', name: 'Test', icon: '🧪',
        status: DetectionStatus.blocked,
      );
      expect(result.statusIcon, '⛔');
      expect(result.statusColor, 0xFF9E9E9E);
    });

    test('category 传递正确', () {
      const runtime = DetectionResult(
        id: 't', name: 'T', icon: '🧪',
        status: DetectionStatus.installed,
      );
      const dev = DetectionResult(
        id: 't', name: 'T', icon: '🧪',
        status: DetectionStatus.installed,
        category: DetectorCategory.development,
      );
      expect(runtime.category, DetectorCategory.runtime);
      expect(dev.category, DetectorCategory.development);
    });

    test('missingHint 传递正确', () {
      const result = DetectionResult(
        id: 'flutter', name: 'Flutter SDK', icon: '🦋',
        status: DetectionStatus.missing,
        category: DetectorCategory.development,
        missingHint: 'Flutter SDK（可选，用于 Flutter 开发）',
      );
      expect(result.missingHint, 'Flutter SDK（可选，用于 Flutter 开发）');
    });
  });

  group('Detector', () {
    test('Runtime 检测器 category 正确', () {
      final detector = MockInstalledRuntimeDetector();
      expect(detector.category, DetectorCategory.runtime);
    });

    test('Development 检测器 category 正确', () {
      final detector = MockInstalledDevDetector();
      expect(detector.category, DetectorCategory.development);
      expect(detector.missingHint, 'Mock Dev（可选，用于开发）');
    });
  });

  group('DetectorService', () {
    test('custom 检测器列表工作正常', () async {
      final service = DetectorService.custom([
        MockInstalledRuntimeDetector(),
        MockMissingDetector(),
      ]);
      final results = await service.detectAll();
      expect(results.length, 2);
      expect(results[0].status, DetectionStatus.installed);
      expect(results[0].category, DetectorCategory.runtime);
      expect(results[1].status, DetectionStatus.missing);
    });

    test('detectOne 返回正确检测器结果', () async {
      final service = DetectorService.custom([MockInstalledRuntimeDetector()]);
      final result = await service.detectOne('mock_runtime_installed');
      expect(result, isNotNull);
      expect(result!.status, DetectionStatus.installed);
    });

    test('detectOne 返回 null 对于不存在的 id', () async {
      final service = DetectorService.custom([MockInstalledRuntimeDetector()]);
      final result = await service.detectOne('nonexistent');
      expect(result, isNull);
    });

    test('detectorIds 返回正确列表', () {
      final service = DetectorService.custom([
        MockInstalledRuntimeDetector(),
        MockMissingDetector(),
      ]);
      expect(service.detectorIds, ['mock_runtime_installed', 'mock_missing']);
    });

    test('getDetector 返回正确检测器', () {
      final service = DetectorService.custom([MockInstalledRuntimeDetector()]);
      final detector = service.getDetector('mock_runtime_installed');
      expect(detector, isNotNull);
      expect(detector!.name, 'Mock Runtime');
    });
  });

  group('DetectorService.summarize', () {
    test('正确统计 installed / missing / failed / blocked / error', () {
      final results = [
        const DetectionResult(
          id: 'a', name: 'A', icon: '🧪',
          status: DetectionStatus.installed,
        ),
        const DetectionResult(
          id: 'b', name: 'B', icon: '🧪',
          status: DetectionStatus.installed,
        ),
        const DetectionResult(
          id: 'c', name: 'C', icon: '🧪',
          status: DetectionStatus.missing,
        ),
        const DetectionResult(
          id: 'd', name: 'D', icon: '🧪',
          status: DetectionStatus.failed,
        ),
        const DetectionResult(
          id: 'e', name: 'E', icon: '🧪',
          status: DetectionStatus.blocked,
        ),
        const DetectionResult(
          id: 'f', name: 'F', icon: '🧪',
          status: DetectionStatus.error,
          category: DetectorCategory.development,
        ),
      ];
      final summary = DetectorService.summarize(results);
      expect(summary['total'], 6);
      expect(summary['installed'], 2);
      expect(summary['missing'], 1);
      expect(summary['failed'], 1);
      expect(summary['blocked'], 1);
      expect(summary['errors'], 1);
    });

    test('空列表统计', () {
      final summary = DetectorService.summarize([]);
      expect(summary['total'], 0);
      expect(summary['installed'], 0);
      expect(summary['missing'], 0);
    });
  });

  group('DetectorService.groupByCategory', () {
    test('按类别正确分组', () {
      final results = [
        const DetectionResult(
          id: 'node', name: 'Node.js', icon: '🟢',
          status: DetectionStatus.installed,
        ),
        const DetectionResult(
          id: 'flutter', name: 'Flutter SDK', icon: '🦋',
          status: DetectionStatus.missing,
          category: DetectorCategory.development,
        ),
        const DetectionResult(
          id: 'git', name: 'Git', icon: '🔀',
          status: DetectionStatus.installed,
        ),
      ];
      final grouped = DetectorService.groupByCategory(results);
      expect(grouped[DetectorCategory.runtime]!.length, 2);
      expect(grouped[DetectorCategory.development]!.length, 1);
    });

    test('空列表分组', () {
      final grouped = DetectorService.groupByCategory([]);
      expect(grouped[DetectorCategory.runtime], isEmpty);
      expect(grouped[DetectorCategory.development], isEmpty);
    });
  });
}
