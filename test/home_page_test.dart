import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:codex_mobile_pro/app.dart';

void main() {
  group('HomePage — Material 3 验证', () {
    testWidgets('首页正确渲染', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: CodexMobileApp(),
        ),
      );

      expect(find.text('Codex Mobile Pro'), findsOneWidget);
      expect(find.byType(Card), findsWidgets);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('终端'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
    });

    testWidgets('Riverpod 计数器交互正常', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: CodexMobileApp(),
        ),
      );

      expect(find.text('0'), findsOneWidget);

      final addButtons = find.byIcon(Icons.add);
      expect(addButtons, findsOneWidget);
      await tester.tap(addButtons);
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });
  });
}
