import 'dart:convert';

import 'package:http/http.dart' as http;

/// 应用更新信息（来自 GitHub Release）
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tagName,
    this.downloadUrl,
    this.releaseNotes,
    this.publishedAt,
  });

  /// 语义版本号（不含 v 前缀），如 1.0.1
  final String version;

  /// GitHub Release tag，如 v1.0.1
  final String tagName;

  /// APK 下载直链（browser_download_url）
  final String? downloadUrl;

  /// Release 说明
  final String? releaseNotes;

  final DateTime? publishedAt;

  bool get hasApkAsset => downloadUrl != null && downloadUrl!.isNotEmpty;
}

/// 语义版本比较（主.次.补丁，忽略 prerelease 后缀）
class VersionCompare {
  VersionCompare._();

  /// 返回 a > b ? 1 : a < b ? -1 : 0
  /// 非法段按 0 处理。
  static int compare(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va < vb ? -1 : 1;
    }
    return 0;
  }

  static List<int> _parts(String v) {
    // 去掉 v 前缀和 prerelease/build 后缀
    final cleaned = v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[-+]')).first;
    return cleaned
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
  }
}

/// GitHub Release 更新检查器
///
/// 查询 https://api.github.com/repos/{owner}/{repo}/releases/latest，
/// 解析 tag_name → 版本号、assets → APK 下载地址。
/// 公共仓库无需 token（未认证 rate limit 60 次/时，足够日常检查）。
class UpdateChecker {
  UpdateChecker({
    required this.currentVersion,
    http.Client? httpClient,
    this.repoOwner = defaultRepoOwner,
    this.repoName = defaultRepoName,
  }) : _client = httpClient ?? http.Client();

  static const String defaultRepoOwner = 'malaxiya2019';
  static const String defaultRepoName = 'codex-mobile-pro';
  static const String _apiBase = 'https://api.github.com';

  /// 当前安装版本（语义版本，无 v 前缀）
  final String currentVersion;
  final String repoOwner;
  final String repoName;
  final http.Client _client;

  /// 检查最新 Release。
  ///
  /// - 有更新且包含 APK 资产：返回 [UpdateInfo]
  /// - 无更新 / 仓库无 Release（404）/ 无 APK 资产：返回 null
  /// - 网络/解析异常：抛出 [UpdateCheckException]
  Future<UpdateInfo?> checkForUpdate() async {
    final uri = Uri.parse('$_apiBase/repos/$repoOwner/$repoName/releases/latest');
    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'codex-mobile-pro',
        },
      );
    } catch (e) {
      throw UpdateCheckException('网络请求失败: $e');
    }

    if (response.statusCode == 404) {
      // 仓库还没有任何 Release
      return null;
    }
    if (response.statusCode != 200) {
      throw UpdateCheckException(
        'GitHub API 返回 ${response.statusCode}: ${response.body}',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw UpdateCheckException('解析 Release 响应失败: $e');
    }

    final tagName = json['tag_name'] as String? ?? '';
    final version = tagName.replaceFirst(RegExp(r'^v'), '');
    if (version.isEmpty) return null;

    // 版本不高于当前 → 无更新
    if (VersionCompare.compare(version, currentVersion) <= 0) return null;

    // 从 assets 找 APK
    String? downloadUrl;
    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map &&
            (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String?;
          if (downloadUrl != null) break;
        }
      }
    }

    return UpdateInfo(
      version: version,
      tagName: tagName,
      downloadUrl: downloadUrl,
      releaseNotes: json['body'] as String?,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
    );
  }

  void dispose() => _client.close();
}

/// 更新检查失败
class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}
