/// ====================================================================
/// 网络质量检测器
///
/// 收集网络环境信息，用于智能选择下载策略：
///   - DNS 可用性
///   - 延迟估算
///   - 带宽估算
///   - 运营商/区域检测
///   - 网络类型（Wi-Fi / 移动数据）
///
/// 设计参考 Firecrawl 的 engine quality scoring 机制。
/// ====================================================================
library;

import 'dart:io';

/// 网络质量等级
enum NetworkQuality {
  /// 优秀（Wi-Fi 强信号，低延迟）
  excellent,

  /// 良好
  good,

  /// 一般（移动数据，中等延迟）
  fair,

  /// 差（高延迟，可能丢包）
  poor,

  /// 未知
  unknown,
}

/// 网络类型
enum NetworkType {
  wifi,
  mobile,
  ethernet,
  unknown,
}

/// 网络环境摘要
class NetworkProfile {
  final bool dnsWorking;
  final NetworkQuality quality;
  final NetworkType type;
  final int latencyMs;
  final int? estimatedBandwidthKbps;
  final String? systemDns;
  final String? localIp;
  final String? carrier;
  final String? region;
  final DateTime timestamp;

  const NetworkProfile({
    required this.dnsWorking,
    this.quality = NetworkQuality.unknown,
    this.type = NetworkType.unknown,
    this.latencyMs = 0,
    this.estimatedBandwidthKbps,
    this.systemDns,
    this.localIp,
    this.carrier,
    this.region,
    required this.timestamp,
  });

  /// 是否需要降级下载策略
  bool get needsDegradation =>
      !dnsWorking || quality == NetworkQuality.poor;

  /// 推荐的最大并发下载数
  int get recommendedConcurrency => switch (quality) {
    NetworkQuality.excellent => 4,
    NetworkQuality.good => 3,
    NetworkQuality.fair => 2,
    NetworkQuality.poor => 1,
    NetworkQuality.unknown => 2,
  };
}

/// 网络性能分析器
class NetworkProfiler {
  /// 探测目标
  static const _latencyTargets = [
    '1.1.1.1',      // Cloudflare DNS（IP 直连，不依赖 DNS）
    '8.8.8.8',      // Google DNS
  ];

  /// 收集完整的网络信息
  static Future<NetworkProfile> profile() async {
    final start = DateTime.now();

    // DNS 可用性
    final dnsWorking = await _checkDnsAvailability();

    // 延迟测试
    final latency = await _measureLatency();

    // 网络类型
    final type = await _detectNetworkType();

    // DNS 服务器
    final dnsServer = await _getSystemDnsServer();

    // 本地 IP
    final localIp = await _getLocalIp();

    return NetworkProfile(
      dnsWorking: dnsWorking,
      quality: _classifyQuality(latency),
      type: type,
      latencyMs: latency,
      systemDns: dnsServer,
      localIp: localIp,
      timestamp: start,
    );
  }

  /// DNS 可用性检测（使用 IP 直连的 HTTP 探测）
  static Future<bool> _checkDnsAvailability() async {
    // 用 IP 直连检测网络本身是否正常
    final ipDirectOk = await _checkHttp('https://1.1.1.1');
    if (!ipDirectOk) return false; // 网络本身不可用

    // 尝试解析域名
    try {
      final result = await Process.run(
        'ping',
        ['-c', '1', '-W', '2', 'github.com'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 延迟测量（取两个目标的最小值）
  static Future<int> _measureLatency() async {
    int minLatency = 9999;

    for (final target in _latencyTargets) {
      try {
        final result = await Process.run(
          'ping',
          ['-c', '1', '-W', '2', target],
          runInShell: true,
        );
        if (result.exitCode == 0) {
          // 从输出中提取延迟
          final stdout = result.stdout as String;
          final timeMatch = RegExp(r'time[=<]\s*(\d+\.?\d*)\s*ms').firstMatch(stdout);
          if (timeMatch != null) {
            final time = double.parse(timeMatch.group(1)!);
            if (time.toInt() < minLatency) {
              minLatency = time.toInt();
            }
          } else {
            minLatency = 0; // ping 成功但无法提取时间
          }
        }
      } catch (_) {}
    }

    return minLatency == 9999 ? -1 : minLatency;
  }

  /// 检测网络类型（Wi-Fi / 移动数据）
  static Future<NetworkType> _detectNetworkType() async {
    try {
      // 检查 Wi-Fi
      final wifiResult = await Process.run(
        'cmd', ['wifi', 'get-connection-info'],
        runInShell: true,
      );
      if (wifiResult.exitCode == 0) {
        final stdout = wifiResult.stdout as String;
        if (stdout.contains('WifiInfo') || stdout.contains('SSID')) {
          return NetworkType.wifi;
        }
      }
    } catch (_) {}

    try {
      // 检查是否有默认路由
      final routeResult = await Process.run(
        'ip', ['route', 'show', 'default'],
        runInShell: true,
      );
      if (routeResult.exitCode == 0) {
        final route = (routeResult.stdout as String).toLowerCase();
        if (route.contains('wlan')) return NetworkType.wifi;
        if (route.contains('rmnet') || route.contains('ccmni')) {
          return NetworkType.mobile;
        }
      }
    } catch (_) {}

    return NetworkType.unknown;
  }

  /// 获取系统 DNS 服务器
  static Future<String?> _getSystemDnsServer() async {
    try {
      final result = await Process.run('getprop', ['net.dns1'], runInShell: true);
      if (result.exitCode == 0) {
        final dns = (result.stdout as String).trim();
        if (dns.isNotEmpty) return dns;
      }
    } catch (_) {}

    try {
      final result = await Process.run('getprop', ['net.dns2'], runInShell: true);
      if (result.exitCode == 0) {
        final dns = (result.stdout as String).trim();
        if (dns.isNotEmpty) return dns;
      }
    } catch (_) {}

    return null;
  }

  /// 获取本地 IP
  static Future<String?> _getLocalIp() async {
    try {
      final result = await Process.run('ip', ['route', 'show', 'default'], runInShell: true);
      if (result.exitCode == 0) {
        final devMatch = RegExp(r'dev\s+(\S+)').firstMatch(result.stdout as String);
        if (devMatch != null) {
          final dev = devMatch.group(1)!;
          final ipResult = await Process.run('ip', ['addr', 'show', dev], runInShell: true);
          if (ipResult.exitCode == 0) {
            final ipMatch = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)')
                .firstMatch(ipResult.stdout as String);
            return ipMatch?.group(1);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// HTTP 连通性检测
  static Future<bool> _checkHttp(String url) async {
    try {
      final result = await Process.run(
        'curl',
        ['-s', '-o', '/dev/null', '-w', '%{http_code}', '--max-time', '3', url],
        runInShell: true,
      );
      if (result.exitCode != 0) return false;
      final codeStr = (result.stdout as String).trim();
      final code = int.tryParse(codeStr);
      return code != null && code >= 200 && code < 400;
    } catch (_) {
      return false;
    }
  }

  /// 根据延迟分类网络质量
  static NetworkQuality _classifyQuality(int latencyMs) {
    if (latencyMs < 0) return NetworkQuality.unknown;
    if (latencyMs < 50) return NetworkQuality.excellent;
    if (latencyMs < 150) return NetworkQuality.good;
    if (latencyMs < 500) return NetworkQuality.fair;
    return NetworkQuality.poor;
  }

  /// 快速检测网络是否可用（< 2s）
  static Future<bool> quickHealthCheck() async {
    try {
      // 先 IP 直连检测（不依赖 DNS）
      final result = await Process.run(
        'curl',
        ['-s', '-o', '/dev/null', '-w', '%{http_code}', '--max-time', '2',
         'https://1.1.1.1'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final code = int.tryParse((result.stdout as String).trim());
        return code != null && code >= 200 && code < 400;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
