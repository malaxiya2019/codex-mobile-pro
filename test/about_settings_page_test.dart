import 'package:codex_mobile_pro/core/config/app_info.dart';
import 'package:codex_mobile_pro/features/settings/views/about_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AboutSettingsPage', () {
    testWidgets('显示应用名、版本号与仓库地址', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AboutSettingsPage()),
      );

      expect(find.textContaining(AppInfo.name), findsOneWidget);
      expect(find.textContaining('v${AppInfo.versionLabel}'), findsOneWidget);
      expect(find.text(AppInfo.githubUrl), findsOneWidget);
    });

    testWidgets('点击仓库地址复制到剪贴板', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AboutSettingsPage()),
      );

      await tester.tap(find.text(AppInfo.githubUrl));
      await tester.pump();

      final clipboard = await Clipboard.getData('text/plain');
      expect(clipboard?.text, AppInfo.githubUrl);
    });
  });
}
