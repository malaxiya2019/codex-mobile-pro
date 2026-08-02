import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// APK 下载服务
///
/// 将 Release 里的 APK 下载到 `<应用文档目录>/updates/`，
/// 供原生安装器通过 FileProvider 生成 content URI 后安装。
class UpdateDownloader {
  UpdateDownloader({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;

  /// 下载 [url] 到 `<文档目录>/updates/<fileName>`，返回本地绝对路径。
  ///
  /// [onProgress] 回调：参数为 (receivedBytes, totalBytes)；total 可能为 0
  /// （服务器未返回 Content-Length 时）。
  Future<String> download(
    String url, {
    required String fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'updates'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final target = File(p.join(dir.path, fileName));

    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw UpdateDownloadException('下载失败，HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? 0;
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
    } catch (e) {
      await sink.close();
      if (target.existsSync()) {
        try {
          target.deleteSync();
        } catch (_) {}
      }
      throw UpdateDownloadException('下载中断: $e');
    }
    await sink.close();
    return target.path;
  }

  void dispose() => _client.close();
}

/// 下载失败
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
