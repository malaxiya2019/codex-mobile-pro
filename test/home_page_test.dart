import 'package:codex_mobile_pro/core/i18n/app_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocaleNotifier', () {
    test('默认语言为英文', () {
      final notifier = LocaleNotifier();
      expect(notifier.state, AppLanguage.enUS);
    });

    test('切换为中文', () {
      final notifier = LocaleNotifier();
      notifier.state = AppLanguage.zhCN;
      expect(notifier.state, AppLanguage.zhCN);
      expect(notifier.state.locale.languageCode, 'zh');
    });

    test('切换为英文', () {
      final notifier = LocaleNotifier();
      notifier.state = AppLanguage.zhCN;
      notifier.state = AppLanguage.enUS;
      expect(notifier.state, AppLanguage.enUS);
      expect(notifier.state.locale.languageCode, 'en');
    });

    test('状态改变通知监听器', () {
      final notifier = LocaleNotifier();
      int callCount = 0;
      notifier.addListener(() => callCount++);

      notifier.state = AppLanguage.zhCN;
      expect(callCount, 1);

      notifier.state = AppLanguage.enUS;
      expect(callCount, 2);
    });

    test('AppLanguage.enUS 属性正确', () {
      const lang = AppLanguage.enUS;
      expect(lang.locale.languageCode, 'en');
      expect(lang.locale.countryCode, 'US');
      expect(lang.flag, '🇺🇸');
      expect(lang.label, 'English');
    });

    test('AppLanguage.zhCN 属性正确', () {
      const lang = AppLanguage.zhCN;
      expect(lang.locale.languageCode, 'zh');
      expect(lang.locale.countryCode, 'CN');
      expect(lang.flag, '🇨🇳');
      expect(lang.label, '中文');
    });

    test('所有 AppLanguage 枚举值对应正确 locale', () {
      for (final lang in AppLanguage.values) {
        expect(lang.locale, isNotNull);
        expect(lang.locale.languageCode, isNotEmpty);
        expect(lang.flag, isNotEmpty);
        expect(lang.label, isNotEmpty);
      }
    });
  });
}
