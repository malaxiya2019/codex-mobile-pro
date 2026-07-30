// ====================================================================
// 网络连通性检测器
//
// 检测 DNS 解析和 HTTP 连通性，在安装前预判网络是否可用。
// 使用系统命令而非 dart:io HttpClient 以避免缓存/复用问题。
//
// 整合了多层 DNS 解析器 (DnsResolver) 作为 fallback:
//   L1 内存缓存 → 系统 DNS → DNS-over-HTTPS → IP 硬编码
//
// 含增强型 DNS 缓存 (DnsCache)，跨会话持久化。
// ====================================================================

import 'dart:io';

import '../../network/dns_cache.dart';
import '../../network/dns_resolver.dart';
import '../../network/network_profiler.dart';
import '../detection_result.dart';
import '../detector.dart';

/// 网络检测结果汇总
class NetworkCheckResult {
  final bool dnsWorking;
  final bool internetReachable;
  final bool ipDirectWorking; // IP 直连是否可用（DNS 无关）
  final List<DnsResolution> dnsResults;
  final List<HttpConnectResult> httpResults;
  final String? dnsServer;
  final String? localIp;
  final NetworkQuality quality;

  const NetworkCheckResult({
    required this.dnsWorking,
    required this.internetReachable,
    this.ipDirectWorking = false,
    this.dnsResults = const [],
    this.httpResults = const [],
    this.dnsServer,
    this.localIp,
    this.quality = NetworkQuality.unknown,
  });

  /// 用户友好的摘要
  String get summary {
    if (ipDirectWorking && !dnsWorking) return '网络可达但 DNS 解析失败';
    if (dnsWorking && internetReachable) return '网络正常';
    if (!dnsWorking) return 'DNS 解析失败';
    if (!internetReachable) return '网络不可达';
    return '网络异常';
  }

  /// 可操作的建议（更详细）
  String get suggestion {
    if (dnsWorking && internetReachable) return '';

    final buf = StringBuffer();

    if (!dnsWorking) {
      if (ipDirectWorking) {
        buf.writeln('⚠️ DNS 解析失败，但 IP 直连可用。');
        buf.writeln('部署中心已自动启用 IP 直连模式，可继续下载。');
        buf.writeln('如遇下载慢，建议：');
      } else {
        buf.writeln('❌ 域名解析和 IP 直连均不可用。');
        buf.writeln('建议：');
      }

      buf.writeln('① 切换 Wi-Fi ↔ 移动数据');
      buf.writeln('② 开关飞行模式后重试');
      buf.writeln('③ 配置公共 DNS：8.8.8.8 / 1.1.1.1');
      buf.writeln('④ 检查 VPN/代理是否正确设置');
    } else if (!internetReachable) {
      buf.writeln('❌ 网络不可达。');
      buf.writeln('建议：');
      buf.writeln('① 检查网络连接是否正常');
      buf.writeln('② 检查是否需要登录 WiFi 门户');
      buf.writeln('③ 尝试开启/关闭 VPN');
    }

    return buf.toString();
  }
}

/// HTTP 连通性结果
class HttpConnectResult {
  final String url;
  final bool reachable;
  final int? statusCode;
  final int durationMs;
  final String? error;

  const HttpConnectResult({
    required this.url,
    required this.reachable,
    this.statusCode,
    this.durationMs = 0,
    this.error,
  });
}

/// 网络检测器
class NetworkDetector extends Detector {
  @override
  String get id => 'network';
  @override
  String get name => '网络连通性';
  @override
  String get icon => '📡';
  @override
  DetectorCategory get category => DetectorCategory.runtime;
  @override
  RuntimeSubCategory? get subCategory => RuntimeSubCategory.basic;

  /// 检测目标主机列表
  static const _dnsTargets = [
    'github.com',
    'packages.termux.dev',
    'api.github.com',
  ];

  /// HTTP 检测目标（DNS 正常时用）
  static const _httpTargets = [
    'https://github.com',
    'https://packages.termux.dev',
  ];

  @override
  Future<DetectionResult> detect() async {
    final start = DateTime.now();

    try {
      final checkResult = await _checkNetwork();

      final elapsed = DateTime.now().difference(start).inMilliseconds;

      // 全部正常 → installed 状态
      if (checkResult.dnsWorking && checkResult.internetReachable) {
        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.installed,
          version: checkResult.dnsServer != null
              ? 'DNS ${checkResult.dnsServer}'
              : '网络正常',
          path: checkResult.localIp,
          durationMs: elapsed,
          category: category,
        );
      }

      // DNS 失败但 IP 直连可用 → warning 但不阻止安装
      if (!checkResult.dnsWorking && checkResult.ipDirectWorking) {
        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.installed,
          version: 'IP 直连模式',
          path: checkResult.localIp,
          durationMs: elapsed,
          category: category,
          missingHint: 'DNS 故障，已启用 IP 直连，下载可能变慢',
        );
      }

      // DNS 失败 → failed 状态，带详细指引
      if (!checkResult.dnsWorking) {
        return DetectionResult(
          id: id,
          name: name,
          icon: icon,
          status: DetectionStatus.failed,
          errorMessage: checkResult.summary,
          durationMs: elapsed,
          category: category,
          missingHint: checkResult.suggestion,
        );
      }

      // 网络不可达
      return DetectionResult(
        id: id,
        name: name,
        icon: icon,
        status: DetectionStatus.error,
        errorMessage: checkResult.summary,
        durationMs: elapsed,
        category: category,
        missingHint: checkResult.suggestion,
      );
    } catch (e) {
      return DetectionResult(
        id: id,
        name: name,
        icon: icon,
        status: DetectionStatus.error,
        errorMessage: '检测网络时出错: $e',
        durationMs: DateTime.now().difference(start).inMilliseconds,
        category: category,
        missingHint: '请检查网络连接后重试',
      );
    }
  }

  /// 执行完整的网络检查
  static Future<NetworkCheckResult> _checkNetwork() async {
    final dnsResults = <DnsResolution>[];
    final httpResults = <HttpConnectResult>[];
    int dnsOk = 0;

    // ─── 0. IP 直连检测（独立于 DNS） ──────────────────────────
    final ipDirectOk = await _checkHttpDirect('https://1.1.1.1');

    // ─── 1. 获取 DNS 服务器 ──────────────────────────────────────
    final dnsServer = await DnsResolver.getSystemDnsServer();

    // ─── 2. 获取本地 IP ──────────────────────────────────────────
    final localIp = await NetworkProfiler.profile().then((p) => p.localIp);

    // ─── 3. DNS 解析测试（多层 fallback） ────────────────────────
    for (final host in _dnsTargets) {
      // 先走缓存
      if (DnsCache.isHostCached(host)) {
        final cached = DnsCache.get(host);
        if (cached != null) {
          dnsOk++;
          dnsResults.add(DnsResolution(
            host: host,
            ip: cached.ip ?? '(cached)',
            resolved: true,
            resolverName: 'L1-cache',
          ));
          continue;
        }
      }

      // 多层 DNS 解析
      final result = await DnsResolver.resolve(
        host,
      );
      dnsResults.add(result);
      if (result.resolved) dnsOk++;
    }

    final dnsWorking = dnsOk >= 1; // 至少一个域名能解析

    // ─── 4. HTTP 连通性测试 ──────────────────────────────────────
    int httpOk = 0;
    for (final url in _httpTargets) {
      final result = await _checkHttp(url);
      httpResults.add(result);
      if (result.reachable) httpOk++;
    }

    // 网络可达性：DNS 解析成功 ≥1 且 HTTP 成功 ≥1，或者 IP 直连成功
    final internetReachable = (dnsWorking && httpOk >= 1) || ipDirectOk;

    // 获取网络质量
    final quality = await _estimateNetworkQuality(ipDirectOk);

    return NetworkCheckResult(
      dnsWorking: dnsWorking,
      internetReachable: internetReachable,
      ipDirectWorking: ipDirectOk,
      dnsResults: dnsResults,
      httpResults: httpResults,
      dnsServer: dnsServer,
      localIp: localIp,
      quality: quality,
    );
  }

  /// HTTP 连通性测试 — 使用系统 cURL
  static Future<HttpConnectResult> _checkHttp(String url) async {
    final start = DateTime.now();

    try {
      final result = await Process.run(
        'curl',
        ['-s', '-o', '/dev/null', '-w', '%{http_code}', '--max-time', '5', url],
        runInShell: true,
      );

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final codeStr = (result.stdout as String).trim();
      final code = int.tryParse(codeStr);

      final reachable = result.exitCode == 0 &&
          code != null && code >= 200 && code < 400;

      return HttpConnectResult(
        url: url,
        reachable: reachable,
        statusCode: code,
        durationMs: elapsed,
      );
    } catch (e) {
      return HttpConnectResult(
        url: url,
        reachable: false,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        error: e.toString(),
      );
    }
  }

  /// IP 直连 HTTP 检测（绕过 DNS，用 IP 直接访问）
  static Future<bool> _checkHttpDirect(String url) async {
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

  /// 估算网络质量
  static Future<NetworkQuality> _estimateNetworkQuality(bool ipDirectOk) async {
    if (!ipDirectOk) return NetworkQuality.poor;

    // ping 两个 DNS 服务器测延迟
    int totalLatency = 0;
    int samples = 0;

    for (final target in ['1.1.1.1', '8.8.8.8']) {
      try {
        final start = DateTime.now();
        final result = await Process.run(
          'ping', ['-c', '1', '-W', '2', target],
          runInShell: true,
        );
        if (result.exitCode == 0) {
          totalLatency += DateTime.now().difference(start).inMilliseconds;
          samples++;
        }
      } catch (_) {}
    }

    if (samples == 0) return NetworkQuality.unknown;

    final avgLatency = totalLatency ~/ samples;
    if (avgLatency < 100) return NetworkQuality.excellent;
    if (avgLatency < 300) return NetworkQuality.good;
    if (avgLatency < 800) return NetworkQuality.fair;
    return NetworkQuality.poor;
  }

  /// 获取当前系统 DNS 服务器（兼容旧接口）
  static Future<String?> _getDnsServer() {
    return DnsResolver.getSystemDnsServer();
  }

  /// 快速网络检查（用于安装前预检）
  ///
  /// 返回 true 表示网络可用，false 表示不可用。
  /// 使用多层 DNS 解析器，优先缓存。
  static Future<bool> quickCheck() async {
    // ─── 先查缓存 ───
    if (DnsCache.isHostCached('github.com')) return true;

    // ─── 多层解析 ───
    final result = await DnsResolver.resolve(
      'github.com',
    );
    return result.resolved;
  }

  /// 深度网络检查（尝试所有方式）
  static Future<NetworkCheckResult> deepCheck() async {
    return await _checkNetwork();
  }
}
