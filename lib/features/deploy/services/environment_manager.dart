import 'dart:io';
import '../../../core/detector/detection_result.dart';
import '../../../runtime/runtime_detector.dart';
import '../../../core/logger/log_service.dart';

/// 环境详细信息
class EnvironmentDetail {
  final String tool;
  final String version;
  final String? path;
  final String? detail;
  final bool installed;

  const EnvironmentDetail({
    required this.tool,
    required this.version,
    this.path,
    this.detail,
    this.installed = true,
  });
}

/// Flutter 环境详情
class FlutterEnvironment {
  final String flutterVersion;
  final String dartVersion;
  final String? sdkPath;
  final List<String> channels;
  final String? engineVersion;

  const FlutterEnvironment({
    required this.flutterVersion,
    required this.dartVersion,
    this.sdkPath,
    this.channels = const [],
    this.engineVersion,
  });
}

/// Rust 环境详情
class RustEnvironment {
  final String rustcVersion;
  final String cargoVersion;
  final String? toolchain;
  final List<String> targets;

  const RustEnvironment({
    required this.rustcVersion,
    required this.cargoVersion,
    this.toolchain,
    this.targets = const [],
  });
}

/// Python 环境详情
class PythonEnvironment {
  final String pythonVersion;
  final String? pipVersion;
  final bool hasVenv;
  final List<String> packages;

  const PythonEnvironment({
    required this.pythonVersion,
    this.pipVersion,
    this.hasVenv = false,
    this.packages = const [],
  });
}

/// 安装结果
class InstallResult {
  final bool success;
  final String tool;
  final String? output;
  final String? errorMessage;

  const InstallResult({
    required this.success,
    required this.tool,
    this.output,
    this.errorMessage,
  });
}

/// 环境管理器
///
/// 统一管理环境检测、详细信息获取、一键安装/修复。
/// 模块化设计，预留 Docker/远程环境接口。
class EnvironmentManager {
  final RuntimeDetector _runtimeDetector;

  EnvironmentManager() : _runtimeDetector = RuntimeDetector();

  /// 运行所有检测
  Future<List<DetectionResult>> detectAll() async {
    final result = await _runtimeDetector.detectAll();
    return result.all;
  }

  /// 获取 Flutter 环境详情
  static Future<FlutterEnvironment?> getFlutterDetail() async {
    try {
      final result = await Process.run('flutter', [
        '--version',
      ], runInShell: true);
      if (result.exitCode != 0) return null;

      final output = result.stdout as String;
      final lines = output.split('\n');

      String flutterVer = '';
      String dartVer = '';
      String? sdkPath;
      String? engineVer;
      final channels = <String>[];

      for (final line in lines) {
        if (line.contains('Flutter')) {
          final parts = line.split('•');
          if (parts.length >= 2) {
            flutterVer = parts[0].replaceAll('Flutter', '').trim();
            if (parts.length >= 3) {
              // 提取 channel
              final channelPart = parts[2].trim();
              if (channelPart.isNotEmpty) channels.add(channelPart);
            }
          } else {
            flutterVer = line.replaceAll('Flutter', '').trim();
          }
        }
        if (line.contains('Dart')) {
          dartVer = line.replaceAll('Dart', '').replaceAll('•', '').trim();
        }
        if (line.contains('Engine')) {
          engineVer = line.split('•').last.trim();
        }
      }

      // 获取 SDK 路径
      final whichResult = await Process.run('which', [
        'flutter',
      ], runInShell: true);
      if (whichResult.exitCode == 0) {
        sdkPath = (whichResult.stdout as String).trim();
      }

      return FlutterEnvironment(
        flutterVersion: flutterVer,
        dartVersion: dartVer,
        sdkPath: sdkPath,
        channels: channels,
        engineVersion: engineVer,
      );
    } catch (e) {
      LogService.error('EnvMgr', '获取 Flutter 详情失败: $e');
      return null;
    }
  }

  /// 获取 Rust 环境详情
  static Future<RustEnvironment?> getRustDetail() async {
    try {
      final rustc = await Process.run('rustc', ['--version'], runInShell: true);
      if (rustc.exitCode != 0) return null;

      final cargo = await Process.run('cargo', ['--version'], runInShell: true);
      final rustcVer = (rustc.stdout as String).trim();

      // 获取 toolchain
      String? toolchain;
      final tcResult = await Process.run('rustup', ['show'], runInShell: true);
      if (tcResult.exitCode == 0) {
        for (final line in (tcResult.stdout as String).split('\n')) {
          if (line.contains('default')) {
            toolchain = line.trim();
            break;
          }
        }
      }

      return RustEnvironment(
        rustcVersion: rustcVer,
        cargoVersion: cargo.exitCode == 0
            ? (cargo.stdout as String).trim()
            : '',
        toolchain: toolchain,
      );
    } catch (e) {
      LogService.error('EnvMgr', '获取 Rust 详情失败: $e');
      return null;
    }
  }

  /// 获取 Python 环境详情
  static Future<PythonEnvironment?> getPythonDetail() async {
    try {
      final result = await Process.run('python3', [
        '--version',
      ], runInShell: true);
      if (result.exitCode != 0) return null;

      final version = (result.stdout as String).trim();

      // pip version
      String? pipVer;
      final pip = await Process.run('pip3', ['--version'], runInShell: true);
      if (pip.exitCode == 0) {
        pipVer = (pip.stdout as String).split(' ')[1];
      }

      // venv 可用性
      final venv = await Process.run('python3', [
        '-m',
        'venv',
        '--help',
      ], runInShell: true);
      final hasVenv = venv.exitCode == 0;

      return PythonEnvironment(
        pythonVersion: version,
        pipVersion: pipVer,
        hasVenv: hasVenv,
      );
    } catch (e) {
      LogService.error('EnvMgr', '获取 Python 详情失败: $e');
      return null;
    }
  }

  /// 一键安装工具
  static Future<InstallResult> install(String tool) async {
    LogService.info('EnvMgr', '开始安装: $tool');

    try {
      switch (tool) {
        case 'flutter':
          return _runInstall('flutter', [
            'git',
            'clone',
            'https://github.com/flutter/flutter.git',
            '-b',
            'stable',
          ]);
        case 'rust':
          return _runInstall('rust', [
            'sh',
            '-c',
            'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y',
          ]);
        case 'python':
          return _runInstall('python', ['pkg', 'install', '-y', 'python']);
        case 'node':
          return _runInstall('node', ['pkg', 'install', '-y', 'nodejs']);
        case 'git':
          return _runInstall('git', ['pkg', 'install', '-y', 'git']);
        default:
          return InstallResult(
            success: false,
            tool: tool,
            errorMessage: '不支持自动安装: $tool',
          );
      }
    } catch (e) {
      return InstallResult(
        success: false,
        tool: tool,
        errorMessage: e.toString(),
      );
    }
  }

  static Future<InstallResult> _runInstall(
    String tool,
    List<String> args,
  ) async {
    try {
      final result = await Process.run(
        args.first,
        args.sublist(1),
        runInShell: true,
        environment: {'HOME': '/data/data/com.termux/files/home'} // TODO: 安装工具需要 Termux 环境
      );

      if (result.exitCode == 0) {
        LogService.info('EnvMgr', '$tool 安装成功');
        return InstallResult(
          success: true,
          tool: tool,
          output: result.stdout as String?,
        );
      } else {
        LogService.error('EnvMgr', '$tool 安装失败: ${result.stderr}');
        return InstallResult(
          success: false,
          tool: tool,
          errorMessage: result.stderr as String?,
          output: result.stdout as String?,
        );
      }
    } catch (e) {
      return InstallResult(
        success: false,
        tool: tool,
        errorMessage: e.toString(),
      );
    }
  }

  /// 获取环境摘要
  static Future<Map<String, String>> getEnvironmentSummary() async {
    final summary = <String, String>{};

    // Flutter
    final flutter = await getFlutterDetail();
    summary['Flutter'] = flutter != null ? flutter.flutterVersion : '❌ 未安装';

    // Rust
    final rust = await getRustDetail();
    summary['Rust'] = rust != null ? rust.rustcVersion : '❌ 未安装';

    // Python
    final python = await getPythonDetail();
    summary['Python'] = python != null ? python.pythonVersion : '❌ 未安装';

    // Git
    try {
      final git = await Process.run('git', ['--version'], runInShell: true);
      summary['Git'] = git.exitCode == 0
          ? (git.stdout as String).trim()
          : '❌ 未安装';
    } catch (_) {
      summary['Git'] = '❌ 未安装';
    }

    return summary;
  }
}
