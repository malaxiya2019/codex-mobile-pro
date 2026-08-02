import 'package:flutter/services.dart';

/// 更新安装平台通道
///
/// 与 Kotlin UpdateInstallerPlugin 通信：通过 FileProvider 生成
/// content:// URI，ACTION_VIEW 拉起系统包安装器安装已下载的 APK。
class UpdateInstallerChannel {
  static const MethodChannel _channel =
      MethodChannel('com.codexmobile.app/update');

  /// 安装本地 APK 文件。
  ///
  /// [apkPath] 必须位于应用私有目录（如文档目录/updates/），
  /// 否则 FileProvider 会拒绝生成 URI。
  /// 成功仅表示已拉起系统安装器，安装结果由系统 UI 决定。
  static Future<bool> installApk(String apkPath) async {
    final result = await _channel.invokeMethod<bool>('installApk', {
      'path': apkPath,
    });
    return result ?? false;
  }
}
