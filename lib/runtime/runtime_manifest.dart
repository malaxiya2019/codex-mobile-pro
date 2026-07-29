/// ====================================================================
/// Runtime 安装清单
///
/// 定义每个 Runtime 工具需要下载的 artifact 列表，
/// 包括下载 URL、SHA256、大小、依赖的共享库和提取方式。
///
/// 数据来源：Termux package mirror (packages.termux.dev)
/// 验证方式：SHA256 来自 Termux Packages 元数据
/// ====================================================================

import 'runtime_dependency.dart';

/// Artifact 类型
enum ArtifactType {
  /// .deb 包（Termux 包格式，包含 ar + tar.xz）
  deb,

  /// npm 包 (通过 node npm install)
  npm,
}

/// 单个下载 artifact
class RuntimeArtifact {
  /// 显示名称
  final String name;

  /// Artifact 类型
  final ArtifactType type;

  /// 下载 URL
  final String url;

  /// SHA256 哈希值（十六进制字符串）
  final String sha256;

  /// 文件大小（字节）
  final int size;

  /// 提取后需要放入的目标子目录（相对 runtime 根目录）
  final String targetSubDir;

  /// 需要从 tar 中提取的文件路径模式
  /// 如果为空，则提取所有文件
  final List<String>? includeFiles;

  /// 提取时要 strip 的路径组件数
  final int stripComponents;

  const RuntimeArtifact({
    required this.name,
    required this.type,
    required this.url,
    required this.sha256,
    required this.size,
    this.targetSubDir = '',
    this.includeFiles,
    this.stripComponents = 5,
  });
}

/// Runtime 工具的安装清单
class RuntimeManifest {
  final RuntimeTool tool;
  final String displayName;
  final String version;
  final List<RuntimeArtifact> artifacts;

  const RuntimeManifest({
    required this.tool,
    required this.displayName,
    required this.version,
    required this.artifacts,
  });

  /// Node.js 安装清单
  static const RuntimeManifest node = RuntimeManifest(
    tool: RuntimeTool.node,
    displayName: 'Node.js',
    version: '26.4.0',
    artifacts: [
      // 主程序 (node binary)
      RuntimeArtifact(
        name: 'nodejs',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/n/nodejs/nodejs_26.4.0_aarch64.deb',
        sha256: 'f2b8530d6d7ae72ee560d2791686f1849df9644396d56da915b31cd42c50a62d',
        size: 10343796,
        includeFiles: ['usr/bin/node'],
      ),
      // npm
      RuntimeArtifact(
        name: 'npm',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/n/npm/npm_11.18.0_all.deb',
        sha256: '08f7aaf7e821f9974a68544cdb501b07ade0a3f21a32437b5efbc94a581e086e',
        size: 2020684,
        includeFiles: ['usr/bin/npm', 'usr/bin/npx', 'usr/lib/node_modules/npm'],
      ),
      // libc++ (libc++_shared.so)
      RuntimeArtifact(
        name: 'libc++',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/libc/libc%2B%2B/libc%2B%2B_29_aarch64.deb',
        sha256: 'bb9f12113c137aa0e8513bb51cc49fe77a5ce3ca39ab9e92c57d228ecdf00222',
        size: 334828,
        includeFiles: ['usr/lib/libc++_shared.so'],
      ),
      // OpenSSL (libcrypto.so.3, libssl.so.3)
      RuntimeArtifact(
        name: 'openssl',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/o/openssl/openssl_1%3A3.6.3_aarch64.deb',
        sha256: '86760e9ce736f463236f2c15b1eb3a3fdcfc5778d0fd7077a917448dcc90f3aa',
        size: 2478376,
        includeFiles: ['usr/lib/libcrypto.so.3', 'usr/lib/libssl.so.3'],
      ),
      // ICU (libicudata.so.78, libicui18n.so.78, libicuuc.so.78)
      RuntimeArtifact(
        name: 'libicu',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/libi/libicu/libicu_78.3_aarch64.deb',
        sha256: 'f536403f65a08fe0df6e7304184e902d54def77d5c3bd5edfd9109d57601d276',
        size: 10210396,
        includeFiles: ['usr/lib/libicudata.so.78', 'usr/lib/libicui18n.so.78', 'usr/lib/libicuuc.so.78'],
      ),
      // libsqlite
      RuntimeArtifact(
        name: 'libsqlite',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/libs/libsqlite/libsqlite_3.53.4_aarch64.deb',
        sha256: '0e909ce0d50fe123305446cd22e0c5edf535d40344b9b065fbdcdee52f53198d',
        size: 759764,
        includeFiles: ['usr/lib/libsqlite3.so'],
      ),
      // libffi
      RuntimeArtifact(
        name: 'libffi',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/libf/libffi/libffi_3.5.2_aarch64.deb',
        sha256: '8c8c1d6ffb049d8496a21c1202d9b4dc9145140886fdbb45716684565f4ed3f5',
        size: 31128,
        includeFiles: ['usr/lib/libffi.so'],
      ),
      // c-ares
      RuntimeArtifact(
        name: 'c-ares',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/c/c-ares/c-ares_1.34.8_aarch64.deb',
        sha256: '7681fc23e822d7988ba8b2adf3468f93ae68f724dda365cff1385096a9fa87e6',
        size: 194924,
        includeFiles: ['usr/lib/libcares.so'],
      ),
      // zlib
      RuntimeArtifact(
        name: 'zlib',
        type: ArtifactType.deb,
        url: 'https://packages.termux.dev/apt/termux-main/pool/main/z/zlib/zlib_1.3.2_aarch64.deb',
        sha256: '75e7d0af17fcc3b40004309fdc00a1ddb9ae08346dce5e269902c34ac3966ac9',
        size: 62840,
        includeFiles: ['usr/lib/libz.so.1'],
      ),
    ],
  );

  /// 获取指定工具的安装清单
  static RuntimeManifest? forTool(RuntimeTool tool) {
    switch (tool) {
      case RuntimeTool.node:
        return node;
      default:
        return null; // Git/Python 等暂未实现
    }
  }

  /// 是否支持自动安装
  static bool isSupported(RuntimeTool tool) {
    return forTool(tool) != null;
  }
}
