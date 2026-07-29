import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as path;
import '../core/logger/log_service.dart';
import 'runtime_manifest.dart';

/// ====================================================================
/// Artifact 管理器
///
/// 负责：
/// 1. 从 Termux package mirror 下载 .deb 文件
/// 2. 验证 SHA256
/// 3. 解析 ar 格式提取 data.tar.xz
/// 4. 使用 archive 包解压 tar.xz 并提取文件
///
/// 不依赖系统命令 (ar/tar/xz)，纯 Dart 实现。
/// ====================================================================

/// 下载进度回调
typedef DownloadProgressCallback = void Function(
    int bytesDownloaded, int totalBytes, String message);

/// Artifact 管理器
class ArtifactManager {
  /// 下载单个 artifact 并提取到目标目录
  ///
  /// [artifact]  要下载的 artifact
  /// [targetDir] 提取目标根目录（如 runtime/node/）
  /// [onProgress] 进度回调
  static Future<void> downloadAndExtract({
    required RuntimeArtifact artifact,
    required String targetDir,
    DownloadProgressCallback? onProgress,
  }) async {
    final cachedDir = '$targetDir/.cache';
    await Directory(cachedDir).create(recursive: true);
    final debPath = '$cachedDir/${artifact.name}.deb';

    onProgress?.call(0, artifact.size, '下载 ${artifact.name}...');

    // ─── 下载 .deb 文件 ───
    await _downloadFile(
      url: artifact.url,
      destPath: debPath,
      expectedSize: artifact.size,
      expectedSha256: artifact.sha256,
      onProgress: (downloaded, total) {
        onProgress?.call(downloaded, total, '下载 ${artifact.name}...');
      },
    );

    onProgress?.call(artifact.size, artifact.size, '验证 ${artifact.name}...');

    // ─── 验证 SHA256 ───
    final actualSha256 = await _computeSha256(debPath);
    if (actualSha256 != artifact.sha256) {
      // 清理损坏文件
      await File(debPath).delete();
      throw ArtifactException(
        '${artifact.name} SHA256 校验失败\n'
        '期望: ${artifact.sha256}\n'
        '实际: $actualSha256',
      );
    }

    onProgress?.call(artifact.size, artifact.size, '解压 ${artifact.name}...');

    // ─── 从 .deb 中提取文件 ───
    await _extractFromDeb(
      debPath: debPath,
      targetDir: targetDir,
      includeFiles: artifact.includeFiles,
      stripComponents: artifact.stripComponents,
    );

    // 清理缓存
    try {
      await File(debPath).delete();
    } catch (_) {}

    onProgress?.call(artifact.size, artifact.size, '${artifact.name} 完成');
  }

  /// 下载文件带进度和 SHA256 验证
  static Future<void> _downloadFile({
    required String url,
    required String destPath,
    required int expectedSize,
    required String expectedSha256,
    required void Function(int downloaded, int total) onProgress,
  }) async {
    // 使用 HttpClient 以获得进度回调
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw ArtifactException(
          '下载失败: HTTP ${response.statusCode} — $url',
        );
      }

      final file = File(destPath);
      final sink = file.openWrite();

      int bytesDownloaded = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        bytesDownloaded += chunk.length;
        onProgress(bytesDownloaded, expectedSize);
      }

      await sink.flush();
      await sink.close();

      final actualSize = await file.length();
      if (actualSize != expectedSize) {
        await file.delete();
        throw ArtifactException(
          '文件大小不匹配: 期望 $expectedSize, 实际 $actualSize',
        );
      }
    } finally {
      client.close();
    }
  }

  /// 从 .deb 文件中提取指定文件
  ///
  /// .deb = ar 归档，包含 debian-binary + control.tar.xz + data.tar.xz
  static Future<void> _extractFromDeb({
    required String debPath,
    required String targetDir,
    List<String>? includeFiles,
    int stripComponents = 5,
  }) async {
    final debBytes = await File(debPath).readAsBytes();

    // 1. 解析 ar 格式，提取 data.tar.xz
    final dataTarXz = _extractArMember(debBytes, 'data.tar.xz');
    if (dataTarXz == null) {
      // 尝试 data.tar.gz
      final dataTarGz = _extractArMember(debBytes, 'data.tar.gz');
      if (dataTarGz == null) {
        throw ArtifactException('.deb 中没有找到 data.tar.xz 或 data.tar.gz');
      }
      // 解压 gzip
      final tarBytes = GZipDecoder().decodeBytes(dataTarGz);
      _extractTarEntries(
        tarBytes: tarBytes,
        targetDir: targetDir,
        includeFiles: includeFiles,
        stripComponents: stripComponents,
      );
    } else {
      // 解压 xz
      final tarBytes = XZDecoder().decodeBytes(dataTarXz);
      _extractTarEntries(
        tarBytes: tarBytes,
        targetDir: targetDir,
        includeFiles: includeFiles,
        stripComponents: stripComponents,
      );
    }
  }

  /// 从 ar 归档中提取指定成员的数据
  ///
  /// Ar 格式:
  /// - 魔数: "!<arch>\n" (8 字节)
  /// - 文件头: 60 字节
  ///   - name: 16 字节
  ///   - timestamp: 12 字节
  ///   - owner: 6 字节
  ///   - group: 6 字节
  ///   - mode: 8 字节
  ///   - size: 10 字节
  ///   - magic: 0x60 0x0A (2 字节)
  /// - 文件名具有 GNU 变长格式时: "/<number>" 表示文件名在符号表中
  static List<int>? _extractArMember(List<int> arBytes, String memberName) {
    const headerSize = 60;
    const magicSize = 8;

    if (arBytes.length < magicSize) return null;
    final magic = String.fromCharCodes(arBytes.sublist(0, magicSize));
    if (magic != '!<arch>\n') return null;

    int offset = magicSize;
    final nameBytes = memberName.codeUnits;

    // 获取文件名表（如果有 GNU 长文件名）
    Map<int, String>? nameMap;
    // 先检查是否有 //
    int nameTableOffset = offset;
    while (nameTableOffset < arBytes.length) {
      if (nameTableOffset + headerSize > arBytes.length) break;
      final header = arBytes.sublist(nameTableOffset, nameTableOffset + headerSize);
      final hName = String.fromCharCodes(
        header.sublist(0, 16).takeWhile((b) => b != 0x2F && b != 0x20),
      );
      if (hName == '//') {
        // 文件名表
        final sizeStr = String.fromCharCodes(
          header.sublist(48, 58).map((b) => b).toList(),
        ).trim();
        final size = int.tryParse(sizeStr) ?? 0;
        if (size > 0) {
          final nameData = arBytes.sublist(nameTableOffset + headerSize, nameTableOffset + headerSize + size);
          nameMap = _parseArNameTable(nameData);
        }
        break;
      }
      // 跳到下一个
      final sizeStr = String.fromCharCodes(
        header.sublist(48, 58).map((b) => b).toList(),
      ).trim();
      final size = int.tryParse(sizeStr) ?? 0;
      final paddedSize = size + (size % 2);
      nameTableOffset += headerSize + paddedSize;
    }

    while (offset + headerSize <= arBytes.length) {
      final headerBytes = arBytes.sublist(offset, offset + headerSize);
      final rawName = String.fromCharCodes(headerBytes.sublist(0, 16));

      // 解析文件名
      String entryName;
      final slashPos = rawName.indexOf('/');
      if (slashPos > 0 && rawName[0] == '/') {
        // GNU 长文件名索引: /<number>
        final idx = int.tryParse(rawName.substring(1, slashPos));
        if (idx != null && nameMap != null && nameMap.containsKey(idx)) {
          entryName = nameMap[idx]!;
        } else {
          entryName = rawName.substring(0, slashPos).trim();
        }
      } else {
        entryName = rawName.substring(0, slashPos > 0 ? slashPos : 16).trim();
      }

      final sizeStr = String.fromCharCodes(
        headerBytes.sublist(48, 58),
      ).trim();
      final size = int.tryParse(sizeStr) ?? 0;
      // 对齐到偶数
      final paddedSize = size + (size % 2);

      if (entryName == memberName) {
        return arBytes.sublist(
          offset + headerSize,
          offset + headerSize + size,
        );
      }

      offset += headerSize + paddedSize;
    }

    return null;
  }

  /// 解析 GNU ar 文件名表
  static Map<int, String> _parseArNameTable(List<int> data) {
    final map = <int, String>{};
    final str = String.fromCharCodes(data);
    final entries = str.split('/\n');
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i].trim();
      if (entry.isNotEmpty) {
        map[i] = entry;
      }
    }
    return map;
  }

  /// 从 tar 字节中提取指定文件
  static void _extractTarEntries({
    required List<int> tarBytes,
    required String targetDir,
    List<String>? includeFiles,
    int stripComponents = 5,
  }) {
    final decoder = TarDecoder();
    final archive = decoder.decodeBytes(tarBytes);

    for (final entry in archive) {
      if (entry.isFile) {
        final tarPath = entry.name;

        // 过滤文件
        if (includeFiles != null && !includeFiles.any((f) => tarPath.contains(f))) {
          continue;
        }

        // Strip path components
        final strippedPath = _stripPathComponents(tarPath, stripComponents);
        if (strippedPath == null || strippedPath.isEmpty) continue;

        final destPath = path.join(targetDir, strippedPath);
        final destDir = path.dirname(destPath);

        // 确保目录存在
        Directory(destDir).createSync(recursive: true);

        // 写入文件
        File(destPath).writeAsBytesSync(entry.content as List<int>);

        // 设置执行权限（如果原文件有 x 权限）
        if (entry.mode != null && (entry.mode! & 0x40) != 0) {
          Process.runSync('chmod', ['+x', destPath]);
        }
      }
    }
  }

  /// 去掉路径的前 N 个组件
  static String? _stripPathComponents(String filePath, int count) {
    final parts = path.split(filePath);
    // 移除空组件（开头的 ./ 等）
    final cleaned = parts.where((p) => p.isNotEmpty && p != '.').toList();
    if (cleaned.length <= count) return null;
    return path.joinAll(cleaned.sublist(count));
  }

  /// 计算文件的 SHA256
  static Future<String> _computeSha256(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// 检查架构是否支持
  static bool isSupportedArchitecture() {
    try {
      // 从 Android 系统属性获取支持的 ABI
      final result = Process.runSync(
        'getprop',
        ['ro.product.cpu.abi'],
      );
      if (result.exitCode == 0) {
        final abi = (result.stdout as String).trim();
        return abi == 'arm64-v8a' || abi == 'aarch64';
      }
    } catch (_) {}

    // 回退: 检查 uname
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        final arch = (result.stdout as String).trim();
        return arch == 'aarch64' || arch == 'arm64';
      }
    } catch (_) {}

    // 默认假设 arm64
    return true;
  }

  /// 获取架构显示名
  static String getArchitectureName() {
    try {
      final result = Process.runSync('getprop', ['ro.product.cpu.abi']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return 'unknown';
  }
}

/// Artifact 异常
class ArtifactException implements Exception {
  final String message;
  const ArtifactException(this.message);

  @override
  String toString() => 'ArtifactException: $message';
}
