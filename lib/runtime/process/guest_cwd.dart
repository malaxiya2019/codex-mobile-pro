/// Guest 工作目录规范化（纯 Dart，无 Flutter 依赖）
///
/// 背景：Terminal 默认使用 App 私有目录
/// （`/data/data/<package>/...`，host 路径）作为会话 cwd。该路径只存在于
/// Android host 侧，PRoot 虚拟化内（guest rootfs）不存在，直接作为
/// `-w` 参数会导致 PRoot 警告：
///   proot warning: can't chdir(...) in the guest rootfs: No such file or directory
///   默认工作目录回落到 "/"。
///
/// 规则：
///   - host 路径（/data/、/storage/、/sdcard 等）→ 回退 /root
///   - 相对路径 / 空 / null → 回退 /root
///   - 合法 guest 绝对路径（/root、/tmp、/home/...）→ 保留并去尾部斜杠
library;

/// 判断 host 侧路径前缀（Android host filesystem 专用根，guest rootfs 内不存在）。
const List<String> _kHostPathPrefixes = [
  '/data/',
  '/storage/',
  '/sdcard',
  '/system/',
  '/vendor/',
];

/// 将可能来自 host 的 cwd 规范化为 PRoot guest 内合法工作目录。
///
/// 返回路径恒为绝对路径且不以 `/` 结尾（`/` 除外）。
String normalizeGuestCwd(String? cwd) {
  final raw = cwd?.trim() ?? '';
  if (raw.isEmpty || !raw.startsWith('/')) {
    // 空 / 相对路径在 PRoot guest 内不可靠，回退到 rootfs 内 root 用户主目录
    return '/root';
  }

  final lower = raw.toLowerCase();
  for (final prefix in _kHostPathPrefixes) {
    if (lower.startsWith(prefix)) return '/root';
  }

  // 合法 guest 绝对路径：保留，但去除尾部斜杠避免 "//" 类重复。
  if (raw == '/') return '/';
  final trimmed = raw.replaceAll(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? '/' : trimmed;
}
