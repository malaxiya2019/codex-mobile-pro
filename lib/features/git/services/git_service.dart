import 'dart:convert';
import 'dart:io';

import '../../../runtime/process/linux_execution.dart';
import '../../../runtime/process/process_runner.dart';
import '../../../runtime/process/runner_models.dart';
import '../../../runtime/provider/linux_runtime_provider.dart';
import '../models/git_repository.dart';
import 'git_path_mapper.dart';

/// Git 操作结果
class GitResult {
  final bool success;
  final String? output;
  final String? error;
  final int exitCode;

  const GitResult({
    required this.success,
    this.output,
    this.error,
    this.exitCode = 0,
  });
}

/// Git 服务
///
/// 封装 Git CLI 操作，支持：
/// - 仓库管理：init, clone, status
/// - 分支管理：branch, checkout, merge, delete
/// - 提交管理：add, commit, log, diff
/// - 远程操作：push, pull, fetch, remote
class GitService {
  /// rootfs 内 git 可执行文件（经 PRoot → Ubuntu 24.04，git 2.43.0）
  static const String _gitBin = '/usr/bin/git';

  final RuntimeProcessRunner _runner;

  /// [runner] 可注入（测试用）。默认自建
  /// `RuntimeProcessRunner + LinuxExecutionAdapter`，
  /// 使所有 git 命令统一运行在 Linux Runtime（PRoot → Ubuntu rootfs），
  /// 与部署中心检测/安装共用同一执行通道，不再依赖 Android 宿主 PATH
  /// （修复 `/system/bin/sh: git: inaccessible or not found`）。
  GitService({RuntimeProcessRunner? runner, LinuxRuntimeProvider? linux})
      : _runner = runner ?? _buildDefaultRunner(linux);

  /// 构建默认 runner：复用现有 PRoot 执行机制（不重复实现）
  static RuntimeProcessRunner _buildDefaultRunner(LinuxRuntimeProvider? linux) {
    final runner = RuntimeProcessRunner();
    runner.registerAdapter(
      LinuxExecutionAdapter(linux ?? LinuxRuntimeProvider()),
    );
    return runner;
  }

  /// 执行 git 命令（统一入口，全部经 Runtime → PRoot）
  ///
  /// [workingDirectory] 为 Android 宿主路径，自动映射为 guest 路径
  /// 并附加 PRoot bind；[bindPath] 为额外需要映射的宿主路径
  /// （如 clone 目标目录）。
  Future<GitResult> _runGit(
    List<String> args, {
    String? workingDirectory,
    String? bindPath,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    // 收集需要映射进 PRoot guest 的宿主路径
    final hostPaths = <String>{};
    if (workingDirectory != null) hostPaths.add(workingDirectory);
    if (bindPath != null) hostPaths.add(bindPath);

    // extraBinds 通道要求纯 bind 串（LinuxExecutionAdapter 自动加 `-b`），
    // 因此这里用 GitPathMapper.bindPath 而非 bindArguments，避免重复 `-b`。
    final binds = <String>[];
    for (final p in hostPaths) {
      final bind = GitPathMapper.bindPath(p);
      if (!binds.contains(bind)) binds.add(bind);
    }

    try {
      final result = await _runner.run(
        RuntimeProcessRequest(
          runtimeId: 'linux',
          executable: _gitBin,
          arguments: args,
          workingDirectory: workingDirectory == null
              ? null
              : GitPathMapper.hostToGuest(workingDirectory),
          extraBinds: binds.isEmpty ? null : binds,
          timeout: timeout,
          label: 'git:${args.isEmpty ? '?' : args.first}',
        ),
      );
      return _toGitResult(result);
    } catch (e) {
      return GitResult(
        success: false,
        error: 'Git 执行失败: $e',
        exitCode: -1,
      );
    }
  }

  /// 将 Runtime 执行结果转换为 GitResult
  ///
  /// 关键：Runtime 未就绪（LinuxExecutionAdapter 返回 failedToStart +
  /// 「Linux Runtime 未初始化」）时给出明确提示，替代 Android 宿主
  /// `/system/bin/sh: git: inaccessible or not found` 的误导性报错。
  GitResult _toGitResult(RuntimeProcessResult result) {
    if (result.failedToStart) {
      final err = result.error ?? '';
      if (err.contains('Linux Runtime 未初始化') ||
          err.contains('Linux Runtime')) {
        return GitResult(
          success: false,
          error: 'Coding Runtime 未就绪，请先部署 Linux Runtime。\n$err',
          exitCode: -1,
        );
      }
      return GitResult(
        success: false,
        error: 'Git 启动失败: $err',
        exitCode: -1,
      );
    }
    if (result.timedOut) {
      return const GitResult(
        success: false,
        error: '命令执行超时',
        exitCode: -2,
      );
    }
    return GitResult(
      success: result.isSuccess,
      output: result.stdout,
      error: result.stderr.isEmpty
          ? (result.isSuccess
              ? null
              : 'git 执行失败 (exit=${result.exitCode})')
          : result.stderr,
      exitCode: result.exitCode,
    );
  }

  /// 执行任意 git 命令（供 GitWorkflowProvider 等复用同一执行器）
  Future<GitResult> execute(
    String workingDirectory,
    List<String> args, {
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _runGit(args, workingDirectory: workingDirectory, timeout: timeout);
  }

  /// 检查 git 是否可用
  Future<bool> isGitAvailable() async {
    final result = await _runGit(['--version']);
    return result.success;
  }

  /// 获取 git 版本
  Future<String?> getVersion() async {
    final result = await _runGit(['--version']);
    return result.success ? result.output?.trim() : null;
  }

  /// 初始化仓库
  Future<GitResult> init(String path) async {
    return _runGit(['init'], workingDirectory: path);
  }

  /// 克隆仓库
  Future<GitResult> clone(
    String url,
    String destination, {
    String? branch,
    bool shallow = false,
  }) async {
    // destination 为 Android 宿主路径 → 映射为 guest 路径（/sdcard/...），
    // 并附加 bind 让 PRoot 内 git 能写入宿主目录。
    final args = ['clone'];
    if (shallow) args.add('--depth=1');
    if (branch != null) {
      args.addAll(['--branch', branch]);
    }
    args.addAll([url, GitPathMapper.hostToGuest(destination)]);
    // bind destination 的父目录（clone 前已存在）而非 destination 本身：
    // PRoot 对不存在的 host 目录 bind 会在 rootfs 内创建隔离目录，
    // git 的写入不会落盘到 Android 宿主。
    final parentDir = Directory(destination).parent.path;
    return _runGit(
      args,
      bindPath: parentDir,
      timeout: const Duration(seconds: 300),
    );
  }

  /// 获取仓库状态
  Future<GitStatus> status(String workingDirectory) async {
    // 获取分支名
    final branchResult = await _runGit(
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: workingDirectory,
    );

    // 获取变更
    final statusResult = await _runGit(
      ['status', '--porcelain'],
      workingDirectory: workingDirectory,
    );

    // 获取 ahead/behind
    final aheadBehind = await _runGit(
      ['rev-list', '--count', '--left-right', '@{upstream}...HEAD'],
      workingDirectory: workingDirectory,
    );

    final changes = <GitFileChange>[];
    if (statusResult.success && statusResult.output != null) {
      for (final line in const LineSplitter().convert(statusResult.output!)) {
        if (line.trim().isEmpty) continue;
        final status = line.substring(0, 2).trim();
        final path = line.substring(3).trim();

        GitChangeType type;
        switch (status) {
          case '??':
            type = GitChangeType.untracked;
            break;
          case 'M ':
          case ' M':
            type = GitChangeType.modified;
            break;
          case 'A ':
          case ' A':
            type = GitChangeType.added;
            break;
          case 'D ':
          case ' D':
            type = GitChangeType.deleted;
            break;
          case 'R ':
          case ' R':
            type = GitChangeType.renamed;
            break;
          default:
            type = GitChangeType.modified;
        }

        changes.add(GitFileChange(path: path, type: type));
      }
    }

    int ahead = 0, behind = 0;
    if (aheadBehind.success && aheadBehind.output != null) {
      final parts = aheadBehind.output!.trim().split('\t');
      if (parts.length == 2) {
        ahead = int.tryParse(parts[0]) ?? 0;
        behind = int.tryParse(parts[1]) ?? 0;
      }
    }

    return GitStatus(
      currentBranch: branchResult.success ? branchResult.output?.trim() : null,
      changes: changes,
      ahead: ahead,
      behind: behind,
    );
  }

  /// 暂存所有变更
  Future<GitResult> addAll(String workingDirectory) async {
    return _runGit(['add', '.'], workingDirectory: workingDirectory);
  }

  /// 暂存指定文件
  Future<GitResult> add(String workingDirectory, List<String> files) async {
    return _runGit(['add', ...files], workingDirectory: workingDirectory);
  }

  /// 提交
  Future<GitResult> commit(
    String workingDirectory,
    String message, {
    bool signOff = false,
  }) async {
    final args = ['commit', '-m', message];
    if (signOff) args.add('--signoff');
    return _runGit(args, workingDirectory: workingDirectory);
  }

  /// 推送
  Future<GitResult> push(
    String workingDirectory, {
    String remote = 'origin',
    String? branch,
    bool force = false,
  }) async {
    final args = ['push', remote];
    if (branch != null) args.add(branch);
    if (force) args.add('--force');
    return _runGit(args, workingDirectory: workingDirectory, timeout: const Duration(seconds: 120));
  }

  /// 拉取
  Future<GitResult> pull(
    String workingDirectory, {
    String remote = 'origin',
    String? branch,
    bool rebase = false,
  }) async {
    final args = ['pull', remote];
    if (branch != null) args.add(branch);
    if (rebase) args.add('--rebase');
    return _runGit(args, workingDirectory: workingDirectory, timeout: const Duration(seconds: 120));
  }

  /// 获取分支列表
  Future<List<GitBranch>> branches(String workingDirectory) async {
    final result = await _runGit(
      ['branch', '-a'],
      workingDirectory: workingDirectory,
    );

    if (!result.success || result.output == null) return [];

    final branches = <GitBranch>[];
    for (final line in const LineSplitter().convert(result.output!)) {
      if (line.trim().isEmpty) continue;
      final isCurrent = line.startsWith('*');
      final name = line.replaceAll('*', '').trim();
      branches.add(GitBranch(name: name, isCurrent: isCurrent));
    }
    return branches;
  }

  /// 切换分支
  Future<GitResult> checkout(
    String workingDirectory,
    String branch, {
    bool create = false,
  }) async {
    final args = ['checkout'];
    if (create) args.add('-b');
    args.add(branch);
    return _runGit(args, workingDirectory: workingDirectory);
  }

  /// 创建并切换分支
  Future<GitResult> createBranch(
    String workingDirectory,
    String branchName, {
    String? from,
  }) async {
    final args = ['checkout', '-b', branchName];
    if (from != null) args.add(from);
    return _runGit(args, workingDirectory: workingDirectory);
  }

  /// 删除分支
  Future<GitResult> deleteBranch(
    String workingDirectory,
    String branchName, {
    bool force = false,
  }) async {
    final args = ['branch'];
    if (force) {
      args.add('-D');
    } else {
      args.add('-d');
    }
    args.add(branchName);
    return _runGit(args, workingDirectory: workingDirectory);
  }

  /// 合并分支
  Future<GitResult> merge(
    String workingDirectory,
    String branch,
  ) async {
    return _runGit(['merge', branch], workingDirectory: workingDirectory);
  }

  /// 获取提交日志
  Future<List<GitCommit>> log(
    String workingDirectory, {
    int maxCount = 10,
    String? branch,
    String? file,
  }) async {
    final args = ['log', '--oneline', '--format=%H|%s|%an|%ae|%ai', '--max-count=$maxCount'];
    if (branch != null) args.add(branch);
    if (file != null) args.addAll(['--', file]);

    final result = await _runGit(args, workingDirectory: workingDirectory);
    if (!result.success || result.output == null) return [];

    final commits = <GitCommit>[];
    for (final line in const LineSplitter().convert(result.output!)) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('|');
      if (parts.length >= 3) {
        commits.add(GitCommit(
          sha: parts[0].substring(0, 7),
          message: parts[1],
          author: parts[2],
          authorEmail: parts.length > 3 ? parts[3] : null,
          date: parts.length > 4 ? DateTime.tryParse(parts[4]) : null,
        ));
      }
    }
    return commits;
  }

  /// 获取 diff
  Future<String?> diff(
    String workingDirectory, {
    bool staged = false,
    String? file,
  }) async {
    final args = ['diff'];
    if (staged) args.add('--cached');
    if (file != null) {
      args.add('--');
      args.add(file);
    }
    final result = await _runGit(args, workingDirectory: workingDirectory);
    return result.success ? result.output : null;
  }

  /// 添加远程仓库
  Future<GitResult> addRemote(
    String workingDirectory,
    String name,
    String url,
  ) async {
    return _runGit(
      ['remote', 'add', name, url],
      workingDirectory: workingDirectory,
    );
  }

  /// 获取远程仓库列表
  Future<List<String>> remotes(String workingDirectory) async {
    final result = await _runGit(
      ['remote', '-v'],
      workingDirectory: workingDirectory,
    );
    if (!result.success || result.output == null) return [];
    final remotes = <String>[];
    for (final line in const LineSplitter().convert(result.output!)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty && !remotes.contains(parts[0])) {
        remotes.add(parts[0]);
      }
    }
    return remotes;
  }

  /// 撤销工作区变更
  Future<GitResult> restore(
    String workingDirectory,
    List<String> files,
  ) async {
    return _runGit(
      ['restore', ...files],
      workingDirectory: workingDirectory,
    );
  }

  /// 暂存工作区（stash）
  Future<GitResult> stash(
    String workingDirectory, {
    String? message,
  }) async {
    final args = ['stash', 'push'];
    if (message != null) args.addAll(['-m', message]);
    return _runGit(args, workingDirectory: workingDirectory);
  }

  /// 恢复 stash
  Future<GitResult> stashPop(String workingDirectory) async {
    return _runGit(['stash', 'pop'], workingDirectory: workingDirectory);
  }

  /// 暂存列表
  Future<List<String>> stashList(String workingDirectory) async {
    final result = await _runGit(
      ['stash', 'list'],
      workingDirectory: workingDirectory,
    );
    if (!result.success || result.output == null) return [];
    return const LineSplitter().convert(result.output!);
  }
}
