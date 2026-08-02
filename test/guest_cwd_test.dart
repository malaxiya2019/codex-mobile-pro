import 'package:codex_mobile_pro/runtime/process/guest_cwd.dart';
import 'package:flutter_test/flutter_test.dart';

/// 核心约束：host filesystem 路径（/data/...、/storage/... 等）只能用于
/// rootfs/bind source，不得直接作为 PRoot guest 工作目录。
void main() {
  group('normalizeGuestCwd — host cwd 不得作为 guest cwd', () {
    test('App 私有目录（Terminal 默认 cwd）→ /root', () {
      expect(
        normalizeGuestCwd('/data/data/com.codexmobile.app/app_flutter'),
        '/root',
      );
    });

    test('带 ./ 尾缀的宿主路径 → /root', () {
      // 真机日志：can't chdir("/data/data/com.codexmobile.app/app_flutter/./.")
      expect(
        normalizeGuestCwd('/data/data/com.codexmobile.app/app_flutter/./.'),
        '/root',
      );
    });

    test('/data 下其它路径 → /root', () {
      expect(normalizeGuestCwd('/data/user/0/com.codexmobile.app/files'), '/root');
    });

    test('/storage /sdcard /system /vendor host 前缀 → /root', () {
      expect(normalizeGuestCwd('/storage/emulated/0'), '/root');
      expect(normalizeGuestCwd('/sdcard/Download'), '/root');
      expect(normalizeGuestCwd('/system/bin'), '/root');
      expect(normalizeGuestCwd('/vendor/lib'), '/root');
    });

    test('null / 空串 / 相对路径 → /root', () {
      expect(normalizeGuestCwd(null), '/root');
      expect(normalizeGuestCwd(''), '/root');
      expect(normalizeGuestCwd('   '), '/root');
      expect(normalizeGuestCwd('relative/path'), '/root');
    });
  });

  group('normalizeGuestCwd — 合法 guest 路径保留', () {
    test('rootfs 内绝对路径原样保留', () {
      expect(normalizeGuestCwd('/root'), '/root');
      expect(normalizeGuestCwd('/tmp'), '/tmp');
      expect(normalizeGuestCwd('/home/user'), '/home/user');
      expect(normalizeGuestCwd('/var/www'), '/var/www');
    });

    test('尾部斜杠规范化（避免 // 重复）', () {
      expect(normalizeGuestCwd('/root/'), '/root');
      expect(normalizeGuestCwd('/tmp///'), '/tmp');
      expect(normalizeGuestCwd('//'), '/');
    });

    test('根目录保留为 /', () {
      expect(normalizeGuestCwd('/'), '/');
    });
  });
}
