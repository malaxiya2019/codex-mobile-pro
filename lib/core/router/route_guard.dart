import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'route_names.dart';

/// 权限级别
enum PermissionLevel {
  /// 公开页面 — 无需登录
  public,

  /// 已登录用户
  authenticated,

  /// 会员用户
  premium,

  /// 管理员
  admin,
}

/// 用户角色
enum UserRole {
  guest,
  user,
  premium,
  admin,
}

/// 鉴权状态
class AuthState {
  final bool isLoggedIn;
  final UserRole role;
  final String? userId;
  final String? token;

  const AuthState({
    this.isLoggedIn = false,
    this.role = UserRole.guest,
    this.userId,
    this.token,
  });

  bool get isGuest => !isLoggedIn;
  bool get isPremium => role == UserRole.premium || role == UserRole.admin;
  bool get isAdmin => role == UserRole.admin;

  /// 检查是否有权限访问某级别页面
  bool canAccess(PermissionLevel level) {
    switch (level) {
      case PermissionLevel.public:
        return true;
      case PermissionLevel.authenticated:
        return isLoggedIn;
      case PermissionLevel.premium:
        return isPremium;
      case PermissionLevel.admin:
        return isAdmin;
    }
  }

  AuthState copyWith({
    bool? isLoggedIn,
    UserRole? role,
    String? userId,
    String? token,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      role: role ?? this.role,
      userId: userId ?? this.userId,
      token: token ?? this.token,
    );
  }
}

/// 鉴权 Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  /// 登录（预留）
  Future<void> login(String userId, String token, {UserRole role = UserRole.user}) async {
    state = AuthState(
      isLoggedIn: true,
      role: role,
      userId: userId,
      token: token,
    );
    await _saveToken(token);
  }

  /// 登出
  Future<void> logout() async {
    state = const AuthState();
    await _clearToken();
  }

  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    } catch (_) {}
  }

  Future<void> _clearToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (_) {}
  }
}

/// 路由配置 — 页面权限映射
class RoutePermissions {
  /// 获取页面的权限级别
  static PermissionLevel of(String path) {
    switch (path) {
      case RouteNames.home:
      case RouteNames.termuxTest:
      case RouteNames.themeSettings:
      case RouteNames.localeSettings:
      case RouteNames.workspaceList:
        return PermissionLevel.public;

      case RouteNames.deploy:
      case RouteNames.aiChat:
        return PermissionLevel.public;

      default:
        return PermissionLevel.public;
    }
  }

  /// 路由是否需要鉴权
  static bool requiresAuth(String path) {
    return of(path) != PermissionLevel.public;
  }

  /// 获取无权访问时的重定向路径
  static String? getRedirectPath(String path, AuthState auth) {
    final required = of(path);
    if (auth.canAccess(required)) return null;

    // 未登录访问需登录页面 → 重定向到首页
    if (required == PermissionLevel.authenticated && !auth.isLoggedIn) {
      return RouteNames.home;
    }

    // 权限不足 → 重定向到首页
    return RouteNames.home;
  }
}
