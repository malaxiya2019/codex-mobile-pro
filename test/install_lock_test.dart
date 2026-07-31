/// ====================================================================
/// InstallLock 单元测试
///
/// 2026-08 止损重构：验证「防并发部署」锁语义：
///   1. 正常获取 / 释放
///   2. 锁被存活进程持有 → acquire 抛 deploymentInProgress
///   3. 陈旧锁（持有者已退出）→ acquire 自动清理并获取
///   4. 非持有者 release 不删除他人锁（防误删新任务锁）
///   5. 锁内容包含 pid 与时间戳
///
/// 不依赖真实 Termux / Android / 网络。
/// ====================================================================
library;

import 'dart:io';

import 'package:codex_mobile_pro/runtime/deploy_error.dart';
import 'package:codex_mobile_pro/runtime/install_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late File lockFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('install_lock_test_');
    lockFile = File('${tmp.path}/${InstallLock.defaultLockName}');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('InstallLock — 基本获取/释放', () {
    test('正常获取后锁文件存在且内容含 pid', () async {
      final lock = InstallLock(lockFile);
      await lock.acquire();

      expect(lockFile.existsSync(), isTrue);
      final content = lockFile.readAsStringSync();
      expect(content, contains('pid=$pid'));
      expect(content, contains('started_at='));

      await lock.release();
      expect(lockFile.existsSync(), isFalse, reason: '释放后锁文件应删除');
    });

    test('未获取直接 release 是安全的（no-op）', () async {
      final lock = InstallLock(lockFile);
      await lock.release();
      expect(lockFile.existsSync(), isFalse);
    });

    test('连续两次 acquire/release 可重复（幂等）', () async {
      for (var i = 0; i < 3; i++) {
        final lock = InstallLock(lockFile);
        await lock.acquire();
        expect(lockFile.existsSync(), isTrue);
        await lock.release();
        expect(lockFile.existsSync(), isFalse);
      }
    });
  });

  group('InstallLock — 并发/陈旧锁', () {
    test('锁被存活进程持有 → acquire 抛 deploymentInProgress', () async {
      // 启动一个存活进程作为「另一部署任务」
      final holder = await Process.start('sh', ['-c', 'sleep 30']);
      addTearDown(() => holder.kill());

      lockFile.writeAsStringSync(
        'pid=${holder.pid}\n'
        'started_at=${DateTime.now().toIso8601String()}\n',
      );

      final lock = InstallLock(lockFile);
      try {
        await lock.acquire();
        fail('应抛 deploymentInProgress');
      } on DeployError catch (e) {
        expect(e.code, DeployErrorCode.deploymentInProgress);
        expect(e.message, contains('已有部署任务'));
      }
      // 锁文件未被破坏
      expect(lockFile.existsSync(), isTrue);
    });

    test('陈旧锁（pid 不存在）→ acquire 清理并成功获取', () async {
      // 用一个几乎不可能存活的 pid（Linux 默认 max pid 通常 < 10000000）
      final deadPid = 99999999;
      lockFile.writeAsStringSync(
        'pid=$deadPid\n'
        'started_at=${DateTime.now().toIso8601String()}\n',
      );

      final lock = InstallLock(lockFile);
      await lock.acquire();
      expect(lockFile.existsSync(), isTrue);
      final content = lockFile.readAsStringSync();
      expect(content, contains('pid=$pid'), reason: '锁应被当前进程重新获取');

      await lock.release();
      expect(lockFile.existsSync(), isFalse);
    });

    test('陈旧锁（内容无 pid 行）→ acquire 清理并成功获取', () async {
      lockFile.writeAsStringSync('garbage-no-pid\n');
      final lock = InstallLock(lockFile);
      await lock.acquire();
      expect(lockFile.existsSync(), isTrue);
      await lock.release();
    });

    test('非持有者 release 不删除他人锁', () async {
      final holder = await Process.start('sh', ['-c', 'sleep 30']);
      addTearDown(() => holder.kill());
      lockFile.writeAsStringSync('pid=${holder.pid}\n');

      // 另一个 InstallLock 实例（模拟另一进程/线程）尝试 release
      final other = InstallLock(lockFile);
      await other.release();
      expect(
        lockFile.existsSync(),
        isTrue,
        reason: '非持有者不应删除他人锁',
      );
      // 且内容仍是持有者的 pid
      expect(lockFile.readAsStringSync(), contains('pid=${holder.pid}'));
    });
  });
}
