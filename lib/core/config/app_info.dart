/// 应用元信息
///
/// ⚠️ 与 pubspec.yaml 的 version 字段保持同步（当前 1.0.0+1）。
abstract class AppInfo {
  static const name = 'Codex Mobile Pro';
  static const version = '1.0.0';
  static const buildNumber = '1';
  static const versionLabel = '1.0.0+1';

  /// 仓库地址（GitHub）
  static const githubUrl = 'https://github.com/malaxiya2019/codex-mobile-pro';

  /// 开源许可说明（仓库未附带 LICENSE 文件，先声明 MIT）
  static const license = 'MIT License（详见仓库 README）';
}
