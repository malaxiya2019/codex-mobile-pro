/// ====================================================================
/// Runtime 安装模型
///
/// 安装流程中共享的数据模型（独立于具体安装器实现）。
/// RuntimeInstaller（.deb 单包）已删除，模型保留供 Linux Runtime
/// 安装器与 RuntimeManager 使用。
/// ====================================================================
library;

import 'runtime_dependency.dart';

/// 安装阶段
enum InstallPhase {
  pending,

  /// 下载 / 拉取阶段
  downloading,

  /// 解压阶段
  extracting,

  /// 安装执行阶段（apt / npm install）
  installing,

  /// 配置阶段
  configuring,

  /// 验证阶段
  verifying,

  /// 完成
  completed,

  /// 失败
  failed,

  /// 因依赖失败被阻塞
  blocked,
}

/// 安装结果
class InstallResult {
  final RuntimeTool tool;
  final bool success;
  final String? errorMessage;
  final String? version;
  final InstallPhase phase;

  /// 非致命告警：主体安装成功，但增强步骤（shell 快捷命令注入 /
  /// config 写入 / skills 部署 / threadripper 部署）失败的原因列表。
  /// UI 在成功态可据此展示「成功但有警告」。为空时 UI 不展示。
  final List<String> warnings;

  const InstallResult({
    required this.tool,
    required this.success,
    this.errorMessage,
    this.version,
    this.phase = InstallPhase.completed,
    this.warnings = const [],
  });
}

/// 安装进度回调
typedef InstallProgressCallback = void Function(
  RuntimeTool tool,
  InstallPhase phase,
  double progress,
  String message,
);

/// 详细安装错误码（@deprecated 改用 DeployErrorCode）
enum InstallErrorCode {
  none,
  archNotSupported,
  downloadFailed,
  sha256Mismatch,
  extractionFailed,
  healthCheckFailed,
  npmMissing,
  storageInsufficient,
  permissionDenied,
  unknown,
}

/// 带错误码的安装异常（@deprecated 改用 DeployError）
class InstallException implements Exception {
  final InstallErrorCode code;
  final String message;
  final String? detail;

  const InstallException(this.code, this.message, {this.detail});

  @override
  String toString() => 'InstallException[$code]: $message';
}
