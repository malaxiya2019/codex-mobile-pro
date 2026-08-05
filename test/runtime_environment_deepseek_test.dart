import 'dart:io';

import 'package:codex_mobile_pro/runtime/runtime_dependency.dart';
import 'package:codex_mobile_pro/runtime/runtime_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepSeek API Key 保存/检测路径一致性', () {
    late Directory temp;
    late RuntimeEnvironment env;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('deepseek-cfg-');
      env = RuntimeEnvironment.forTest(temp.path);
    });

    tearDown(() => temp.delete(recursive: true));

    test('mimoConfigDir = App目录/.mimo2codex（与文档 ~/.mimo2codex/.env 一致）', () {
      expect(env.mimoConfigDir, '${temp.path}/.mimo2codex');
      expect(env.mimoConfigDir, isNot(contains('/runtime/')),
          reason: '保存路径不得多出 runtime 层');
    });

    test('key 写入 mimoConfigDir/.env → deepseekKey 检测为 installed', () async {
      final dir = Directory(env.mimoConfigDir);
      await dir.create(recursive: true);
      await File('${env.mimoConfigDir}/.env')
          .writeAsString('DS_API_KEY=sk-test-key\n');

      expect(await env.isToolInstalled(RuntimeTool.deepseekKey), isTrue);
    });

    test('回归锁定 Bug1：key 写入 runtimeDir/.mimo2codex/.env 不被识别', () async {
      final wrongDir = Directory('${env.runtimeDir}/.mimo2codex');
      await wrongDir.create(recursive: true);
      await File('${wrongDir.path}/.env')
          .writeAsString('DS_API_KEY=sk-test-key\n');

      expect(await env.isToolInstalled(RuntimeTool.deepseekKey), isFalse,
          reason: '旧保存路径（runtime/.mimo2codex）不应被检测为已配置');
    });

    test('env 文件存在但不含 DS_API_KEY → 仍为 missing', () async {
      final dir = Directory(env.mimoConfigDir);
      await dir.create(recursive: true);
      await File('${env.mimoConfigDir}/.env').writeAsString('OTHER_KEY=x\n');

      expect(await env.isToolInstalled(RuntimeTool.deepseekKey), isFalse);
    });

    test('saveDeepSeekKey → App 侧 + rootfs 侧双写，codex 可读取', () async {
      // 构造 Ubuntu rootfs 已安装（ubuntuRootfsDir 存在）
      final rootfs = Directory(env.ubuntuRootfsDir);
      await rootfs.create(recursive: true);

      await env.saveDeepSeekKey('sk-rootfs-sync');

      // App 侧（部署中心检测路径）
      expect(await env.isToolInstalled(RuntimeTool.deepseekKey), isTrue,
          reason: 'App 侧写入 mimoConfigDir/.env');

      // rootfs 内（codex 进程读取路径）
      final rootfsEnv = File(
        '${env.ubuntuRootfsDir}/root/.mimo2codex/.env',
      );
      expect(rootfsEnv.existsSync(), isTrue,
          reason: 'rootfs 存在时需同步写入 root/.mimo2codex/.env');
      expect(rootfsEnv.readAsStringSync(), contains('DS_API_KEY=sk-rootfs-sync'));
    });

    test('saveDeepSeekKey → rootfs 未安装时仅写 App 侧，不报错', () async {
      // 不创建 ubuntuRootfsDir
      await env.saveDeepSeekKey('sk-app-only');

      expect(await env.isToolInstalled(RuntimeTool.deepseekKey), isTrue);
      expect(
        Directory('${env.ubuntuRootfsDir}/root').existsSync(),
        isFalse,
        reason: 'rootfs 不存在时不应创建多余目录',
      );
    });
  });
}
