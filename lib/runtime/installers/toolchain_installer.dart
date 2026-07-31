/// ====================================================================
/// 工具链安装器 — 抽象基类
///
/// 每个 Coding Runtime 工具一个 Installer：
///   install(ctx) 幂等执行：
///     1. 检测已安装（rootfs 内 --version）→ 已装直接 PASS（SKIP）
///     2. 安装（apt / npm，全部在 Ubuntu rootfs 内）
///     3. 验证版本
///
/// 状态约定（用户 Phase 4）：
///   - NOT_INSTALLED → INSTALLING → VERIFYING → INSTALLED
///   - FAILED（带真实原因） / UNSUPPORTED（仅真正的平台不支持）
/// 禁止把「未实现」显示成「暂不支持」。
/// ====================================================================
library;

import '../../core/logger/log_service.dart';
import '../deploy_error.dart';
import '../install_models.dart';
import '../runtime_dependency.dart';
import 'toolchain_context.dart';

/// 工具链安装器抽象基类
abstract class ToolchainInstaller {
  /// 对应工具
  RuntimeTool get tool;

  /// 显示名称（Node.js / Git / ...）
  String get displayName;

  /// 执行安装（幂等）
  ///
  /// 返回 InstallResult：
  ///   - 已安装 / 安装成功 → success: true, version: 版本号
  ///   - 安装失败 → success: false, errorMessage: DeployError.userFriendly
  Future<InstallResult> install(ToolchainContext ctx);

  /// 是否已安装（rootfs 内真实检测）
  Future<bool> isInstalled(ToolchainContext ctx);

  /// 获取已安装版本（未安装返回 null）
  Future<String?> installedVersion(ToolchainContext ctx);

  /// 上报安装进度
  void report(
    ToolchainContext ctx,
    InstallPhase phase,
    double progress,
    String message,
  ) {
    _onProgress?.call(tool, phase, progress, message);
    LogService.info('Toolchain', '[$displayName] $message');
  }

  /// 构造成功结果
  InstallResult success(String version, {bool skipped = false}) {
    return InstallResult(
      tool: tool,
      success: true,
      version: skipped ? '已安装 $version' : version,
    );
  }

  /// 构造失败结果（携带真实原因）
  InstallResult failure(Object error) {
    final message = error is DeployError
        ? error.userFriendly
        : '安装失败: $error';
    return InstallResult(
      tool: tool,
      success: false,
      errorMessage: message,
      phase: InstallPhase.failed,
    );
  }

  /// 安装进度回调（由 RuntimeManager 注入）
  InstallProgressCallback? _onProgress;

  /// 绑定进度回调
  void bindProgress(InstallProgressCallback? cb) {
    _onProgress = cb;
  }
}
