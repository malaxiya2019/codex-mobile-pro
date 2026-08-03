import 'package:codex_mobile_pro/features/settings/views/log_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 构造带注入日志加载器的页面（避免真实文件 IO 在 fake async 下挂起）
  Widget buildPage(String logs) {
    return MaterialApp(
      home: LogCenterPage(logsLoader: () async => logs),
    );
  }

  testWidgets('空日志显示「暂无日志」', (tester) async {
    await tester.pumpWidget(buildPage(''));
    await tester.pump();

    expect(find.text('日志中心'), findsOneWidget);
    expect(find.text('暂无日志'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '崩溃'), findsOneWidget);
  });

  testWidgets('显示日志条目并按崩溃过滤', (tester) async {
    const logs = '[2026-08-03T12:00:00][INFO][Test] normal-info-marker\n'
        '[2026-08-03T12:00:01][ERROR][CRASH] [FlutterError] Exception: boom-marker\n';
    await tester.pumpWidget(buildPage(logs));
    await tester.pump();

    // 全部：普通日志与崩溃日志均可见
    expect(find.textContaining('normal-info-marker'), findsOneWidget);
    expect(find.textContaining('boom-marker'), findsOneWidget);

    // 切到「崩溃」过滤：只剩崩溃日志
    await tester.tap(find.widgetWithText(ChoiceChip, '崩溃'));
    await tester.pump();

    expect(find.textContaining('boom-marker'), findsOneWidget);
    expect(find.textContaining('normal-info-marker'), findsNothing);
  });

  testWidgets('级别过滤 ERROR 只显示错误日志', (tester) async {
    const logs = '[2026-08-03T12:00:00][INFO][Test] info-marker\n'
        '[2026-08-03T12:00:01][ERROR][Test] error-marker\n';
    await tester.pumpWidget(buildPage(logs));
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'ERROR'));
    await tester.pump();

    expect(find.textContaining('error-marker'), findsOneWidget);
    expect(find.textContaining('info-marker'), findsNothing);
  });
}
