import 'package:flutter/services.dart';

/// 日志导出平台通道
///
/// 与 Kotlin LogExportPlugin 通信，通过 MediaStore 将日志写入
/// 公共 Download 目录（targetSdk 36 下无需运行时权限）。
class LogExportChannel {
  static const MethodChannel _channel =
      MethodChannel('com.codexmobile.app/log/export');

  /// 写入 Download 目录，成功返回目标文件名，失败抛异常。
  static Future<String> writeToDownload({
    required String fileName,
    required String content,
  }) async {
    final result = await _channel.invokeMethod<String>('writeToDownload', {
      'fileName': fileName,
      'content': content,
    });
    if (result == null || result.isEmpty) {
      throw StateError('写入 Download 失败（返回空）');
    }
    return result;
  }
}
