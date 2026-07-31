import 'package:codex_mobile_pro/core/router/route_guard.dart';
import 'package:codex_mobile_pro/core/router/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionLevel', () {
    test('值定义正确', () {
      expect(PermissionLevel.values.length, 4);
      expect(PermissionLevel.values, contains(PermissionLevel.public));
      expect(PermissionLevel.values, contains(PermissionLevel.authenticated));
      expect(PermissionLevel.values, contains(PermissionLevel.premium));
      expect(PermissionLevel.values, contains(PermissionLevel.admin));
    });
  });

  group('UserRole', () {
    test('值定义正确', () {
      expect(UserRole.values.length, 4);
      expect(UserRole.values, contains(UserRole.guest));
      expect(UserRole.values, contains(UserRole.user));
      expect(UserRole.values, contains(UserRole.premium));
      expect(UserRole.values, contains(UserRole.admin));
    });
  });

  group('AuthState', () {
    test('默认是未登录访客', () {
      const state = AuthState();
      expect(state.isLoggedIn, false);
      expect(state.isGuest, true);
      expect(state.role, UserRole.guest);
    });

    test('登录后可访问 authenticated 页面', () {
      const state = AuthState(isLoggedIn: true, role: UserRole.user);
      expect(state.canAccess(PermissionLevel.public), true);
      expect(state.canAccess(PermissionLevel.authenticated), true);
      expect(state.canAccess(PermissionLevel.premium), false);
      expect(state.canAccess(PermissionLevel.admin), false);
    });

    test('premium 可访问 premium 页面', () {
      const state = AuthState(isLoggedIn: true, role: UserRole.premium);
      expect(state.canAccess(PermissionLevel.premium), true);
      expect(state.canAccess(PermissionLevel.admin), false);
    });

    test('admin 可访问所有页面', () {
      const state = AuthState(isLoggedIn: true, role: UserRole.admin);
      expect(state.canAccess(PermissionLevel.admin), true);
      expect(state.canAccess(PermissionLevel.premium), true);
      expect(state.canAccess(PermissionLevel.authenticated), true);
      expect(state.canAccess(PermissionLevel.public), true);
    });

    test('copyWith 正确', () {
      const state = AuthState();
      final updated = state.copyWith(isLoggedIn: true, role: UserRole.user);
      expect(updated.isLoggedIn, true);
      expect(updated.role, UserRole.user);
      expect(updated.isGuest, false);
    });
  });

  group('AuthNotifier', () {
    test('初始状态为访客', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final state = container.read(authProvider);
      expect(state.isLoggedIn, false);
    });

    test('login 更新状态', () async {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(authProvider.notifier);
      await notifier.login('user-1', 'token-123');

      final state = container.read(authProvider);
      expect(state.isLoggedIn, true);
      expect(state.userId, 'user-1');
      expect(state.token, 'token-123');
    });

    test('logout 重置状态', () async {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(authProvider.notifier);
      await notifier.login('user-1', 'token-123');
      await notifier.logout();

      final state = container.read(authProvider);
      expect(state.isLoggedIn, false);
      expect(state.role, UserRole.guest);
    });
  });

  group('RoutePermissions', () {
    test('公开页面无需鉴权', () {
      expect(RoutePermissions.requiresAuth(RouteNames.home), false);
      expect(RoutePermissions.requiresAuth(RouteNames.themeSettings), false);
    });

    test('访客访问公开页面不重定向', () {
      const auth = AuthState();
      expect(RoutePermissions.getRedirectPath(RouteNames.home, auth), isNull);
      expect(RoutePermissions.getRedirectPath(RouteNames.deploy, auth), isNull);
    });

    test('getRedirectPath 对公开页面返回 null', () {
      const auth = AuthState();
      expect(RoutePermissions.getRedirectPath(RouteNames.home, auth), isNull);
    });
  });
}
