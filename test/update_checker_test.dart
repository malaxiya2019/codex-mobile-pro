import 'dart:convert';

import 'package:codex_mobile_pro/features/settings/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  group('VersionCompare', () {
    test('比较主版本', () {
      expect(VersionCompare.compare('1.0.0', '1.0.0'), 0);
      expect(VersionCompare.compare('1.0.1', '1.0.0'), 1);
      expect(VersionCompare.compare('1.0.0', '1.0.1'), -1);
    });

    test('忽略 v 前缀和 prerelease/build 后缀', () {
      expect(VersionCompare.compare('v1.0.1', '1.0.0'), 1);
      expect(VersionCompare.compare('1.0.1-beta.1', '1.0.0'), 1);
      expect(VersionCompare.compare('1.0.1+build5', '1.0.1'), 0);
      expect(VersionCompare.compare('1.10.0', '1.9.9'), 1);
    });

    test('不同分段长度', () {
      expect(VersionCompare.compare('1.0', '1.0.0'), 0);
      expect(VersionCompare.compare('1.0.0.1', '1.0.0'), 1);
    });

    test('非法段按 0 处理', () {
      expect(VersionCompare.compare('1.0.x', '1.0.0'), 0);
    });
  });

  group('UpdateChecker.checkForUpdate', () {
    late MockHttpClient mockClient;
    late UpdateChecker checker;

    setUp(() {
      mockClient = MockHttpClient();
      checker = UpdateChecker(
        currentVersion: '1.0.0',
        httpClient: mockClient,
      );
    });

    http.Response releaseResponse({
      String tagName = 'v1.0.1',
      String? assetUrl = 'https://github.com/owner/repo/releases/download/v1.0.1/app.apk',
      String? assetName = 'app.apk',
    }) {
      return http.Response(
        jsonEncode({
          'tag_name': tagName,
          'body': '修复若干问题',
          'published_at': '2026-08-01T00:00:00Z',
          'assets': [
            {
              'name': assetName,
              'browser_download_url': assetUrl,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    test('有更新且有 APK 资产', () async {
      when(() => mockClient.get(
        any(),
        headers: any(named: 'headers'),
      )).thenAnswer((_) async => releaseResponse());

      final update = await checker.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.version, '1.0.1');
      expect(update.tagName, 'v1.0.1');
      expect(update.downloadUrl,
          'https://github.com/owner/repo/releases/download/v1.0.1/app.apk');
      expect(update.releaseNotes, '修复若干问题');
      expect(update.publishedAt, DateTime.utc(2026, 8));
    });

    test('tag 不带 v 前缀也能解析', () async {
      when(() => mockClient.get(
        any(),
        headers: any(named: 'headers'),
      )).thenAnswer((_) async => releaseResponse(tagName: '1.0.2'));

      final update = await checker.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.version, '1.0.2');
    });

    test('404（仓库无 Release）返回 null', () async {
      when(() => mockClient.get(
        any(),
        headers: any(named: 'headers'),
      )).thenAnswer((_) async => http.Response('Not Found', 404));

      final update = await checker.checkForUpdate();
      expect(update, isNull);
    });

    test('版本不高于当前 → 无更新', () async {
      when(() => mockClient.get(
        any(),
        headers: any(named: 'headers'),
      )).thenAnswer((_) async => releaseResponse(tagName: 'v1.0.0'));

      final update = await checker.checkForUpdate();
      expect(update, isNull);
    });

    test('Release 无 APK 资产 → 返回空下载地址', () async {
      when(() => mockClient.get(
        any(),
        headers: any(named: 'headers'),
      )).thenAnswer((_) async => releaseResponse(assetUrl: null, assetName: 'app.zip'));

      final update = await checker.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.hasApkAsset, isFalse);
      expect(update.downloadUrl, isNull);
    });

    test('网络异常抛出 UpdateCheckException', () async {
      when(() => mockClient.get(
        any(),
        headers: any(named: 'headers'),
      )).thenThrow(Exception('socket closed'));

      expect(
        checker.checkForUpdate(),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('请求 GitHub API 时带 User-Agent', () async {
      when(() => mockClient.get(
        any(),
        headers: any(named: 'headers'),
      )).thenAnswer((_) async => releaseResponse());

      await checker.checkForUpdate();
      final captured = verify(
        () => mockClient.get(
          any(),
          headers: captureAny(named: 'headers'),
        ),
      ).captured;
      final headers = captured.single as Map<String, String>;
      expect(headers['User-Agent'], 'codex-mobile-pro');
    });
  });
}
