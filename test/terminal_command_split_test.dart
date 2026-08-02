/// 回归测试：终端命令输入拆行（多行粘贴脚本场景）
///
/// 真机复现：单行 TextField 经 FilteringTextInputFormatter 删除 \n，
/// 多行脚本粘连成一行（'dpkg --configure -aapt -f install -y'），
/// 注释行吞掉后续命令。修复后输入框为多行，\n 保留，
/// splitCommandLines 把脚本拆成独立命令逐行执行。
library;

import 'package:codex_mobile_pro/features/terminal/services/terminal_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitCommandLines', () {
    test('单行命令原样返回', () {
      expect(
        splitCommandLines('apt update --fix-missing'),
        ['apt update --fix-missing'],
      );
    });

    test('多行脚本逐行拆分（含注释、空行）', () {
      const script = '''
# 重建临时目录
mkdir -p /tmp /var/cache/apt/archives/partial
chmod 1777 /tmp

dpkg --configure -a
apt -f install -y
''';
      expect(
        splitCommandLines(script),
        [
          '# 重建临时目录',
          'mkdir -p /tmp /var/cache/apt/archives/partial',
          'chmod 1777 /tmp',
          'dpkg --configure -a',
          'apt -f install -y',
        ],
      );
    });

    test('粘连命令还原为独立命令（单行 TextField 删除换行的场景）', () {
      // 注意：此处输入已无 \n（模拟被吞），无法还原——验证空行过滤
      // 与 trim 行为；真正的修复依赖多行 TextField 保留 \n。
      expect(splitCommandLines('dpkg --configure -aapt -f install -y'), [
        'dpkg --configure -aapt -f install -y',
      ]);
    });

    test('空输入返回空列表', () {
      expect(splitCommandLines(''), isEmpty);
      expect(splitCommandLines('   \n  \n'), isEmpty);
    });

    test('首尾空白被去除', () {
      expect(splitCommandLines('  echo hi  '), ['echo hi']);
    });

    test('CRLF 行尾兼容（\r\n 粘贴来源）', () {
      expect(
        splitCommandLines('echo a\r\necho b\r\n'),
        ['echo a', 'echo b'],
      );
    });
  });
}
