/// ====================================================================
/// Codex 工作目录解析 — 纯 Dart（无 Flutter 依赖，便于单元测试）
///
/// 背景：AI 对话「工作目录：默认（App 文档目录）」传入 CodexRunner 的是
/// App 文档目录根（host 侧），被 PRoot bind 为 guest /workspace。但真实
/// 项目（git clone 的仓库）位于 `App文档目录/git/<repo>`；Codex 启动在
/// /workspace 根目录、并非 Git 仓库，AI 看不到项目文件。
///
/// 本模块在 Codex 启动前统一执行一次工作目录解析：
///   1. 判断 requested 目录是否存在、是否为 Git 仓库；
///   2. 不是 Git 仓库时 → 检查已知项目根目录（`requested/git/` 下的
///      git clone 仓库统一落位处，见 git_operations_page），按最近修改
///      优先取一个 Git 仓库；
///   3. 返回解析后的 host 绝对路径，由 CodexRunner bind 为 guest
///      /workspace —— Codex 的 cwd 内容即项目根。
///
/// 幂等：对已解析出的 Git 仓库再次调用，结果不变（.git 存在即直接命中）。
/// ====================================================================
library;

import 'dart:io';

/// 工作目录解析结果
class ResolvedWorkspaceDir {
  /// 解析后的 host 绝对路径
  final String path;

  /// 解析后的目录是否为 Git 仓库
  final bool isGitRepository;

  /// 是否从默认目录解析到了项目根（path != requested）
  final bool wasResolved;

  const ResolvedWorkspaceDir({
    required this.path,
    required this.isGitRepository,
    this.wasResolved = false,
  });
}

/// 判断目录是否为 Git 仓库。
///
/// `.git` 可能是目录（普通仓库）或文件（worktree / submodule）。
bool isGitRepository(String dir) {
  final dotGit = '$dir/.git';
  return Directory(dotGit).existsSync() || File(dotGit).existsSync();
}

/// 统一工作目录解析（Codex 启动前调用一次）。
///
/// [requested] — 请求的工作目录（host 绝对路径，通常为 App 文档目录）
///
/// 规则：
///   1. requested 为空或不存在 → 原样返回（保持调用方原有行为，不猜测）；
///   2. requested 本身是 Git 仓库 → 直接使用；
///   3. 否则扫描 `requested/git/` 下的已知项目根目录（git clone 仓库统一
///      落位处），按目录最近修改时间降序取第一个 Git 仓库；
///   4. 无候选 → 原样返回 requested。
ResolvedWorkspaceDir resolveCodexWorkspaceDir(String requested) {
  if (requested.isEmpty) {
    return ResolvedWorkspaceDir(path: requested, isGitRepository: false);
  }
  final norm = _normalizePath(requested);
  if (!Directory(norm).existsSync()) {
    return ResolvedWorkspaceDir(path: norm, isGitRepository: false);
  }
  if (isGitRepository(norm)) {
    return ResolvedWorkspaceDir(path: norm, isGitRepository: true);
  }

  final candidates = _findGitReposUnder(norm);
  if (candidates.isNotEmpty) {
    return ResolvedWorkspaceDir(
      path: candidates.first,
      isGitRepository: true,
      wasResolved: true,
    );
  }
  return ResolvedWorkspaceDir(path: norm, isGitRepository: false);
}

/// 规范化路径：相对路径转绝对（基于进程 cwd），去尾部斜杠（保留根 "/"）。
String _normalizePath(String path) {
  final p = path.trim();
  if (p.isEmpty) return p;
  final abs = Directory(p).absolute.path;
  if (abs.length > 1 && abs.endsWith('/')) {
    return abs.substring(0, abs.length - 1);
  }
  return abs;
}

/// 扫描 `<base>/git/` 下的 Git 仓库，按最近修改时间降序。
List<String> _findGitReposUnder(String base) {
  final gitBase = Directory('$base/git');
  if (!gitBase.existsSync()) return const [];
  try {
    final repos = <String>[];
    for (final child in gitBase.listSync(followLinks: false)) {
      if (child is Directory && isGitRepository(child.path)) {
        repos.add(child.path);
      }
    }
    repos.sort((a, b) => _modified(b).compareTo(_modified(a)));
    return repos;
  } catch (_) {
    return const [];
  }
}

DateTime _modified(String path) {
  try {
    return Directory(path).statSync().modified;
  } catch (_) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
