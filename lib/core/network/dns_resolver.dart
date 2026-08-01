/// ====================================================================
/// 多层 DNS 解析器
///
/// 解析策略链（依次尝试）：
///   1. L1 内存缓存（DnsCache）
///   2. 系统 DNS（ping / getprop）
///   3. DNS-over-HTTPS（Google / Cloudflare）
///   4. IP 硬编码（IpHosts）
///
/// 设计参考 Firecrawl 的 cacheable-lookup + engine fallback 模式。
/// ====================================================================
library;

import 'dart:convert';
import 'dart:io';

import 'dns_cache.dart';
import 'ip_hosts.dart';

/// DNS 解析结果
class DnsResolution {
  final String host;
  final String? ip;
  final bool resolved;
  final int durationMs;
  final String resolverName; // 哪个解析器成功的

  const DnsResolution({
    required this.host,
    this.ip,
    required this.resolved,
    this.durationMs = 0,
    this.resolverName = 'unknown',
  });
}

/// DNS 解析器统计
class DnsResolverStats {
  int systemOk = 0;
  int systemFail = 0;
  int dohOk = 0;
  int dohFail = 0;
  int ipHardcodeOk = 0;
  int cacheHit = 0;

  int get total => systemOk + systemFail + dohOk + dohFail + ipHardcodeOk + cacheHit;
  int get success => systemOk + dohOk + ipHardcodeOk + cacheHit;

  String get summary {
    return 'DNS 解析统计：'
        '缓存命中 $cacheHit | '
        '系统 DNS $systemOk成功/$systemFail失败 | '
        'DoH $dohOk成功/$dohFail失败 | '
        'IP硬编码 $ipHardcodeOk | '
        '成功率 ${success > 0 ? (success / total * 100).toStringAsFixed(0) : "N/A"}%';
  }
}

/// DNS 解析选项
class DnsResolveOptions {
  /// 超时时间（毫秒）
  final int timeoutMs;

  /// 是否允许 DoH fallback
  final bool allowDoh;

  /// 是否允许 IP 硬编码 fallback
  final bool allowIpHardcode;

  /// 是否写入缓存
  final bool writeCache;

  const DnsResolveOptions({
    this.timeoutMs = 3000,
    this.allowDoh = true,
    this.allowIpHardcode = true,
    this.writeCache = true,
  });

  static const DnsResolveOptions default_ = DnsResolveOptions();
  static const DnsResolveOptions quick = DnsResolveOptions(
    timeoutMs: 1000,
    allowDoh: false,
    allowIpHardcode: false,
    writeCache: false,
  );
  static const DnsResolveOptions deep = DnsResolveOptions(
    timeoutMs: 5000,
  );
}

/// 多层 DNS 解析器
class DnsResolver {
  /// 运行时统计
  static final DnsResolverStats stats = DnsResolverStats();

  /// DoH 端点
  static const _dohEndpoints = [
    'https://dns.google/resolve?name=HOST&type=A',       // Google DoH
    'https://cloudflare-dns.com/dns-query?name=HOST&type=A', // Cloudflare DoH
  ];

  /// 解析域名（多层 fallback）
  ///
  /// 返回解析结果，依次尝试：
  /// 1. L1 内存缓存
  /// 2. 系统 DNS（ping）
  /// 3. DNS-over-HTTPS
  /// 4. IP 硬编码
  static Future<DnsResolution> resolve(
    String host, {
    DnsResolveOptions options = DnsResolveOptions.default_,
  }) async {
    final start = DateTime.now();

    // ─── 步骤 1：L1 内存缓存 ─────────────────────────────────────
    final cached = DnsCache.get(host);
    if (cached != null && cached.resolved) {
      stats.cacheHit++;
      return DnsResolution(
        host: host,
        ip: cached.ip,
        resolved: true,
        resolverName: 'L1-cache',
      );
    }

    // ─── 步骤 2：系统 DNS ───────────────────────────────────────
    final systemResult = await _resolveSystemDns(host, timeoutMs: options.timeoutMs);
    if (systemResult.resolved) {
      stats.systemOk++;
      if (options.writeCache) {
        DnsCache.recordResult(
          host: host,
          resolved: true,
          ip: systemResult.ip,
        );
      }
      return systemResult;
    }
    stats.systemFail++;

    // ─── 步骤 3：DNS-over-HTTPS ────────────────────────────────
    if (options.allowDoh) {
      for (final endpoint in _dohEndpoints) {
        final dohResult = await _resolveDoh(host, endpoint, timeoutMs: options.timeoutMs);
        if (dohResult.resolved) {
          stats.dohOk++;
          if (options.writeCache) {
            DnsCache.recordResult(
              host: host,
              resolved: true,
              ip: dohResult.ip,
              ttlSeconds: 60, // DoH 结果用更长的缓存时间
            );
          }
          return dohResult;
        }
        stats.dohFail++;
      }
    }

    // ─── 步骤 4：IP 硬编码 ─────────────────────────────────────
    if (options.allowIpHardcode) {
      final ip = IpHosts.primaryIp(host);
      if (ip != null) {
        stats.ipHardcodeOk++;
        if (options.writeCache) {
          DnsCache.recordResult(
            host: host,
            resolved: true,
            ip: ip,
            ttlSeconds: 300, // 硬编码 IP 缓存 5 分钟
          );
        }
        return DnsResolution(
          host: host,
          ip: ip,
          resolved: true,
          durationMs: DateTime.now().difference(start).inMilliseconds,
          resolverName: 'ip-hardcode',
        );
      }
    }

    // ─── 全部失败 ─────────────────────────────────────────────
    if (options.writeCache) {
      DnsCache.recordResult(host: host, resolved: false);
    }
    return DnsResolution(
      host: host,
      resolved: false,
      durationMs: DateTime.now().difference(start).inMilliseconds,
      resolverName: 'all-failed',
    );
  }

  /// 使用系统 DNS 解析域名
  ///
  /// 优先 Dart 原生 `InternetAddress.lookup`（Android 上走系统
  /// resolver，返回真实 A/AAAA，无需依赖 ping 可用性）；
  /// 解析失败时降级到 `ping` 探测（Termux/部分 Android 可用）。
  ///
  /// 2026-08 真机修复背景：App 内 `Process.run('ping')` 在部分
  /// Android 版本受网络权限/ICMP 限制，导致系统 DNS 层误报失败，
  /// 而 Termux 的 curl 正常——两者行为差异是「App 内 3 个下载源
  /// 全失败、Termux 却能下载」的关键。
  static Future<DnsResolution> _resolveSystemDns(
    String host, {
    int timeoutMs = 3000,
  }) async {
    final start = DateTime.now();

    // ─── 首选：Dart 原生系统 DNS ───────────────────────────────
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(Duration(milliseconds: timeoutMs));
      if (addresses.isNotEmpty) {
        // 优先 IPv4，避免 IPv6 黑洞导致后续连接挂起
        InternetAddress? ipv4;
        for (final a in addresses) {
          if (a.type == InternetAddressType.IPv4) {
            ipv4 = a;
            break;
          }
        }
        final ip = (ipv4 ?? addresses.first).address;
        return DnsResolution(
          host: host,
          ip: ip,
          resolved: true,
          durationMs: DateTime.now().difference(start).inMilliseconds,
          resolverName: 'system-dns',
        );
      }
    } catch (_) {
      // 降级到 ping
    }

    // ─── 降级：ping 探测 ───────────────────────────────────────
    try {
      final result = await Process.run(
        'ping',
        ['-c', '1', '-W', '${(timeoutMs / 1000).ceil()}', host],
        runInShell: true,
      );

      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        final ipMatch = RegExp(r'PING\s+\S+\s+\(([^)]+)\)').firstMatch(stdout);
        final ip = ipMatch?.group(1);

        return DnsResolution(
          host: host,
          ip: ip ?? '(resolved)',
          resolved: true,
          durationMs: elapsed,
          resolverName: 'system-dns',
        );
      }

      return DnsResolution(
        host: host,
        resolved: false,
        durationMs: elapsed,
        resolverName: 'system-dns',
      );
    } catch (e) {
      return DnsResolution(
        host: host,
        resolved: false,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        resolverName: 'system-dns',
      );
    }
  }

  /// 使用 DNS-over-HTTPS 解析域名
  static Future<DnsResolution> _resolveDoh(
    String host,
    String endpoint, {
    int timeoutMs = 3000,
  }) async {
    final start = DateTime.now();
    final url = endpoint.replaceFirst('HOST', host);

    try {
      // 先检查 curl 是否可用
      final curlCheck = await Process.run('which', ['curl'], runInShell: true);
      if (curlCheck.exitCode != 0) {
        // curl 不可用，尝试 dart:io HttpClient
        return await _resolveDohDart(host, url, timeoutMs: timeoutMs);
      }

      final result = await Process.run(
        'curl',
        [
          '-s',
          '--max-time', '${(timeoutMs / 1000).ceil()}',
          '-H', 'accept: application/dns-json',
          url,
        ],
        runInShell: true,
      );

      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        try {
          final json = jsonDecode(stdout) as Map<String, dynamic>;
          final answers = json['Answer'] as List<dynamic>?;
          if (answers != null && answers.isNotEmpty) {
            for (final answer in answers) {
              final type = answer['type'] as int;
              if (type == 1 || type == 28) { // A or AAAA record
                final ip = answer['data'] as String;
                return DnsResolution(
                  host: host,
                  ip: ip,
                  resolved: true,
                  durationMs: elapsed,
                  resolverName: 'doh',
                );
              }
            }
          }
        } catch (_) {
          // JSON 解析失败，视为未解析
        }
      }

      return DnsResolution(
        host: host,
        resolved: false,
        durationMs: elapsed,
        resolverName: 'doh',
      );
    } catch (e) {
      return DnsResolution(
        host: host,
        resolved: false,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        resolverName: 'doh',
      );
    }
  }

  /// 使用 dart:io HttpClient 解析 DoH（无 curl 时备用）
  static Future<DnsResolution> _resolveDohDart(
    String host,
    String url, {
    int timeoutMs = 3000,
  }) async {
    final start = DateTime.now();

    try {
      final client = HttpClient()
        ..connectionTimeout = Duration(milliseconds: timeoutMs);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('accept', 'application/dns-json');
        final response = await request.close();

        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final answers = json['Answer'] as List<dynamic>?;
          if (answers != null && answers.isNotEmpty) {
            for (final answer in answers) {
              final type = answer['type'] as int;
              if (type == 1 || type == 28) {
                final ip = answer['data'] as String;
                return DnsResolution(
                  host: host,
                  ip: ip,
                  resolved: true,
                  durationMs: DateTime.now().difference(start).inMilliseconds,
                  resolverName: 'doh-dart',
                );
              }
            }
          }
        }

        return DnsResolution(
          host: host,
          resolved: false,
          durationMs: DateTime.now().difference(start).inMilliseconds,
          resolverName: 'doh-dart',
        );
      } finally {
        client.close();
      }
    } catch (e) {
      return DnsResolution(
        host: host,
        resolved: false,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        resolverName: 'doh-dart',
      );
    }
  }

  /// 快速检查（仅缓存 + ping，通常 < 1s）
  static Future<bool> quickCheck(String host) async {
    final result = await resolve(
      host,
      options: DnsResolveOptions.quick,
    );
    return result.resolved;
  }

  /// 深度检查（尝试所有解析器，通常 < 5s）
  static Future<bool> deepCheck(String host) async {
    final result = await resolve(
      host,
      options: DnsResolveOptions.deep,
    );
    return result.resolved;
  }

  /// 批量解析多个域名
  static Future<Map<String, DnsResolution>> resolveAll(
    List<String> hosts, {
    DnsResolveOptions options = DnsResolveOptions.default_,
  }) async {
    final results = <String, DnsResolution>{};
    for (final host in hosts) {
      results[host] = await resolve(host, options: options);
    }
    return results;
  }

  /// 获取当前系统 DNS 服务器
  static Future<String?> getSystemDnsServer() async {
    try {
      final result = await Process.run(
        'getprop', ['net.dns1'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final dns = (result.stdout as String).trim();
        if (dns.isNotEmpty) return dns;
      }
    } catch (_) {}

    try {
      final result = await Process.run(
        'getprop', ['net.dns2'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final dns = (result.stdout as String).trim();
        if (dns.isNotEmpty) return dns;
      }
    } catch (_) {}

    return null;
  }
}
