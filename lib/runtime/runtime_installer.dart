import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/logger/log_service.dart';
import 'runtime_dependency.dart';
import 'runtime_environment.dart';

/// ====================================================================
/// Runtime 安装器
///
/// 负责在 App 私有目录下安装 Node.js / Git / Python / Codex CLI / mimo2codex。
///
/// 所有安装在 App 私有目录中进行，不修改系统目录。
/// ====================================================================

/// 安装进度回调
typedef InstallProgressCallback = void Function(
  RuntimeTool tool,
  InstallPhase phase,
  double progress,
  String message,
);

/// 安装阶段
enum InstallPhase {
  pending,
  downloading,
  extracting,
  configuring,
  verifying,
  completed,
  failed,
}

/// 安装结果
class InstallResult {
  final RuntimeTool tool;
  final bool success;
  final String? errorMessage;
  final String? version;
  final InstallPhase phase;

  const InstallResult({
    required this.tool,
    required this.success,
    this.errorMessage,
    this.version,
    this.phase = InstallPhase.completed,
  });
}

/// Runtime 安装器
class RuntimeInstaller {
  final RuntimeEnvironment _env;
  final InstallProgressCallback? _onProgress;

  RuntimeInstaller(this._env, [this._onProgress]);

  /// 安装单个工具
  Future<InstallResult> install(RuntimeTool tool) async {
    _report(tool, InstallPhase.pending, 0, '准备安装...');

    try {
      switch (tool) {
        case RuntimeTool.node:
          return await _installNode();
        case RuntimeTool.git:
          return await _installGit();
        case RuntimeTool.python:
          return await _installPython();
        case RuntimeTool.codexCli:
          return await _installCodexCli();
        case RuntimeTool.mimo2codex:
          return await _installMimo2codex();
        case RuntimeTool.deepseekKey:
          return await _configureDeepSeekKey();
        default:
          return InstallResult(
            tool: tool,
            success: false,
            errorMessage: '不支持自动安装',
            phase: InstallPhase.failed,
          );
      }
    } catch (e) {
      _report(tool, InstallPhase.failed, 0, '安装失败: $e');
      return InstallResult(
        tool: tool,
        success: false,
        errorMessage: e.toString(),
        phase: InstallPhase.failed,
      );
    }
  }

  /// 一键安装所有 Coding Runtime（按依赖顺序）
  Future<List<InstallResult>> installCodingRuntime() async {
    final order = RuntimeDependency.installOrder();
    final results = <InstallResult>[];

    for (final tool in order) {
      final dep = RuntimeDependency.forTool(tool);
      if (dep == null || dep.category == RuntimeCategory.basic) continue;
      if (dep.optional) continue;

      // 跳过已安装的
      if (_env.isToolInstalled(tool)) {
        results.add(InstallResult(
          tool: tool,
          success: true,
          version: '已安装',
        ));
        continue;
      }

      final result = await install(tool);
      results.add(result);
      if (!result.success) break; // 依赖失败则停止
    }

    return results;
  }

  /// ─── Node.js 安装 ──────────────────────────────────────────────

  Future<InstallResult> _installNode() async {
    _report(RuntimeTool.node, InstallPhase.downloading, 0.1, '下载 Node.js...');

    // 检测架构
    final arch = _getArch();
    final nodeVersion = '18.20.4'; // LTS
    final url =
        'https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-linux-$arch.tar.xz';
    final dest = '${_env.nodeDir}/node.tar.xz';

    await _downloadFile(url, dest, (progress) {
      _report(RuntimeTool.node, InstallPhase.downloading, progress * 0.5,
          '下载 Node.js ${(progress * 100).toInt()}%');
    });

    _report(RuntimeTool.node, InstallPhase.extracting, 0.5, '解压 Node.js...');
    await _extractTarXz(dest, _env.runtimeDir);

    _report(RuntimeTool.node, InstallPhase.configuring, 0.8, '配置 Node.js...');
    // 移动 node-v*/bin/node 到 node/bin/node
    await _moveNodeBinaries();

    // 验证
    _report(RuntimeTool.node, InstallPhase.verifying, 0.9, '验证 Node.js...');
    final version = await _getVersion('${_env.nodeBinDir}/node', ['--version']);

    if (version != null) {
      _report(RuntimeTool.node, InstallPhase.completed, 1.0, 'Node.js $version 安装完成');
      return InstallResult(
        tool: RuntimeTool.node,
        success: true,
        version: version,
      );
    } else {
      _report(RuntimeTool.node, InstallPhase.failed, 0, 'Node.js 验证失败');
      return InstallResult(
        tool: RuntimeTool.node,
        success: false,
        errorMessage: '验证失败：无法执行 node --version',
        phase: InstallPhase.failed,
      );
    }
  }

  /// ─── Git 安装 ──────────────────────────────────────────────────

  Future<InstallResult> _installGit() async {
    _report(RuntimeTool.git, InstallPhase.downloading, 0.1, '下载 Git...');

    final arch = _getArch();
    // 使用预编译的 Git for Android
    final url =
        'https://github.com/git-for-android/git-for-android/releases/latest/download/git-$arch.tar.gz';
    final dest = '${_env.gitDir}/git.tar.gz';

    await _downloadFile(url, dest, (progress) {
      _report(RuntimeTool.git, InstallPhase.downloading, progress * 0.5,
          '下载 Git ${(progress * 100).toInt()}%');
    });

    _report(RuntimeTool.git, InstallPhase.extracting, 0.5, '解压 Git...');
    await _extractTarGz(dest, _env.gitDir);

    _report(RuntimeTool.git, InstallPhase.verifying, 0.9, '验证 Git...');
    final version =
        await _getVersion('${_env.gitBinDir}/git', ['--version']);

    if (version != null) {
      _report(RuntimeTool.git, InstallPhase.completed, 1.0, 'Git $version 安装完成');
      return InstallResult(
        tool: RuntimeTool.git,
        success: true,
        version: version,
      );
    } else {
      _report(RuntimeTool.git, InstallPhase.failed, 0, 'Git 验证失败');
      return InstallResult(
        tool: RuntimeTool.git,
        success: false,
        errorMessage: '验证失败：无法执行 git --version',
        phase: InstallPhase.failed,
      );
    }
  }

  /// ─── Python 3 安装 ──────────────────────────────────────────────

  Future<InstallResult> _installPython() async {
    _report(RuntimeTool.python, InstallPhase.downloading, 0.1, '下载 Python 3...');

    final arch = _getArch();
    final url =
        'https://github.com/python-android/python-android/releases/latest/download/python3-$arch.tar.gz';
    final dest = '${_env.pythonDir}/python.tar.gz';

    await _downloadFile(url, dest, (progress) {
      _report(RuntimeTool.python, InstallPhase.downloading, progress * 0.5,
          '下载 Python 3 ${(progress * 100).toInt()}%');
    });

    _report(RuntimeTool.python, InstallPhase.extracting, 0.5, '解压 Python 3...');
    await _extractTarGz(dest, _env.pythonDir);

    _report(RuntimeTool.python, InstallPhase.verifying, 0.9, '验证 Python 3...');
    final version =
        await _getVersion('${_env.pythonBinDir}/python3', ['--version']);

    if (version != null) {
      _report(RuntimeTool.python, InstallPhase.completed, 1.0, 'Python 3 $version 安装完成');
      return InstallResult(
        tool: RuntimeTool.python,
        success: true,
        version: version,
      );
    } else {
      _report(RuntimeTool.python, InstallPhase.failed, 0, 'Python 3 验证失败');
      return InstallResult(
        tool: RuntimeTool.python,
        success: false,
        errorMessage: '验证失败：无法执行 python3 --version',
        phase: InstallPhase.failed,
      );
    }
  }

  /// ─── Codex CLI 安装 ─────────────────────────────────────────────

  Future<InstallResult> _installCodexCli() async {
    _report(RuntimeTool.codexCli, InstallPhase.downloading, 0.1, '安装 Codex CLI...');

    final npmBin = '${_env.nodeBinDir}/npm';
    final result = await _runProcess(npmBin, [
      'install',
      '-g',
      '@openai/codex',
      '--prefix',
      _env.npmGlobalDir,
    ], progress: (p) {
      _report(RuntimeTool.codexCli, InstallPhase.downloading, p * 0.8,
          '安装 Codex CLI...');
    });

    if (result.exitCode != 0) {
      _report(RuntimeTool.codexCli, InstallPhase.failed, 0,
          'Codex CLI 安装失败: ${result.stderr}');
      return InstallResult(
        tool: RuntimeTool.codexCli,
        success: false,
        errorMessage: result.stderr.toString().trim(),
        phase: InstallPhase.failed,
      );
    }

    _report(RuntimeTool.codexCli, InstallPhase.verifying, 0.9, '验证 Codex CLI...');
    final version =
        await _getVersion('${_env.npmGlobalBinDir}/codex', ['--version']);

    if (version != null) {
      _report(RuntimeTool.codexCli, InstallPhase.completed, 1.0,
          'Codex CLI $version 安装完成');
      return InstallResult(
        tool: RuntimeTool.codexCli,
        success: true,
        version: version,
      );
    } else {
      _report(RuntimeTool.codexCli, InstallPhase.failed, 0, 'Codex CLI 验证失败');
      return InstallResult(
        tool: RuntimeTool.codexCli,
        success: false,
        errorMessage: '验证失败',
        phase: InstallPhase.failed,
      );
    }
  }

  /// ─── mimo2codex 安装 ───────────────────────────────────────────

  Future<InstallResult> _installMimo2codex() async {
    _report(RuntimeTool.mimo2codex, InstallPhase.downloading, 0.1,
        '安装 mimo2codex...');

    final npmBin = '${_env.nodeBinDir}/npm';
    final result = await _runProcess(npmBin, [
      'install',
      '-g',
      'mimo2codex',
      '--prefix',
      _env.npmGlobalDir,
    ], progress: (p) {
      _report(RuntimeTool.mimo2codex, InstallPhase.downloading, p * 0.8,
          '安装 mimo2codex...');
    });

    if (result.exitCode != 0) {
      _report(RuntimeTool.mimo2codex, InstallPhase.failed, 0,
          'mimo2codex 安装失败: ${result.stderr}');
      return InstallResult(
        tool: RuntimeTool.mimo2codex,
        success: false,
        errorMessage: result.stderr.toString().trim(),
        phase: InstallPhase.failed,
      );
    }

    _report(RuntimeTool.mimo2codex, InstallPhase.verifying, 0.9,
        '验证 mimo2codex...');
    final version = await _getVersion('${_env.npmGlobalBinDir}/mimo2codex',
        ['--version']);

    if (version != null) {
      _report(RuntimeTool.mimo2codex, InstallPhase.completed, 1.0,
          'mimo2codex $version 安装完成');
      return InstallResult(
        tool: RuntimeTool.mimo2codex,
        success: true,
        version: version,
      );
    } else {
      _report(RuntimeTool.mimo2codex, InstallPhase.failed, 0,
          'mimo2codex 验证失败');
      return InstallResult(
        tool: RuntimeTool.mimo2codex,
        success: false,
        errorMessage: '验证失败',
        phase: InstallPhase.failed,
      );
    }
  }

  /// ─── DeepSeek API Key 配置 ────────────────────────────────────

  Future<InstallResult> _configureDeepSeekKey() async {
    // 这个方法只创建目录结构，实际 key 由用户在 UI 中输入
    final dir = Directory('${_env.runtimeDir}/.mimo2codex');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _report(RuntimeTool.deepseekKey, InstallPhase.completed, 1.0, '已准备配置目录');
    return InstallResult(
      tool: RuntimeTool.deepseekKey,
      success: true,
      version: '待配置',
    );
  }

  /// ─── 工具方法 ──────────────────────────────────────────────────

  void _report(RuntimeTool tool, InstallPhase phase, double progress,
      String message) {
    _onProgress?.call(tool, phase, progress, message);
    LogService.info('RuntimeInstaller', '[$tool] $message');
  }

  /// 获取设备架构
  String _getArch() {
    // Android arm64
    return 'arm64';
  }

  /// 下载文件（带进度回调）
  Future<void> _downloadFile(
    String url,
    String dest,
    void Function(double progress) onProgress,
  ) async {
    // 使用 curl 下载
    final result = await Process.run('curl', [
      '-L',
      '-o',
      dest,
      url,
    ], runInShell: true);

    if (result.exitCode != 0) {
      throw Exception('下载失败: ${result.stderr}');
    }

    onProgress(1.0);
  }

  /// 解压 tar.xz
  Future<void> _extractTarXz(String file, String destDir) async {
    final result = await Process.run('tar', [
      '-xf',
      file,
      '-C',
      destDir,
    ], runInShell: true);

    if (result.exitCode != 0) {
      // 如果 tar 不可用，尝试用 busybox
      final bbResult = await Process.run('busybox', [
        'tar',
        '-xf',
        file,
        '-C',
        destDir,
      ], runInShell: true);
      if (bbResult.exitCode != 0) {
        throw Exception('解压失败');
      }
    }

    // 清理压缩包
    await File(file).delete();
  }

  /// 解压 tar.gz
  Future<void> _extractTarGz(String file, String destDir) async {
    final result = await Process.run('tar', [
      '-xzf',
      file,
      '-C',
      destDir,
    ], runInShell: true);

    if (result.exitCode != 0) {
      throw Exception('解压失败: ${result.stderr}');
    }

    await File(file).delete();
  }

  /// 移动 Node.js 二进制到正确位置
  Future<void> _moveNodeBinaries() async {
    // 查找 node-v*/bin/node
    final runtimeDir = Directory(_env.runtimeDir);
    final entries = runtimeDir.listSync();
    for (final entry in entries) {
      if (entry is Directory && entry.path.contains('node-v')) {
        // 移动 bin/ 内容到 node/bin/
        final srcBin = Directory('${entry.path}/bin');
        if (srcBin.existsSync()) {
          for (final f in srcBin.listSync()) {
            if (f is File) {
              final destPath = '${_env.nodeBinDir}/${path.basename(f.path)}';
              await f.rename(destPath);
              // 添加执行权限
              await Process.run('chmod', ['+x', destPath], runInShell: true);
            }
          }
        }
        // 移动 lib/ 内容到 node/lib/
        final srcLib = Directory('${entry.path}/lib');
        if (srcLib.existsSync()) {
          final destLibDir = Directory('${_env.nodeDir}/lib');
          if (!destLibDir.existsSync()) {
            await destLibDir.create(recursive: true);
          }
          await Process.run('cp', ['-r', '${srcLib.path}/.', destLibDir.path],
              runInShell: true);
        }
        // 删除原始目录
        await entry.delete(recursive: true);
        break;
      }
    }
  }

  /// 获取工具版本
  Future<String?> _getVersion(String binPath, List<String> args) async {
    try {
      final result = await Process.run(binPath, args, runInShell: true);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 运行进程
  Future<ProcessResult> _runProcess(
    String executable,
    List<String> args, {
    void Function(double progress)? progress,
  }) async {
    return Process.run(executable, args,
        runInShell: true,
        environment: {
          'PATH': '${_env.nodeBinDir}:/system/bin:/system/xbin',
          'HOME': _env.runtimeDir,
        });
  }
}
