import 'package:codex_mobile_pro/features/git/models/git_repository.dart';
import 'package:codex_mobile_pro/features/git/services/git_service.dart';
import 'package:codex_mobile_pro/features/git/services/github_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'capability/fake_runner.dart';

void main() {
  group('GitResult', () {
    test('创建成功结果', () {
      const result = GitResult(success: true, output: 'ok');
      expect(result.success, true);
      expect(result.output, 'ok');
      expect(result.exitCode, 0);
    });

    test('创建失败结果', () {
      const result = GitResult(success: false, error: 'error msg', exitCode: 1);
      expect(result.success, false);
      expect(result.error, 'error msg');
      expect(result.exitCode, 1);
    });
  });

  group('GitRepository', () {
    test('从 JSON 创建', () {
      final repo = GitRepository.fromJson({
        'id': 123456,
        'name': 'test-repo',
        'full_name': 'user/test-repo',
        'description': 'A test repository',
        'html_url': 'https://github.com/user/test-repo',
        'clone_url': 'https://github.com/user/test-repo.git',
        'default_branch': 'main',
        'private': false,
        'owner': {'login': 'user', 'avatar_url': 'https://avatars.githubusercontent.com/u/1?v=4'},
        'updated_at': '2026-07-28T10:00:00Z',
        'stargazers_count': 10,
        'forks_count': 5,
        'language': 'Dart',
      });

      expect(repo.name, 'test-repo');
      expect(repo.fullName, 'user/test-repo');
      expect(repo.description, 'A test repository');
      expect(repo.isPrivate, false);
      expect(repo.owner, 'user');
      expect(repo.starCount, 10);
      expect(repo.forkCount, 5);
      expect(repo.language, 'Dart');
    });

    test('JSON 缺少字段时使用默认值', () {
      final repo = GitRepository.fromJson({
        'id': 1,
        'name': 'repo',
      });

      expect(repo.name, 'repo');
      expect(repo.fullName, 'repo');
      expect(repo.isPrivate, false);
      expect(repo.description, isNull);
      expect(repo.starCount, isNull);
    });

    test('toJson 序列化', () {
      const repo = GitRepository(
        id: '1',
        name: 'test',
        fullName: 'user/test',
        description: 'desc',
        isPrivate: true,
        owner: 'user',
        cloneUrl: 'https://github.com/user/test.git',
        starCount: 5,
        language: 'Rust',
      );

      final json = repo.toJson();
      expect(json['name'], 'test');
      expect(json['private'], true);
      expect(json['language'], 'Rust');
    });
  });

  group('GitStatus', () {
    test('干净工作区', () {
      const status = GitStatus(currentBranch: 'main');
      expect(status.isClean, true);
      expect(status.currentBranch, 'main');
      expect(status.changes, isEmpty);
    });

    test('有变更的工作区', () {
      const status = GitStatus(
        currentBranch: 'dev',
        changes: [
          GitFileChange(path: 'file1.dart', type: GitChangeType.modified),
          GitFileChange(path: 'file2.dart', type: GitChangeType.added),
          GitFileChange(path: 'file3.dart', type: GitChangeType.deleted),
        ],
        ahead: 2,
        behind: 1,
      );

      expect(status.isClean, false);
      expect(status.modifiedCount, 1);
      expect(status.addedCount, 1);
      expect(status.deletedCount, 1);
      expect(status.ahead, 2);
      expect(status.behind, 1);
    });

    test('变更计数', () {
      const status = GitStatus(
        changes: [
          GitFileChange(path: 'a.dart', type: GitChangeType.added),
          GitFileChange(path: 'b.dart', type: GitChangeType.modified),
          GitFileChange(path: 'c.dart', type: GitChangeType.deleted),
          GitFileChange(path: 'd.dart', type: GitChangeType.renamed),
          GitFileChange(path: 'e.dart', type: GitChangeType.untracked),
        ],
      );

      expect(status.addedCount, 1);
      expect(status.modifiedCount, 1);
      expect(status.deletedCount, 1);
      expect(status.changes.length, 5);
    });
  });

  group('GitCommit', () {
    test('创建提交', () {
      const commit = GitCommit(
        sha: 'abc1234',
        message: 'Fix bug',
        author: 'Dev',
        authorEmail: 'dev@example.com',
      );

      expect(commit.sha, 'abc1234');
      expect(commit.message, 'Fix bug');
      expect(commit.author, 'Dev');
    });
  });

  group('GitBranch', () {
    test('创建分支', () {
      const branch = GitBranch(name: 'feature-x', isCurrent: true);
      expect(branch.name, 'feature-x');
      expect(branch.isCurrent, true);
    });

    test('非当前分支', () {
      const branch = GitBranch(name: 'main');
      expect(branch.isCurrent, false);
    });
  });

  group('GitHubService', () {
    test('初始未登录', () {
      final service = GitHubService();
      expect(service.isLoggedIn, false);
      expect(service.username, isNull);
    });

    test('loadToken 从旧版 SharedPreferences 迁移明文 Token', () async {
      SharedPreferences.setMockInitialValues({
        'github_token': 'ghp_legacy',
        'github_user': '{"login":"octocat"}',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final service = GitHubService();
      expect(service.isLoggedIn, false);

      final ok = await service.loadToken();
      expect(ok, isTrue);
      expect(service.accessToken, 'ghp_legacy');
      expect(service.username, 'octocat');

      // 已迁移到 secure storage
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'github_token'), 'ghp_legacy');
      // 旧位置已清理
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('github_token'), isNull);
      expect(prefs.getString('github_user'), isNull);
    });

    test('loadToken 无旧值时返回 false（不迁移）', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      final service = GitHubService();
      final ok = await service.loadToken();
      expect(ok, isFalse);
      expect(service.isLoggedIn, false);
    });

    test('loadToken secure storage 有值时不再读旧位置', () async {
      SharedPreferences.setMockInitialValues({
        'github_token': 'ghp_legacy',
      });
      FlutterSecureStorage.setMockInitialValues({
        'github_token': 'ghp_secure',
      });

      final service = GitHubService();
      final ok = await service.loadToken();
      expect(ok, isTrue);
      // secure storage 值优先，旧位置不覆盖
      expect(service.accessToken, 'ghp_secure');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('github_token'), 'ghp_legacy');
    });

    test('Token 管理', () async {
      final service = GitHubService();
      expect(service.isLoggedIn, false);

      await service.saveToken('test_token');
      // 内存中
      expect(service.isLoggedIn, true);
    });

    test('Token 清除', () async {
      final service = GitHubService();
      await service.saveToken('test_token');
      expect(service.isLoggedIn, true);

      await service.clearToken();
      expect(service.isLoggedIn, false);
      expect(service.username, isNull);
    });

    test('无效 Token 验证返回 null', () async {
      final service = GitHubService();
      final result = await service.verifyToken('invalid_token_xxx');
      // 网络请求会失败，返回 null
      expect(result, isNull);
    });
  });

  group('GitService', () {
    test('GitService 可创建（默认 runner 安全）', () {
      final service = GitService();
      expect(service, isNotNull);
    });
  });

  group('GitService 统一 Runtime 执行入口', () {
    test('clone 请求走 runtimeId=linux + /usr/bin/git + guest 路径映射',
        () async {
      final runner = FakeProcessRunner();
      runner.when(
        '/usr/bin/git clone https://github.com/malaxiya2019/codex-mobile-pro.git /sdcard/repos/codex-mobile-pro',
        const FakeCommandResult( stdout: 'done\n'),
      );
      final service = GitService(runner: runner);

      final result = await service.clone(
        'https://github.com/malaxiya2019/codex-mobile-pro.git',
        '/storage/emulated/0/repos/codex-mobile-pro',
      );

      expect(result.success, isTrue);
      expect(runner.executedRequests, hasLength(1));
      final req = runner.executedRequests.first;
      // 统一入口：Linux Runtime（PRoot → Ubuntu rootfs），绝不依赖宿主 PATH
      expect(req.runtimeId, 'linux');
      expect(req.executable, '/usr/bin/git');
      expect(req.arguments, contains('/sdcard/repos/codex-mobile-pro'));
      expect(req.arguments, isNot(contains('/storage/emulated/0')));
      // clone 无 workingDirectory；bind 目标是已存在的父目录
      expect(req.workingDirectory, isNull);
      expect(req.extraBinds, isNotNull);
      // extraBinds 只含纯 bind 串（LinuxExecutionAdapter 自动加 `-b`），
      // 绝不能包含 '-b' 本身，否则会生成重复的 `-b -b` 参数
      expect(req.extraBinds, isNot(contains('-b')));
      expect(req.extraBinds, contains('/storage/emulated/0:/sdcard'));
    });

    test('clone bind 父目录而非不存在的目标目录', () async {
      final runner = FakeProcessRunner();
      runner.when(
        '/usr/bin/git clone https://github.com/x/y.git /sdcard/yy',
        const FakeCommandResult( stdout: 'ok\n'),
      );
      final service = GitService(runner: runner);

      await service.clone(
        'https://github.com/x/y.git',
        '/storage/emulated/0/yy',
      );

      final req = runner.executedRequests.first;
      // destination=/storage/emulated/0/yy 的父目录 = /storage/emulated/0
      expect(req.extraBinds, contains('/storage/emulated/0:/sdcard'));
      expect(req.extraBinds, isNot(contains('/storage/emulated/0/yy')));
    });

    test('status 请求带 workingDirectory 映射 + extraBinds', () async {
      final runner = FakeProcessRunner();
      final service = GitService(runner: runner);
      const repoPath = '/data/data/com.codexmobile.app/app_flutter/git/repo';
      runner.when(
        '/usr/bin/git rev-parse --abbrev-ref HEAD',
        const FakeCommandResult( stdout: 'main\n'),
      );
      runner.when(
        '/usr/bin/git status --porcelain',
        const FakeCommandResult(),
      );
      runner.when(
        '/usr/bin/git rev-list --count --left-right @{upstream}...HEAD',
        const FakeCommandResult( stdout: '0\t0\n'),
      );

      final status = await service.status(repoPath);

      expect(status.currentBranch, 'main');
      expect(status.isClean, isTrue);
      expect(runner.executedRequests, isNotEmpty);
      final first = runner.executedRequests.first;
      expect(first.runtimeId, 'linux');
      expect(first.executable, '/usr/bin/git');
      // 非 /storage 路径原样映射；extraBinds 同名 bind（无 `-b` 前缀）
      expect(first.workingDirectory, repoPath);
      expect(first.extraBinds, isNot(contains('-b')));
      expect(first.extraBinds, contains(repoPath));
    });

    test('execute() 复用同一 Runtime 入口（GitWorkflowProvider 路径）',
        () async {
      final runner = FakeProcessRunner();
      runner.when(
        '/usr/bin/git status --porcelain',
        const FakeCommandResult( stdout: ' M file.dart\n'),
      );
      final service = GitService(runner: runner);

      final result = await service.execute(
        '/data/data/com.codexmobile.app/app_flutter/git/repo',
        ['status', '--porcelain'],
      );

      expect(result.success, isTrue);
      final req = runner.executedRequests.single;
      expect(req.runtimeId, 'linux');
      expect(req.executable, '/usr/bin/git');
    });

    test('Runtime 未就绪 → 明确提示「Coding Runtime 未就绪，请先部署 Linux Runtime」',
        () async {
      final runner = FakeProcessRunner();
      runner.when(
        '/usr/bin/git --version',
        const FakeCommandResult(
          exitCode: -1,
          error: 'Linux Runtime 未初始化\n[proot] null\n[loader] null\n[bash] 缺失',
        ),
      );
      final service = GitService(runner: runner);

      final result = await service.execute(
        '/data/data/com.codexmobile.app/app_flutter/git/repo',
        ['--version'],
      );

      expect(result.success, isFalse);
      expect(
        result.error,
        contains('Coding Runtime 未就绪，请先部署 Linux Runtime'),
      );
      // 绝不出现 Android 宿主的误导性报错
      expect(result.error, isNot(contains('/system/bin/sh')));
    });

    test('超时 → 明确「命令执行超时」', () async {
      final runner = FakeProcessRunner();
      runner.when(
        '/usr/bin/git --version',
        const FakeCommandResult(timedOut: true),
      );
      final service = GitService(runner: runner);

      final result = await service.execute(
        '/data/data/com.codexmobile.app/app_flutter/git/repo',
        ['--version'],
      );

      expect(result.success, isFalse);
      expect(result.error, contains('命令执行超时'));
    });

    test('getVersion 返回真实版本输出', () async {
      final runner = FakeProcessRunner();
      runner.when(
        '/usr/bin/git --version',
        const FakeCommandResult( stdout: 'git version 2.43.0\n'),
      );
      final service = GitService(runner: runner);

      final version = await service.getVersion();
      expect(version, 'git version 2.43.0');
    });
  });
}
