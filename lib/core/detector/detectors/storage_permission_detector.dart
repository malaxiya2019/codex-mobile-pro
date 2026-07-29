import '../detection_result.dart';
import '../detector.dart';
import '../environment_service.dart';

class StoragePermissionDetector extends Detector {
  @override
  String get id => 'storage';
  @override
  String get name => '存储权限';
  @override
  String get icon => '💾';
  @override
  DetectorCategory get category => DetectorCategory.runtime;
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.basic;

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      var result = await EnvironmentService.detectTool(
        'ls /sdcard/Download/ 2>/dev/null | head -5 || ls /storage/emulated/0/Download/ 2>/dev/null | head -5 || echo "no_access"',
      );
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (result.isSuccess &&
          result.stdout.isNotEmpty &&
          !result.stdout.contains('no_access')) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: '可读写',
          path: '/sdcard/Download',
          durationMs: elapsed,
          category: category,
        );
      }

      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        category: category,
      );
    } catch (e) {
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        errorMessage: e.toString(),
        category: category,
      );
    }
  }
}
