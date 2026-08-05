/// ====================================================================
/// Environment Doctor — 统一环境诊断与修复（Phase 8）
///
/// 集中处理部署中心的运行环境问题，避免 UI / DeployNotifier /
/// RuntimeManager / Codex CLI 各自实现一套环境判断：
///
///   PRoot Doctor（proot/loader/bash 就绪）
///     → TMP Doctor（rootfs /tmp + TMPDIR/TMP/TEMP 环境变量）
///     → dpkg recovery（interrupted → dpkg --configure -a）
///     → apt recovery（apt-get update）
///     → Toolchain Doctor（node/npm/git/python3 验证 + npm 补装）
///
/// 设计原则：
///   - 所有命令经 RuntimeProcessRunner + LinuxExecutionAdapter
///     （runtimeId='linux' → PRoot → Ubuntu rootfs），统一执行上下文
///   - 整轮共享同一个 ToolchainContext，dpkgHealthy / aptUpdated
///     幂等标记在 dpkg → apt → npm 补装之间传递，避免重复执行
///   - 顺序执行且安全中断：PRoot 未就绪 / dpkg 未恢复 → 立即返回，
///     不再继续 apt / 安装，防止错误扩大
///   - Capability 独立：node / npm / git / python3 各自独立检查，
///     npm 失败不得把 Node.js 判为未安装
///   - 只做最小修复，禁止删除 dpkg lock / 重建 rootfs / 强制 ready
///   - 每一步独立返回结构化状态（passed/repaired/detail）
///   - 幂等：重复执行不会产生副作用
/// ====================================================================
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/logger/log_service.dart';
import 'installers/apt_source_manager.dart';
import 'installers/apt_toolchain_installers.dart';
import 'installers/npm_toolchain_installers.dart';
import 'installers/toolchain_context.dart';
import 'process/process_runner.dart';
import 'process/runner_models.dart';
import 'provider/linux_runtime_provider.dart';

/// 单项检查结果
class DoctorCheck {
  /// 检查项名称（proot / loader / rootfs / tmp / tmp-env / dpkg / apt /
  /// node / npm / git / python3）
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

  /// 可注入的 apt 源测速探针（透传给 ToolchainContext；测试注入
  /// 「全部不可达」避免真实 HTTP；生产 null → 默认真实测速）
  final AptSourceProbe? _aptSourceProbe;

  EnvironmentDoctor({
    RuntimeProcessRunner? runner,
    LinuxRuntimeProvider? linux,
    LinuxRuntimePaths? injectedPaths,
    AptSourceProbe? aptSourceProbe,
  })  : _runner = runner ?? RuntimeProcessRunner(),
        _linux = linux,
        _injectedPaths = injectedPaths,
        _aptSourceProbe = aptSourceProbe;

  /// 构建工具链执行上下文（与安装链路同通道）
  ToolchainContext _buildContext() {
    return ToolchainContext(
      runner: _runner,
      linux: _linux,
      injectedPaths: _injectedPaths,
      aptSourceProbe: _aptSourceProbe,
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

  /// 运行完整修复流程（幂等、顺序执行、安全中断）：
  ///   1. PRoot Doctor（proot/loader/rootfs bash 就绪 + proot 冒烟）
  ///   2. TMP Doctor（rootfs /tmp 存在可写；TMPDIR/TMP/TEMP=/tmp）
  ///   3. dpkg recovery（interrupted → dpkg --configure -a）
  ///      —— 失败立即返回，禁止继续 apt/install 扩大错误
  ///   4. apt recovery（apt-get update，含源 fallback）
  ///   5. Toolchain Doctor（node/npm/git/python3 独立验证；
  ///      node 已装但 npm 缺失 → 仅补装 npm，不重装 nodejs）
  ///
  /// 整轮共享同一个 ToolchainContext：
  ///   - dpkg 恢复成功 → dpkgHealthy=true，后续 npm 补装不再重复 audit
  ///   - apt update 成功 → aptUpdated=true，后续 npm 补装不再重复 update
  Future<DoctorReport> runFullRepair() async {
    final checks = <DoctorCheck>[];
    final ctx = _buildContext();

    // 0. 路径解析
    LinuxRuntimePaths paths;
    try {
      paths = await _resolvePaths();
    } catch (e) {
      return DoctorReport([
        DoctorCheck(
          name: 'paths',
          passed: false,
          detail: '路径解析失败: $e',
        ),
      ]);
    }

    // 1. PRoot Doctor（失败 → 后续 rootfs 内操作无意义，安全中断）
    final pr = await _doctorProot(paths);
    checks.addAll(pr);
    if (!pr.every((c) => c.passed)) {
      return DoctorReport(checks);
    }

    // 2. TMP Doctor（rootfs /tmp + TMPDIR/TMP/TEMP 环境变量）
    checks.addAll(await _doctorTmp(paths));

    // 3. dpkg recovery（失败 → 安全中断，防止错误扩大）
    final dpkgChecks = await _doctorDpkg(ctx);
    checks.addAll(dpkgChecks);
    if (dpkgChecks.any((c) => !c.passed)) {
      LogService.warning(
        'EnvironmentDoctor',
        'dpkg 未恢复，安全中断后续 apt/install 流程',
      );
      return DoctorReport(checks);
    }

    // 4. apt recovery（含源 fallback）
    final apt = await _doctorApt(ctx);
    checks.add(apt);

    // 5. Toolchain Doctor：只读验证 node/npm/git/python3；
    //    apt 不可用时不补装 npm（只报告缺失），不扩大错误
    checks.addAll(await _doctorToolchain(ctx, aptReady: apt.passed));

    return DoctorReport(checks);
  }

  // ─── PRoot Doctor ────────────────────────────────────────────

  Future<List<DoctorCheck>> _doctorProot(LinuxRuntimePaths paths) async {
    final checks = <DoctorCheck>[];

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
      final ok = smoke.isSuccess && smoke.stdout.trim().isNotEmpty;
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

  /// rootfs /tmp 存在且可写 + guest 内 TMPDIR/TMP/TEMP 指向 Ubuntu /tmp。
  Future<List<DoctorCheck>> _doctorTmp(LinuxRuntimePaths paths) async {
    final checks = <DoctorCheck>[];

    // 1. rootfs /tmp 存在且可写
    final tmpDir = Directory(p.join(paths.rootfsDir, 'tmp'));
    try {
      if (!await tmpDir.exists()) {
        await tmpDir.create(recursive: true);
        LogService.info('EnvironmentDoctor', '创建 rootfs /tmp');
        checks.add(const DoctorCheck(
          name: 'tmp',
          passed: true,
          repaired: true,
          detail: 'rootfs /tmp 不存在，已创建',
        ));
      } else {
        // 可写性验证（不删除已有文件，写入临时探针后删除）
        final probe = File(p.join(tmpDir.path, '.codex_doctor_probe'));
        await probe.writeAsString('ok');
        await probe.delete();
        checks.add(const DoctorCheck(
          name: 'tmp',
          passed: true,
          detail: 'rootfs /tmp 存在且可写',
        ));
      }
    } catch (e) {
      checks.add(DoctorCheck(
        name: 'tmp',
        passed: false,
        detail: 'rootfs /tmp 不可用: $e',
      ));
      return checks;
    }

    // 2. TMPDIR/TMP/TEMP 环境变量（guest 内统一指向 Ubuntu /tmp）
    //
    // 与 linux_execution 注入的 PROOT_TMP_DIR（宿主侧临时目录）解耦：
    // PROOT_TMP_DIR 只影响 PRoot 进程自身，guest 内 apt/dpkg/npm 使用
    // 的是 TMPDIR/TMP/TEMP。三者必须一致且指向 rootfs 内 /tmp，
    // 否则出现「can't canonicalize .../usr/tmp/ No such file」类警告。
    final env = _guestEnv(paths);
    final guestTmp = env['TMPDIR'] ?? paths.tmpDir;
    final tmpVars = <String, String?>{
      'TMPDIR': env['TMPDIR'],
      'TMP': env['TMP'],
      'TEMP': env['TEMP'],
    };
    final missing = tmpVars.entries
        .where((e) => e.value == null || e.value!.isEmpty)
        .map((e) => e.key)
        .toList();
    if (missing.isNotEmpty) {
      checks.add(DoctorCheck(
        name: 'tmp-env',
        passed: false,
        detail: 'TMPDIR/TMP/TEMP 环境变量缺失: ${missing.join(', ')}',
      ));
    } else {
      final consistent = tmpVars.values.every((v) => v == guestTmp);
      checks.add(DoctorCheck(
        name: 'tmp-env',
        passed: consistent,
        detail: consistent
            ? 'TMPDIR/TMP/TEMP=$guestTmp（Ubuntu 内部 /tmp）'
            : 'TMPDIR/TMP/TEMP 不一致: TMPDIR=$guestTmp, '
                'TMP=${tmpVars['TMP']}, TEMP=${tmpVars['TEMP']}',
      ));
    }

    return checks;
  }

  /// 构造 guest（Ubuntu）环境变量。
  ///
  /// 优先使用 LinuxRuntimeProvider.buildEnvironment（唯一构建点），
  /// 测试注入场景下回退到默认值（TMPDIR/TMP/TEMP = paths.tmpDir）。
  Map<String, String> _guestEnv(LinuxRuntimePaths paths) {
    final linux = _linux;
    if (linux != null) {
      return linux.buildEnvironment(paths);
    }
    return {
      'HOME': paths.homeDir,
      'TMPDIR': paths.tmpDir,
      'TMP': paths.tmpDir,
      'TEMP': paths.tmpDir,
    };
  }

  // ─── dpkg recovery ───────────────────────────────────────────

  Future<List<DoctorCheck>> _doctorDpkg(ToolchainContext ctx) async {
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
      // dpkg 健康 → 共享 ctx 标记，后续 apt install 不再重复 audit
      ctx.dpkgHealthy = true;
      checks.add(const DoctorCheck(
        name: 'dpkg',
        passed: true,
        detail: 'dpkg --audit 无异常',
      ));
      return checks;
    }

    // 2. 发现 interrupted → 修复（禁止删除 dpkg lock 绕过）
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

    if (!stillInterrupted) {
      ctx.dpkgHealthy = true;
      checks.add(const DoctorCheck(
        name: 'dpkg',
        passed: true,
        repaired: true,
        detail: 'dpkg interrupted 已修复（dpkg --configure -a 成功）',
      ));
      return checks;
    }

    // 3. configure -a 无法恢复（缺 list/md5sums 控制文件等）→ 重装损坏包。
    //    本地验证：apt-get install --reinstall 可重建控制文件；apt-get -f
    //    install 无效（apt 不视为依赖 broken），故逐包显式 reinstall。
    final broken = _dpkgBrokenPackages(reText);
    if (broken.isEmpty) {
      checks.add(DoctorCheck(
        name: 'dpkg',
        passed: false,
        repaired: true,
        detail: 'dpkg --configure -a 后仍存在 interrupted 状态:\n$reText',
      ));
      return checks;
    }

    LogService.warning(
      'EnvironmentDoctor',
      'dpkg 控制文件缺失，尝试重装损坏包: $broken',
    );
    try {
      await ctx.ensureAptUpdated();
      final reinstall = await ctx.runInRootfs(
        '/usr/bin/apt-get',
        arguments: ['install', '--reinstall', '-y', ...broken],
        timeout: const Duration(minutes: 10),
        label: 'doctor:dpkg-reinstall',
      );
      if (!reinstall.isSuccess) {
        checks.add(DoctorCheck(
          name: 'dpkg',
          passed: false,
          repaired: true,
          detail: '重装损坏包失败: exit=${reinstall.exitCode} '
              '${reinstall.stderr.trim()}',
        ));
        return checks;
      }
    } catch (e) {
      checks.add(DoctorCheck(
        name: 'dpkg',
        passed: false,
        repaired: true,
        detail: '重装损坏包异常: $e',
      ));
      return checks;
    }

    // 4. 最终复验
    final finalAudit = await ctx.runInRootfs(
      '/usr/bin/dpkg',
      arguments: const ['--audit'],
      timeout: const Duration(seconds: 60),
      label: 'doctor:dpkg-final-audit',
    );
    final finalText = '${finalAudit.stderr}\n${finalAudit.stdout}';
    final clean = !_hasDpkgInterrupted(finalAudit.exitCode, finalText);
    if (clean) {
      ctx.dpkgHealthy = true;
    }
    checks.add(DoctorCheck(
      name: 'dpkg',
      passed: clean,
      repaired: true,
      detail: clean
          ? 'dpkg 已修复：重装损坏包 $broken 后 audit 干净'
          : 'dpkg 重装后仍异常:\n$finalText',
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
        lower.contains('serious problems') ||
        lower.contains('missing the list control file') ||
        lower.contains('missing the md5sums control file') ||
        lower.contains('need to be reinstalled') ||
        lower.contains('must be reinstalled');
  }

  /// 解析需要重装的损坏包名列表（missing list/md5sums control file 等）。
  ///
  /// 支持两种输出格式：
  ///   - dpkg --audit: "dpkg-dev             Debian package development tools"
  ///   - apt 报错:     "dpkg-dev (no description available)"
  /// 触发行（含 reinstalled）之后、下一个空行之前的包名行。
  static List<String> _dpkgBrokenPackages(String text) {
    final result = <String>[];
    var inSection = false;
    for (final line in text.split('\n')) {
      if (line.toLowerCase().contains('reinstalled')) {
        inSection = true;
        continue;
      }
      if (!inSection) continue;
      if (line.trim().isEmpty) {
        inSection = false;
        continue;
      }
      final trimmed = line.trim();
      // 跳过段落头（以冒号结尾的标题行）
      if (trimmed.endsWith(':')) continue;
      final name =
          trimmed.split(RegExp(r'\s+')).first.replaceAll(RegExp(r'[(),]'), '');
      if (RegExp(r'^[a-zA-Z0-9+._-]+$').hasMatch(name) &&
          !result.contains(name)) {
        result.add(name);
      }
    }
    return result;
  }

  // ─── apt recovery ────────────────────────────────────────────

  Future<DoctorCheck> _doctorApt(ToolchainContext ctx) async {
    // 复用工具链的幂等 update（含源 fallback），失败返回结构化原因。
    // 整轮共享 ctx：aptUpdated 标记在后续 npm 补装中生效。
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

  // ─── Toolchain Doctor（验证 + 补装）────────────────────────────

  /// 工具链独立 capability 验证 + 补装。
  ///
  /// 顺序：
  ///   1. 只读快照 node/npm/git/python3/codex
  ///   2. node 缺失/broken 且 apt 可用 → NodeJsInstaller 补装
  ///      （node+npm 全缺 → apt install nodejs npm；node 在但 npm
  ///        broken → 仅 apt install npm，不重装 nodejs）
  ///   3. npm 独立 capability：node 可用但 npm 缺失/broken → 补装 npm
  ///   4. git 缺失/broken 且 apt 可用 → GitInstaller 补装
  ///   5. python3 只读验证（rootfs 基础组件，不做自动安装）
  ///   6. codex 缺失/broken 且 npm 可用 → CodexCliInstaller 补装
  ///
  /// 每项独立生成 DoctorCheck：任一失败不影响其它工具的判定。
  /// [aptReady] = false 时跳过 apt/npm 补装，只做只读验证，
  /// 防止在 apt/dpkg 未恢复时扩大错误。
  Future<List<DoctorCheck>> _doctorToolchain(
    ToolchainContext ctx, {
    required bool aptReady,
  }) async {
    final checks = <DoctorCheck>[];

    // 1. 只读快照
    final nodeBefore = await ctx.versionOf('/usr/bin/node');
    final npmBefore = await ctx.versionOf('/usr/bin/npm');
    final gitBefore = await ctx.versionOf('/usr/bin/git');
    final pyBefore = await ctx.versionOf('/usr/bin/python3');
    final codexBefore = await ctx.versionOf('/usr/bin/codex');

    // 2. Node.js 独立 capability（缺失/broken → 补装 node+npm）
    var nodeVer = nodeBefore;
    if (nodeVer == null && aptReady) {
      LogService.info(
        'EnvironmentDoctor',
        'node 缺失/broken，apt 补装 nodejs+npm...',
      );
      final result = await NodeJsInstaller().install(ctx);
      nodeVer = result.success ? await ctx.versionOf('/usr/bin/node') : null;
      checks.add(DoctorCheck(
        name: 'node',
        passed: result.success && nodeVer != null,
        repaired: true,
        detail: result.success && nodeVer != null
            ? 'Node.js 补装成功: $nodeVer'
            : 'Node.js 补装失败: ${result.errorMessage}',
      ));
    } else {
      checks.add(DoctorCheck(
        name: 'node',
        passed: nodeVer != null,
        detail: nodeVer != null ? 'Node.js 可用: $nodeVer' : 'Node.js 不可用',
      ));
    }

    // 3. npm 独立 capability（node 可用但 npm 缺失/broken → 补装 npm）
    var npmVer = npmBefore;
    if (npmVer == null && nodeVer != null && aptReady) {
      LogService.info(
        'EnvironmentDoctor',
        'node 已安装、npm 缺失/broken，补装 npm...',
      );
      final result = await NodeJsInstaller().install(ctx);
      npmVer = result.success ? await ctx.versionOf('/usr/bin/npm') : null;
      checks.add(DoctorCheck(
        name: 'npm',
        passed: result.success && npmVer != null,
        repaired: true,
        detail: result.success && npmVer != null
            ? 'npm 补装成功（node 已安装，npm 缺失/broken）: $npmVer'
            : 'npm 补装失败: ${result.errorMessage}',
      ));
    } else {
      checks.add(DoctorCheck(
        name: 'npm',
        passed: npmVer != null,
        detail: npmVer != null
            ? 'npm 可用: $npmVer'
            : nodeVer == null
                ? 'node 未安装，跳过 npm 补装'
                : !aptReady
                    ? 'apt 不可用，跳过 npm 补装'
                    : 'npm 不可用',
      ));
    }

    // 4. Git 独立 capability（缺失/broken → 补装）
    var gitVer = gitBefore;
    if (gitVer == null && aptReady) {
      LogService.info('EnvironmentDoctor', 'git 缺失/broken，apt 补装 git...');
      final result = await GitInstaller().install(ctx);
      gitVer = result.success ? await ctx.versionOf('/usr/bin/git') : null;
      checks.add(DoctorCheck(
        name: 'git',
        passed: result.success && gitVer != null,
        repaired: true,
        detail: result.success && gitVer != null
            ? 'Git 补装成功: $gitVer'
            : 'Git 补装失败: ${result.errorMessage}',
      ));
    } else {
      checks.add(DoctorCheck(
        name: 'git',
        passed: gitVer != null,
        detail: gitVer != null ? 'Git 可用: $gitVer' : 'Git 不可用',
      ));
    }

    // 5. Python3 独立 capability（rootfs 基础组件，只读验证）
    checks.add(DoctorCheck(
      name: 'python3',
      passed: pyBefore != null,
      detail: pyBefore != null ? 'Python 3 可用: $pyBefore' : 'Python 3 不可用',
    ));

    // 6. Codex CLI（npm 可用且缺失/broken → 补装；失败不阻断其它结果）
    var codexVer = codexBefore;
    if (codexVer == null && npmVer != null) {
      LogService.info(
        'EnvironmentDoctor',
        'codex 缺失/broken，npm 补装 @openai/codex...',
      );
      final result = await CodexCliInstaller().install(ctx);
      codexVer = result.success ? await ctx.versionOf('/usr/bin/codex') : null;
      checks.add(DoctorCheck(
        name: 'codex',
        passed: result.success && codexVer != null,
        repaired: true,
        detail: result.success && codexVer != null
            ? 'Codex CLI 补装成功: $codexVer'
            : 'Codex CLI 补装失败: ${result.errorMessage}',
      ));
    } else {
      checks.add(DoctorCheck(
        name: 'codex',
        passed: codexVer != null,
        detail: codexVer != null ? 'Codex CLI 可用: $codexVer' : 'Codex CLI 不可用',
      ));
    }

    return checks;
  }

  // ─── 工具 ────────────────────────────────────────────────────

  static String? _firstExisting(List<String> candidates) {
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }
}
