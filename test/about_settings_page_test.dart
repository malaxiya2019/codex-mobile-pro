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

      expect(find.text(AppInfo.name), findsOneWidget);
      expect(find.textContaining('v${AppInfo.versionLabel}'), findsOneWidget);
      expect(find.text(AppInfo.githubUrl), findsOneWidget);
    });

    testWidgets('点击仓库地址复制到剪贴板', (tester) async {
      // mock 剪贴板平台通道（flutter_test 无真实剪贴板，否则调用挂起）
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': copied};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        const MaterialApp(home: AboutSettingsPage()),
      );

      await tester.tap(find.text(AppInfo.githubUrl));
      await tester.pump();

      expect(copied, AppInfo.githubUrl);
      expect(find.textContaining('仓库地址已复制'), findsOneWidget);
    });
  });
}
