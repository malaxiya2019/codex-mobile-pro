// ====================================================================
// 网络连通性检测器
//
// 检测 DNS 解析和 HTTP 连通性，在安装前预判网络是否可用。
// 使用系统命令而非 dart:io HttpClient 以避免缓存/复用问题。
// ====================================================================

import 'dart:io';

import '../detection_result.dart';
import '../detector.dart';

/// DNS 解析结果
class DnsResult {
  final String host;
  final bool resolved;
  final String? ip;
  final int durationMs;

  const DnsResult({
    required this.host,
    required this.resolved,
    this.ip,
    this.durationMs = 0,
  });
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

/// 网络检测结果汇总
class NetworkCheckResult {
  final bool dnsWorking;
  final bool internetReachable;
  final List<DnsResult> dnsResults;
  final List<HttpConnectResult> httpResults;
  final String? dnsServer;
  final String? localIp;

  const NetworkCheckResult({
    required this.dnsWorking,
    required this.internetReachable,
    this.dnsResults = const [],
    this.httpResults = const [],
    this.dnsServer,
    this.localIp,
  });

  /// 用户友好的摘要
  String get summary {
    if (dnsWorking && internetReachable) return '网络正常';
    if (!dnsWorking) return 'DNS 解析失败';
    if (!internetReachable) return '网络不可达';
    return '网络异常';
  }

  /// 可操作的建议
  String get suggestion {
    if (dnsWorking && internetReachable) return '';
    if (!dnsWorking) {
      return 'DNS 解析失败，建议：\n'
          '① 切换 Wi-Fi ↔ 移动数据\n'
          '② 开关飞行模式后重试\n'
          '③ 配置公共 DNS：8.8.8.8 / 1.1.1.1';
    }
    if (!internetReachable) {
      return '网络不可达，建议检查网络连接后重试';
    }
    return '请检查网络连接';
  }
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

  /// HTTP 检测目标
  static const _httpTargets = [
    'https://github.com',
    'https://packages.termux.dev',
    'https://1.1.1.1', // 通过 IP 直连验证网络（绕过 DNS）
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
    final dnsResults = <DnsResult>[];
    final httpResults = <HttpConnectResult>[];
    int dnsOk = 0;

    // 1. 获取 DNS 服务器
    final dnsServer = await _getDnsServer();

    // 2. 获取本地 IP
    final localIp = await _getLocalIp();

    // 3. DNS 解析测试
    for (final host in _dnsTargets) {
      final result = await _resolveDns(host);
      dnsResults.add(result);
      if (result.resolved) dnsOk++;
    }

    final dnsWorking = dnsOk >= 1; // 至少一个域名能解析

    // 4. HTTP 连通性测试（只有 DNS 正常时才测）
    int httpOk = 0;
    if (dnsWorking) {
      for (final url in _httpTargets) {
        // 跳过 IP 直连的 HTTP 检测，减少延迟
        if (url.contains('1.1.1.1')) continue;

        final result = await _checkHttp(url);
        httpResults.add(result);
        if (result.reachable) httpOk++;
      }
    }

    final internetReachable = dnsWorking && httpOk >= 1;

    // 5. 尝试 IP 直连测试（即使 DNS 挂了）
    if (!dnsWorking) {
      final ipResult = await _checkHttp('https://1.1.1.1');
      httpResults.add(ipResult);
    }

    return NetworkCheckResult(
      dnsWorking: dnsWorking,
      internetReachable: internetReachable,
      dnsResults: dnsResults,
      httpResults: httpResults,
      dnsServer: dnsServer,
      localIp: localIp,
    );
  }

  /// DNS 解析测试 — 使用系统 ping
  static Future<DnsResult> _resolveDns(String host) async {
    final start = DateTime.now();

    try {
      final result = await Process.run(
        'ping',
        ['-c', '1', '-W', '3', host],
        runInShell: true,
      );

      final elapsed = DateTime.now().difference(start).inMilliseconds;

      if (result.exitCode == 0) {
        // 从输出中提取 IP
        final stdout = result.stdout as String;
        final ipMatch = RegExp(r'PING\s+\S+\s+\(([^)]+)\)').firstMatch(stdout);
        final ip = ipMatch?.group(1);

        return DnsResult(
          host: host,
          resolved: true,
          ip: ip,
          durationMs: elapsed,
        );
      }

      return DnsResult(
        host: host,
        resolved: false,
        durationMs: elapsed,
      );
    } catch (e) {
      return DnsResult(
        host: host,
        resolved: false,
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
    }
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

      // HTTP 2xx/3xx 算成功
      final reachable = result.exitCode == 0 &&
          code != null &&
          code >= 200 &&
          code < 400;

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

  /// 获取系统 DNS 服务器
  static Future<String?> _getDnsServer() async {
    try {
      final result = await Process.run(
        'getprop',
        ['net.dns1'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final dns = (result.stdout as String).trim();
        if (dns.isNotEmpty) return dns;
      }
    } catch (_) {}

    try {
      final result = await Process.run(
        'getprop',
        ['net.dns2'],
        runInShell: true,
      );
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
      final result = await Process.run(
        'ip',
        ['route', 'show', 'default'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        final devMatch = RegExp(r'dev\s+(\S+)').firstMatch(stdout);
        if (devMatch != null) {
          final dev = devMatch.group(1)!;
          final ipResult = await Process.run(
            'ip',
            ['addr', 'show', dev],
            runInShell: true,
          );
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

  /// 执行快速网络检查（用于安装前预检）
  ///
  /// 返回 true 表示网络可用，false 表示不可用。
  /// 比完整 detect() 更快，只检查 DNS。
  static Future<bool> quickCheck() async {
    try {
      final result = await Process.run(
        'ping',
        ['-c', '1', '-W', '3', 'github.com'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
