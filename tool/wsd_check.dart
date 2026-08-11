// 独立手动验证脚本（纯 Dart，无需 Flutter/pub 解析）
// 直接驱动 lib/core/ai/workspace_dir_resolver.dart 的真实逻辑
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:io';
import '../lib/core/ai/workspace_dir_resolver.dart';

int _passed = 0;
int _failed = 0;

void check(String name, bool cond) {
  if (cond) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    print('  FAIL  $name');
  }
}

Directory _git(String path) {
  Directory(path).createSync(recursive: true);
  Directory('$path/.git').createSync(recursive: true);
  return Directory(path);
}

void main() {
  final temp = Directory.systemTemp.createTempSync('wsd-manual');
  print('临时根: ${temp.path}');
  try {
    // 1. git 仓库原样
    final repo = _git('${temp.path}/repo-a');
    var r = resolveCodexWorkspaceDir(repo.path);
    check('git 仓库原样使用 (isGit=true)', r.path == repo.path && r.isGitRepository);

    // 2. 默认目录 → 解析到 git/<repo>
    _git('${temp.path}/git/codex-mobile-pro');
    r = resolveCodexWorkspaceDir(temp.path);
    check('默认目录 → 解析到 git/codex-mobile-pro',
        r.path == '${temp.path}/git/codex-mobile-pro' && r.isGitRepository && r.wasResolved);

    // 3. 多仓库选最近修改
    _git('${temp.path}/git/old-repo');
    sleep(const Duration(milliseconds: 100)); // 目录 mtime 随增删子项更新，间隔制造新旧差异
    final neu = _git('${temp.path}/git/new-repo');
    r = resolveCodexWorkspaceDir(temp.path);
    check('多仓库按最近修改选 new-repo', r.path == neu.path);

    // 4. git/ 下无仓库 → 原样
    Directory('${temp.path}/plain/git/not-a-repo').createSync(recursive: true);
    r = resolveCodexWorkspaceDir('${temp.path}/plain');
    check('无 git 仓库 → 原样返回 (isGit=false)',
        r.path == '${temp.path}/plain' && !r.isGitRepository);

    // 5. 不存在 → 原样
    r = resolveCodexWorkspaceDir('${temp.path}/missing');
    check('不存在 → 原样返回 (isGit=false)',
        r.path == '${temp.path}/missing' && !r.isGitRepository);

    // 6. 幂等：已解析仓库再解析不变
    final first = resolveCodexWorkspaceDir(temp.path);
    final second = resolveCodexWorkspaceDir(first.path);
    check('幂等：二次解析结果不变', first.path == second.path && second.isGitRepository);

    // 7. 尾部斜杠
    r = resolveCodexWorkspaceDir('${temp.path}/git/new-repo/');
    check('尾部斜杠规范化', r.path == neu.path);
  } finally {
    temp.deleteSync(recursive: true);
  }
  print('\n结果: $_passed 通过, $_failed 失败');
  exit(_failed == 0 ? 0 : 1);
}
