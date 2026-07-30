import 'package:codex_mobile_pro/features/deploy/services/environment_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvironmentDetail', () {
    test('构造正确', () {
      const detail = EnvironmentDetail(
        tool: 'Flutter',
        version: '3.22.0',
        path: '/usr/bin/flutter',
        detail: 'stable channel',
      );

      expect(detail.tool, 'Flutter');
      expect(detail.version, '3.22.0');
      expect(detail.path, '/usr/bin/flutter');
      expect(detail.detail, 'stable channel');
      expect(detail.installed, true);
    });

    test('未安装状态', () {
      const detail = EnvironmentDetail(
        tool: 'Rust',
        version: '',
        installed: false,
      );

      expect(detail.installed, false);
      expect(detail.version, '');
      expect(detail.path, isNull);
    });
  });

  group('FlutterEnvironment', () {
    test('构造正确', () {
      const env = FlutterEnvironment(
        flutterVersion: '3.22.0',
        dartVersion: '3.5.0',
        sdkPath: '/opt/flutter',
        channels: ['stable'],
        engineVersion: 'abc123',
      );

      expect(env.flutterVersion, '3.22.0');
      expect(env.dartVersion, '3.5.0');
      expect(env.sdkPath, '/opt/flutter');
      expect(env.channels, ['stable']);
      expect(env.engineVersion, 'abc123');
    });

    test('默认值', () {
      const env = FlutterEnvironment(
        flutterVersion: '3.22.0',
        dartVersion: '3.5.0',
      );

      expect(env.sdkPath, isNull);
      expect(env.channels, isEmpty);
      expect(env.engineVersion, isNull);
    });
  });

  group('RustEnvironment', () {
    test('构造正确', () {
      const env = RustEnvironment(
        rustcVersion: '1.79.0',
        cargoVersion: '1.79.0',
        toolchain: 'stable-aarch64-linux-android',
        targets: ['aarch64-linux-android'],
      );

      expect(env.rustcVersion, '1.79.0');
      expect(env.cargoVersion, '1.79.0');
      expect(env.toolchain, 'stable-aarch64-linux-android');
      expect(env.targets, ['aarch64-linux-android']);
    });
  });

  group('PythonEnvironment', () {
    test('构造正确', () {
      const env = PythonEnvironment(
        pythonVersion: '3.11.5',
        pipVersion: '23.2.1',
        hasVenv: true,
        packages: ['requests', 'flask'],
      );

      expect(env.pythonVersion, '3.11.5');
      expect(env.pipVersion, '23.2.1');
      expect(env.hasVenv, true);
      expect(env.packages, ['requests', 'flask']);
    });
  });

  group('InstallResult', () {
    test('安装成功', () {
      const result = InstallResult(
        success: true,
        tool: 'flutter',
        output: 'Cloned to /opt/flutter',
      );

      expect(result.success, true);
      expect(result.tool, 'flutter');
      expect(result.output, 'Cloned to /opt/flutter');
      expect(result.errorMessage, isNull);
    });

    test('安装失败', () {
      const result = InstallResult(
        success: false,
        tool: 'rust',
        errorMessage: 'curl: command not found',
      );

      expect(result.success, false);
      expect(result.errorMessage, 'curl: command not found');
    });
  });

  group('EnvironmentManager', () {
    test('创建实例', () {
      final mgr = EnvironmentManager();
      expect(mgr, isNotNull);
    });

    test('检测所有返回列表', () async {
      final mgr = EnvironmentManager();
      final results = await mgr.detectAll();
      expect(results, isA<List>());
      expect(results.length, greaterThanOrEqualTo(1));
    });

    test('不支持的工具安装返回错误', () async {
      final result = await EnvironmentManager.install('unknown-tool');
      expect(result.success, false);
      expect(result.errorMessage, contains('不支持自动安装'));
    });

    test('环境摘要返回 Map', () async {
      final summary = await EnvironmentManager.getEnvironmentSummary();
      expect(summary, isA<Map>());
      expect(summary.containsKey('Flutter'), true);
      expect(summary.containsKey('Rust'), true);
      expect(summary.containsKey('Python'), true);
      expect(summary.containsKey('Git'), true);
    });
  });
}
