/// ====================================================================
/// FakeTermuxTransport — 测试用
///
/// 预设所有 TermuxTransport API 的返回值，不执行真实 IPC。
/// 用于 TermuxRuntimeProvider 和 TermuxExecutionAdapter 的单元测试。
/// ====================================================================
library;

import 'termux_transport.dart';

/// Fake Termux Transport
class FakeTermuxTransport implements TermuxTransport {
  TermuxDiagnosticResult _diagnoseResult = const TermuxDiagnosticResult();
  Map<String, TermuxExecResult> _execResults = {};
  TermuxEnvResult _envResult = const TermuxEnvResult();
  Map<String, String?> _whichResults = {};
  TermuxInstallResult _installResult = const TermuxInstallResult();
  TermuxInstallResult _updateResult = const TermuxInstallResult();

  /// 记录已执行的命令（用于断言）
  final List<String> executedCommands = [];

  // ─── 预设方法 ───────────────────────────────────────────────

  void setDiagnoseResult(TermuxDiagnosticResult result) {
    _diagnoseResult = result;
  }

  void setExecResult(String command, TermuxExecResult result) {
    _execResults[command] = result;
  }

  void setEnvResult(TermuxEnvResult result) {
    _envResult = result;
  }

  void setWhichResult(String binary, String? path) {
    _whichResults[binary] = path;
  }

  void setInstallResult(TermuxInstallResult result) {
    _installResult = result;
  }

  void setUpdateResult(TermuxInstallResult result) {
    _updateResult = result;
  }

  void reset() {
    _diagnoseResult = const TermuxDiagnosticResult();
    _execResults = {};
    _envResult = const TermuxEnvResult();
    _whichResults = {};
    _installResult = const TermuxInstallResult();
    _updateResult = const TermuxInstallResult();
    executedCommands.clear();
  }

  // ─── Transport 接口 ──────────────────────────────────────────

  @override
  Future<TermuxDiagnosticResult> diagnose() async => _diagnoseResult;

  @override
  Future<TermuxExecResult> execute(String command) async {
    executedCommands.add(command);
    return _execResults[command] ??
        TermuxExecResult(
          exitCode: 0,
          stdout: 'mock:$command',
          usedTermux: true,
        );
  }

  @override
  Future<TermuxEnvResult> getEnvironment() async => _envResult;

  @override
  Future<String?> which(String binaryName) async {
    // 已预设的值（含 null=未找到）直接返回；未预设才回退到默认 Termux 路径
    if (_whichResults.containsKey(binaryName)) {
      return _whichResults[binaryName];
    }
    return '/data/data/com.termux/files/usr/bin/$binaryName';
  }

  @override
  Future<TermuxInstallResult> installPackage(
    String packageName, {
    int timeoutMs = 120000,
  }) async => _installResult;

  @override
  Future<TermuxInstallResult> updatePackageList({int timeoutMs = 60000}) async =>
      _updateResult;
}
