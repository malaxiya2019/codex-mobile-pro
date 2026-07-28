import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/git_repository.dart';
import '../models/github_pr.dart';
import '../../../core/logger/log_service.dart';

/// GitHub API 服务
///
/// 提供：
/// - GitHub OAuth 设备授权码登录
/// - Token 安全存储
/// - 仓库列表/详情查询
/// - 用户信息获取
class GitHubService {
  // static const String _clientId = .Ov23li123456789abcdef.; // 占位，实际需注册
  static const String _tokenKey = 'github_token';
  static const String _userKey = 'github_user';

  String? _token;

  /// 获取当前 Access Token
  String? get accessToken => _token;
  Map<String, dynamic>? _userInfo;

  /// 是否已登录
  bool get isLoggedIn => _token != null;

  /// 当前用户信息
  Map<String, dynamic>? get userInfo => _userInfo;

  /// 当前用户名
  String? get username => _userInfo?['login'];

  /// 加载已保存的 Token
  Future<bool> loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token != null) {
        _token = token;
        // 加载用户信息
        final userJson = prefs.getString(_userKey);
        if (userJson != null) {
          _userInfo = jsonDecode(userJson) as Map<String, dynamic>;
        }
        return true;
      }
    } catch (e) {
      LogService.error('GitHub', '加载 Token 失败: $e');
    }
    return false;
  }

  /// 保存 Token
  Future<void> saveToken(String token) async {
    _token = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      LogService.error('GitHub', '保存 Token 失败: $e');
    }
  }

  /// 清除 Token（登出）
  Future<void> clearToken() async {
    _token = null;
    _userInfo = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (e) {
      LogService.error('GitHub', '清除 Token 失败: $e');
    }
  }

  /// 发起 GitHub API 请求
  Future<Map<String, dynamic>?> _apiGet(String path) async {
    if (_token == null) return null;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(
        Uri.parse('https://api.github.com$path'),
      );
      request.headers.set('Authorization', 'Bearer $_token');
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'CodexMobilePro/1.0');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(body) as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        LogService.warning('GitHub', 'Token 无效，请重新登录');
        await clearToken();
        return null;
      } else {
        LogService.warning('GitHub', 'API 请求失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      LogService.error('GitHub', 'API 请求异常: $e');
      return null;
    }
  }

  /// 发起 GitHub API GET 请求（返回列表）
  Future<List<dynamic>> _apiGetList(String path) async {
    if (_token == null) return [];
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(
        Uri.parse('https://api.github.com$path'),
      );
      request.headers.set('Authorization', 'Bearer $_token');
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'CodexMobilePro/1.0');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        return jsonDecode(body) as List<dynamic>;
      }
    } catch (e) {
      LogService.error('GitHub', 'API 列表请求异常: $e');
    }
    return [];
  }

  /// 验证 Token 并获取用户信息
  Future<Map<String, dynamic>?> verifyToken(String token) async {
    _token = token;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/user'),
      );
      request.headers.set('Authorization', 'Bearer $_token');
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'CodexMobilePro/1.0');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final user = jsonDecode(body) as Map<String, dynamic>;
        _userInfo = user;
        await saveToken(token);
        // 保存用户信息
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, jsonEncode(user));
        return user;
      } else {
        _token = null;
        return null;
      }
    } catch (e) {
      _token = null;
      LogService.error('GitHub', 'Token 验证失败: $e');
      return null;
    }
  }

  /// 获取当前用户信息
  Future<Map<String, dynamic>?> getUserInfo() async {
    if (_token == null) return null;
    final data = await _apiGet('/user');
    if (data != null) {
      _userInfo = data;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(data));
    }
    return data;
  }

  /// 获取用户仓库列表
  Future<List<GitRepository>> getUserRepos({
    int page = 1,
    int perPage = 30,
    String type = 'owner',
    String sort = 'updated',
  }) async {
    final data = await _apiGetList(
      '/user/repos?page=$page&per_page=$perPage&type=$type&sort=$sort',
    );

    return data
        .map((e) => GitRepository.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 搜索仓库
  Future<List<GitRepository>> searchRepos(
    String query, {
    int page = 1,
    int perPage = 10,
  }) async {
    final data = await _apiGet(
      '/search/repositories?q=${Uri.encodeComponent(query)}&page=$page&per_page=$perPage',
    );

    if (data == null) return [];
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => GitRepository.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取仓库详情
  Future<GitRepository?> getRepo(String owner, String repo) async {
    final data = await _apiGet('/repos/$owner/$repo');
    if (data == null) return null;
    return GitRepository.fromJson(data);
  }

  /// 获取仓库分支列表
  Future<List<GitBranch>> getRepoBranches(String owner, String repo) async {
    final data = await _apiGetList('/repos/$owner/$repo/branches');
    return data.map((e) {
      final item = e as Map<String, dynamic>;
      return GitBranch(
        name: item['name'] ?? '',
        commitSha: item['commit']?['sha']?.toString().substring(0, 7),
      );
    }).toList();
  }


  // ── Pull Request 操作 ──

  /// 获取仓库 Pull Request 列表
  Future<List<PullRequest>> getPullRequests(
    String owner, String repo, {
    String state = 'open',
    int page = 1,
    int perPage = 20,
  }) async {
    final data = await _apiGetList(
      '/repos///pulls?state=&page=&per_page=',
    );
    return data
        .map((e) => PullRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取 Pull Request 详情
  Future<PullRequest?> getPullRequest(String owner, String repo, int number) async {
    final data = await _apiGet('/repos///pulls/');
    if (data == null) return null;
    return PullRequest.fromJson(data);
  }

  /// 获取 Pull Request 评论
  Future<List<GitHubComment>> getPullRequestComments(
    String owner, String repo, int number,
  ) async {
    final data = await _apiGetList(
      '/repos///pulls//comments',
    );
    return data
        .map((e) => GitHubComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Issue 操作 ──

  /// 获取仓库 Issue 列表
  Future<List<GitHubIssue>> getIssues(
    String owner, String repo, {
    String state = 'open',
    int page = 1,
    int perPage = 20,
  }) async {
    final data = await _apiGetList(
      '/repos///issues?state=&page=&per_page=',
    );
    return data
        .map((e) => GitHubIssue.fromJson(e as Map<String, dynamic>))
        .where((i) => !i.isPullRequest) // 过滤掉 PR（GitHub API 会将 PR 也返回为 Issue）
        .toList();
  }

  /// 获取 Issue 详情
  Future<GitHubIssue?> getIssue(String owner, String repo, int number) async {
    final data = await _apiGet('/repos///issues/');
    if (data == null) return null;
    return GitHubIssue.fromJson(data);
  }

  /// 获取 Issue 评论
  Future<List<GitHubComment>> getIssueComments(
    String owner, String repo, int number,
  ) async {
    final data = await _apiGetList(
      '/repos///issues//comments',
    );
    return data
        .map((e) => GitHubComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 检查是否有可用 Token
  Future<bool> hasToken() async {
    if (_token != null) return true;
    return loadToken();
  }
}
