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
  });
}
