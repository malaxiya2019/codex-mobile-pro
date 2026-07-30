import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 支持的语言
enum AppLanguage {
  zhCN('zh', 'CN', '简体中文', '🇨🇳', '中文'),
  enUS('en', 'US', 'English', '🇺🇸', 'English');

  final String languageCode;
  final String countryCode;
  final String displayName;
  final String flag;
  final String label;

  const AppLanguage(
    this.languageCode,
    this.countryCode,
    this.displayName,
    this.flag,
    this.label,
  );

  Locale get locale => Locale(languageCode, countryCode);

  String get key => '${languageCode}_$countryCode';

  static AppLanguage fromKey(String key) {
    switch (key) {
      case 'zh_CN':
        return AppLanguage.zhCN;
      case 'en_US':
        return AppLanguage.enUS;
      default:
        return AppLanguage.zhCN;
    }
  }
}

/// 语言 Provider
final localeProvider = StateNotifierProvider<LocaleNotifier, AppLanguage>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<AppLanguage> {
  LocaleNotifier() : super(AppLanguage.zhCN) {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('app_locale') ?? 'zh_CN';
      state = AppLanguage.fromKey(saved);
    } catch (_) {
      // 使用默认值
    }
  }

  Future<void> setLocale(AppLanguage language) async {
    state = language;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_locale', language.key);
    } catch (_) {
      // 忽略保存失败
    }
  }

  void toggleLocale() {
    final newLang = state == AppLanguage.zhCN
        ? AppLanguage.enUS
        : AppLanguage.zhCN;
    setLocale(newLang);
  }
}
