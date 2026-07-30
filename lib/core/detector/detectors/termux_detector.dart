/// ====================================================================
/// Termux Runtime 检测器（新版）
///
/// 检测 Termux Runtime 的真实状态，不是 Android 系统 Shell。
///
/// 检测项：
///   1. Termux APK 是否安装
///   2. RUN_COMMAND Intent 是否可用
///   3. Termux 命令能否真正执行
///   4. Termux Prefix 是否存在
///   5. 包管理器是否可用（pkg / apt / dpkg）
///
/// 不再把 /system/bin/sh 误报为「Termux 环境」。
/// ====================================================================

import '../../termux/termux_runtime_bridge.dart';
import '../../logger/log_service.dart';
import '../detection_result.dart';
import '../detector.dart';

/// Termux Runtime 检测状态
enum TermuxRuntimeStatus {
  /// Termux 完全可用（包已安装 + Intent 可用 + 命令可执行）
  available,

  /// Termux 已安装但通信失败
  installedButUnreachable,

  /// Termux 未安装
  notInstalled,
}

class TermuxDetector extends Detector {
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

  /// 缺失提示
  @override
  String? get missingHint => '需要安装 Termux（F-Droid 版本），用于提供开发环境';

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();
    final bridge = TermuxRuntimeBridge.instance;

    try {
      // 1. 完整诊断
      final diag = await bridge.diagnose();
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      // 2. 如果 Termux 完全可用
      if (diag.isAvailable) {
        // 获取详细环境信息
        final env = await bridge.getEnvironment();

        // 版本文字
        final versionParts = <String>[];
        if (diag.version != null) versionParts.add(diag.version!);

        // 包管理器
        String pkgInfo;
        switch (diag.pkgManager) {
          case TermuxPackageManagerStatus.pkg:
            pkgInfo = 'pkg';
            break;
          case TermuxPackageManagerStatus.apt:
            pkgInfo = 'apt';
            break;
          case TermuxPackageManagerStatus.dpkg:
            pkgInfo = 'dpkg';
            break;
          case TermuxPackageManagerStatus.unavailable:
            pkgInfo = '无包管理器';
            break;
        }
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
