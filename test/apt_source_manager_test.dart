/// ====================================================================
/// Ubuntu APT 源管理器单元测试
///
/// 覆盖：
///   1. sources.list 生成（noble + updates + security，签名 keyring 保留）
///   2. 出厂配置（ports.ubuntu.com HTTP）识别
///   3. deb822（.sources）配置识别
///   4. writeSource：覆盖 + .orig 备份 + 旧 .sources 禁用
///   5. fallback 链构建（排除当前源）
/// ====================================================================
library;

import 'dart:io';

import 'package:codex_mobile_pro/runtime/installers/apt_source_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late String rootfs;
  late AptSourceManager mgr;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('apt_source_test_');
    rootfs = temp.path;
    mgr = AptSourceManager(rootfs);
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('buildSourcesList', () {
    test('生成 official-https 源（noble 三个 suite + keyring）', () {
      const src = AptSourceEntry(
        name: 'official-https',
        baseUri: 'https://ports.ubuntu.com/ubuntu-ports',
      );
      final content = mgr.buildSourcesList(src);

      expect(content, contains('https://ports.ubuntu.com/ubuntu-ports'));
      expect(content, contains('noble main universe multiverse'));
      expect(content, contains('noble-updates main universe multiverse'));
      expect(content, contains('noble-security main universe multiverse'));
      expect(
          content, contains('/usr/share/keyrings/ubuntu-archive-keyring.gpg'));
      // 与 App 出厂格式一致：deb [signed-by=...] <uri> <suite> <components>
      expect(content, contains('deb [signed-by="'));
    });

    test('镜像源生成同样保留 keyring', () {
      const tuna = AptSourceEntry(
        name: 'tuna',
        baseUri: 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports',
        region: 'cn',
      );
      final content = mgr.buildSourcesList(tuna);
      expect(content, contains('mirrors.tuna.tsinghua.edu.cn'));
      expect(content, contains('noble-security'));
    });
  });

  group('readCurrentUri', () {
    test('识别出厂 ports.ubuntu.com HTTP 配置', () async {
      final file = File('$rootfs/etc/apt/sources.list');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        'deb [signed-by="/usr/share/keyrings/ubuntu-archive-keyring.gpg"] '
        'http://ports.ubuntu.com/ubuntu-ports noble main universe multiverse\n',
      );

      expect(
          await mgr.readCurrentUri(), 'http://ports.ubuntu.com/ubuntu-ports');
    });

    test('识别 deb822 .sources 配置', () async {
      final file = File('$rootfs/etc/apt/sources.list.d/ubuntu.sources');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        'Types: deb\nURIs: http://archive.ubuntu.com/ubuntu/\n'
        'Suites: resolute\nComponents: main universe\n',
      );

      expect(await mgr.readCurrentUri(), 'http://archive.ubuntu.com/ubuntu/');
    });

    test('无配置 → null', () async {
      expect(await mgr.readCurrentUri(), isNull);
    });
  });

  group('writeSource', () {
    test('覆盖 + 首次备份 .orig + 禁用旧 deb822', () async {
      // 模拟出厂配置 + 一个旧版 deb822
      final listFile = File('$rootfs/etc/apt/sources.list');
      await listFile.parent.create(recursive: true);
      await listFile.writeAsString(
        'deb [signed-by="/usr/share/keyrings/ubuntu-archive-keyring.gpg"] '
        'http://ports.ubuntu.com/ubuntu-ports noble main universe multiverse\n',
      );
      final dFile = File('$rootfs/etc/apt/sources.list.d/ubuntu.sources');
      await dFile.parent.create(recursive: true);
      await dFile.writeAsString('Types: deb\nURIs: http://old.example.com/\n');

      const tuna = AptSourceEntry(
        name: 'tuna',
        baseUri: 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports',
      );
      await mgr.writeSource(tuna);

      expect(await listFile.readAsString(),
          contains('mirrors.tuna.tsinghua.edu.cn'));
      expect(await File('$rootfs/etc/apt/sources.list.orig').readAsString(),
          contains('ports.ubuntu.com'));
      expect(
          await File('$rootfs/etc/apt/sources.list.d/ubuntu.sources.disabled')
              .exists(),
          isTrue);
      expect(await dFile.exists(), isFalse, reason: '旧 deb822 必须被移走');
    });

    test('重复切换不重复备份（.orig 保持出厂配置）', () async {
      final listFile = File('$rootfs/etc/apt/sources.list');
      await listFile.parent.create(recursive: true);
      await listFile.writeAsString(
        'deb [signed-by="/usr/share/keyrings/ubuntu-archive-keyring.gpg"] '
        'http://ports.ubuntu.com/ubuntu-ports noble main universe multiverse\n',
      );

      await mgr.writeSource(const AptSourceEntry(
        name: 'official-https',
        baseUri: 'https://ports.ubuntu.com/ubuntu-ports',
      ));
      await mgr.writeSource(const AptSourceEntry(
        name: 'tuna',
        baseUri: 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports',
      ));

      final orig =
          await File('$rootfs/etc/apt/sources.list.orig').readAsString();
      expect(orig, contains('http://ports.ubuntu.com/ubuntu-ports'));
      expect(orig, isNot(contains('tuna')));
    });
  });

  group('buildFallbackChain', () {
    test('默认包含 4 个备用源，按优先级降序', () {
      final chain = mgr.buildFallbackChain();
      expect(chain.map((e) => e.name).toList(),
          ['official-https', 'tuna', 'aliyun', 'ustc']);
      expect(chain.first.baseUri, 'https://ports.ubuntu.com/ubuntu-ports');
    });

    test('排除当前源（已是官方 HTTPS 则不再重复尝试）', () {
      final chain = mgr.buildFallbackChain(
          currentUri: 'https://ports.ubuntu.com/ubuntu-ports/');
      expect(chain.map((e) => e.name).toList(), ['tuna', 'aliyun', 'ustc']);
    });

    test('尾部斜杠归一化（http://ports.ubuntu.com/ubuntu-ports/ 与出厂一致）', () {
      final chain = mgr.buildFallbackChain(
        currentUri: 'http://ports.ubuntu.com/ubuntu-ports',
      );
      // 官方 HTTP 是出厂源，不在 fallback 链中 → 全部保留
      expect(chain.length, 4);
    });
  });
}
