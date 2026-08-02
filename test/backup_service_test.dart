import 'dart:convert';
import 'dart:io';

import 'package:codex_mobile_pro/core/config/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BackupService', () {
    test('collectConfig 只收集白名单 key', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'app_locale': 'zh_CN',
        'terminal_fontSize': 14.0,
        'terminal_cursorBlink': true,
        'github_token': 'ghp_test',
        'workspaces': '[]',
        // 非白名单 key 不应被收集
        'internal_temp': 'should-not-appear',
      });

      final data = await BackupService.collectConfig();

      expect(data['theme_mode'], 'dark');
      expect(data['app_locale'], 'zh_CN');
      expect(data['terminal_fontSize'], 14.0);
      expect(data['terminal_cursorBlink'], true);
      expect(data['github_token'], 'ghp_test');
      expect(data.containsKey('internal_temp'), isFalse);
    });

    test('exportBackup 生成合法 JSON 备份文件', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'app_locale': 'zh_CN',
        'github_token': 'ghp_test',
      });

      final dir = await Directory.systemTemp.createTemp('backup-test');
      addTearDown(() => dir.delete(recursive: true));

      final path = await BackupService.exportBackup(backupDir: dir);
      final file = File(path);
      expect(await file.exists(), isTrue);

      final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(payload['app'], 'codex-mobile-pro');
      expect(payload['schema'], '1');
      final data = payload['data'] as Map<String, dynamic>;
      expect(data['theme_mode'], 'dark');
      expect(data['github_token'], 'ghp_test');
    });

    test('listBackups 按时间倒序列出 .json 文件', () async {
      final dir = await Directory.systemTemp.createTemp('backup-list');
      addTearDown(() => dir.delete(recursive: true));

      await File('${dir.path}/codex-mobile-pro-backup-20260802-010000.json')
          .writeAsString('{"a":1}');
      await File('${dir.path}/codex-mobile-pro-backup-20260802-020000.json')
          .writeAsString('{"b":2}');
      await File('${dir.path}/notes.txt').writeAsString('ignore');

      final backups = await BackupService.listBackups(backupDir: dir);

      expect(backups.length, 2);
      expect(backups.first.fileName, contains('020000')); // 最新在前
      expect(backups.every((b) => b.filePath.endsWith('.json')), isTrue);
    });

    test('restore 写回 SharedPreferences 并保留类型', () async {
      SharedPreferences.setMockInitialValues({});

      final dir = await Directory.systemTemp.createTemp('backup-restore');
      addTearDown(() => dir.delete(recursive: true));

      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'terminal_fontSize': 16.0,
        'terminal_cursorBlink': false,
        'github_token': 'ghp_restore',
      });
      final backupPath = await BackupService.exportBackup(backupDir: dir);

      // 清空后恢复
      SharedPreferences.setMockInitialValues({});
      final restored = await BackupService.restore(backupPath);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getDouble('terminal_fontSize'), 16.0);
      expect(prefs.getBool('terminal_cursorBlink'), isFalse);
      expect(prefs.getString('github_token'), 'ghp_restore');
      expect(restored.length, greaterThanOrEqualTo(3));
    });

    test('restore 空备份安全（无异常）', () async {
      final dir = await Directory.systemTemp.createTemp('backup-empty');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/empty.json');
      await file.writeAsString(jsonEncode({
        'app': 'codex-mobile-pro',
        'schema': '1',
        'data': <String, dynamic>{},
      }));

      final restored = await BackupService.restore(file.path);
      expect(restored, isEmpty);
    });
  });
}
