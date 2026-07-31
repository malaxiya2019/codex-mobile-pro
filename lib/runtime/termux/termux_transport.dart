/// ====================================================================
/// Termux Transport — 传输层抽象
///
/// 抽象 Termux 与 App 之间的通信方式。
/// Provider 和 Adapter 只依赖此抽象，不直接依赖 MethodChannel。
///
/// 当前实现：MethodChannelTermuxTransport
/// 未来可替换：SocketTransport、ContentProviderTransport 等
///
/// 设计原则：
///   - 所有返回类型使用结构化结果，不抛出原始异常
///   - Transport 不关心「做什么」，只关心「怎么通信」
///   - 业务逻辑（重试、降级、缓存）由 Provider 层负责
/// ====================================================================
library;

/// ====================================================================
/// Termux 命令执行结果
/// ====================================================================
class TermuxExecResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final bool usedTermux;

  const TermuxExecResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.durationMs = 0,
    this.usedTermux = false,
  });

  bool get isSuccess => exitCode == 0;
}

/// ====================================================================
/// Termux 诊断结果
/// ====================================================================
class TermuxDiagnosticResult {
  final bool packageInstalled;
  final bool intentAvailable;
  final bool works;
  final String? version;
  final String lastError;
  final TermuxPkgManager pkgManager;

  const TermuxDiagnosticResult({
    this.packageInstalled = false,
    this.intentAvailable = false,
    this.works = false,
    this.version,
    this.lastError = '',
    this.pkgManager = TermuxPkgManager.unavailable,
  });

  bool get isAvailable => packageInstalled && intentAvailable && works;
}

/// ====================================================================
/// Termux 包管理器状态
/// ====================================================================
enum TermuxPkgManager {
  pkg,
  apt,
  dpkg,
  unavailable,
}

/// ====================================================================
/// Termux 环境信息
/// ====================================================================
class TermuxEnvResult {
  final String? prefixPath;
  final String? homePath;
  final String? shellPath;
  final String? architecture;
  final TermuxPkgManager pkgManager;
  final String? pkgManagerPath;

  const TermuxEnvResult({
    this.prefixPath,
    this.homePath,
    this.shellPath,
    this.architecture,
    this.pkgManager = TermuxPkgManager.unavailable,
    this.pkgManagerPath,
  });

  bool get isAvailable => prefixPath != null;
}

/// ====================================================================
/// Termux 包安装结果
/// ====================================================================
class TermuxInstallResult {
  final bool success;
  final String? errorMessage;
  final int durationMs;
  final String? output;

  const TermuxInstallResult({
    this.success = false,
    this.errorMessage,
    this.durationMs = 0,
    this.output,
  });
}

/// ====================================================================
/// Termux Transport 接口
///
/// 职责：
///   1. 检测 Termux 是否可用（diagnose）
///   2. 在 Termux 中执行命令（execute）
///   3. 获取环境变量（getEnvironment）
///   4. 查找可执行文件（which）
///   5. 包管理（installPackage / updatePackageList）
///
/// 不负责：
///   - 业务逻辑（重试、降级、缓存）
///   - 结果解析（版本号提取、路径拼接）
///   - Provider 生命周期管理
/// ====================================================================
abstract class TermuxTransport {
  /// 检测 Termux 状态
  Future<TermuxDiagnosticResult> diagnose();

  /// 在 Termux 中执行单条命令
  Future<TermuxExecResult> execute(String command);

  /// 获取 Termux 环境变量
  Future<TermuxEnvResult> getEnvironment();

  /// 查找可执行文件路径
  Future<String?> which(String binaryName);

  /// 安装包
  Future<TermuxInstallResult> installPackage(
    String packageName, {
    int timeoutMs = 120000,
  });

  /// 更新包列表
  Future<TermuxInstallResult> updatePackageList({int timeoutMs = 60000});
}
