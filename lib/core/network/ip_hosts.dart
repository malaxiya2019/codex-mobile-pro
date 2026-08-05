/// ====================================================================
/// 关键域名 IP 硬编码映射
///
/// 当系统 DNS 和 DNS-over-HTTPS 都失败时，使用这些预存 IP 直连。
/// 这些 IP 可能随时间变化，需定期更新。
///
/// 更新方式：运行 `dig +short github.com` 或 `nslookup github.com`
/// ====================================================================
library;

/// 硬编码的域名→IP 映射
class IpHosts {
  IpHosts._();

  /// 主映射表：域名 → 候选 IP 列表（按优先级排序）
  static const Map<String, List<String>> _entries = {
    'github.com': [
      '140.82.112.4', // lb-140-82-112-4-fra.github.com
      '140.82.112.3', // lb-140-82-112-3-fra.github.com
      '20.205.243.166', // github.com (Singapore)
    ],
    'api.github.com': [
      '140.82.112.10', // api.github.com
      '140.82.112.9',
    ],
    'packages.termux.dev': [
      '188.114.96.0', // packages.termux.dev (Cloudflare)
      '188.114.97.0',
    ],
    'raw.githubusercontent.com': [
      '185.199.108.133', // Fastly
      '185.199.109.133',
      '185.199.110.133',
      '185.199.111.133',
    ],
    'objects.githubusercontent.com': [
      '185.199.108.133', // GitHub Assets (Fastly)
      '185.199.109.133',
      '185.199.110.133',
      '185.199.111.133',
    ],
    'codeload.github.com': [
      '140.82.112.9', // codeload.github.com
    ],
    '1.1.1.1': [
      '1.1.1.1', // Cloudflare DNS (自身就是 IP)
    ],
    'dns.google': [
      '8.8.8.8', // Google DNS
      '8.8.4.4',
    ],
  };

  /// 域名列表（用于遍历检测）
  static List<String> get allHosts => _entries.keys.toList();

  /// 获取域名的首选 IP
  static String? primaryIp(String host) {
    final ips = _entries[host];
    if (ips == null || ips.isEmpty) return null;
    return ips.first;
  }

  /// 获取域名的所有候选 IP
  static List<String> ipsFor(String host) {
    return _entries[host] ?? [];
  }

  static int get _knownHostCount => _entries.length;
}
