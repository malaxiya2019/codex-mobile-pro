import '../../termux/termux_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class StoragePermissionDetector extends Detector {
  @override
  String get id => 'storage';
  @override
  String get name => '存储权限';
  @override
  String get icon => '💾';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    try {
      // 尝试读取 /sdcard/Download
      var result = await TermuxService.execute('ls /sdcard/Download/ 2>/dev/null | head -5 || ls /storage/emulated/0/Download/ 2>/dev/null | head -5 || echo "no_access"');
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (result.isSuccess && result.stdout.isNotEmpty && !result.stdout.contains('no_access')) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: '可读写',
          path: '/sdcard/Download',
          durationMs: elapsed,
        );
      }

      // 备选: 检查应用私有目录
      result = await TermuxService.execute('ls /data/data/com.codexmobile.app/ 2>/dev/null | head -3 || echo "no_access"');
      if (result.isSuccess && !result.stdout.contains('no_access')) {
        return DetectionResult(
          id: id, name: name, icon: icon,
          status: DetectionStatus.installed,
          version: '应用私有目录',
          path: '/data/data/com.codexmobile.app',
          durationMs: elapsed,
        );
      }

      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        errorMessage: '存储权限未授予',
      );
    } catch (e) {
      return DetectionResult(
        id: id, name: name, icon: icon,
        status: DetectionStatus.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        errorMessage: e.toString(),
      );
    }
  }
}
