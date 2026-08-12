library;
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Gemini 视觉模型配置
///
/// API Key 读取优先级：
///   1. SharedPreferences（AI 对话页设置入口写入）
///   2. 环境变量 GEMINI_API_KEY
///   3. 本地文件 ~/.gemini_api_key（CLI / 测试兜底，不写日志）
/// 模型名持久化在 SharedPreferences，默认 `gemini-2.5-flash`
/// （Google AI Studio 免费 Key 可用，支持图片/视频理解）。

class GeminiConfig {
  GeminiConfig._();

  /// SharedPreferences 键
  static const String prefKeyApiKey = 'gemini_api_key';
  static const String prefKeyModel = 'gemini_model';

  /// 默认模型（免费 Key 可用，支持图片理解）
  static const String defaultModel = 'gemini-2.5-flash';

  /// 可选模型（Google AI Studio 免费 Key 通常可用 flash / flash-lite；
  /// pro 有免费额度但较少）
  static const List<String> supportedModels = [
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.5-pro',
  ];

  /// 读取 API Key（见类注释优先级）。找不到返回空字符串。
  static Future<String> loadApiKey() async {
    // 1. SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefKeyApiKey);
      if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    } catch (_) {}
    // 2. 环境变量
    final env = Platform.environment['GEMINI_API_KEY'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    // 3. 本地文件兜底
    try {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final f = File('$home/.gemini_api_key');
        if (await f.exists()) {
          final key = (await f.readAsString()).trim();
          if (key.isNotEmpty) return key;
        }
      }
    } catch (_) {}
    return '';
  }

  /// 读取模型名（无持久化时用默认值）
  static Future<String> loadModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefKeyModel);
      if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    } catch (_) {}
    return defaultModel;
  }

  /// 保存 API Key（设置入口写入；仅存 SharedPreferences）
  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKeyApiKey, key.trim());
  }

  /// 保存模型名
  static Future<void> saveModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKeyModel, model.trim());
  }

  /// 清除 API Key
  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefKeyApiKey);
  }
}
