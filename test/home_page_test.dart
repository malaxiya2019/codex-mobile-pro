import 'package:codex_mobile_pro/app.dart';
import 'package:codex_mobile_pro/core/i18n/app_locale.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomePage — Material 3 验证', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'app_locale': 'en_US'});
    });

    testWidgets('首页正确渲染', (tester) async {
      // 增大测试屏幕高度，确保所有 ListView 子元素均可渲染
      tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = LocaleNotifier();
      notifier.state = AppLanguage.enUS;

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
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
    });

    testWidgets('计数器交互正常', (tester) async {
      // 增大测试屏幕高度，确保计数器 Card 可见
      tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = LocaleNotifier();
      notifier.state = AppLanguage.enUS;

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
