/// ====================================================================
/// Environment Doctor — 统一环境诊断与修复（Phase 8）
///
/// 集中处理部署中心的运行环境问题，避免 UI / DeployNotifier /
/// RuntimeManager / Codex CLI 各自实现一套环境判断：
///
///   PRoot Doctor（proot/loader/bash 就绪 + /tmp + TMPDIR）
///     → dpkg recovery（interrupted → dpkg --configure -a）
///     → apt recovery（apt-get update 可用）
///
/// 设计原则：
///   - 所有命令经 RuntimeProcessRunner + LinuxExecutionAdapter
///     （runtimeId='linux' → PRoot → Ubuntu rootfs），统一执行上下文
///   - 只做最小修复，禁止删除 dpkg lock / 重建 rootfs / 强制 ready
///   - 每一步独立返回结构化状态（passed/repaired/detail）
///   - 幂等：重复执行不会产生副作用
/// ====================================================================
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/logger/log_service.dart';
import 'installers/toolchain_context.dart';
import 'process/process_runner.dart';
import 'process/runner_models.dart';
import 'provider/linux_runtime_provider.dart';

/// 单项检查结果
class DoctorCheck {
  /// 检查项名称（proot / loader / rootfs / tmp / dpkg / apt）
  final String name;

  /// 是否通过
  final bool passed;

  /// 本次是否执行了修复动作
  final bool repaired;

  /// 人类可读详情（失败原因或修复结果）
  final String detail;

  const DoctorCheck({
    required this.name,
    required this.passed,
    this.repaired = false,
    required this.detail,
  });

  @override
  String toString() =>
      '${passed ? "✅" : "❌"} $name${repaired ? " (已修复)" : ""} — $detail';
}

/// 修复报告
class DoctorReport {
  final List<DoctorCheck> checks;

  const DoctorReport(this.checks);

  bool get allPassed => checks.every((c) => c.passed);

  /// 需要用户手动处理（无法自动修复）
  bool get hasUnresolved => checks.any((c) => !c.passed);

  /// 是否有任何修复动作被执行
  bool get anyRepaired => checks.any((c) => c.repaired);

  String get summary => checks.map((c) => c.toString()).join('\n');
}

/// 统一环境诊断/修复器
///
/// 使用方式：
///   final doctor = EnvironmentDoctor(runner: sharedRunner, linux: linuxProvider);
///   final report = await doctor.runFullRepair();
class EnvironmentDoctor {
  final RuntimeProcessRunner _runner;
  final LinuxRuntimeProvider? _linux;
  final LinuxRuntimePaths? _injectedPaths;

  EnvironmentDoctor({
    RuntimeProcessRunner? runner,
    LinuxRuntimeProvider? linux,
    LinuxRuntimePaths? injectedPaths,
  })  : _runner = runner ?? RuntimeProcessRunner(),
        _linux = linux,
        _injectedPaths = injectedPaths;

  /// 构建工具链执行上下文（与安装链路同通道）
  ToolchainContext _buildContext() {
    return ToolchainContext(
      runner: _runner,
      linux: _linux,
      injectedPaths: _injectedPaths,
    );
  }

  /// 解析 Linux Runtime 路径（注入优先，其次 Provider）
  Future<LinuxRuntimePaths> _resolvePaths() async {
    final injected = _injectedPaths;
    if (injected != null) return injected;
    final linux = _linux;
    if (linux == null) {
      throw StateError('EnvironmentDoctor: 无 LinuxRuntimeProvider');
    }
    return linux.resolvePaths();
  }

  // ─── 完整修复入口 ────────────────────────────────────────────

  /// 运行完整修复流程：
  ///   1. PRoot Doctor（proot/loader/rootfs bash 就绪）
  ///   2. TMP Doctor（rootfs /tmp 存在且可写；TMPDIR=/tmp 由环境保证）
  ///   3. dpkg recovery（interrupted → dpkg --configure -a）
  ///   4. apt recovery（apt-get update）
  Future<DoctorReport> runFullRepair() async {
    final checks = <DoctorCheck>[];

    // 1. PRoot Doctor
    final pr = await _doctorProot();
    checks.addAll(pr);

    // PRoot 未就绪 → 后续 rootfs 内操作无意义，直接返回
    if (!pr.every((c) => c.passed)) {
      return DoctorReport(checks);
    }

    // 2. TMP Doctor
    checks.add(await _doctorTmp());

    // 3. dpkg recovery
    checks.addAll(await _doctorDpkg());

    // 4. apt recovery
    checks.add(await _doctorApt());

    return DoctorReport(checks);
  }

  // ─── PRoot Doctor ────────────────────────────────────────────

  Future<List<DoctorCheck>> _doctorProot() async {
    final checks = <DoctorCheck>[];
    LinuxRuntimePaths? paths;
    try {
      paths = await _resolvePaths();
    } catch (e) {
      return [
        DoctorCheck(
          name: 'paths',
          passed: false,
          detail: '路径解析失败: $e',
        ),
      ];
    }

    // proot executable
    final prootExists = File(paths.prootExecutable).existsSync();
    checks.add(DoctorCheck(
      name: 'proot',
      passed: prootExists,
      detail: prootExists
          ? paths.prootExecutable
          : 'PRoot 可执行文件不存在: ${paths.prootExecutable}',
    ));

    // loader
    final loaderExists = File(paths.loaderPath).existsSync();
    checks.add(DoctorCheck(
      name: 'loader',
      passed: loaderExists,
      detail: loaderExists
          ? paths.loaderPath
          : 'PRoot loader 不存在: ${paths.loaderPath}',
    ));

    // rootfs bash
    final bash = _firstExisting([
      '${paths.rootfsDir}/usr/bin/bash',
      '${paths.rootfsDir}/bin/bash',
    ]);
    checks.add(DoctorCheck(
      name: 'rootfs',
      passed: bash != null,
      detail:
          bash != null ? bash : 'Ubuntu rootfs bash 不存在: ${paths.rootfsDir}',
    ));

    // proot 冒烟（--version）
    //
    // proot 是宿主可执行文件（nativeLibraryDir），不在 rootfs 内，
    // 因此不能走 ToolchainContext.versionOf（会把路径转成 rootfs 内路径）。
    // 必须直接经 RuntimeProcessRunner 宿主上下文执行，并携带 PROOT_LOADER。
    if (prootExists && loaderExists) {
      final smoke = await _runner.run(
        RuntimeProcessRequest(
          executable: paths.prootExecutable,
          arguments: const ['--version'],
          environment: {'PROOT_LOADER': paths.loaderPath},
          timeout: const Duration(seconds: 15),
          label: 'doctor:proot-version',
        ),
      );
      final ok =
          smoke.isSuccess && smoke.stdout.trim().isNotEmpty;
      checks.add(DoctorCheck(
        name: 'proot-smoke',
        passed: ok,
        detail: ok
            ? 'PRoot 可启动: ${smoke.stdout.trim()}'
            : 'PRoot --version 失败（loader/可执行文件损坏？）'
                '${smoke.error != null ? ' ${smoke.error}' : ''}',
      ));
    } else {
      checks.add(const DoctorCheck(
        name: 'proot-smoke',
        passed: false,
        detail: 'PRoot 未就绪，跳过冒烟',
      ));
    }

    return checks;
  }

  // ─── TMP Doctor ──────────────────────────────────────────────

  Future<DoctorCheck> _doctorTmp() async {
    final paths = await _resolvePaths();
    final tmpDir = Directory(p.join(paths.rootfsDir, 'tmp'));

    try {
      if (!await tmpDir.exists()) {
        await tmpDir.create(recursive: true);
        LogService.info('EnvironmentDoctor', '创建 rootfs /tmp');
        return const DoctorCheck(
          name: 'tmp',
          passed: true,
          repaired: true,
          detail: 'rootfs /tmp 不存在，已创建',
        );
      }

      // 可写性验证（不删除已有文件，写入临时探针后删除）
      final probe = File(p.join(tmpDir.path, '.codex_doctor_probe'));
      await probe.writeAsString('ok');
      await probe.delete();
      return const DoctorCheck(
        name: 'tmp',
        passed: true,
        detail: 'rootfs /tmp 存在且可写',
      );
    } catch (e) {
      return DoctorCheck(
        name: 'tmp',
        passed: false,
        detail: 'rootfs /tmp 不可用: $e',
      );
    }
  }

  // ─── dpkg recovery ───────────────────────────────────────────

  Future<List<DoctorCheck>> _doctorDpkg() async {
    final ctx = _buildContext();
    final checks = <DoctorCheck>[];

    // 1. 审计 dpkg 状态
    final audit = await ctx.runInRootfs(
      '/usr/bin/dpkg',
      arguments: const ['--audit'],
      timeout: const Duration(seconds: 60),
      label: 'doctor:dpkg-audit',
    );

    final auditText = '${audit.stderr}\n${audit.stdout}';
    final interrupted = _hasDpkgInterrupted(audit.exitCode, auditText);

    if (!interrupted) {
      checks.add(const DoctorCheck(
        name: 'dpkg',
        passed: true,
        detail: 'dpkg --audit 无异常',
      ));
      return checks;
    }

    // 2. 发现 interrupted → 修复
    LogService.warning(
      'EnvironmentDoctor',
      'dpkg interrupted 检测到，执行 dpkg --configure -a',
    );
    final fix = await ctx.runInRootfs(
      '/usr/bin/dpkg',
      arguments: const ['--configure', '-a'],
      timeout: const Duration(minutes: 5),
      label: 'doctor:dpkg-configure-a',
    );

    if (!fix.isSuccess) {
      checks.add(DoctorCheck(
        name: 'dpkg',
        passed: false,
        repaired: true,
        detail: 'dpkg --configure -a 失败: exit=${fix.exitCode} '
            '${fix.stderr.trim()}',
      ));
      return checks;
    }

    // 3. 复验
    final reAudit = await ctx.runInRootfs(
      '/usr/bin/dpkg',
      arguments: const ['--audit'],
      timeout: const Duration(seconds: 60),
      label: 'doctor:dpkg-reaudit',
    );
    final reText = '${reAudit.stderr}\n${reAudit.stdout}';
    final stillInterrupted = _hasDpkgInterrupted(reAudit.exitCode, reText);

    checks.add(DoctorCheck(
      name: 'dpkg',
      passed: !stillInterrupted,
      repaired: true,
      detail: stillInterrupted
          ? 'dpkg --configure -a 后仍存在 interrupted 状态:\n$reText'
          : 'dpkg interrupted 已修复（dpkg --configure -a 成功）',
    ));
    return checks;
  }

  /// 判定 dpkg 是否处于 interrupted 状态
  static bool _hasDpkgInterrupted(int exitCode, String text) {
    if (exitCode != 0) return true;
    final lower = text.toLowerCase();
    return lower.contains('interrupted') ||
        lower.contains('in a mess') ||
        lower.contains('requires manual intervention') ||
        lower.contains('serious problems');
  }

  // ─── apt recovery ────────────────────────────────────────────

  Future<DoctorCheck> _doctorApt() async {
    final ctx = _buildContext();
    // 复用工具链的幂等 update（含源 fallback），失败返回结构化原因
    ctx.aptUpdated = false; // doctor 强制独立验证一次
    try {
      await ctx.ensureAptUpdated();
      return const DoctorCheck(
        name: 'apt',
        passed: true,
        detail: 'apt-get update 成功',
      );
    } catch (e) {
      return DoctorCheck(
        name: 'apt',
        passed: false,
        detail: 'apt-get update 失败: $e',
      );
    }
  }

  // ─── 工具 ────────────────────────────────────────────────────

  static String? _firstExisting(List<String> candidates) {
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }
}
