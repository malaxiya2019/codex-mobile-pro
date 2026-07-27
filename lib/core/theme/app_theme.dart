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
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _primaryLight,
        brightness: Brightness.light,
        fontFamily: 'Roboto',
      );

  // ── 暗色主题 ──
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _primaryDark,
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
      );
}
