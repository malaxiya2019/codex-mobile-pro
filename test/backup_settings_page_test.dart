import 'package:codex_mobile_pro/features/settings/views/backup_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupSettingsPage', () {
    testWidgets('无备份时显示空态与备份按钮', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BackupSettingsPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('备份与恢复'), findsOneWidget);
      expect(find.text('暂无备份文件'), findsOneWidget);
      expect(find.text('立即备份'), findsOneWidget);
    });
  });
}
