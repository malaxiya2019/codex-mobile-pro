/// ====================================================================
/// 增强型 DNS 缓存
///
/// 相比当前 network_detector.dart 中的 DnsCache 类，新增：
///   1. 文件持久化：跨会话保留 DNS 解析结果
///   2. TTL 跟随 DNS 记录（最小 30s，最大 1h）
///   3. 缓存统计：命中率、有效条目数
///   4. 网络切换自动失效
///
/// 缓存层级：
///   L1: 内存缓存（最快，当前会话）
///   L2: 文件缓存（跨会话，应用重启后加载）
/// ====================================================================
library;

import 'dart:convert';
import 'dart:io';

/// DNS 缓存条目
class DnsCacheEntry {
  final String host;
  final String? ip;
  final bool resolved;
  final DateTime timestamp;
  final int ttlSeconds; // DNS 记录的原始 TTL，最小 30s

  const DnsCacheEntry({
    required this.host,
    this.ip,
    required this.resolved,
    required this.timestamp,
    this.ttlSeconds = 30,
  });

  /// 是否已过期
  bool get isExpired {
    final age = DateTime.now().difference(timestamp);
    final effectiveTtl = ttlSeconds < 30 ? 30 : (ttlSeconds > 3600 ? 3600 : ttlSeconds);
    return age.inSeconds > effectiveTtl;
  }

  /// 剩余有效秒数
  int get remainingSeconds {
    final age = DateTime.now().difference(timestamp).inSeconds;
    final effectiveTtl = ttlSeconds < 30 ? 30 : (ttlSeconds > 3600 ? 3600 : ttlSeconds);
    return (effectiveTtl - age).clamp(0, effectiveTtl);
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'ip': ip,
    'resolved': resolved,
    'timestamp': timestamp.toIso8601String(),
    'ttl': ttlSeconds,
  };

  factory DnsCacheEntry.fromJson(Map<String, dynamic> json) => DnsCacheEntry(
    host: json['host'],
    ip: json['ip'],
    resolved: json['resolved'],
    timestamp: DateTime.parse(json['timestamp']),
    ttlSeconds: json['ttl'] ?? 30,
  );
}

/// DNS 缓存管理器
class DnsCache {
  // ─── L1: 内存缓存 ─────────────────────────────────────────────
  static final Map<String, DnsCacheEntry> _memoryCache = {};

  // ─── 统计 ───────────────────────────────────────────────────────
  static int hits = 0;
  static int misses = 0;
  static int fileLoads = 0;
  static int fileSaves = 0;

  /// 缓存文件路径（需在应用启动时设置）
  static String? _cacheFilePath;
  static bool _initialized = false;

  /// 初始化缓存（从文件加载）
  static Future<void> initialize(String appFilesDir) async {
    if (_initialized) return;
    _cacheFilePath = '$appFilesDir/.dns_cache.json';
    await _loadFromFile();
    _initialized = true;
  }

  /// 检查域名缓存是否命中且未过期
  static bool isHostCached(String host) {
    final entry = _memoryCache[host];
    if (entry == null) return false;
    if (entry.isExpired) {
      _memoryCache.remove(host);
      return false;
    }
    return entry.resolved;
  }

  /// 从缓存获取解析结果
  static DnsCacheEntry? get(String host) {
    final entry = _memoryCache[host];
    if (entry == null) {
      misses++;
      return null;
    }
    if (entry.isExpired) {
      _memoryCache.remove(host);
      misses++;
      return null;
    }
    hits++;
    return entry;
  }

  /// 记录 DNS 解析结果
  static void recordResult({
    required String host,
    required bool resolved,
    String? ip,
    int ttlSeconds = 30,
  }) {
    final entry = DnsCacheEntry(
      host: host,
      ip: ip,
      resolved: resolved,
      timestamp: DateTime.now(),
      ttlSeconds: ttlSeconds,
    );
    _memoryCache[host] = entry;
  }

  /// 清空全部缓存（网络切换时调用）
  static Future<void> invalidate() async {
    _memoryCache.clear();
    hits = 0;
    misses = 0;
    // 同时清空文件缓存
    if (_cacheFilePath != null) {
      try {
        final file = File(_cacheFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  /// 持久化缓存到文件
  static Future<void> persist() async {
    if (_cacheFilePath == null) return;
    try {
      final entries = _memoryCache.values
          .where((e) => !e.isExpired && e.resolved) // 只保存成功的
          .map((e) => e.toJson())
          .toList();
      final json = jsonEncode(entries);
      await File(_cacheFilePath!).writeAsString(json);
      fileSaves++;
    } catch (_) {
      // 持久化失败不阻塞业务
    }
  }

  /// 从文件加载缓存
  static Future<void> _loadFromFile() async {
    if (_cacheFilePath == null) return;
    try {
      final file = File(_cacheFilePath!);
      if (!await file.exists()) return;
      final json = await file.readAsString();
      final list = jsonDecode(json) as List<dynamic>;
      for (final item in list) {
        final entry = DnsCacheEntry.fromJson(item as Map<String, dynamic>);
        if (!entry.isExpired && entry.resolved) {
          _memoryCache[entry.host] = entry;
          fileLoads++;
        }
      }
    } catch (_) {
      // 加载失败不阻塞
    }
  }

  // ─── 统计 ───────────────────────────────────────────────────────

  /// 命中率
  static double get hitRate {
    final total = hits + misses;
    if (total == 0) return 0;
    return hits / total;
  }

  /// 缓存条目数
  static int get entryCount => _memoryCache.length;
  static int get validCount =>
      _memoryCache.values.where((e) => e.resolved && !e.isExpired).length;

  /// 缓存摘要
  static String get summary {
    return 'DNS 缓存：$validCount个有效 / $entryCount个总计 | '
        '命中率 ${(hitRate * 100).toStringAsFixed(0)}% | '
        '文件加载 $fileLoads / 保存 $fileSaves';
  }
}
