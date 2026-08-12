import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 终端外观设置
class TerminalSettings {
  final double fontSize;
  final String fontFamily;
  final ThemeMode themeMode;
  final bool cursorBlink;
  final Color cursorColor;
  final Color foregroundColor;
  final Color backgroundColor;

  const TerminalSettings({
    this.fontSize = 13.0,
    this.fontFamily = 'monospace',
    this.themeMode = ThemeMode.dark,
    this.cursorBlink = true,
    this.cursorColor = Colors.greenAccent,
    this.foregroundColor = const Color(0xFFE6E6E6),
    this.backgroundColor = const Color(0xFF000000),
  });

  TerminalSettings copyWith({
    double? fontSize,
    String? fontFamily,
    ThemeMode? themeMode,
    bool? cursorBlink,
    Color? cursorColor,
    Color? foregroundColor,
    Color? backgroundColor,
  }) {
    return TerminalSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      themeMode: themeMode ?? this.themeMode,
      cursorBlink: cursorBlink ?? this.cursorBlink,
      cursorColor: cursorColor ?? this.cursorColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'themeMode': themeMode.index,
        'cursorBlink': cursorBlink,
        'cursorColor': cursorColor.toARGB32(),
        'foregroundColor': foregroundColor.toARGB32(),
        'backgroundColor': backgroundColor.toARGB32(),
      };

  factory TerminalSettings.fromJson(Map<String, dynamic> json) {
    return TerminalSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 13.0,
      fontFamily: json['fontFamily'] as String? ?? 'monospace',
      themeMode: ThemeMode.values[json['themeMode'] as int? ?? 1],
      cursorBlink: json['cursorBlink'] as bool? ?? true,
      cursorColor: Color(json['cursorColor'] as int? ?? 0xFF00FF00),
      foregroundColor: Color(json['foregroundColor'] as int? ?? 0xFFE6E6E6),
      backgroundColor: Color(json['backgroundColor'] as int? ?? 0xFF000000),
    );
  }
}

/// 终端设置 Notifier
class TerminalSettingsNotifier extends StateNotifier<TerminalSettings> {
  TerminalSettingsNotifier() : super(const TerminalSettings());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      'fontSize': prefs.getDouble('terminal_fontSize') ?? 13.0,
      'fontFamily': prefs.getString('terminal_fontFamily') ?? 'monospace',
      'themeMode': prefs.getInt('terminal_themeMode') ?? 1,
      'cursorBlink': prefs.getBool('terminal_cursorBlink') ?? true,
      'cursorColor': prefs.getInt('terminal_cursorColor') ?? 0xFF00FF00,
      'foregroundColor': prefs.getInt('terminal_foregroundColor') ?? 0xFFE6E6E6,
      'backgroundColor': prefs.getInt('terminal_backgroundColor') ?? 0xFF000000,
    };
    state = TerminalSettings.fromJson(json);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('terminal_fontSize', state.fontSize);
    await prefs.setString('terminal_fontFamily', state.fontFamily);
    await prefs.setInt('terminal_themeMode', state.themeMode.index);
    await prefs.setBool('terminal_cursorBlink', state.cursorBlink);
    await prefs.setInt('terminal_cursorColor', state.cursorColor.toARGB32());
    await prefs.setInt('terminal_foregroundColor', state.foregroundColor.toARGB32());
    await prefs.setInt('terminal_backgroundColor', state.backgroundColor.toARGB32());
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size.clamp(8.0, 32.0));
    await _save();
  }

  Future<void> setFontFamily(String family) async {
    state = state.copyWith(fontFamily: family);
    await _save();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _save();
  }

  Future<void> setCursorBlink(bool blink) async {
    state = state.copyWith(cursorBlink: blink);
    await _save();
  }

  Future<void> setCursorColor(Color color) async {
    state = state.copyWith(cursorColor: color);
    await _save();
  }

  Future<void> setForegroundColor(Color color) async {
    state = state.copyWith(foregroundColor: color);
    await _save();
  }

  Future<void> setBackgroundColor(Color color) async {
    state = state.copyWith(backgroundColor: color);
    await _save();
  }
}

final terminalSettingsProvider =
    StateNotifierProvider<TerminalSettingsNotifier, TerminalSettings>(
  (ref) => TerminalSettingsNotifier(),
);
