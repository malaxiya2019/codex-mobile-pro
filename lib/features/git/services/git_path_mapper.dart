/// ====================================================================
/// Android 宿主路径 ↔ Ubuntu PRoot guest 路径映射
///
/// git 运行在 PRoot（Ubuntu rootfs）内，只能访问 guest 视角的路径。
/// Android 宿主路径（如 /storage/emulated/0）需通过 PRoot bind
/// 挂载进 guest，并映射为 guest 路径才能被 git 访问。
///
/// 映射规则：
///   - /storage/emulated/0        → /sdcard
///   - /storage/emulated/0/xxx    → /sdcard/xxx
///   - 其他绝对路径（/data/... 等）→ 原样（同名 bind）
///
/// 纯 Dart，无 Flutter 依赖，便于单元测试。
/// ====================================================================
library;

/// 宿主↔guest 路径映射工具
class GitPathMapper {
  /// Android 公共存储宿主根
  static const String hostStorageRoot = '/storage/emulated/0';

  /// guest（PRoot）内对应挂载点
  static const String guestStorageRoot = '/sdcard';

  GitPathMapper._();

  /// host → guest 路径
  ///
  /// 例：/storage/emulated/0/foo → /sdcard/foo
  /// 其他路径（/data/data/...）原样返回。
  static String hostToGuest(String hostPath) {
    if (hostPath == hostStorageRoot) return guestStorageRoot;
    if (hostPath.startsWith('$hostStorageRoot/')) {
      return '$guestStorageRoot/${hostPath.substring(hostStorageRoot.length + 1)}';
    }
    return hostPath;
  }

  /// guest → host 路径（反向映射，供 UI 展示）
  ///
  /// 例：/sdcard/foo → /storage/emulated/0/foo
  static String guestToHost(String guestPath) {
    if (guestPath == guestStorageRoot) return hostStorageRoot;
    if (guestPath.startsWith('$guestStorageRoot/')) {
      return '$hostStorageRoot/${guestPath.substring(guestStorageRoot.length + 1)}';
    }
    return guestPath;
  }

  /// 为宿主路径生成 PRoot bind 参数对（完整 `-b` 形式）
  ///
  /// 返回 PRoot `-b` 参数对，例如：
  ///   /storage/emulated/0/foo → ['-b', '/storage/emulated/0:/sdcard']
  ///   /data/data/&lt;pkg&gt;/... → ['-b', '/data/data/&lt;pkg&gt;/...']
  ///
  /// 注意：`extraBinds` 通道（LinuxExecutionAdapter 会为每个元素自动加
  /// `-b`）应使用 [bindPath]，而不是本方法，否则会产生重复 `-b`。
  static List<String> bindArguments(String hostPath) => ['-b', bindPath(hostPath)];

  /// 返回纯 bind 串（无 `-b` 前缀），供 `RuntimeProcessRequest.extraBinds`
  /// 使用——LinuxExecutionAdapter 会为每个元素自动生成 `-b <bind>`。
  ///
  /// 例如：
  ///   /storage/emulated/0/foo → '/storage/emulated/0:/sdcard'
  ///   /data/data/&lt;pkg&gt;/... → '/data/data/&lt;pkg&gt;/...'
  static String bindPath(String hostPath) {
    if (hostPath == hostStorageRoot ||
        hostPath.startsWith('$hostStorageRoot/')) {
      return '$hostStorageRoot:$guestStorageRoot';
    }
    return hostPath;
  }

  /// 判断路径是否属于 Android 宿主（需要 bind 映射进 guest）
  static bool isHostPath(String path) {
    return path.startsWith('/storage/') ||
        path.startsWith('/data/') ||
        path.startsWith('/sdcard');
  }
}
