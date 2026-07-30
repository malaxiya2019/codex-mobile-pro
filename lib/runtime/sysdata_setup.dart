/// ====================================================================
/// Fake Sysdata 设置器
///
/// 在 Ubuntu rootfs 的 /proc 目录下创建 fake 系统数据文件。
///
/// 原理：Android 对 /proc 文件系统有严格限制，proot 无法直接从
/// Android 的 procfs 读取正确数据。proot 会在读取 /proc/stat 时
/// 透明地重定向到 /proc/.stat（带前缀 . 的文件）。
///
/// 本模块在 rootfs 解压后在 /proc 目录下创建这些带 . 前缀的 fake 文件，
/// 使 Ubuntu 下依赖 /proc 的工具（如 ps, uptime, neofetch）可以正常工作。
///
/// 设计原则：
///   - 纯 Dart 实现，不依赖 shell 脚本
///   - CPU 核心数从 Android 系统属性获取（实际值）
///   - 文件内容使用固定模板的合理值
///   - 只在首次初始化 rootfs 时执行一次
///   - 不复制任何 GPLv3 代码（仅参考概念）
/// ====================================================================

import 'dart:io';

/// Fake sysdata 设置器
class SysDataSetup {
  /// 在 rootfs 的 /proc 目录下创建所有需要 fake 文件
  ///
  /// [rootfsPath] — Ubuntu rootfs 的绝对路径
  static Future<void> setup(String rootfsPath) async {
    final procDir = Directory('$rootfsPath/proc');
    if (!procDir.existsSync()) {
      await procDir.create(recursive: true);
    }

    await Future.wait([
      _createLoadavg(procDir),
      _createStat(procDir),
      _createUptime(procDir),
      _createVersion(procDir),
      _createVmstat(procDir),
      _createCapLastCap(procDir),
      _createInotifyMax(procDir),
    ]);
  }

  /// 检查所有 fake 文件是否已存在
  static bool isSetupComplete(String rootfsPath) {
    final procDir = '$rootfsPath/proc';
    return File('$procDir/.loadavg').existsSync() &&
        File('$procDir/.stat').existsSync() &&
        File('$procDir/.uptime').existsSync() &&
        File('$procDir/.version').existsSync();
  }

  /// ─── /proc/.loadavg ──────────────────────────────────────────
  ///
  /// CPU 平均负载（1min, 5min, 15min, 活跃进程/总进程, 最近 PID）
  static Future<void> _createLoadavg(Directory procDir) async {
    final file = File('${procDir.path}/.loadavg');
    if (await file.exists()) return;
    await file.writeAsString('0.12 0.07 0.02 2/165 765\n');
  }

  /// ─── /proc/.stat ─────────────────────────────────────────────
  ///
  /// CPU 统计信息。动态生成与实际 CPU 核心数匹配的条目。
  static Future<void> _createStat(Directory procDir) async {
    final file = File('${procDir.path}/.stat');
    if (await file.exists()) return;

    // 尝试获取实际 CPU 核心数
    final cpuCount = _getCpuCount();
    final buffer = StringBuffer();

    // cpu 合计行
    buffer.writeln('cpu  1957 0 2877 93280 262 342 254 87 0 0');

    // 每个核心单独一行
    for (int i = 0; i < cpuCount; i++) {
      final user = 31 + (i * 7) % 500;
      final nice = 0;
      final system = 226 - (i * 15) % 200;
      final idle = 12027 + (i * 123) % 5000;
      final iowait = 82 - (i * 3) % 60;
      final irq = 10 + (i * 25) % 250;
      final softirq = 4 + (i * 2) % 20;
      final steal = 9 + (i * 1) % 5;
      buffer.writeln('cpu$i  $user $nice $system $idle $iowait $irq $softirq $steal 0 0');
    }

    buffer.writeln('intr 127541 38 290 0 0 0 0 4 0 1 0 0 25329 258 0 5777 277 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0');
    buffer.writeln('ctxt 140223');
    buffer.writeln('btime 1680020856');
    buffer.writeln('processes 772');
    buffer.writeln('procs_running 2');
    buffer.writeln('procs_blocked 0');
    buffer.writeln('softirq 75663 0 5903 6 25375 10774 0 243 11685 0 21677');

    await file.writeAsString(buffer.toString());
  }

  /// ─── /proc/.uptime ─────────────────────────────────────────────
  ///
  /// 系统运行时间（秒）和空闲时间（秒）
  static Future<void> _createUptime(Directory procDir) async {
    final file = File('${procDir.path}/.uptime');
    if (await file.exists()) return;
    await file.writeAsString('124.08 932.80\n');
  }

  /// ─── /proc/.version ────────────────────────────────────────────
  ///
  /// Linux 内核版本字符串
  static Future<void> _createVersion(Directory procDir) async {
    final file = File('${procDir.path}/.version');
    if (await file.exists()) return;
    await file.writeAsString(
      'Linux version 6.2.1-android (proot@codex-mobile) '
      '(gcc (GCC) 13.3.0, GNU ld (GNU Binutils) 2.42) '
      '#1 SMP PREEMPT_DYNAMIC 2026-07-30\n',
    );
  }

  /// ─── /proc/.vmstat ─────────────────────────────────────────────
  ///
  /// 虚拟内存统计信息
  static Future<void> _createVmstat(Directory procDir) async {
    final file = File('${procDir.path}/.vmstat');
    if (await file.exists()) return;

    final buffer = StringBuffer();
    buffer.writeln('nr_free_pages 1743136');
    buffer.writeln('nr_zone_inactive_anon 179281');
    buffer.writeln('nr_zone_active_anon 7183');
    buffer.writeln('nr_zone_inactive_file 22858');
    buffer.writeln('nr_zone_active_file 51328');
    buffer.writeln('nr_zone_unevictable 642');
    buffer.writeln('nr_zone_write_pending 0');
    buffer.writeln('nr_mlock 0');
    buffer.writeln('nr_bounce 0');
    buffer.writeln('nr_zspages 0');
    buffer.writeln('nr_free_cma 0');
    buffer.writeln('numa_hit 1259626');
    buffer.writeln('numa_miss 0');
    buffer.writeln('numa_foreign 0');
    buffer.writeln('numa_interleave 720');
    buffer.writeln('numa_local 1259626');
    buffer.writeln('numa_other 0');
    buffer.writeln('nr_inactive_anon 179281');
    buffer.writeln('nr_active_anon 7183');
    buffer.writeln('nr_inactive_file 22858');
    buffer.writeln('nr_active_file 51328');
    buffer.writeln('nr_unevictable 642');
    buffer.writeln('nr_slab_reclaimable 8091');
    buffer.writeln('nr_slab_unreclaimable 7804');
    buffer.writeln('nr_isolated_anon 0');
    buffer.writeln('nr_isolated_file 0');
    buffer.writeln('workingset_nodes 0');
    buffer.writeln('workingset_refault_anon 0');
    buffer.writeln('workingset_refault_file 0');
    buffer.writeln('workingset_activate_anon 0');
    buffer.writeln('workingset_activate_file 0');
    buffer.writeln('workingset_restore_anon 0');
    buffer.writeln('workingset_restore_file 0');
    buffer.writeln('workingset_nodereclaim 0');
    buffer.writeln('nr_anon_pages 7723');
    buffer.writeln('nr_mapped 8905');
    buffer.writeln('nr_file_pages 253569');
    buffer.writeln('nr_dirty 0');
    buffer.writeln('nr_writeback 0');
    buffer.writeln('nr_writeback_temp 0');
    buffer.writeln('nr_shmem 178741');
    buffer.writeln('nr_shmem_hugepages 0');
    buffer.writeln('nr_shmem_pmdmapped 0');
    buffer.writeln('nr_file_hugepages 0');
    buffer.writeln('nr_file_pmdmapped 0');
    buffer.writeln('nr_anon_transparent_hugepages 1');
    buffer.writeln('nr_vmscan_write 0');
    buffer.writeln('nr_vmscan_immediate_reclaim 0');
    buffer.writeln('nr_dirtied 0');
    buffer.writeln('nr_written 0');
    buffer.writeln('nr_throttled_written 0');
    buffer.writeln('nr_kernel_misc_reclaimable 0');
    buffer.writeln('nr_foll_pin_acquired 0');
    buffer.writeln('nr_foll_pin_released 0');
    buffer.writeln('nr_kernel_stack 2780');
    buffer.writeln('nr_page_table_pages 344');
    buffer.writeln('nr_sec_page_table_pages 0');
    buffer.writeln('nr_swapcached 0');
    buffer.writeln('oom_kill 0');
    await file.writeAsString(buffer.toString());
  }

  /// ─── /proc/.sysctl_entry_cap_last_cap ─────────────────────────
  ///
  /// Linux capabilities 上限值
  static Future<void> _createCapLastCap(Directory procDir) async {
    final file = File('${procDir.path}/.sysctl_entry_cap_last_cap');
    if (await file.exists()) return;
    await file.writeAsString('40\n');
  }

  /// ─── /proc/.sysctl_inotify_max_user_watches ───────────────────
  ///
  /// inotify 最大监视数
  static Future<void> _createInotifyMax(Directory procDir) async {
    final file = File('${procDir.path}/.sysctl_inotify_max_user_watches');
    if (await file.exists()) return;
    await file.writeAsString('4096\n');
  }

  /// ─── 工具方法 ─────────────────────────────────────────────────

  /// 获取设备 CPU 核心数
  ///
  /// 优先从 Android 系统属性获取，如果获取失败返回 8（默认值）。
  static int _getCpuCount() {
    try {
      return Platform.numberOfProcessors;
    } catch (_) {
      // 回退：尝试通过 getprop 获取
      try {
        final result = Process.runSync('getprop', ['ro.product.cpu.abi']);
        if (result.exitCode == 0) {
          // arm64 设备通常有 8 核
          return 8;
        }
      } catch (_) {}
    }
    return 8;
  }

  /// 移除所有 fake sysdata 文件
  static Future<void> cleanup(String rootfsPath) async {
    final procDir = Directory('$rootfsPath/proc');
    if (!procDir.existsSync()) return;

    final files = [
      '.loadavg', '.stat', '.uptime', '.version', '.vmstat',
      '.sysctl_entry_cap_last_cap', '.sysctl_inotify_max_user_watches',
    ];

    for (final f in files) {
      final file = File('${procDir.path}/$f');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
