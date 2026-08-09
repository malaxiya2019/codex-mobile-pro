/// ====================================================================
/// GitPathMapper 单元测试 — 宿主↔guest 路径映射与 PRoot bind 参数
///
/// 覆盖：
///   1. /storage/emulated/0 ↔ /sdcard 映射
///   2. 其他绝对路径原样
///   3. bindArguments 生成 PRoot `-b` 参数
///   4. isHostPath 判断
/// ====================================================================
library;

import 'package:codex_mobile_pro/features/git/services/git_path_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitPathMapper.hostToGuest', () {
    test('存储根映射', () {
      expect(GitPathMapper.hostToGuest('/storage/emulated/0'), '/sdcard');
    });

    test('存储子路径映射', () {
      expect(
        GitPathMapper.hostToGuest('/storage/emulated/0/repos/foo'),
        '/sdcard/repos/foo',
      );
    });

    test('App 文档目录原样（PRoot 经同名 bind 可访问）', () {
      const app = '/data/data/com.codexmobile.app/app_flutter/git/repo';
      expect(GitPathMapper.hostToGuest(app), app);
    });

    test('普通绝对路径原样', () {
      expect(GitPathMapper.hostToGuest('/tmp/x'), '/tmp/x');
    });
  });

  group('GitPathMapper.guestToHost', () {
    test('反向映射存储根', () {
      expect(GitPathMapper.guestToHost('/sdcard'), '/storage/emulated/0');
    });

    test('反向映射子路径', () {
      expect(
        GitPathMapper.guestToHost('/sdcard/repos/foo'),
        '/storage/emulated/0/repos/foo',
      );
    });

    test('非存储路径原样', () {
      const app = '/data/data/com.codexmobile.app/app_flutter/git/repo';
      expect(GitPathMapper.guestToHost(app), app);
    });
  });

  group('GitPathMapper.bindArguments', () {
    test('存储路径 → 挂载整个 /storage/emulated/0 到 /sdcard', () {
      expect(
        GitPathMapper.bindArguments('/storage/emulated/0/repos/foo'),
        ['-b', '/storage/emulated/0:/sdcard'],
      );
    });

    test('非存储路径 → 同名 bind', () {
      const app = '/data/data/com.codexmobile.app/app_flutter/git';
      expect(GitPathMapper.bindArguments(app), ['-b', app]);
    });
  });

  group('GitPathMapper.bindPath (extraBinds 通道，无 -b 前缀)', () {
    test('存储路径 → 纯 bind 串 /storage/emulated/0:/sdcard', () {
      expect(
        GitPathMapper.bindPath('/storage/emulated/0/repos/foo'),
        '/storage/emulated/0:/sdcard',
      );
    });

    test('非存储路径 → 原样（同名 bind）', () {
      const app = '/data/data/com.codexmobile.app/app_flutter/git';
      expect(GitPathMapper.bindPath(app), app);
    });

    test('bindArguments 与 bindPath 一致（仅差 -b 前缀）', () {
      const app = '/data/data/com.codexmobile.app/app_flutter/git';
      expect(GitPathMapper.bindArguments(app), [
        '-b',
        GitPathMapper.bindPath(app),
      ]);
    });
  });

  group('GitPathMapper.isHostPath', () {
    test('识别宿主路径', () {
      expect(GitPathMapper.isHostPath('/storage/emulated/0/x'), isTrue);
      expect(GitPathMapper.isHostPath('/data/data/x'), isTrue);
      expect(GitPathMapper.isHostPath('/sdcard/x'), isTrue);
    });

    test('非宿主路径', () {
      expect(GitPathMapper.isHostPath('/tmp/x'), isFalse);
      expect(GitPathMapper.isHostPath('/usr/bin/git'), isFalse);
    });
  });
}
