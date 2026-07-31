/// ====================================================================
/// InstallLock — 安装锁（防并发部署 / 重复初始化互相破坏）
///
/// 2026-08 止损重构：部署中心存在「Dart 侧解压 + Kotlin 侧初始化 +
/// 手动重复初始化」并发触发部署的可能。rootfs 解压/替换不是原子流程，
/// 并发写入会互相破坏（Permission denied / 半解压 rootfs）。
///
/// 锁语义：
///   - 锁文件内容 `pid=<pid>\nstarted_at=<iso>`
///   - [acquire]：锁存在且持有进程存活 → 抛
///     [DeployError.deploymentInProgress]；持有进程已退出（崩溃/被杀
///     遗留）→ 视为陈旧锁，清理后重新获取。
///   - [release]：仅当持有者仍是当前进程时删除锁，避免误删新任务锁。
///
/// 与 Operit 的 install.lock + PID 锁设计对齐（不依赖 Flutter/网络）。
/// ====================================================================
library;

import 'dart:io';

import 'deploy_error.dart';

/// 安装锁
class InstallLock {
  /// 默认锁文件名（位于 `<runtimeDir>/.install.lock`）
  static const String defaultLockName = '.install.lock';

  /// 锁文件
  final File file;

  /// 当前进程持有的锁 PID（用于释放时校验持有者）
  String? _owner;

  InstallLock(this.file);

  /// 锁文件是否已被存活进程持有
  Future<bool> isHeldByAliveProcess() async {
    if (!await file.exists()) return false;
    try {
      final content = await file.readAsString();
      final m = RegExp(r'pid=(\d+)').firstMatch(content);
      if (m == null) return false;
      final holder = int.tryParse(m.group(1)!);
      if (holder == null) return false;
      return await _pidAlive(holder);
    } catch (_) {
      return false;
    }
  }

  /// 获取安装锁。
  ///
  /// 锁已存在且持有进程存活 → 抛 [DeployError.deploymentInProgress]。
  /// 陈旧锁（持有者已退出）→ 清理后重新获取。
  Future<void> acquire() async {
    if (await file.exists()) {
      if (await isHeldByAliveProcess()) {
        final content = await file.readAsString();
        final m = RegExp(r'pid=(\d+)').firstMatch(content);
        final holder = m?.group(1) ?? '未知';
        throw DeployError(
          code: DeployErrorCode.deploymentInProgress,
          message: '已有部署任务正在进行中',
          detail: '锁文件 ${file.path} 由进程 $holder 持有',
          userSuggestion: '请等待当前部署完成后重试',
        );
      }
      // 陈旧锁（持有者已退出 / 崩溃遗留）→ 清理
      try {
        await file.delete();
      } catch (_) {}
    }
    await file.writeAsString(
      'pid=$pid\n'
      'started_at=${DateTime.now().toIso8601String()}\n',
      flush: true,
    );
    _owner = '$pid';
  }

  /// 释放安装锁（仅当持有者仍是当前进程时删除，避免误删新任务锁）。
  Future<void> release() async {
    final owner = _owner;
    _owner = null;
    if (owner == null) return;
    try {
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.contains('pid=$owner')) {
          await file.delete();
        }
      }
    } catch (_) {
      // 释放失败不影响主流程
    }
  }

  /// 进程是否存活（kill -0 探测；失败按不存活处理）
  Future<bool> _pidAlive(int pid) async {
    try {
      final r = await Process.run('kill', ['-0', '$pid']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
