/// 编译检查：确保 terminal_page.dart 经 CFE（kernel）编译通过。
///
/// 背景：flutter test 编译测试文件及其 import 链时才检查类型；
/// 此前无测试 import terminal_page.dart，导致
/// `onSubmitted: _submitCommand`（void Function() 赋给
/// void Function(String)）被本地 analyzer 放行、CI 编译才报错。
/// 本测试仅构造页面（不 pump），触发 CFE 编译即达成目的。
library;

import 'package:codex_mobile_pro/features/terminal/views/terminal_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TerminalPage 可构造（CFE 编译检查）', (tester) async {
    const page = TerminalPage();
    expect(page, isNotNull);
  });
}
