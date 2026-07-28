import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/git_provider.dart';

/// GitHub 登录页
class GitHubLoginPage extends ConsumerStatefulWidget {
  const GitHubLoginPage({super.key});

  @override
  ConsumerState<GitHubLoginPage> createState() => _GitHubLoginPageState();
}

class _GitHubLoginPageState extends ConsumerState<GitHubLoginPage> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showSnackBar('请输入 Personal Access Token');
      return;
    }

    final success =
        await ref.read(gitHubAuthProvider.notifier).loginWithToken(token);
    if (success) {
      _showSnackBar('GitHub 登录成功');
      if (mounted) Navigator.of(context).pop();
    } else {
      _showSnackBar('Token 无效，请检查后重试');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(gitHubAuthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 登录'),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surfaceContainer,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 图标和标题
            Icon(Icons.code_rounded, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '连接 GitHub',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '使用 Personal Access Token 登录\n以管理仓库和执行 Git 操作',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Token 输入
            TextField(
              controller: _tokenController,
              obscureText: _obscureToken,
              decoration: InputDecoration(
                labelText: 'Personal Access Token',
                hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureToken ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                ),
                border: const OutlineInputBorder(),
              ),
              maxLines: 1,
            ),

            const SizedBox(height: 12),

            // 如何获取 Token 指引
            TextButton.icon(
              icon: const Icon(Icons.help_outline, size: 16),
              label: const Text('如何获取 Personal Access Token？'),
              onPressed: () => _showTokenGuide(),
            ),

            const SizedBox(height: 24),

            // 登录按钮
            FilledButton.icon(
              onPressed: authState.isLoading ? null : _login,
              icon: authState.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(authState.isLoading ? '验证中...' : '登录'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 16),

            // 跳过
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('稍后再说'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTokenGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('如何获取 Token'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. 访问 github.com/settings/tokens'),
            SizedBox(height: 8),
            Text('2. 点击 "Generate new token (classic)"'),
            SizedBox(height: 8),
            Text('3. 选择以下权限范围：'),
            SizedBox(height: 4),
            Text('   - repo (完整仓库控制)'),
            Text('   - workflow (GitHub Actions)'),
            Text('   - read:user (用户信息)'),
            SizedBox(height: 8),
            Text('4. 点击 "Generate token"'),
            SizedBox(height: 8),
            Text('5. 复制生成的 Token 并粘贴到上方'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
