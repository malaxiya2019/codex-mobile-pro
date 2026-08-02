import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logger/log_export_channel.dart';
import '../logger/log_service.dart';

/// 备份条目（文档目录中的备份文件）
class BackupEntry {
  final String fileName;
  final String filePath;
  final DateTime createdAt;
  final int size;

  const BackupEntry({
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.size,
  });
}

/// 配置备份/恢复服务
///
/// 备份范围（全部存储于 SharedPreferences）：
/// - 主题：theme_mode / font_family / font_scale
/// - 语言：app_locale
/// - 终端：terminal_fontFamily / terminal_fontSize / terminal_*Color / terminal_themeMode / terminal_cursorBlink
/// - 登录：auth_token（App 会话）/ github_token
/// - 工作区：workspaces / current_workspace_id
/// - 项目：projects
///
/// 导出：写 JSON 到应用文档目录 backups/（恢复源），并复制一份到公共 Download（用户可取走）。
/// 恢复：从文档目录备份文件读取，写回 SharedPreferences；热生效由各 Provider 初始化时读取，
/// 已加载的页面配置建议重启 App 生效。
class BackupService {
  BackupService._();

  static const String backupDirName = 'backups';
  static const String backupSchemaVersion = '1';

  /// 备份白名单 — 只备份业务配置，忽略内部临时 key
  static const List<String> backupKeys = [
    // 主题
    'theme_mode',
    'font_family',
    'font_scale',
    // 语言
    'app_locale',
    // 终端
    'terminal_fontFamily',
    'terminal_fontSize',
    'terminal_backgroundColor',
    'terminal_cursorColor',
    'terminal_foregroundColor',
    'terminal_themeMode',
    'terminal_cursorBlink',
    // 登录
    'auth_token',
    'github_token',
    // 工作区
    'workspaces',
    'current_workspace_id',
    // 项目
    'projects',
  ];

  /// 收集备份数据（仅白名单 key，跳过未设置项）
  static Future<Map<String, dynamic>> collectConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};

    for (final key in backupKeys) {
      final value = prefs.get(key);
      if (value != null) {
        data[key] = value;
      }
    }
    return data;
  }

  /// 导出备份
  ///
  /// 返回文档目录备份文件路径。Download 副本失败仅告警，不影响导出。
  /// [backupDir] 供测试注入临时目录；为空时使用应用文档目录。
  static Future<String> exportBackup({Directory? backupDir}) async {
    final data = await collectConfig();
    final timestamp = _timestamp();
    final fileName = 'codex-mobile-pro-backup-$timestamp.json';
    final content = jsonEncode({
      'app': 'codex-mobile-pro',
      'schema': backupSchemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'data': data,
    });

    final dir = backupDir ?? await _defaultBackupDir();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content, flush: true);

    // Download 副本（用户可取走）— 失败不影响导出
    try {
      await LogExportChannel.writeToDownload(
        fileName: fileName,
        content: content,
      );
    } catch (e) {
      LogService.warning('BackupService', '写 Download 副本失败（可忽略）: $e');
    }

    LogService.info('BackupService', '备份完成: ${file.path} (${data.length} 项)');
    return file.path;
  }

  /// 列出文档目录中的备份文件（按时间倒序）
  static Future<List<BackupEntry>> listBackups({Directory? backupDir}) async {
    try {
      final dir = backupDir ?? await _defaultBackupDir();
      if (!await dir.exists()) return const [];

      final entries = <BackupEntry>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.json')) continue;
        final stat = await entity.stat();
        entries.add(BackupEntry(
          fileName: entity.uri.pathSegments.last,
          filePath: entity.path,
          createdAt: stat.modified,
          size: stat.size,
        ));
      }
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (e) {
      LogService.warning('BackupService', '列出备份失败: $e');
      return const [];
    }
  }

  /// 恢复备份
  ///
  /// 返回恢复的 key → 值类型 映射（供 UI 展示摘要）。
  /// 已加载的 Provider 不会热更新，调用方应提示重启 App。
  static Future<Map<String, String>> restore(String filePath) async {
    final file = File(filePath);
    final raw = await file.readAsString();
    final payload = jsonDecode(raw) as Map<String, dynamic>;

    final data = payload['data'] as Map<String, dynamic>? ?? const {};
    final prefs = await SharedPreferences.getInstance();
    final restored = <String, String>{};

    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      try {
        if (value is String) {
          await prefs.setString(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else {
          // 未知类型（如嵌套 List/Map）以 JSON 字符串存回
          await prefs.setString(key, jsonEncode(value));
        }
        restored[key] = value.runtimeType.toString();
      } catch (e) {
        LogService.error('BackupService', '恢复 key=$key 失败: $e');
      }
    }

    LogService.info('BackupService', '恢复完成: $filePath (${restored.length} 项)');
    return restored;
  }

  /// 默认备份目录：<应用文档目录>/backups
  static Future<Directory> _defaultBackupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$backupDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
