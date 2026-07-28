import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/git_repository.dart';

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
  static const String _gitBin = 'git';

  /// 执行 git 命令
  Future<GitResult> _runGit(
    List<String> args, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final process = await Process.start(
        _gitBin,
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
      );

      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();

      final exitCode = await process.exitCode.timeout(timeout);

      return GitResult(
        success: exitCode == 0,
        output: await stdout,
        error: await stderr,
        exitCode: exitCode,
      );
    } on TimeoutException {
      return const GitResult(
        success: false,
        error: '命令执行超时',
        exitCode: -1,
      );
    } catch (e) {
      return GitResult(
        success: false,
        error: 'Git 执行失败: $e',
        exitCode: -1,
      );
    }
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
    final args = ['clone'];
    if (shallow) args.add('--depth=1');
    if (branch != null) {
      args.addAll(['--branch', branch]);
    }
    args.addAll([url, destination]);
    return _runGit(args, timeout: const Duration(seconds: 300));
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
    if (force) args.add('-D');
    else args.add('-d');
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
