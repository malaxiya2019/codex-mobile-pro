import 'dart:io';

import 'package:codex_mobile_pro/core/ai/workspace_dir_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════
// resolveCodexWorkspaceDir 单元测试
//
// 覆盖「Codex 启动前统一工作目录解析」规则：
//   1. requested 本身是 Git 仓库 → 直接使用
//   2. 不是 Git 仓库 → 扫描 requested/git/ 下的已知项目根，按最近修改取一
//   3. requested/git/ 无 Git 仓库 → 原样返回
//   4. requested 不存在 → 原样返回（不猜测）
//   5. 多个候选 → 选最近修改的 Git 仓库（mtime 降序）
// ══════════════════════════════════════════════════════════════

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('wsd-resolver-test');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  Directory createGitRepo(String path) {
    final repo = Directory(path)..createSync(recursive: true);
    Directory('$path/.git').createSync(recursive: true);
    return repo;
  }

  group('isGitRepository', () {
    test('普通仓库（.git 目录）→ true', () {
      final repo = createGitRepo('${temp.path}/repo-a');
      expect(isGitRepository(repo.path), isTrue);
    });

    test('worktree / submodule（.git 文件）→ true', () {
      final repo = Directory('${temp.path}/repo-file')..createSync();
      File('${repo.path}/.git').writeAsStringSync('gitdir: /elsewhere/.git\n');
      expect(isGitRepository(repo.path), isTrue);
    });

    test('普通目录 → false', () {
      final plain = Directory('${temp.path}/plain')..createSync();
      expect(isGitRepository(plain.path), isFalse);
    });

    test('不存在目录 → false', () {
      expect(isGitRepository('${temp.path}/nope'), isFalse);
    });
  });

  group('resolveCodexWorkspaceDir', () {
    test('requested 本身就是 Git 仓库 → 原样使用，isGit=true', () {
      final repo = createGitRepo('${temp.path}/repo-a');
      final r = resolveCodexWorkspaceDir(repo.path);
      expect(r.path, repo.path);
      expect(r.isGitRepository, isTrue);
      expect(r.wasResolved, isFalse);
    });

    test('默认目录（App 文档目录）不是仓库，但 requested/git/ 下有仓库 → 解析到它', () {
      final docs = Directory(temp.path)..createSync();
      createGitRepo('${docs.path}/git/codex-mobile-pro');

      final r = resolveCodexWorkspaceDir(docs.path);
      expect(r.path, '${docs.path}/git/codex-mobile-pro');
      expect(r.isGitRepository, isTrue);
      expect(r.wasResolved, isTrue);
    });

    test('多个候选 → 按最近修改时间选最新的 Git 仓库', () async {
      final docs = Directory(temp.path)..createSync();
      createGitRepo('${docs.path}/git/old-repo');
      // 目录 mtime 在 Linux 上随增删子项更新：间隔写入，制造明确新旧差异
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final newer = createGitRepo('${docs.path}/git/new-repo');
      final r = resolveCodexWorkspaceDir(docs.path);
      expect(r.path, newer.path);
      expect(r.isGitRepository, isTrue);
    });

    test('requested/git/ 下只有普通目录（非仓库）→ 原样返回，isGit=false', () {
      final docs = Directory(temp.path)..createSync();
      Directory('${docs.path}/git/not-a-repo').createSync(recursive: true);

      final r = resolveCodexWorkspaceDir(docs.path);
      expect(r.path, docs.path);
      expect(r.isGitRepository, isFalse);
      expect(r.wasResolved, isFalse);
    });

    test('requested 不存在 → 原样返回（不猜测），isGit=false', () {
      final missing = '${temp.path}/no-such-dir';
      final r = resolveCodexWorkspaceDir(missing);
      expect(r.path, missing);
      expect(r.isGitRepository, isFalse);
    });

    test('requested/git/ 不存在 → 原样返回，isGit=false', () {
      final docs = Directory(temp.path)..createSync();
      final r = resolveCodexWorkspaceDir(docs.path);
      expect(r.path, docs.path);
      expect(r.isGitRepository, isFalse);
    });

    test('空字符串 → 原样返回空串', () {
      final r = resolveCodexWorkspaceDir('');
      expect(r.path, '');
      expect(r.isGitRepository, isFalse);
    });

    test('已解析出的仓库再次调用（幂等）→ 结果不变', () {
      final docs = Directory(temp.path)..createSync();
      final repo = createGitRepo('${docs.path}/git/codex-mobile-pro');

      final first = resolveCodexWorkspaceDir(docs.path);
      final second = resolveCodexWorkspaceDir(first.path);
      expect(second.path, repo.path);
      expect(second.isGitRepository, isTrue);
    });

    test('尾部斜杠规范化', () {
      final repo = createGitRepo('${temp.path}/git/trail');
      final r = resolveCodexWorkspaceDir('${temp.path}/git/trail/');
      expect(r.path, repo.path);
    });
  });
}
