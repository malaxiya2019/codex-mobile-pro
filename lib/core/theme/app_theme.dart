import 'package:flutter/material.dart';

/// Codex Mobile Pro 主题配置
///
/// 基于 Material 3 设计规范，支持亮色/暗色自适应。
class AppTheme {
  AppTheme._();

  // ── 品牌色 ──
  static const Color _primaryLight = Color(0xFF1E88E5);
  static const Color _primaryDark = Color(0xFF64B5F6);

  // ── 亮色主题 ──
  static ThemeData light({String fontFamily = 'Roboto'}) => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _primaryLight,
    brightness: Brightness.light,
    fontFamily: fontFamily,
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dialogTheme: DialogTheme(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );

  // ── 暗色主题 ──
  static ThemeData dark({String fontFamily = 'Roboto'}) => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _primaryDark,
    brightness: Brightness.dark,
    fontFamily: fontFamily,
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dialogTheme: DialogTheme(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
