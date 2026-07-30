/// ====================================================================
/// Runtime 安装清单
///
/// 定义每个 Runtime 工具需要下载的 artifact 列表，
/// 包括下载 URL、SHA256、大小、依赖的共享库和提取方式。
///
/// 多镜像支持（P1）：
///   每个 artifact 可携带备用镜像 URL 列表。
///   MirrorRegistry 提供已知的 Termux / GitHub 镜像变换规则。
///   下载时按 主源→镜像→IP直连 顺序尝试。
///
/// 设计参考 Firecrawl 的 engine fallback + feature matching 模式。
/// ====================================================================
library;

import 'runtime_dependency.dart';

// ====================================================================
// 镜像源定义
// ====================================================================

/// 镜像源描述
class MirrorSource {
  /// 完整 URL（与 artifact.url 格式一致）
  final String url;

  /// 区域标签（'cn' = 中国大陆, 'global' = 全球, '' = 通用）
  final String region;

  /// 优先级（越大越优先尝试，主源隐含 priority=100）
  final int priority;

  /// 是否需要 DNS 解析才能访问
  final bool requiresDns;

  const MirrorSource({
    required this.url,
    this.region = '',
    this.priority = 50,
    this.requiresDns = true,
  });
}

// ====================================================================
// Artifact 类型
// ====================================================================

/// Artifact 类型
enum ArtifactType {
  /// .deb 包（Termux 包格式，包含 ar + tar.xz）
  deb,

  /// npm 包 (通过 node npm install)
  npm,

  /// rootfs tar.xz（如 Ubuntu rootfs）
  rootfs,

  /// proot loader 二进制（通过 .deb 提取）
  proot,
}

// ====================================================================
// 单个下载 artifact
// ====================================================================

/// 单个下载 artifact
class RuntimeArtifact {
  /// 显示名称
  final String name;

  /// Artifact 类型
  final ArtifactType type;

  /// 主下载 URL
  final String url;

  /// SHA256 哈希值（十六进制字符串）
  final String sha256;

  /// 文件大小（字节）
  final int size;

  /// 备用镜像源（P1 新增）
  final List<MirrorSource> mirrors;

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
    this.mirrors = const [],
    this.targetSubDir = '',
    this.includeFiles,
    this.stripComponents = 6,
  });

  /// 构建有序的下载 URL 列表：主源 → 镜像 → IP直连占位
  ///
  /// [dnsWorking] 当前 DNS 是否可用
  /// [region]     区域偏好（如 'cn' 优先使用国内镜像）
  List<String> buildUrlFallbackChain({
    bool dnsWorking = true,
    String region = '',
  }) {
    final urls = <String>[];

    // 1. 主源（优先级 100）
    if (!dnsWorking) {
      // DNS 不可用时，跳过需要 DNS 的 URL
      // 主源通常需要 DNS，但保留第一个尝试机会
    }
    urls.add(url);

    // 2. 镜像（按优先级降序）
    final sortedMirrors = List<MirrorSource>.from(mirrors)
      ..sort((a, b) => b.priority.compareTo(a.priority));

    // 区域匹配的镜像优先
    final regionMirrors = sortedMirrors.where((m) =>
      m.region.isNotEmpty && region.isNotEmpty && m.region == region);
    final otherMirrors = sortedMirrors.where((m) =>
      m.region.isEmpty || region.isEmpty || m.region != region);

    for (final mirror in [...regionMirrors, ...otherMirrors]) {
      if (!dnsWorking && mirror.requiresDns) continue; // DNS 挂了就跳过
      if (!urls.contains(mirror.url)) {
        urls.add(mirror.url);
      }
    }

    return urls;
  }
}

// ====================================================================
// 镜像注册表
// ====================================================================

/// 已知镜像源注册表
///
/// 用于自动为 artifact URL 生成备用镜像。
/// 每个镜像入口定义域名替换规则，避免为每个 artifact 手动写镜像 URL。
class MirrorRegistry {
  MirrorRegistry._();

  /// 镜像替换规则
  ///
  /// key  = 原始域名（完整，含端口）
  /// value = 镜像配置列表
  static const Map<String, List<_MirrorRule>> _rules = {
    'packages.termux.dev': [
      // 国内教育网镜像
      _MirrorRule(
        mirrorHost: 'mirrors.tuna.tsinghua.edu.cn',
        pathPrefix: '/termux',
        region: 'cn',
        priority: 80,
      ),
      _MirrorRule(
        mirrorHost: 'mirrors.ustc.edu.cn',
        pathPrefix: '/termux',
        region: 'cn',
        priority: 75,
      ),
      _MirrorRule(
        mirrorHost: 'mirrors.bfsu.edu.cn',
        pathPrefix: '/termux',
        region: 'cn',
        priority: 70,
      ),
      // 社区镜像（无须 DNS 也可用 IP 访问）
      _MirrorRule(
        mirrorHost: 'termux.ivanon.dev',
        pathPrefix: '',
        region: 'global',
        priority: 40,
      ),
    ],
    'github.com': [
      // GitHub 代理（注意这些代理服务可能不稳定）
      _MirrorRule(
        mirrorHost: 'ghproxy.com',
        pathPrefix: '/https://github.com',
        region: 'cn',
        priority: 60,
      ),
      _MirrorRule(
        mirrorHost: 'mirror.ghproxy.com',
        pathPrefix: '/https://github.com',
        region: 'cn',
        priority: 55,
      ),
    ],
    'raw.githubusercontent.com': [
      _MirrorRule(
        mirrorHost: 'ghproxy.com',
        pathPrefix: '/https://raw.githubusercontent.com',
        region: 'cn',
        priority: 60,
      ),
      _MirrorRule(
        mirrorHost: 'mirror.ghproxy.com',
        pathPrefix: '/https://raw.githubusercontent.com',
        region: 'cn',
        priority: 55,
      ),
    ],
    'objects.githubusercontent.com': [
      // GitHub release assets 走同样的代理
      _MirrorRule(
        mirrorHost: 'ghproxy.com',
        pathPrefix: '/https://objects.githubusercontent.com',
        region: 'cn',
        priority: 50,
      ),
    ],
  };

  /// 为给定 URL 生成备用镜像
  ///
  /// 如果该 URL 的域名有注册的镜像规则，返回镜像 MirrorSource 列表；
  /// 否则返回空列表。
  static List<MirrorSource> mirrorsFor(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      final rules = _rules[host];
      if (rules == null || rules.isEmpty) return [];

      return rules.map((rule) {
        // 镜像 URL = scheme + mirrorHost + pathPrefix + 原路径
        final newPath = '${rule.pathPrefix}${uri.path}';
        final query = uri.query.isEmpty ? '' : '?${uri.query}';
        final mirrorUrl = '${uri.scheme}://${rule.mirrorHost}$newPath$query';

        return MirrorSource(
          url: mirrorUrl,
          region: rule.region,
          priority: rule.priority,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取所有已注册的域名
  static List<String> get registeredHosts => _rules.keys.toList();

  /// 获取所有已知镜像数量
  static int get mirrorCount =>
      _rules.values.fold(0, (sum, list) => sum + list.length);

  /// 可读摘要
  static String get summary {
    final buf = StringBuffer('镜像注册表：\n');
    for (final entry in _rules.entries) {
      buf.writeln('  ${entry.key}:');
      for (final rule in entry.value) {
        buf.writeln('    → ${rule.mirrorHost} (${rule.region}, pri=${rule.priority})');
      }
    }
    buf.write('共 ${_rules.length} 个域名，$mirrorCount 个镜像');
    return buf.toString();
  }
}

/// 镜像替换规则（内部）
class _MirrorRule {
  final String mirrorHost;
  final String pathPrefix;
  final String region;
  final int priority;

  const _MirrorRule({
    required this.mirrorHost,
    required this.pathPrefix,
    required this.region,
    required this.priority,
  });
}

// ====================================================================
// 安装清单
// ====================================================================

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
  ///
  /// 每个 artifact 通过 MirrorRegistry.mirrorsFor(url) 自动附加镜像源，
  /// 无须手动编写镜像 URL。
  static RuntimeManifest get node => _buildNodeManifest();
  static RuntimeManifest get ubuntu => _buildUbuntuManifest();

  /// 构建 Node.js 清单
  static RuntimeManifest _buildNodeManifest() {
    return RuntimeManifest(
      tool: RuntimeTool.node,
      displayName: 'Node.js',
      version: '26.4.0',
      artifacts: [
        RuntimeArtifact(
          name: 'nodejs',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/n/nodejs/nodejs_26.4.0_aarch64.deb',
          sha256: 'f2b8530d6d7ae72ee560d2791686f1849df9644396d56da915b31cd42c50a62d',
          size: 10343796,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/n/nodejs/nodejs_26.4.0_aarch64.deb'),
          includeFiles: ['usr/bin/node'],
        ),
        RuntimeArtifact(
          name: 'npm',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/n/npm/npm_11.18.0_all.deb',
          sha256: '08f7aaf7e821f9974a68544cdb501b07ade0a3f21a32437b5efbc94a581e086e',
          size: 2020684,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/n/npm/npm_11.18.0_all.deb'),
          includeFiles: ['usr/bin/npm', 'usr/bin/npx', 'usr/lib/node_modules/npm'],
        ),
        RuntimeArtifact(
          name: 'libc++',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/libc/libc%2B%2B/libc%2B%2B_29_aarch64.deb',
          sha256: 'bb9f12113c137aa0e8513bb51cc49fe77a5ce3ca39ab9e92c57d228ecdf00222',
          size: 334828,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/libc/libc%2B%2B/libc%2B%2B_29_aarch64.deb'),
          includeFiles: ['usr/lib/libc++_shared.so'],
        ),
        RuntimeArtifact(
          name: 'openssl',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/o/openssl/openssl_1%3A3.6.3_aarch64.deb',
          sha256: '86760e9ce736f463236f2c15b1eb3a3fdcfc5778d0fd7077a917448dcc90f3aa',
          size: 2478376,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/o/openssl/openssl_1%3A3.6.3_aarch64.deb'),
          includeFiles: ['usr/lib/libcrypto.so.3', 'usr/lib/libssl.so.3'],
        ),
        RuntimeArtifact(
          name: 'libicu',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/libi/libicu/libicu_78.3_aarch64.deb',
          sha256: 'f536403f65a08fe0df6e7304184e902d54def77d5c3bd5edfd9109d57601d276',
          size: 10210396,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/libi/libicu/libicu_78.3_aarch64.deb'),
          includeFiles: ['usr/lib/libicudata.so.78', 'usr/lib/libicui18n.so.78', 'usr/lib/libicuuc.so.78'],
        ),
        RuntimeArtifact(
          name: 'libsqlite',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/libs/libsqlite/libsqlite_3.53.4_aarch64.deb',
          sha256: '0e909ce0d50fe123305446cd22e0c5edf535d40344b9b065fbdcdee52f53198d',
          size: 759764,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/libs/libsqlite/libsqlite_3.53.4_aarch64.deb'),
          includeFiles: ['usr/lib/libsqlite3.so'],
        ),
        RuntimeArtifact(
          name: 'libffi',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/libf/libffi/libffi_3.5.2_aarch64.deb',
          sha256: '8c8c1d6ffb049d8496a21c1202d9b4dc9145140886fdbb45716684565f4ed3f5',
          size: 31128,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/libf/libffi/libffi_3.5.2_aarch64.deb'),
          includeFiles: ['usr/lib/libffi.so'],
        ),
        RuntimeArtifact(
          name: 'c-ares',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/c/c-ares/c-ares_1.34.8_aarch64.deb',
          sha256: '7681fc23e822d7988ba8b2adf3468f93ae68f724dda365cff1385096a9fa87e6',
          size: 194924,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/c/c-ares/c-ares_1.34.8_aarch64.deb'),
          includeFiles: ['usr/lib/libcares.so'],
        ),
        RuntimeArtifact(
          name: 'zlib',
          type: ArtifactType.deb,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/z/zlib/zlib_1.3.2_aarch64.deb',
          sha256: '75e7d0af17fcc3b40004309fdc00a1ddb9ae08346dce5e269902c34ac3966ac9',
          size: 62840,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/z/zlib/zlib_1.3.2_aarch64.deb'),
          includeFiles: ['usr/lib/libz.so.1'],
        ),
      ],
    );
  }

  /// 构建 Ubuntu 安装清单
  static RuntimeManifest _buildUbuntuManifest() {
    return RuntimeManifest(
      tool: RuntimeTool.ubuntu,
      displayName: 'Ubuntu Runtime',
      version: '24.04',
      artifacts: [
        // ─── rootfs ───
        RuntimeArtifact(
          name: 'ubuntu-rootfs',
          type: ArtifactType.rootfs,
          url: 'https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-aarch64-pd-v4.18.0.tar.xz',
          sha256: '91acaa786b8e2fbba56a9fd0f8a1188cee482b5c7baeed707b29ddaa9a294daa',
          size: 64133552,
          mirrors: MirrorRegistry.mirrorsFor('https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-aarch64-pd-v4.18.0.tar.xz'),
          targetSubDir: 'ubuntu/rootfs',
          stripComponents: 1,
        ),
        // ─── proot loader 包 ───
        RuntimeArtifact(
          name: 'proot',
          type: ArtifactType.proot,
          url: 'https://packages.termux.dev/apt/termux-main/pool/main/p/proot/proot_5.1.107.89_aarch64.deb',
          sha256: 'ec9fe38c50cfd49dd31fe360ffbcc3124a945dc1ea16293a8a769303dd724f46',
          size: 95784,
          mirrors: MirrorRegistry.mirrorsFor('https://packages.termux.dev/apt/termux-main/pool/main/p/proot/proot_5.1.107.89_aarch64.deb'),
          targetSubDir: 'ubuntu/bin',
          includeFiles: [
            'usr/bin/proot',
            'usr/libexec/proot/loader',
            'usr/libexec/proot/loader32',
          ],
        ),
      ],
    );
  }

  /// 获取指定工具的安装清单
  static RuntimeManifest? forTool(RuntimeTool tool) {
    switch (tool) {
      case RuntimeTool.node:
        return node;
      case RuntimeTool.ubuntu:
        return ubuntu;
      default:
        return null;
    }
  }

  /// 是否支持自动安装
  static bool isSupported(RuntimeTool tool) {
    return forTool(tool) != null;
  }
}
