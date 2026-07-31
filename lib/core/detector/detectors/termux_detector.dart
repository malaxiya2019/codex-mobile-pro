/// ====================================================================
/// Termux Runtime 检测器（新版）
///
/// 检测 Termux Runtime 的真实状态，不是 Android 系统 Shell。
///
/// 使用 TermuxTransport 进行检测，不再直接访问 TermuxRuntimeBridge。
///
/// 检测项：
///   1. Termux APK 是否安装
///   2. RUN_COMMAND Intent 是否可用
///   3. Termux 命令能否真正执行
///   4. Termux Prefix 是否存在
///   5. 包管理器是否可用（pkg / apt / dpkg）
/// ====================================================================
library;

import '../../../runtime/termux/termux_transport.dart';
import '../../../runtime/termux/method_channel_transport.dart';
import '../../logger/log_service.dart';
import '../detection_result.dart';
import '../detector.dart';

class TermuxDetector extends Detector {
  final TermuxTransport _transport;

  TermuxDetector({TermuxTransport? transport})
    : _transport = transport ?? MethodChannelTermuxTransport();

  @override
  String get id => 'termux';
  @override
  String get name => 'Termux Runtime';
  @override
  String get icon => '📦';

  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.coding;

  @override
  String? get missingHint => '需要安装 Termux（F-Droid 版本），用于提供开发环境';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();

    try {
      // 1. 完整诊断
      final diag = await _transport.diagnose();
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      // 2. 如果 Termux 完全可用
      if (diag.isAvailable) {
        final env = await _transport.getEnvironment();

        final versionParts = <String>[];
        if (diag.version != null) versionParts.add(diag.version!);

        final pkgInfo = switch (diag.pkgManager) {
          TermuxPkgManager.pkg => 'pkg',
          TermuxPkgManager.apt => 'apt',
          TermuxPkgManager.dpkg => 'dpkg',
          TermuxPkgManager.unavailable => '无包管理器',
        };
        if (versionParts.isNotEmpty) {
          versionParts.add('PM: $pkgInfo');
        } else {
          versionParts.add(pkgInfo);
        }

        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.installed,
          version: versionParts.join(' · '),
          path: env.prefixPath ?? '/data/data/com.termux/files/usr',
          durationMs: elapsed,
          category: category,
        );
      }

      // 3. 安装了但不可用
      if (diag.packageInstalled && !diag.works) {
        LogService.warning('TermuxDetector',
            'Termux 已安装但不可用: ${diag.lastError}');

        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.missing,
          version: '已安装但不可用',
          errorMessage: diag.lastError.isNotEmpty
              ? diag.lastError
              : 'RUN_COMMAND Intent 通信失败',
          durationMs: elapsed,
          category: category,
          missingHint: 'Termux 已安装但 App 无法通信，请重启 Termux 后重试',
        );
      }

      // 4. 未安装
      LogService.info('TermuxDetector', 'Termux 未安装');
      return DetectionResult(
        id: id,
        name: name,
        icon: icon,
        status: DetectionStatus.missing,
        durationMs: elapsed,
        category: category,
        missingHint: missingHint,
      );
    } catch (e) {
      LogService.error('TermuxDetector', '检测失败: $e');
      return DetectionResult(
        id: id,
        name: name,
        icon: icon,
        status: DetectionStatus.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        errorMessage: e.toString(),
        category: category,
      );
    }
  }
}
