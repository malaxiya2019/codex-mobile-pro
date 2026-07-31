/// ====================================================================
/// Termux Runtime Smoke Test
///
/// 在真实设备上测试 Termux Runtime Provider 各功能。
/// 运行方式：flutter test test/termux_smoke_test.dart
///
/// 注意：
///   此测试需要真实 Termux 环境（MethodChannel 可用）。
///   如果在无 Termux 的设备上运行，detect 等测试应返回不可用（不失败）。
///
/// 测试顺序：
///   1. detect — Termux 检测
///   2. environment — 环境变量
///   3. shell — Shell 基础命令
///   4. node --version — Node 检测
///   5. python --version — Python 检测
///   6. git --version — Git 检测
///   7. npm --version — npm 检测
///   8. codex --version — Codex CLI 检测
///
/// 每项记录：provider, executable, version, exitCode, stdout, stderr, duration, error
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/provider/termux_provider.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TermuxRuntimeProvider provider;

  setUp(() {
    provider = TermuxRuntimeProvider();
  });

  group('Termux Smoke Test', () {
    test('1. detect — Termux 检测', () async {
      final info = await provider.detect();

      // 不应抛出异常
      expect(info.detectionDurationMs, greaterThanOrEqualTo(0));

      // 记录结果（失败不导致测试失败，因为可能无 Termux）
      debugPrint('[Smoke] detect: status=${info.status}, '
          'version=${info.version ?? "N/A"}, '
          'desc=${info.description ?? "N/A"}, '
          'duration=${info.detectionDurationMs}ms');
    });

    test('2. environment — 环境变量', () async {
      final env = await provider.getEnvironment();

      // 应包含基本变量
      expect(env.containsKey('HOME'), true);
      expect(env.containsKey('PATH'), true);
      expect(env.containsKey('TMPDIR'), true);

      debugPrint('[Smoke] environment: '
          'HOME=${env["HOME"]}, '
          'PREFIX=${env["PREFIX"] ?? "N/A"}, '
          'PATH=${env["PATH"]}');
    });

    test('3. shell — Shell 基础命令', () async {
      await provider.detect();

      if (!await provider.isAvailable()) {
        debugPrint('[Smoke] shell: SKIP (Termux not available)');
        return;
      }

      final result = await provider.executeInTermux('echo "smoke_test_ok"');

      debugPrint('[Smoke] shell: exitCode=${result.exitCode}, '
          'stdout="${result.stdout.trim()}", '
          'stderr="${result.stderr.trim()}", '
          'duration=${result.durationMs}ms');

      expect(result.exitCode, 0);
      expect(result.stdout.trim(), contains('smoke_test_ok'));
    });

    test('4. node --version', () async {
      await provider.detect();

      if (!await provider.isAvailable()) {
        debugPrint('[Smoke] node: SKIP (Termux not available)');
        return;
      }

      final executable = await provider.resolveExecutable('node');
      final result = await provider.executeInTermux('node --version');

      debugPrint('[Smoke] node: executable=${executable ?? "N/A"}, '
          'exitCode=${result.exitCode}, '
          'stdout="${result.stdout.trim()}", '
          'duration=${result.durationMs}ms');
    });

    test('5. python --version', () async {
      await provider.detect();

      if (!await provider.isAvailable()) {
        debugPrint('[Smoke] python: SKIP (Termux not available)');
        return;
      }

      final result = await provider.executeInTermux('python3 --version 2>/dev/null || python --version 2>/dev/null');

      debugPrint('[Smoke] python: exitCode=${result.exitCode}, '
          'stdout="${result.stdout.trim()}", '
          'duration=${result.durationMs}ms');
    });

    test('6. git --version', () async {
      await provider.detect();

      if (!await provider.isAvailable()) {
        debugPrint('[Smoke] git: SKIP (Termux not available)');
        return;
      }

      final result = await provider.executeInTermux('git --version');

      debugPrint('[Smoke] git: exitCode=${result.exitCode}, '
          'stdout="${result.stdout.trim()}", '
          'duration=${result.durationMs}ms');
    });

    test('7. npm --version', () async {
      await provider.detect();

      if (!await provider.isAvailable()) {
        debugPrint('[Smoke] npm: SKIP (Termux not available)');
        return;
      }

      final result = await provider.executeInTermux('npm --version');

      debugPrint('[Smoke] npm: exitCode=${result.exitCode}, '
          'stdout="${result.stdout.trim()}", '
          'duration=${result.durationMs}ms');
    });

    test('8. codex --version', () async {
      await provider.detect();

      if (!await provider.isAvailable()) {
        debugPrint('[Smoke] codex: SKIP (Termux not available)');
        return;
      }

      final result = await provider.executeInTermux('codex --version 2>/dev/null || echo "codex not found"');

      // codex 可能未安装，不失败
      debugPrint('[Smoke] codex: exitCode=${result.exitCode}, '
          'stdout="${result.stdout.trim()}", '
          'duration=${result.durationMs}ms');
    });
  });
}
