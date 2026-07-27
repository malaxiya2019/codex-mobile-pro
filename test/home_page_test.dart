import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lib/app.dart';

void main() {
  group('HomePage — Material 3 验证', () {
    testWidgets('首页正确渲染', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: CodexMobileApp()));

      // 验证标题
      expect(find.text('Codex Mobile Pro'), findsOneWidget);

      // 验证 Material 3 Card 组件
      expect(find.byType(Card), findsWidgets);

      // 验证 NavigationBar（Material 3 底部导航）
      expect(find.byType(NavigationBar), findsOneWidget);

      // 验证底部导航项
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('终端'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
    });

    testWidgets('Riverpod 计数器交互正常', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: CodexMobileApp()));

      // 初始值应为 0
      expect(find.text('0'), findsOneWidget);

      // 点击 + 按钮
      final addButtons = find.byIcon(Icons.add);
      expect(addButtons, findsOneWidget);
      await tester.tap(addButtons);
      await tester.pump();

      // 值应变为 1
      expect(find.text('1'), findsOneWidget);
    });
  });
}
