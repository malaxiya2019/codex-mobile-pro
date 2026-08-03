import 'package:codex_mobile_pro/features/settings/services/log_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLogLine', () {
    test('解析标准行', () {
      final e = parseLogLine('[2026-08-03T12:00:00.000][INFO][Test] hello');
      expect(e, isNotNull);
      expect(e!.level, LogEntryLevel.info);
      expect(e.tag, 'Test');
      expect(e.message, 'hello');
      expect(e.isCrash, isFalse);
      expect(e.timestamp, isNotNull);
    });

    test('解析 WARN 行', () {
      final e = parseLogLine('[2026-08-03T12:00:00][WARN][AptSource] fallback');
      expect(e!.level, LogEntryLevel.warning);
      expect(e.message, 'fallback');
    });

    test('解析 ERROR 行', () {
      final e = parseLogLine('[2026-08-03T12:00:00][ERROR][Runtime] boom');
      expect(e!.level, LogEntryLevel.error);
    });

    test('崩溃日志 tag 为 CRASH 且 isCrash=true', () {
      final e = parseLogLine(
          '[2026-08-03T12:00:00.000][ERROR][CRASH][FlutterError] boom');
      expect(e, isNotNull);
      expect(e!.isCrash, isTrue);
      expect(e.tag, 'CRASH');
      expect(e.message, '[FlutterError] boom');
    });

    test('解析失败返回 null（无关行）', () {
      expect(parseLogLine(''), isNull);
      expect(parseLogLine('plain text line'), isNull);
      expect(parseLogLine('[2026-08-03T12:00:00][INFO] no tag'), isNull);
    });
  });

  group('parseLogText', () {
    test('解析多行并跳过无效行', () {
      final entries = parseLogText(
        'first line\n'
        '[2026-08-03T12:00:00][INFO][A] a\n'
        'noise\n'
        '[2026-08-03T12:00:01][ERROR][B] b\n',
      );
      expect(entries.length, 2);
      expect(entries[0].tag, 'A');
      expect(entries[1].tag, 'B');
    });
  });

  group('filterLogEntries', () {
    final entries = parseLogText(
      '[2026-08-03T12:00:00][DEBUG][T] d\n'
      '[2026-08-03T12:00:01][INFO][T] i\n'
      '[2026-08-03T12:00:02][WARN][T] w\n'
      '[2026-08-03T12:00:03][ERROR][T] e\n'
      '[2026-08-03T12:00:04][ERROR][CRASH][FlutterError] c\n',
    );

    test('默认不过滤', () {
      expect(filterLogEntries(entries).length, 5);
    });

    test('按最低级别过滤', () {
      // WARN、ERROR、CRASH(ERROR 级) 共 3 条
      final r = filterLogEntries(entries, minLevel: LogEntryLevel.warning);
      expect(r.length, 3);
      expect(r.every((e) => e.level.priority >= 2), isTrue);
    });

    test('仅崩溃', () {
      final r = filterLogEntries(entries, onlyCrash: true);
      expect(r.length, 1);
      expect(r.single.isCrash, isTrue);
      expect(r.single.tag, 'CRASH');
    });

    test('崩溃 + ERROR 组合', () {
      final r = filterLogEntries(entries,
          minLevel: LogEntryLevel.error, onlyCrash: true);
      expect(r.length, 1);
    });
  });
}
