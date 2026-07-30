import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as path;
import '../core/network/dns_cache.dart';
import '../core/network/dns_resolver.dart';
import '../core/network/ip_hosts.dart';
import 'deploy_error.dart';
import 'runtime_manifest.dart';

/// ====================================================================
/// Artifact 管理器
///
/// 负责：
/// 1. 从 Termux package mirror 下载 .deb / tar.xz 文件
/// 2. 验证 SHA256
/// 3. 解析 ar 格式提取 data.tar.xz
/// 4. 使用 archive 包解压 tar.xz 并提取文件
///
/// 不依赖系统命令 (ar/tar/xz)，纯 Dart 实现。
///
/// 多镜像 Fallback（P1）：
///   主源失败 → 按优先级尝试备用镜像 → IP 直连 → 硬编码 IP
///   参考 Firecrawl 的多引擎 fallback + feature matching 模式。
/// ====================================================================

/// 下载进度回调
typedef DownloadProgressCallback = void Function(
    int bytesDownloaded, int totalBytes, String message);

/// Artifact 管理器
class ArtifactManager {
  /// 下载单个 artifact 并提取到目标目录
  ///
  /// [artifact]  要下载的 artifact（含主 URL + 备用镜像）
  /// [targetDir] 提取目标根目录（如 runtime/node/）
  /// [onProgress] 进度回调
  /// [region]     区域偏好（如 'cn' 优先国内镜像）
  /// [dnsWorking] 当前 DNS 状态（影响镜像选择策略）
  static Future<void> downloadAndExtract({
    required RuntimeArtifact artifact,
    required String targetDir,
    DownloadProgressCallback? onProgress,
    String region = '',
    bool dnsWorking = true,
  }) async {
    final cachedDir = '$targetDir/.cache';
    await Directory(cachedDir).create(recursive: true);
    final debPath = '$cachedDir/${artifact.name}.deb';

    onProgress?.call(0, artifact.size, '下载 ${artifact.name}...');

    // ─── 构建多镜像 Fallback 链 ───────────────────────────────────
    final fallbackUrls = artifact.buildUrlFallbackChain(
      dnsWorking: dnsWorking,
      region: region,
    );

    // ─── 下载（带多镜像 fallback） ────────────────────────────────
    await _downloadFile(
      fallbackUrls: fallbackUrls,
      destPath: debPath,
      expectedSize: artifact.size,
      expectedSha256: artifact.sha256,
      onProgress: (downloaded, total) {
        onProgress?.call(downloaded, total, '下载 ${artifact.name}...');
      },
    );

    onProgress?.call(artifact.size, artifact.size, '验证 ${artifact.name}...');

    // ─── 验证 SHA256 ────────────────────────────────────────────
    final actualSha256 = await _computeSha256(debPath);
    if (actualSha256 != artifact.sha256) {
      await File(debPath).delete();
      throw DeployError(
        code: DeployErrorCode.sha256Mismatch,
        message: '${artifact.name} SHA256 校验失败',
        detail: '期望 ${artifact.sha256}, 实际 $actualSha256',
        userSuggestion: DeployErrorSuggestions.forCode(DeployErrorCode.sha256Mismatch),
      );
    }

    onProgress?.call(artifact.size, artifact.size, '解压 ${artifact.name}...');

    // ─── 从 .deb / tar.xz 中提取文件 ────────────────────────────
    if (artifact.type == ArtifactType.rootfs) {
      await _extractTarXz(
        filePath: debPath,
        targetDir: targetDir,
        stripComponents: artifact.stripComponents,
      );
    } else {
      await _extractFromDeb(
        debPath: debPath,
        targetDir: targetDir,
        includeFiles: artifact.includeFiles,
        stripComponents: artifact.stripComponents,
      );
    }

    // 清理缓存
    try { await File(debPath).delete(); } catch (_) {}

    onProgress?.call(artifact.size, artifact.size, '${artifact.name} 完成');
  }

  // ==================================================================
  // 多镜像 Fallback 下载
  // ==================================================================

  /// 每个 URL 的最大重试次数
  static const int _maxRetriesPerUrl = 3;

  /// 重试延迟基数（秒）
  static const int _retryBaseDelaySeconds = 2;

  /// 需要自动重试的网络错误关键词
  static const _retryableErrors = [
    'Connection closed',
    'connection reset',
    'Connection reset',
    'Connection refused',
    'Connection timed out',
    'SocketException',
    'HandshakeException',
    'timeout',
    'Timeout',
    'EOF',
    'broken pipe',
    'network is unreachable',
    'Network is unreachable',
    'Connection terminated',
    'Failed host lookup',
    'No address associated',
    'No such host',
    'Name or service not known',
    'Temporary failure in name resolution',
  ];

  /// DNS 相关错误关键词（触发 IP 直连 fallback）
  static const _dnsErrors = [
    'Failed host lookup',
    'No address associated',
    'No such host',
    'Name or service not known',
    'Temporary failure in name resolution',
  ];

  /// 按 fallback 链下载文件
  ///
  /// 策略：
  ///   每个 URL 尝试 _maxRetriesPerUrl 次（含指数退避）
  ///   DNS 错误自动切换到 IP 直连
  ///   当前 URL 全部重试失败 → 换下一个 URL
  ///   全部 URL 失败 → 抛出异常
  static Future<void> _downloadFile({
    required List<String> fallbackUrls,
    required String destPath,
    required int expectedSize,
    required String expectedSha256,
    required void Function(int downloaded, int total) onProgress,
  }) async {
    final partPath = '$destPath.part';
    final errors = <String>[];

    for (int urlIdx = 0; urlIdx < fallbackUrls.length; urlIdx++) {
      final baseUrl = fallbackUrls[urlIdx];
      bool dnsFailed = false;

      for (int attempt = 1; attempt <= _maxRetriesPerUrl; attempt++) {
        String currentUrl = baseUrl;

        // ─── DNS 故障时切 IP 直连 ───────────────────────────────
        if (attempt > 1 && dnsFailed) {
          final ipUrl = await _tryIpResolveAsync(currentUrl);
          if (ipUrl != null) {
            currentUrl = ipUrl;
          }
        }

        try {
          await _doDownloadFile(
            url: currentUrl,
            originalUrl: baseUrl,
            destPath: destPath,
            partPath: partPath,
            expectedSize: expectedSize,
            expectedSha256: expectedSha256,
            onProgress: onProgress,
          );
          return; // ✅ 下载成功
        } catch (e) {
          // 清理临时文件
          try { await File(partPath).delete(); } catch (_) {}
          try { await File(destPath).delete(); } catch (_) {}

          final errMsg = e.toString();
          final isRetryable = _retryableErrors.any((kw) => errMsg.contains(kw));

          if (!isRetryable) {
            // 非网络错误（SHA256 不匹配等）— 不重试，切下一个 URL
            errors.add('[$baseUrl] 不可重试: $errMsg');
            break;
          }

          // DNS 错误标记
          if (_dnsErrors.any((kw) => errMsg.contains(kw))) {
            dnsFailed = true;
          }

          // 当前 URL 已用完重试次数
          if (attempt >= _maxRetriesPerUrl) {
            errors.add('[$baseUrl] 重试耗尽: $errMsg');
            break; // 切下一个 URL
          }

          // 指数退避：2s, 4s, 8s
          final delay = Duration(seconds: _retryBaseDelaySeconds << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }

    // 所有 URL 全部失败
    throw DeployError(
        code: DeployErrorCode.allSourcesExhausted,
        message: '所有下载源均失败 (${fallbackUrls.length} 个尝试)',
        detail: errors.join('\n'),
        userSuggestion: DeployErrorSuggestions.forCode(DeployErrorCode.allSourcesExhausted),
      );
  }
  /// 公开的下载方法（仅下载，不解压）
  ///
  /// 使用 artifact 的多镜像 fallback 链尝试下载到 [destPath]。
  /// 如果 [fallbackUrls] 提供，优先使用；否则用 artifact 构建。
  static Future<void> downloadFile({
    required RuntimeArtifact artifact,
    required String destPath,
    required int expectedSize,
    required String expectedSha256,
    required void Function(int downloaded, int total) onProgress,
    List<String>? fallbackUrls,
    String region = '',
    bool dnsWorking = true,
  }) async {
    final urls = fallbackUrls ?? artifact.buildUrlFallbackChain(
      dnsWorking: dnsWorking,
      region: region,
    );
    await _downloadFile(
      fallbackUrls: urls,
      destPath: destPath,
      expectedSize: expectedSize,
      expectedSha256: expectedSha256,
      onProgress: onProgress,
    );
  }

  /// 尝试将 URL 域名替换为 IP
  ///
  /// 优先使用 DnsResolver（多层 fallback），其次使用 IpHosts 硬编码。
  static Future<String?> _tryIpResolveAsync(String url) async {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;

      // 已经是 IP，跳过
      if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) return null;

      // L1: 查 DNS 缓存（同步，最快）
      final cached = DnsCache.get(host);
      if (cached != null && cached.resolved && cached.ip != null) {
        return url.replaceFirst(host, cached.ip!);
      }

      // L2: 走 DnsResolver 完整链路（缓存 → ping → DoH → IP硬编码）
      final result = await DnsResolver.resolve(
        host,
        options: DnsResolveOptions.deep,
      );
      if (result.resolved && result.ip != null) {
        return url.replaceFirst(host, result.ip!);
      }

      // L3: 兜底 — IpHosts 硬编码
      final ips = IpHosts.ipsFor(host);
      if (ips.isNotEmpty) {
        return url.replaceFirst(host, ips.first);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // ==================================================================
  // 单次下载
  // ==================================================================

  /// 实际下载（单次，无重试）
  static Future<void> _doDownloadFile({
    required String url,
    required String originalUrl,
    required String destPath,
    required String partPath,
    required int expectedSize,
    required String expectedSha256,
    required void Function(int downloaded, int total) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));

      // IP 直连时设置 Host header
      final uri = Uri.parse(url);
      if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(uri.host)) {
        final originalUri = Uri.parse(originalUrl);
        request.headers.set('Host', originalUri.host);
      }

      final response = await request.close();

      if (response.statusCode != 200) {
        throw DeployError(
            code: DeployErrorCode.httpError,
            message: '下载失败: HTTP ${response.statusCode} — $url',
            userSuggestion: DeployErrorSuggestions.forCode(DeployErrorCode.httpError),
          );
      }

      final file = File(partPath);
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
        throw DeployError(
            code: DeployErrorCode.sizeMismatch,
            message: '文件大小不匹配: 期望 $expectedSize, 实际 $actualSize',
            userSuggestion: DeployErrorSuggestions.forCode(DeployErrorCode.sizeMismatch),
          );
      }

      await file.rename(destPath);
    } finally {
      client.close();
    }
  }

  // ==================================================================
  // 提取
  // ==================================================================

  /// 从 .deb 文件中提取指定文件
  ///
  /// .deb = ar 归档，包含 debian-binary + control.tar.xz + data.tar.xz
  static Future<void> _extractFromDeb({
    required String debPath,
    required String targetDir,
    List<String>? includeFiles,
    int stripComponents = 6,
  }) async {
    final debBytes = await File(debPath).readAsBytes();

    final dataTarXz = _extractArMember(debBytes, 'data.tar.xz');
    if (dataTarXz == null) {
      final dataTarGz = _extractArMember(debBytes, 'data.tar.gz');
      if (dataTarGz == null) {
        throw DeployError(
          code: DeployErrorCode.extractionFailed,
          message: '.deb 中没有找到 data.tar.xz 或 data.tar.gz',
          userSuggestion: DeployErrorSuggestions.forCode(DeployErrorCode.extractionFailed),
        );
      }
      final tarBytes = GZipDecoder().decodeBytes(dataTarGz);
      _extractTarEntries(
        tarBytes: tarBytes,
        targetDir: targetDir,
        includeFiles: includeFiles,
        stripComponents: stripComponents,
      );
    } else {
      final tarBytes = XZDecoder().decodeBytes(dataTarXz);
      _extractTarEntries(
        tarBytes: tarBytes,
        targetDir: targetDir,
        includeFiles: includeFiles,
        stripComponents: stripComponents,
      );
    }
  }

  /// 解压 tar.xz 文件（用于 rootfs）
  static Future<void> _extractTarXz({
    required String filePath,
    required String targetDir,
    int stripComponents = 1,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final tarBytes = XZDecoder().decodeBytes(bytes);
    _extractTarEntries(
      tarBytes: tarBytes,
      targetDir: targetDir,
      stripComponents: stripComponents,
    );
  }

  /// 从 ar 归档中提取指定成员
  static List<int>? _extractArMember(List<int> arBytes, String memberName) {
    const headerSize = 60;
    const magicSize = 8;

    if (arBytes.length < magicSize) return null;
    final magic = String.fromCharCodes(arBytes.sublist(0, magicSize));
    if (magic != '!<arch>\n') return null;

    int offset = magicSize;

    // 文件名表
    Map<int, String>? nameMap;
    int nameTableOffset = offset;
    while (nameTableOffset < arBytes.length) {
      if (nameTableOffset + headerSize > arBytes.length) break;
      final header = arBytes.sublist(nameTableOffset, nameTableOffset + headerSize);
      final hName = String.fromCharCodes(
        header.sublist(0, 16).takeWhile((b) => b != 0x2F && b != 0x20),
      );
      if (hName == '//') {
        final sizeStr = String.fromCharCodes(
          header.sublist(48, 58).map((b) => b).toList(),
        ).trim();
        final size = int.tryParse(sizeStr) ?? 0;
        if (size > 0) {
          final nameData = arBytes.sublist(
            nameTableOffset + headerSize,
            nameTableOffset + headerSize + size,
          );
          nameMap = _parseArNameTable(nameData);
        }
        break;
      }
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

      String entryName;
      final slashPos = rawName.indexOf('/');
      if (slashPos > 0 && rawName[0] == '/') {
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
    int stripComponents = 6,
  }) {
    final decoder = TarDecoder();
    final archive = decoder.decodeBytes(tarBytes);

    for (final entry in archive) {
      if (entry.isFile) {
        final tarPath = entry.name;

        if (includeFiles != null && !includeFiles.any((f) => tarPath.contains(f))) {
          continue;
        }

        final strippedPath = _stripPathComponents(tarPath, stripComponents);
        if (strippedPath == null || strippedPath.isEmpty) continue;

        final destPath = path.join(targetDir, strippedPath);
        final destDir = path.dirname(destPath);

        Directory(destDir).createSync(recursive: true);
        File(destPath).writeAsBytesSync(entry.content as List<int>);

        if ((entry.mode & 0x40) != 0) {
          Process.runSync('chmod', ['+x', destPath]);
        }
      }
    }
  }

  /// 去掉路径的前 N 个组件
  static String? _stripPathComponents(String filePath, int count) {
    final parts = path.split(filePath);
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
      final result = Process.runSync(
        'getprop', ['ro.product.cpu.abi'],
      );
      if (result.exitCode == 0) {
        final abi = (result.stdout as String).trim();
        return abi == 'arm64-v8a' || abi == 'aarch64';
      }
    } catch (_) {}

    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        final arch = (result.stdout as String).trim();
        return arch == 'aarch64' || arch == 'arm64';
      }
    } catch (_) {}

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

  /// 将域名 URL 转换为 IP 直连 URL
  static String? urlToIpDirect(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) return null;
      final ips = IpHosts.ipsFor(host);
      if (ips.isEmpty) return null;
      return url.replaceFirst(host, ips.first);
    } catch (_) {
      return null;
    }
  }
}

