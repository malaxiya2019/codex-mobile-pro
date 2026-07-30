import 'package:codex_mobile_pro/core/i18n/app_locale.dart';
import 'package:codex_mobile_pro/core/i18n/strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLanguage', () {
    test('所有语言定义正确', () {
      expect(AppLanguage.values.length, 2);
      expect(AppLanguage.zhCN.languageCode, 'zh');
      expect(AppLanguage.zhCN.countryCode, 'CN');
      expect(AppLanguage.enUS.languageCode, 'en');
      expect(AppLanguage.enUS.countryCode, 'US');
    });

    test('key 正确', () {
      expect(AppLanguage.zhCN.key, 'zh_CN');
      expect(AppLanguage.enUS.key, 'en_US');
    });

    test('fromKey 反映射正确', () {
      expect(AppLanguage.fromKey('zh_CN'), AppLanguage.zhCN);
      expect(AppLanguage.fromKey('en_US'), AppLanguage.enUS);
      expect(AppLanguage.fromKey('unknown'), AppLanguage.zhCN);
    });

    test('locale 正确', () {
      expect(AppLanguage.zhCN.locale.languageCode, 'zh');
      expect(AppLanguage.enUS.locale.languageCode, 'en');
    });
  });

  group('LocaleNotifier', () {
    test('初始状态为 zh_CN', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final state = container.read(localeProvider);
      expect(state, AppLanguage.zhCN);
    });

    test('setLocale 更新语言', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      container.read(localeProvider.notifier).setLocale(AppLanguage.enUS);
      expect(container.read(localeProvider), AppLanguage.enUS);
    });

    test('toggleLocale 切换语言', () {
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(localeProvider.notifier);
      notifier.toggleLocale();
      expect(container.read(localeProvider), AppLanguage.enUS);
      notifier.toggleLocale();
      expect(container.read(localeProvider), AppLanguage.zhCN);
    });
  });

  group('Strings', () {
    test('中文返回中文文本', () {
      const s = Strings(AppLanguage.zhCN);
      expect(s.appName, 'Codex Mobile Pro');
      expect(s.ok, '确定');
      expect(s.cancel, '取消');
      expect(s.aiChatTitle, 'AI 对话');
    });

    test('英文返回英文文本', () {
      const s = Strings(AppLanguage.enUS);
      expect(s.appName, 'Codex Mobile Pro');
      expect(s.ok, 'OK');
      expect(s.cancel, 'Cancel');
      expect(s.aiChatTitle, 'AI Chat');
    });

    test('所有字符串在两种语言都有定义', () {
      const zh = Strings(AppLanguage.zhCN);
      const en = Strings(AppLanguage.enUS);

      // 通用
      expect(zh.appName, isNotEmpty);
      expect(en.appName, isNotEmpty);
      expect(zh.ok, isNotEmpty);
      expect(en.ok, isNotEmpty);

      // AI
      expect(zh.aiChatTitle, isNotEmpty);
      expect(en.aiChatTitle, isNotEmpty);
      expect(zh.aiInputHint, isNotEmpty);
      expect(en.aiInputHint, isNotEmpty);

      // 主题
      expect(zh.themeSettingsTitle, isNotEmpty);
      expect(en.themeSettingsTitle, isNotEmpty);

      // 错误
      expect(zh.errorAppTitle, isNotEmpty);
      expect(en.errorAppTitle, isNotEmpty);
      expect(zh.errorFatalMsg, isNotEmpty);
      expect(en.errorFatalMsg, isNotEmpty);

      // Termux
      expect(zh.termuxTestTitle, isNotEmpty);
      expect(en.termuxTestTitle, isNotEmpty);

      // 部署
      expect(zh.deployTitle, isNotEmpty);
      expect(en.deployTitle, isNotEmpty);
    });
  });
}
