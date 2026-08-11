import 'dart:async';

import 'package:codex_mobile_pro/features/git/providers/git_provider.dart';
import 'package:codex_mobile_pro/features/git/services/github_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 无网络 fake：替代 GitHubService 的网络调用，仅驱动认证状态流转。
/// 只 override Notifier 依赖的方法（hasToken/userInfo/getUserInfo/clearToken/isLoggedIn），
/// 不触碰生产网络逻辑。
class FakeGitHubService extends GitHubService {
  FakeGitHubService({super.storage});

  /// secure storage 中是否存在 token
  bool tokenExists = false;

  /// token 是否有效（false 模拟 GitHub 401 后 service 已 clearToken）
  bool tokenValid = true;

  /// 缓存的用户信息
  Map<String, dynamic>? userResult;

  /// 模拟网络/5xx/限流：getUserInfo 返回 null 但 token 仍有效
  bool userInfoReturnsNull = false;

  /// 模拟 GitHub 401：getUserInfo 内部已清 token 并返回 null
  bool userInfoReturnsUnauthorized = false;

  int clearTokenCalls = 0;
  final userInfoCalled = Completer<void>();

  @override
  bool get isLoggedIn => tokenExists && tokenValid;

  @override
  Map<String, dynamic>? get userInfo => userResult;

  @override
  Future<bool> hasToken() async => tokenExists;

  @override
  Future<Map<String, dynamic>?> getUserInfo() async {
    if (!userInfoCalled.isCompleted) userInfoCalled.complete();
    if (userInfoReturnsUnauthorized) {
      // 复刻 _apiGet 的 401 行为：先清 token 再返回 null
      tokenExists = false;
      return null;
    }
    if (userInfoReturnsNull) return null;
    return userResult;
  }

  @override
  Future<void> clearToken() async {
    clearTokenCalls++;
    tokenExists = false;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('GitHub Token 持久化', () {
    test('登录成功 → Token 写入 secure storage（不落在 SharedPreferences 明文）', () async {
      final service = GitHubService();
      await service.saveToken('ghp_persist_secret');

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'github_token'), 'ghp_persist_secret');

      // 禁止明文落 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('github_token'), isNull);
    });

    test('App 重启（新实例）→ loadToken 从 secure storage 恢复登录态', () async {
      FlutterSecureStorage.setMockInitialValues({
        'github_token': 'ghp_persist_secret',
        'github_user': '{"login":"octocat","avatar_url":"https://x/a.png"}',
      });

      // 模拟重启：全新实例，内存 _token 为空
      final restarted = GitHubService();
      expect(restarted.isLoggedIn, isFalse);

      final ok = await restarted.loadToken();
      expect(ok, isTrue);
      expect(restarted.accessToken, 'ghp_persist_secret');
      expect(restarted.isLoggedIn, isTrue);
      expect(restarted.username, 'octocat');
    });

    test('登出 → Token 与用户信息从 secure storage 删除', () async {
      FlutterSecureStorage.setMockInitialValues({
        'github_token': 'ghp_persist_secret',
        'github_user': '{"login":"octocat"}',
      });

      const storage = FlutterSecureStorage();
      final service = GitHubService();
      expect(await service.loadToken(), isTrue);
      expect(service.isLoggedIn, isTrue);

      await service.clearToken();

      expect(service.isLoggedIn, isFalse);
      expect(await storage.read(key: 'github_token'), isNull);
      expect(await storage.read(key: 'github_user'), isNull);
    });

    test('saveToken/loadToken/clearToken 全程无异常（异常信息才会进日志，绝不带 token）', () async {
      // 设计保证：GitHubService 日志只输出平台异常 $e，绝不拼接 token 内容。
      // 这里验证正常存取全程无异常，避免任何 token 进入日志/异常信息。
      final service = GitHubService();
      await service.saveToken('ghp_should_not_leak_123456');
      final ok = await service.loadToken();
      expect(ok, isTrue);
      await service.clearToken();
      expect(service.isLoggedIn, isFalse);
    });
  });

  group('GitHubAuthNotifier 登录态恢复', () {
    test('初始 isRestoring=true，恢复完成后置 false', () async {
      final fake = FakeGitHubService()..tokenExists = true;
      final notifier = GitHubAuthNotifier(fake);

      // 恢复是异步的：刚创建时处于恢复中（页面应显示加载，不弹登录页）
      expect(notifier.state.isRestoring, isTrue);

      await fake.userInfoCalled.future;
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.isRestoring, isFalse);
      expect(notifier.state.isLoggedIn, isTrue);
    });

    test('secure storage 有 token → 恢复登录态（含用户名）', () async {
      final fake = FakeGitHubService()
        ..tokenExists = true
        ..userResult = {'login': 'octocat', 'avatar_url': 'https://x/a.png'};
      final notifier = GitHubAuthNotifier(fake);

      await fake.userInfoCalled.future;
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.isLoggedIn, isTrue);
      expect(notifier.state.username, 'octocat');
      expect(notifier.state.isRestoring, isFalse);
    });

    test('secure storage 无 token → 保持未登录（isRestoring 正常结束）', () async {
      final fake = FakeGitHubService(); // tokenExists = false
      final notifier = GitHubAuthNotifier(fake);

      // 无 token：不调用 getUserInfo，等 hasToken 完成即可
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isRestoring, isFalse);
      expect(notifier.state.isLoggedIn, isFalse);
      expect(fake.userInfoCalled.isCompleted, isFalse);
    });

    test('用户信息刷新失败（网络/限流）→ 保留登录态，不误删有效 token', () async {
      final fake = FakeGitHubService()
        ..tokenExists = true
        ..tokenValid = true
        ..userResult = {'login': 'octocat'}
        ..userInfoReturnsNull = true; // 模拟 5xx/限流：返回 null 但 token 仍有效
      final notifier = GitHubAuthNotifier(fake);

      await fake.userInfoCalled.future;
      await Future<void>.delayed(Duration.zero);

      // 关键回归：网络失败不清 token、不清登录态（旧版在这里误删）
      expect(notifier.state.isLoggedIn, isTrue);
      expect(notifier.state.username, 'octocat'); // 用缓存恢复
      expect(fake.clearTokenCalls, 0);
    });

    test('GitHub 明确 401 → 登录态被清除（token 已失效）', () async {
      final fake = FakeGitHubService()
        ..tokenExists = true
        ..userResult = {'login': 'octocat'}
        ..userInfoReturnsUnauthorized = true;
      final notifier = GitHubAuthNotifier(fake);

      await fake.userInfoCalled.future;
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.isLoggedIn, isFalse);
      expect(notifier.state.isRestoring, isFalse);
    });
  });
}
