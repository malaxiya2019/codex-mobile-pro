/// ====================================================================
/// LinuxRuntimeProvider
///
/// App 内置 Linux Runtime（PRoot + Ubuntu ARM64 rootfs）。
///
/// 架构：
///   LinuxRuntimeProvider
///     ↓
///   LinuxRuntimeInstaller（rootfs + proot bootstrap）
///     ↓
///   PRoot
///     ↓
///   Ubuntu 24.04 ARM64 rootfs（/bin/bash）
///
/// 职责：
///   1. detect() — 检测 PRoot + rootfs 是否就绪
///   2. getEnvironment() — 统一 Linux 环境（HOME/PATH/SHELL/TMPDIR/...）
///   3. isAvailable() / healthCheck()
///   4. capabilities — 只报告真实存在的能力
///   5. resolveExecutable() — 在 rootfs 内解析可执行文件
///   6. buildProcessSpec() — 结构化 PRoot 执行参数（禁止外部拼接）
///
/// 约束：
///   - 不依赖 Termux（APK → bundled PRoot → rootfs）
///   - 不使用 /system/bin/sh 作为 Linux shell
///   - 所有路径来自 App 私有目录（RuntimeEnvironment）
///   - PRoot 参数只在本 Provider 生成，禁止在调用点重复拼接
/// ====================================================================
library;

import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/logger/log_service.dart';
import '../native/native_proot.dart';
import '../process/runner_models.dart';
import '../runtime_environment.dart';
import 'runtime_capability.dart';
import 'runtime_provider.dart';

/// Linux Runtime 关键路径（可注入，便于测试）
class LinuxRuntimePaths {
  /// PRoot 可执行文件绝对路径
  final String prootExecutable;

  /// Ubuntu rootfs 根目录
  final String rootfsDir;

  /// proot loader 路径（libexec/proot/loader）
  final String loaderPath;

  /// rootfs 内 HOME（/root）
  final String homeDir;

  /// rootfs 内 TMPDIR（/tmp）
  final String tmpDir;

  /// 路径是否来自 Android nativeLibraryDir（jniLibs 解压区）。
  ///
  /// native 路径在 [NativeProot.ensureInstalled] 中已通过完整最小
  /// 自动检测（存在 / 可启动 / `--version` 成功 / loader 存在），
  /// detect() 无需重复冒烟；fallback（rootfs 内 proot）为 false。
  final bool fromNativeLibrary;

  const LinuxRuntimePaths({
    required this.prootExecutable,
    required this.rootfsDir,
    required this.loaderPath,
    this.homeDir = '/root',
    this.tmpDir = '/tmp',
    this.fromNativeLibrary = false,
  });

  /// 从 RuntimeEnvironment 派生默认路径
  factory LinuxRuntimePaths.fromEnvironment(RuntimeEnvironment env) {
    return LinuxRuntimePaths(
      prootExecutable: path.join(env.ubuntuBinDir, 'proot'),
      rootfsDir: env.ubuntuRootfsDir,
      loaderPath: env.ubuntuLoaderPath,
    );
  }
}

/// ====================================================================
/// LinuxProcessSpec — 结构化 PRoot 执行参数
///
/// 禁止把 `proot -r <rootfs> /bin/bash` 拼成单个 shellPath 字符串。
/// 所有 PRoot 参数由此处统一生成。
/// ====================================================================
class LinuxProcessSpec {
  /// PRoot 可执行文件绝对路径
  final String executable;

  /// PRoot 参数（-r rootfs -w cwd /bin/bash ...）
  final List<String> arguments;

  /// Linux 环境变量
  final Map<String, String> environment;

  /// 工作目录（rootfs 内路径）
  final String? workingDirectory;

  /// 超时
  final Duration? timeout;

  /// 自定义标签
  final String? label;

  const LinuxProcessSpec({
    required this.executable,
    required this.arguments,
    required this.environment,
    this.workingDirectory,
    this.timeout,
    this.label,
  });

  /// 转换为 RuntimeProcessRunner 请求（runtimeId=linux）
  RuntimeProcessRequest toProcessRequest() {
    return RuntimeProcessRequest(
      executable: executable,
      arguments: arguments,
      environment: environment,
      workingDirectory: workingDirectory,
      timeout: timeout,
      runtimeId: 'linux',
      label: label,
    );
  }

  @override
  String toString() =>
      'LinuxProcessSpec($executable ${arguments.join(" ")})';
}

/// Linux Runtime Provider
class LinuxRuntimeProvider implements IRuntimeProvider {
  final LinuxRuntimePaths? _paths;
  ProviderStatus _status = ProviderStatus.unavailable;
  List<RuntimeCapability> _cachedCapabilities = const [];

  /// rootfs 内 PATH（Ubuntu 标准 PATH，不含 Android 系统目录）
  static const String linuxPath =
      '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';

  /// 声明的可执行能力（通过 resolveExecutable 真实检测后报告）
  static const _declaredCapabilities = <CapabilityType>[
    CapabilityType.bash,
    CapabilityType.node,
    CapabilityType.npm,
    CapabilityType.python,
    CapabilityType.git,
    CapabilityType.codexCli,
    CapabilityType.mimo2codex,
    CapabilityType.tar,
    CapabilityType.xz,
  ];

  LinuxRuntimeProvider({LinuxRuntimePaths? paths}) : _paths = paths;

  LinuxRuntimePaths? _cachedPaths;

  // ─── 路径解析 ────────────────────────────────────────────────

  /// 获取 Linux Runtime 路径（懒加载 RuntimeEnvironment）
  ///
  /// 公开给 LinuxExecutionAdapter / RuntimeManager 使用。
  /// path_provider 不可用时（如测试环境）回退到系统临时目录，
  /// 保证 detect/healthCheck 不因环境问题崩溃。
  Future<LinuxRuntimePaths> resolvePaths() async {
    if (_paths != null) return _paths;
    if (_cachedPaths != null) return _cachedPaths!;

    // 先解析 rootfs（native 与 fallback 共用同一 rootfs 来源）
    String rootfsDir;
    try {
      final env = await RuntimeEnvironment.getInstance();
      rootfsDir = env.ubuntuRootfsDir;
    } catch (e) {
      LogService.warning('LinuxProvider', 'path_provider 不可用，回退临时目录: $e');
      rootfsDir = '${Directory.systemTemp.path}/runtime/ubuntu/rootfs';
    }

    // 1. 优先 nativeLibraryDir（jniLibs 交付的自包含 proot + loader，
    //    已通过 --version 冒烟；不依赖 Termux 动态库）。
    //    proot = nativeLibraryDir/proot（libproot.so）
    //    loader = nativeLibraryDir/loader（libloader.so）
    //    rootfs = app_flutter/runtime/ubuntu/rootfs（保持不变）
    try {
      final native = await NativeProot.ensureInstalled();
      if (native != null) {
        _cachedPaths = LinuxRuntimePaths(
          prootExecutable: native.prootExecutable,
          rootfsDir: rootfsDir,
          loaderPath: native.loaderPath,
          fromNativeLibrary: true,
        );
        LogService.info(
          'LinuxProvider',
          '使用 nativeLibraryDir proot: ${native.prootExecutable}',
        );
        return _cachedPaths!;
      }
    } catch (e) {
      LogService.warning(
        'LinuxProvider',
        'nativeLibraryDir proot 不可用，回退 rootfs 内 proot: $e',
      );
    }

    // 2. fallback：rootfs 内 proot（旧安装流程产物）
    _cachedPaths = LinuxRuntimePaths(
      prootExecutable: path.join(
        Directory(rootfsDir).parent.path,
        'bin',
        'proot',
      ),
      rootfsDir: rootfsDir,
      loaderPath: path.join(
        Directory(rootfsDir).parent.path,
        'libexec',
        'proot',
        'loader',
      ),
    );
    return _cachedPaths!;
  }

  // ─── IRuntimeProvider ────────────────────────────────────────

  @override
  String get id => 'linux';

  @override
  String get name => 'Linux Runtime';

  @override
  ProviderType get type => ProviderType.linux;

  @override
  ProviderStatus get status => _status;

  @override
  Future<ProviderInfo> detect() async {
    final start = DateTime.now();

    try {
      final paths = await resolvePaths();

      // 1. PRoot 是否就绪
      final prootReady = File(paths.prootExecutable).existsSync();
      // 2. rootfs bash 是否就绪
      final rootfsBash = File(
        path.join(paths.rootfsDir, 'usr', 'bin', 'bash'),
      ).existsSync() ||
          File(path.join(paths.rootfsDir, 'bin', 'bash')).existsSync();
      // 3. loader 是否就绪
      final loaderReady = File(paths.loaderPath).existsSync();

      final available = prootReady && rootfsBash;

      if (available) {
        _status = ProviderStatus.available;
      } else if (rootfsBash || prootReady) {
        // 部分就绪 → degraded（等待 bootstrap 完成）
        _status = ProviderStatus.degraded;
      } else {
        _status = ProviderStatus.unavailable;
      }

      // 4. 构建 Capability 列表（真实检测可执行文件）
      _cachedCapabilities = await _buildCapabilities(paths, available);

      // 5. 健康检查
      final health = ProviderHealth(
        healthy: available,
        version: _readOsVersion(paths),
        latencyMs: DateTime.now().difference(start).inMilliseconds,
        detail: _statusDescription(paths, available),
        checks: [
          DiagnosticCheck(
            name: 'PRoot',
            passed: prootReady,
            detail: prootReady
                ? paths.prootExecutable +
                    (paths.fromNativeLibrary ? ' (nativeLibraryDir)' : '')
                : '未安装',
          ),
          DiagnosticCheck(
            name: 'Ubuntu rootfs',
            passed: rootfsBash,
            detail: rootfsBash ? paths.rootfsDir : '未安装',
          ),
          DiagnosticCheck(
            name: 'proot loader',
            passed: loaderReady,
            detail: loaderReady ? paths.loaderPath : '未安装',
          ),
        ],
      );

      return ProviderInfo(
        type: type,
        status: _status,
        version: _readOsVersion(paths),
        description: _statusDescription(paths, available),
        capabilities: _cachedCapabilities,
        health: health,
        detectionDurationMs: DateTime.now().difference(start).inMilliseconds,
      );
    } catch (e) {
      LogService.error('LinuxProvider', '检测失败: $e');
      _status = ProviderStatus.error;

      return ProviderInfo(
        type: type,
        status: ProviderStatus.error,
        description: '检测异常: $e',
        detectionDurationMs: DateTime.now().difference(start).inMilliseconds,
      );
    }
  }

  /// PRoot fake-root + 绑定挂载参数
  ///
  /// apt/dpkg 依赖 /proc /dev /sys 基础设施，Android 宿主目录直接
  /// 映射进 rootfs；与 Termux 标准 proot 用法一致。
  ///
  /// Android /data 不支持 Ubuntu dpkg 所需的 hardlink 行为：
  ///   - `--link2symlink`：硬链接 → 符号链接，解决 dpkg backup/link()
  ///   - `--change-id=0:0`：guest 内 fake root（uid/gid 映射为 0）
  /// 真机等价环境已验证：加入这两个参数后 apt install 可完整成功。
  static List<String> prootBindArguments() => const [
    '--link2symlink',
    '--change-id=0:0',
    '-b', '/proc',
    '-b', '/dev',
    '-b', '/sys',
  ];

  /// rootfs 内 resolv.conf 当前是否可用（不指向 systemd-resolved stub）
  static bool resolvConfUsable(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    // 127.0.0.53 是 systemd-resolved stub，Android/PRoot 内不存在该服务
    if (trimmed.contains('127.0.0.53')) return false;
    if (!trimmed.contains('nameserver')) return false;
    return true;
  }

  /// 修复 rootfs 的 DNS 配置（幂等，best-effort）
  ///
  /// rootfs 解压后 /etc/resolv.conf 常保留构建机的
  /// `nameserver 127.0.0.53`（systemd-resolved stub），Android 上
  /// 无此服务 → apt-get update 无法解析域名而失败。
  /// 不可用则写入公共 DNS（IPv4，避免 Android IPv6 路由问题）。
  Future<bool> ensureResolvConf() async {
    try {
      final paths = await resolvePaths();
      final resolv = File('${paths.rootfsDir}/etc/resolv.conf');
      if (await resolv.exists()) {
        final content = await resolv.readAsString();
        if (resolvConfUsable(content)) return true;
      }
      await resolv.parent.create(recursive: true);
      await resolv.writeAsString(
        '# codex-mobile-pro: Android 环境公共 DNS（覆盖构建机 stub）\n'
        'nameserver 8.8.8.8\n'
        'nameserver 1.1.1.1\n',
      );
      LogService.info(
        'LinuxRuntime',
        '已修复 rootfs /etc/resolv.conf（写入公共 DNS）',
      );
      return true;
    } catch (e) {
      LogService.warning('LinuxRuntime', '修复 resolv.conf 失败(忽略): $e');
      return false;
    }
  }

  /// 配置 apt 强制 IPv4（幂等，best-effort）
  ///
  /// Android 网络 IPv6 常不可达；apt 若优先尝试 IPv6 会长时间卡住。
  Future<void> ensureAptIpv4Only() async {
    try {
      final paths = await resolvePaths();
      final conf = File(
        '${paths.rootfsDir}/etc/apt/apt.conf.d/99codex-force-ipv4',
      );
      if (await conf.exists()) return;
      await conf.parent.create(recursive: true);
      await conf.writeAsString('Acquire::ForceIPv4 "true";\n');
    } catch (e) {
      LogService.warning('LinuxRuntime', '配置 apt ForceIPv4 失败(忽略): $e');
    }
  }

  @override
  Future<Map<String, String>> getEnvironment({String? appHome}) async {
    final paths = await resolvePaths();
    return buildEnvironment(paths);
  }

  /// 构建 Linux Runtime 环境变量（唯一构建点）
  ///
  /// 所有模块（TerminalService / CapabilityResolver / 安装流程）必须使用
  /// 本方法获取 Linux 环境，禁止各自硬编码。
  Map<String, String> buildEnvironment(LinuxRuntimePaths paths) {
    return {
      'HOME': paths.homeDir,
      'SHELL': '/bin/bash',
      'PATH': linuxPath,
      'TERM': 'xterm-256color',
      'TMPDIR': paths.tmpDir,
      'LANG': 'en_US.UTF-8',
      'LC_ALL': 'en_US.UTF-8',
      'USER': 'root',
      'LOGNAME': 'root',
      'DEBIAN_FRONTEND': 'noninteractive',
      'PROOT_LOADER': paths.loaderPath,
      'PROOT_ROOTFS': paths.rootfsDir,
    };
  }

  @override
  Future<bool> isAvailable() async {
    final info = await detect();
    return info.status == ProviderStatus.available;
  }

  @override
  Future<ProviderHealth> healthCheck() async {
    final start = DateTime.now();
    final paths = await resolvePaths();

    final prootReady = File(paths.prootExecutable).existsSync();
    final rootfsBash = File(
      path.join(paths.rootfsDir, 'usr', 'bin', 'bash'),
    ).existsSync() ||
        File(path.join(paths.rootfsDir, 'bin', 'bash')).existsSync();

    return ProviderHealth(
      healthy: prootReady && rootfsBash,
      version: _readOsVersion(paths),
      latencyMs: DateTime.now().difference(start).inMilliseconds,
      checks: [
        DiagnosticCheck(
          name: 'PRoot',
          passed: prootReady,
          detail: prootReady ? paths.prootExecutable : '未安装',
        ),
        DiagnosticCheck(
          name: 'Ubuntu rootfs',
          passed: rootfsBash,
          detail: rootfsBash ? paths.rootfsDir : '未安装',
        ),
      ],
    );
  }

  @override
  List<RuntimeCapability> get capabilities => _cachedCapabilities;

  // ─── 扩展方法 ────────────────────────────────────────────────

  /// 在 rootfs 内解析可执行文件绝对路径
  ///
  /// 按 Ubuntu 标准目录搜索：/usr/local/bin /usr/bin /bin /usr/local/sbin /usr/sbin /sbin
  /// 未找到返回 null（不假设工具存在）。
  Future<String?> resolveExecutable(String name) async {
    final paths = await resolvePaths();
    final candidates = <String>[
      path.join(paths.rootfsDir, 'usr', 'local', 'bin', name),
      path.join(paths.rootfsDir, 'usr', 'bin', name),
      path.join(paths.rootfsDir, 'bin', name),
      path.join(paths.rootfsDir, 'usr', 'local', 'sbin', name),
      path.join(paths.rootfsDir, 'usr', 'sbin', name),
      path.join(paths.rootfsDir, 'sbin', name),
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) return candidate;
    }
    return null;
  }

  /// 构建交互式 shell 执行规格
  ///
  /// 返回：proot -r rootfs -w cwd /bin/bash -l
  Future<LinuxProcessSpec> buildShellSpec({
    String? workingDirectory,
    bool login = true,
    Duration? timeout,
  }) async {
    final paths = await resolvePaths();
    return _buildProotSpec(
      paths,
      innerCommand: login ? ['/bin/bash', '-l'] : ['/bin/bash'],
      workingDirectory: workingDirectory,
      timeout: timeout,
      label: 'linux-shell',
    );
  }

  /// 构建单条命令执行规格
  ///
  /// 返回：`proot -r rootfs -w cwd /bin/bash -lc '<command>'`
  Future<LinuxProcessSpec> buildCommandSpec(
    List<String> command, {
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final paths = await resolvePaths();
    return _buildProotSpec(
      paths,
      innerCommand: ['/bin/bash', '-lc', command.join(' ')],
      workingDirectory: workingDirectory,
      timeout: timeout,
      label: 'linux-command',
    );
  }

  /// 统一生成 PRoot 参数（禁止在调用点重复拼接）
  LinuxProcessSpec _buildProotSpec(
    LinuxRuntimePaths paths, {
    required List<String> innerCommand,
    String? workingDirectory,
    Duration? timeout,
    required String label,
  }) {
    final arguments = <String>[
      '-r',
      paths.rootfsDir,
      ...prootBindArguments(),
      if (workingDirectory != null) ...[
        '-w',
        workingDirectory,
      ],
      ...innerCommand,
    ];

    return LinuxProcessSpec(
      executable: paths.prootExecutable,
      arguments: arguments,
      environment: buildEnvironment(paths),
      workingDirectory: workingDirectory,
      timeout: timeout,
      label: label,
    );
  }

  // ─── 内部 ────────────────────────────────────────────────────

  /// 构建 Capability 列表（只报告真实存在的工具）
  Future<List<RuntimeCapability>> _buildCapabilities(
    LinuxRuntimePaths paths,
    bool runtimeReady,
  ) async {
    final result = <RuntimeCapability>[];

    // Linux Runtime 本身（Ubuntu rootfs 能力）
    result.add(RuntimeCapability(
      type: CapabilityType.ubuntu,
      provider: type,
      available: runtimeReady,
      status: runtimeReady
          ? CapabilityStatus.available
          : CapabilityStatus.unavailable,
      version: runtimeReady ? _readOsVersion(paths) : null,
      path: paths.rootfsDir,
      health: runtimeReady
          ? CapabilityHealth.healthy
          : CapabilityHealth.unavailable,
      reason: runtimeReady ? null : 'Linux Runtime 未初始化',
    ));

    // Runtime 未就绪时不再检测具体工具
    if (!runtimeReady) return result;

    // 真实检测各可执行文件
    for (final capType in _declaredCapabilities) {
      final binary = _binaryForCapability(capType);
      if (binary == null) continue;

      final executablePath = await resolveExecutable(binary);
      final available = executablePath != null;

      result.add(RuntimeCapability(
        type: capType,
        provider: type,
        available: available,
        status: available
            ? CapabilityStatus.available
            : CapabilityStatus.unavailable,
        executable: executablePath,
        health: available
            ? CapabilityHealth.healthy
            : CapabilityHealth.unavailable,
        reason: available ? null : 'rootfs 中未安装 $binary',
      ));
    }

    return result;
  }

  /// Capability 类型 → rootfs 内可执行文件名
  static String? _binaryForCapability(CapabilityType type) {
    switch (type) {
      case CapabilityType.bash: return 'bash';
      case CapabilityType.node: return 'node';
      case CapabilityType.npm: return 'npm';
      case CapabilityType.python: return 'python3';
      case CapabilityType.git: return 'git';
      case CapabilityType.codexCli: return 'codex';
      case CapabilityType.mimo2codex: return 'mimo2codex';
      case CapabilityType.tar: return 'tar';
      case CapabilityType.xz: return 'xz';
      default: return null;
    }
  }

  /// 读取 rootfs /etc/os-release 的版本号
  String? _readOsVersion(LinuxRuntimePaths paths) {
    try {
      final osRelease = File(
        path.join(paths.rootfsDir, 'etc', 'os-release'),
      );
      if (!osRelease.existsSync()) return null;
      final content = osRelease.readAsStringSync();
      final match = RegExp(r'VERSION_ID="([^"]+)"').firstMatch(content);
      if (match != null) return 'Ubuntu ${match.group(1)}';
      final nameMatch = RegExp(r'PRETTY_NAME="([^"]+)"').firstMatch(content);
      if (nameMatch != null) return nameMatch.group(1);
    } catch (_) {}
    return null;
  }

  String _statusDescription(LinuxRuntimePaths paths, bool available) {
    if (available) {
      final parts = <String>['Linux Runtime'];
      final version = _readOsVersion(paths);
      if (version != null) parts.add(version);
      parts.add(paths.rootfsDir);
      return parts.join(' · ');
    }
    return 'Linux Runtime 未初始化';
  }
}
