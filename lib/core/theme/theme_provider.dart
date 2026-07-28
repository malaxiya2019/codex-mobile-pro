import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式
enum ThemeModeOption {
  light,
  dark,
  system;

  String get key {
    switch (this) {
      case ThemeModeOption.light:
        return 'light';
      case ThemeModeOption.dark:
        return 'dark';
      case ThemeModeOption.system:
        return 'system';
    }
  }

  static ThemeModeOption fromKey(String key) {
    switch (key) {
      case 'light':
        return ThemeModeOption.light;
      case 'dark':
        return ThemeModeOption.dark;
      case 'system':
        return ThemeModeOption.system;
      default:
        return ThemeModeOption.system;
    }
  }
}

/// 字体配置
class FontConfig {
  final String family;
  final double scale;

  const FontConfig({
    this.family = 'Roboto',
    this.scale = 1.0,
  });

  FontConfig copyWith({String? family, double? scale}) {
    return FontConfig(
      family: family ?? this.family,
      scale: scale ?? this.scale,
    );
  }

  Map<String, dynamic> toJson() => {'family': family, 'scale': scale};

  factory FontConfig.fromJson(Map<String, dynamic> json) => FontConfig(
    family: json['family'] as String? ?? 'Roboto',
    scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
  );
}

/// 主题状态
class ThemeState {
  final ThemeModeOption mode;
  final FontConfig fontConfig;

  const ThemeState({
    this.mode = ThemeModeOption.system,
    this.fontConfig = const FontConfig(),
  });

  ThemeState copyWith({ThemeModeOption? mode, FontConfig? fontConfig}) {
    return ThemeState(
      mode: mode ?? this.mode,
      fontConfig: fontConfig ?? this.fontConfig,
    );
  }

  /// 转为 Material ThemeMode
  ThemeMode get materialMode {
    switch (mode) {
      case ThemeModeOption.light:
        return ThemeMode.light;
      case ThemeModeOption.dark:
        return ThemeMode.dark;
      case ThemeModeOption.system:
        return ThemeMode.system;
    }
  }
}

/// 主题 Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(const ThemeState()) {
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeKey = prefs.getString('theme_mode') ?? 'system';
      final fontFamily = prefs.getString('font_family') ?? 'Roboto';
      final fontScale = prefs.getDouble('font_scale') ?? 1.0;
      state = ThemeState(
        mode: ThemeModeOption.fromKey(modeKey),
        fontConfig: FontConfig(family: fontFamily, scale: fontScale),
      );
    } catch (_) {
      // 使用默认值
    }
  }

  Future<void> _saveTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', state.mode.key);
      await prefs.setString('font_family', state.fontConfig.family);
      await prefs.setDouble('font_scale', state.fontConfig.scale);
    } catch (_) {
      // 忽略保存失败
    }
  }

  /// 切换主题模式
  void setThemeMode(ThemeModeOption mode) {
    state = state.copyWith(mode: mode);
    _saveTheme();
  }

  /// 切换亮/暗
  void toggleTheme() {
    final newMode = state.mode == ThemeModeOption.light
        ? ThemeModeOption.dark
        : ThemeModeOption.light;
    setThemeMode(newMode);
  }

  /// 设置字体
  void setFontFamily(String family) {
    state = state.copyWith(fontConfig: FontConfig(family: family, scale: state.fontConfig.scale));
    _saveTheme();
  }

  /// 设置字体缩放
  void setFontScale(double scale) {
    scale = scale.clamp(0.8, 1.5);
    state = state.copyWith(fontConfig: state.fontConfig.copyWith(scale: scale));
    _saveTheme();
  }
}
