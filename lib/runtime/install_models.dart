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
  downloading,
  extracting,
  configuring,
  verifying,
  completed,
  failed,
  blocked,
}

/// 安装结果
class InstallResult {
  final RuntimeTool tool;
  final bool success;
  final String? errorMessage;
  final String? version;
  final InstallPhase phase;

  const InstallResult({
    required this.tool,
    required this.success,
    this.errorMessage,
    this.version,
    this.phase = InstallPhase.completed,
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
