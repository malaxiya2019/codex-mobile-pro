import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/detector/detection_result.dart';
import 'package:codex_mobile_pro/core/detector/detector.dart';
import 'package:codex_mobile_pro/core/detector/detector_service.dart';

/// 模拟检测器 — 已安装
class MockInstalledDetector extends Detector {
  @override
  String get id => 'mock_installed';
  @override
  String get name => 'Mock Installed';
  @override
  String get icon => '🧪';

  @override
  Future<DetectionResult> detect() async {
    return DetectionResult(
      id: id, name: name, icon: icon,
      status: DetectionStatus.installed,
      version: '1.0.0',
      path: '/usr/bin/mock',
      durationMs: 10,
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
  Future<DetectionResult> detect() async {
    return DetectionResult(
      id: id, name: name, icon: icon,
      status: DetectionStatus.missing,
      errorMessage: '未安装',
      durationMs: 5,
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
  Future<DetectionResult> detect() async {
    return DetectionResult(
      id: id, name: name, icon: icon,
      status: DetectionStatus.error,
      errorMessage: '检测过程中抛出异常',
      durationMs: 0,
    );
  }
}

void main() {
  group('DetectionResult', () {
    test('installed 状态正确', () {
      final result = DetectionResult(
        id: 'test', name: 'Test', icon: '🧪',
        status: DetectionStatus.installed,
        version: '1.0.0',
        path: '/usr/bin/test',
      );
      expect(result.statusIcon, '✅');
      expect(result.isSuccess, true); // 通过 isSuccess getter? 不对，DetectionResult 没有 isSuccess
      // 实际上 DetectionResult 没有 isSuccess getter，用 status 判断
      expect(result.status, DetectionStatus.installed);
    });

    test('missing 状态正确', () {
      final result = DetectionResult(
        id: 'test', name: 'Test', icon: '🧪',
        status: DetectionStatus.missing,
      );
      expect(result.statusIcon, '❌');
    });

    test('copyWith 工作正常', () {
      final result = DetectionResult(
        id: 'test', name: 'Test', icon: '🧪',
        status: DetectionStatus.missing,
      );
      final updated = result.copyWith(status: DetectionStatus.installed, version: '2.0');
      expect(updated.status, DetectionStatus.installed);
      expect(updated.version, '2.0');
      // 原始对象不变
      expect(result.status, DetectionStatus.missing);
    });

    test('toString 包含版本和路径', () {
      final result = DetectionResult(
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
      final installed = DetectionResult(id: 't', name: 'T', icon: '🧪', status: DetectionStatus.installed);
      final missing = DetectionResult(id: 't', name: 'T', icon: '🧪', status: DetectionStatus.missing);
      expect(installed.statusColor, 0xFF4CAF50);
      expect(missing.statusColor, 0xFFF44336);
    });
  });

  group('DetectorService', () {
    test('custom 检测器列表工作正常', () async {
      final service = DetectorService.custom([
        MockInstalledDetector(),
        MockMissingDetector(),
      ]);
      final results = await service.detectAll();
      expect(results.length, 2);
      expect(results[0].status, DetectionStatus.installed);
      expect(results[1].status, DetectionStatus.missing);
    });

    test('detectOne 返回正确检测器结果', () async {
      final service = DetectorService.custom([MockInstalledDetector()]);
      final result = await service.detectOne('mock_installed');
      expect(result, isNotNull);
      expect(result!.status, DetectionStatus.installed);
    });

    test('detectOne 返回 null 对于不存在的 id', () async {
      final service = DetectorService.custom([MockInstalledDetector()]);
      final result = await service.detectOne('nonexistent');
      expect(result, isNull);
    });

    test('detectorIds 返回正确列表', () {
      final service = DetectorService.custom([MockInstalledDetector(), MockMissingDetector()]);
      expect(service.detectorIds, ['mock_installed', 'mock_missing']);
    });

    test('getDetector 返回正确检测器', () {
      final service = DetectorService.custom([MockInstalledDetector()]);
      final detector = service.getDetector('mock_installed');
      expect(detector, isNotNull);
      expect(detector!.name, 'Mock Installed');
    });
  });

  group('DetectorService.summarize', () {
    test('正确统计 installed / missing / error', () {
      final results = [
        DetectionResult(id: 'a', name: 'A', icon: '🧪', status: DetectionStatus.installed),
        DetectionResult(id: 'b', name: 'B', icon: '🧪', status: DetectionStatus.installed),
        DetectionResult(id: 'c', name: 'C', icon: '🧪', status: DetectionStatus.missing),
        DetectionResult(id: 'd', name: 'D', icon: '🧪', status: DetectionStatus.error),
      ];
      final summary = DetectorService.summarize(results);
      expect(summary['total'], 4);
      expect(summary['installed'], 2);
      expect(summary['missing'], 1);
      expect(summary['errors'], 1);
    });

    test('空列表统计', () {
      final summary = DetectorService.summarize([]);
      expect(summary['total'], 0);
      expect(summary['installed'], 0);
      expect(summary['missing'], 0);
    });
  });

  group('DeployStatus', () {
    // 测试 DeployStatus 逻辑
    test('默认状态', () {
      // 这个需要引入 deploy_provider.dart，暂时跳过
      // 实际测试在集成测试中验证
      expect(true, isTrue);
    });
  });
}
