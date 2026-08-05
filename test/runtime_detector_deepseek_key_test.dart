/// ====================================================================
/// DeepSeek API Key 部署中心输入框链路测试
///
/// 根因回归：`_kCapabilityMappings` 缺少 deepseek_key 映射，
/// `_detectCapabilities` 不生成 deepseek_key 结果 → ai 分组永远为空
/// → 部署中心「🤖 AI Runtime」分组不渲染 → API 输入框入口（配置按钮）
/// 不可见，_showApiKeyDialog / _saveApiKey 成为死代码。
///
/// 覆盖：
///   A. reGroupResults 将 deepseek_key 归入 ai 分组
///   B. detectOne('deepseek_key') 无 environment → missing
///   C. detectOne 带 environment + key 文件存在 → installed（保存后复检闭环）
///   D. detectOne 带 environment + key 文件缺失 → missing
///   E. detectOne 带 environment + 旧格式/空文件 → missing
/// ====================================================================
library;

import 'dart:io';

import 'package:codex_mobile_pro/core/detector/detection_result.dart';
import 'package:codex_mobile_pro/core/detector/detector.dart';

import 'package:codex_mobile_pro/runtime/runtime_detector.dart';
import 'package:codex_mobile_pro/runtime/runtime_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeDetector — DeepSeek API Key 输入框链路', () {
    test('A. reGroupResults 将 deepseek_key 归入 ai 分组', () {
      final detector = RuntimeDetector();
      final grouped = detector.reGroupResults([
        const DetectionResult(
          id: 'deepseek_key',
          name: 'DeepSeek API Key',
          icon: '🔑',
          status: DetectionStatus.missing,
          subCategory: RuntimeSubCategory.ai,
        ),
      ]);

      expect(grouped.ai, isNotEmpty);
      expect(grouped.ai.first.id, 'deepseek_key');
      expect(grouped.ai.first.subCategory, RuntimeSubCategory.ai);
    });

    test('B. detectOne(deepseek_key) 无 environment → missing 且不崩溃', () async {
      final detector = RuntimeDetector();
      final result = await detector.detectOne('deepseek_key');

      expect(result, isNotNull);
      expect(result!.id, 'deepseek_key');
      expect(result.name, 'DeepSeek API Key');
      expect(result.status, DetectionStatus.missing);
    });

    test('C. key 已保存 → detectOne 返回 installed（保存后复检闭环）', () async {
      final temp = await Directory.systemTemp.createTemp('rtd-ds-');
      addTearDown(() => temp.delete(recursive: true));

      final env = RuntimeEnvironment.forTest(temp.path);
      // 模拟「配置」对话框保存的 .env（_saveApiKey 同款内容）
      final dir = Directory(env.mimoConfigDir);
      dir.createSync(recursive: true);
      File('${dir.path}/.env').writeAsStringSync('DS_API_KEY=sk-test-123\n');

      final detector = RuntimeDetector();
      final result = await detector.detectOne('deepseek_key', environment: env);

      expect(result, isNotNull);
      expect(result!.status, DetectionStatus.installed,
          reason: '保存路径（mimoConfigDir）与检测路径一致，保存后应立即可见');
    });

    test('D. key 未保存 → detectOne 返回 missing', () async {
      final temp = await Directory.systemTemp.createTemp('rtd-ds-');
      addTearDown(() => temp.delete(recursive: true));

      final env = RuntimeEnvironment.forTest(temp.path);
      // 不创建 .env

      final detector = RuntimeDetector();
      final result = await detector.detectOne('deepseek_key', environment: env);

      expect(result, isNotNull);
      expect(result!.status, DetectionStatus.missing);
    });

    test('E. .env 存在但不含 DS_API_KEY → missing（不误判）', () async {
      final temp = await Directory.systemTemp.createTemp('rtd-ds-');
      addTearDown(() => temp.delete(recursive: true));

      final env = RuntimeEnvironment.forTest(temp.path);
      final dir = Directory(env.mimoConfigDir);
      dir.createSync(recursive: true);
      File('${dir.path}/.env').writeAsStringSync('OTHER=1\n');

      final detector = RuntimeDetector();
      final result = await detector.detectOne('deepseek_key', environment: env);

      expect(result, isNotNull);
      expect(result!.status, DetectionStatus.missing);
    });
  });
}
