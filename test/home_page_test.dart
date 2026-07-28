import 'package:codex_mobile_pro/app.dart';
import 'package:codex_mobile_pro/core/i18n/app_locale.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomePage — Material 3 验证', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'app_locale': 'zh_CN'});
    });
    testWidgets('首页正确渲染', (tester) async {
      final notifier = LocaleNotifier();
      notifier.state = AppLanguage.zhCN;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localeProvider.overrideWith((ref) => notifier),
          ],
          child: const CodexMobileApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Codex Mobile Pro'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
    });

    testWidgets('计数器交互正常', (tester) async {
      final notifier = LocaleNotifier();
      notifier.state = AppLanguage.zhCN;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localeProvider.overrideWith((ref) => notifier),
          ],
          child: const CodexMobileApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('0'), findsOneWidget);

      final addButtons = find.byIcon(Icons.add);
      expect(addButtons, findsOneWidget);
      await tester.tap(addButtons);
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });
  });
}
