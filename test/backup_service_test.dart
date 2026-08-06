import 'dart:convert';
import 'dart:io';

import 'package:codex_mobile_pro/core/config/backup_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('BackupService', () {
    test('collectConfig 只收集白名单 key（prefs + secure storage）', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'app_locale': 'zh_CN',
        'terminal_fontSize': 14.0,
        'terminal_cursorBlink': true,
        'workspaces': '[]',
        // 非白名单 key 不应被收集
        'internal_temp': 'should-not-appear',
      });
      // github_token 已迁 secure storage（9679cba），不再从 prefs 读取
      FlutterSecureStorage.setMockInitialValues({
        'github_token': 'ghp_test',
        'github_user': 'octocat',
      });

      final data = await BackupService.collectConfig();

      expect(data['theme_mode'], 'dark');
      expect(data['app_locale'], 'zh_CN');
      expect(data['terminal_fontSize'], 14.0);
      expect(data['terminal_cursorBlink'], true);
      // secure storage 登录态被收集
      expect(data['github_token'], 'ghp_test');
      expect(data['github_user'], 'octocat');
      expect(data.containsKey('internal_temp'), isFalse);
    });

    test('collectConfig 无 secure 值时跳过', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final data = await BackupService.collectConfig();
      expect(data['theme_mode'], 'dark');
      expect(data.containsKey('github_token'), isFalse);
      expect(data.containsKey('github_user'), isFalse);
    });

    test('exportBackup 生成合法 JSON 备份文件（含 secure 登录态）', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'app_locale': 'zh_CN',
      });
      FlutterSecureStorage.setMockInitialValues({
        'github_token': 'ghp_test',
        'github_user': 'octocat',
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
      expect(data['github_user'], 'octocat');
    });

    test('listBackups 按时间倒序列出 .json 文件', () async {
      final dir = await Directory.systemTemp.createTemp('backup-list');
      addTearDown(() => dir.delete(recursive: true));

      final early = File('${dir.path}/codex-mobile-pro-backup-20260802-010000.json');
      final late = File('${dir.path}/codex-mobile-pro-backup-20260802-020000.json');
      await early.writeAsString('{"a":1}');
      await late.writeAsString('{"b":2}');
      await File('${dir.path}/notes.txt').writeAsString('ignore');

      // 显式设置 mtime：避免同秒创建的文件在 mtime 精度受限的文件系统
      // （如 PRoot overlayfs）上排序不稳定
      final base = DateTime.now().subtract(const Duration(minutes: 1));
      await early.setLastModified(base);
      await late.setLastModified(base.add(const Duration(seconds: 1)));

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
      });
      final backupPath = await BackupService.exportBackup(backupDir: dir);

      // 清空后恢复
      SharedPreferences.setMockInitialValues({});
      final restored = await BackupService.restore(backupPath);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getDouble('terminal_fontSize'), 16.0);
      expect(prefs.getBool('terminal_cursorBlink'), isFalse);
      expect(restored.length, greaterThanOrEqualTo(3));
    });

    test('restore 把 github_token/github_user 写回 secure storage（而非 prefs）', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'github_token': 'ghp_secure',
        'github_user': 'octocat',
      });

      final dir = await Directory.systemTemp.createTemp('backup-secure-restore');
      addTearDown(() => dir.delete(recursive: true));

      final backupPath = await BackupService.exportBackup(backupDir: dir);
      expect(
        (jsonDecode(await File(backupPath).readAsString())
            as Map<String, dynamic>)['data']['github_token'],
        'ghp_secure',
      );

      // 清空 secure storage 后恢复
      FlutterSecureStorage.setMockInitialValues({});
      final restored = await BackupService.restore(backupPath);

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'github_token'), 'ghp_secure');
      expect(await storage.read(key: 'github_user'), 'octocat');
      // prefs 中不应出现 github_token
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('github_token'), isNull);
      expect(restored['github_token'], 'secure');
      expect(restored['github_user'], 'secure');
    });

    test('restore 兼容旧备份：github_token 在 data 中时写回 secure storage', () async {
      final dir = await Directory.systemTemp.createTemp('backup-legacy');
      addTearDown(() => dir.delete(recursive: true));

      // 模拟 9679cba 之前生成的旧备份：github_token 存在 data 中
      final legacyFile = File('${dir.path}/legacy.json');
      await legacyFile.writeAsString(jsonEncode({
        'app': 'codex-mobile-pro',
        'schema': '1',
        'data': {
          'theme_mode': 'dark',
          'github_token': 'ghp_legacy',
        },
      }));

      FlutterSecureStorage.setMockInitialValues({});
      final restored = await BackupService.restore(legacyFile.path);

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'github_token'), 'ghp_legacy');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getString('github_token'), isNull);
      expect(restored['github_token'], 'secure');
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
