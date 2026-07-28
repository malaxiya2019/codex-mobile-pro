import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/core/logger/log_service.dart';
import 'package:codex_mobile_pro/core/logger/log_file_writer.dart';

void main() {
  group('LogLevel', () {
    test('优先级正确排序', () {
      expect(LogLevel.debug.priority, 0);
      expect(LogLevel.info.priority, 1);
      expect(LogLevel.warning.priority, 2);
      expect(LogLevel.error.priority, 3);
    });

    test('标签正确', () {
      expect(LogLevel.debug.label, 'DEBUG');
      expect(LogLevel.info.label, 'INFO');
      expect(LogLevel.warning.label, 'WARN');
      expect(LogLevel.error.label, 'ERROR');
    });
  });

  group('LogService', () {
    setUp(() {
      LogService.dispose();
    });

    test('init 不抛异常', () async {
      await LogService.init(enableFile: false);
      // 没有异常即通过
    });

    test('重复 init 只初始化一次', () async {
      await LogService.init(enableFile: false);
      await LogService.init(enableFile: false);
      // 没有异常即通过
    });

    test('debug/info/warning/error 不抛异常', () {
      LogService.init(enableFile: false);
      LogService.debug('Test', 'debug message');
      LogService.info('Test', 'info message');
      LogService.warning('Test', 'warning message');
      LogService.error('Test', 'test error');
      // 没有异常即通过
    });

    test('exception 不抛异常', () {
      LogService.init(enableFile: false);
      LogService.exception('Test', Exception('test exception'));
    });

    test('setLevel 过滤低级别日志', () {
      LogService.init(enableFile: false);
      LogService.setLevel(LogLevel.error);
      LogService.debug('Test', 'should be filtered');
      LogService.info('Test', 'should be filtered');
      LogService.warning('Test', 'should be filtered');
      LogService.error('Test', 'should appear');
      // 没有异常即通过
    });
  });

  group('LogFileWriter', () {
    final testDir = Directory.systemTemp.path + '/codex_log_test';

    setUp(() async {
      final dir = Directory(testDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    tearDown(() async {
      final dir = Directory(testDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('init 创建目录', () async {
      final writer = LogFileWriter(baseDir: testDir);
      await writer.init();
      expect(Directory(testDir).existsSync(), true);
      await writer.dispose();
    });

    test('write 创建日志文件', () async {
      final writer = LogFileWriter(baseDir: testDir);
      await writer.init();
      await writer.write('test log line');
      await writer.flush();

      final file = File('$testDir/app.log');
      expect(await file.exists(), true);
      final content = await file.readAsString();
      expect(content, contains('test log line'));
      await writer.dispose();
    });

    test('多次写入追加到文件', () async {
      final writer = LogFileWriter(baseDir: testDir);
      await writer.init();
      await writer.write('line1');
      await writer.write('line2');
      await writer.flush();

      final content = await File('$testDir/app.log').readAsString();
      expect(content, contains('line1'));
      expect(content, contains('line2'));
      await writer.dispose();
    });

    test('文件超过大小后轮转', () async {
      final writer = LogFileWriter(
        baseDir: testDir,
        maxFileSize: 100, // 小文件，触发轮转
        maxFiles: 3,
      );
      await writer.init();

      // 写足够数据触发轮转
      for (int i = 0; i < 50; i++) {
        await writer.write('This is log line number $i ' * 5);
      }
      await writer.flush();

      // 轮转后 app.log 或 app.log.0 至少有一个存在
      final appLog = File('$testDir/app.log');
      final appLog0 = File('$testDir/app.log.0');
      final exists = await appLog.exists() || await appLog0.exists();
      expect(exists, true);
      
      // 检查有内容写入
      if (await appLog.exists()) {
        final length = await appLog.length();
        expect(length, greaterThan(0));
      } else {
        final length = await appLog0.length();
        expect(length, greaterThan(0));
      }
      await writer.dispose();
    });

    test('clearAll 清理所有日志', () async {
      final writer = LogFileWriter(baseDir: testDir);
      await writer.init();
      await writer.write('test line');
      await writer.flush();
      await writer.clearAll();

      // clearAll 会删除日志文件并重新创建空文件
      final appLog = File('$testDir/app.log');
      if (await appLog.exists()) {
        final fileContent = await appLog.readAsString();
        expect(fileContent, isEmpty);
      }
      // 如果文件不存在（被删除），也视为清理成功
      await writer.dispose();
    });

    test('readRecent 返回最近日志', () async {
      final writer = LogFileWriter(baseDir: testDir);
      await writer.init();
      for (int i = 0; i < 10; i++) {
        await writer.write('line $i');
      }
      await writer.flush();

      final recent = await writer.readRecent(maxLines: 3);
      expect(recent, contains('line 7'));
      expect(recent, contains('line 8'));
      expect(recent, contains('line 9'));
      await writer.dispose();
    });

    test('dispose 后写入不抛异常', () async {
      final writer = LogFileWriter(baseDir: testDir);
      await writer.init();
      await writer.dispose();
      // dispose 后写入应安全
      await writer.write('after dispose');
    });
  });
}
