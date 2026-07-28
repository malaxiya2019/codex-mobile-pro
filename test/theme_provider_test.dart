import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:codex_mobile_pro/core/theme/theme_provider.dart';

void main() {
  group('ThemeModeOption', () {
    test('key 映射正确', () {
      expect(ThemeModeOption.light.key, 'light');
      expect(ThemeModeOption.dark.key, 'dark');
      expect(ThemeModeOption.system.key, 'system');
    });

    test('fromKey 反映射正确', () {
      expect(ThemeModeOption.fromKey('light'), ThemeModeOption.light);
      expect(ThemeModeOption.fromKey('dark'), ThemeModeOption.dark);
      expect(ThemeModeOption.fromKey('system'), ThemeModeOption.system);
      expect(ThemeModeOption.fromKey('unknown'), ThemeModeOption.system);
    });
  });

  group('FontConfig', () {
    test('默认值正确', () {
      const config = FontConfig();
      expect(config.family, 'Roboto');
      expect(config.scale, 1.0);
    });

    test('copyWith 正确', () {
      const config = FontConfig();
      final copy = config.copyWith(family: 'Noto Sans SC', scale: 1.2);
      expect(copy.family, 'Noto Sans SC');
      expect(copy.scale, 1.2);
    });

    test('toJson / fromJson 互相转换', () {
      const config = FontConfig(family: 'monospace', scale: 0.9);
      final json = config.toJson();
      final restored = FontConfig.fromJson(json);
      expect(restored.family, 'monospace');
      expect(restored.scale, 0.9);
    });
  });

  group('ThemeState', () {
    test('默认值正确', () {
      const state = ThemeState();
      expect(state.mode, ThemeModeOption.system);
      expect(state.fontConfig.family, 'Roboto');
      expect(state.fontConfig.scale, 1.0);
    });

    test('copyWith 正确', () {
      const state = ThemeState();
      final updated = state.copyWith(mode: ThemeModeOption.dark);
      expect(updated.mode, ThemeModeOption.dark);
      expect(updated.fontConfig, state.fontConfig);
    });

    test('materialMode 映射正确', () {
      expect(const ThemeState(mode: ThemeModeOption.light).materialMode, ThemeMode.light);
      expect(const ThemeState(mode: ThemeModeOption.dark).materialMode, ThemeMode.dark);
      expect(const ThemeState(mode: ThemeModeOption.system).materialMode, ThemeMode.system);
    });
  });

  group('ThemeNotifier', () {
    test('初始状态为 system', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final state = container.read(themeProvider);
      expect(state.mode, ThemeModeOption.system);
    });

    test('setThemeMode 更新模式', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(themeProvider.notifier);
      notifier.setThemeMode(ThemeModeOption.dark);

      final state = container.read(themeProvider);
      expect(state.mode, ThemeModeOption.dark);
    });

    test('toggleTheme 切换亮暗', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(themeProvider.notifier);
      notifier.setThemeMode(ThemeModeOption.light);
      notifier.toggleTheme();
      expect(container.read(themeProvider).mode, ThemeModeOption.dark);
      notifier.toggleTheme();
      expect(container.read(themeProvider).mode, ThemeModeOption.light);
    });

    test('setFontFamily 更新字体', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(themeProvider.notifier);
      notifier.setFontFamily('Noto Sans SC');

      expect(container.read(themeProvider).fontConfig.family, 'Noto Sans SC');
    });

    test('setFontScale 限制范围', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(themeProvider.notifier);
      notifier.setFontScale(2.0);
      expect(container.read(themeProvider).fontConfig.scale, 1.5);

      notifier.setFontScale(0.5);
      expect(container.read(themeProvider).fontConfig.scale, 0.8);
    });
  });

  group('AppTheme', () {
    test('亮色主题是 light brightness', () {
      final theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
    });

    test('暗色主题是 dark brightness', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
    });

    test('自定义字体应用到主题', () {
      final theme = AppTheme.light(fontFamily: 'Noto Sans SC');
      expect(theme.fontFamily, 'Noto Sans SC');
    });

    test('M3 启用', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, true);
    });
  });
}
