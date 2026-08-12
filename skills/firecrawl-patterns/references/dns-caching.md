# DNS 缓存模式

> 来源：Firecrawl `apps/api/src/scraper/scrapeURL/lib/cacheableLookup.ts`

## 模式描述

在内存中缓存 DNS 解析结果，避免每次网络请求重复查询 DNS。
开发环境不缓存（方便调试），生产环境自动缓存。

## 核心结构

```dart
/// DNS 缓存条目
class _DnsCacheEntry {
  final String host;
  final List<InternetAddress>? addresses;
  final DateTime timestamp;
  final bool resolved;
  
  bool get isExpired => 
    DateTime.now().difference(timestamp).inSeconds > _ttlSeconds;
}

class DnsCache {
  static const _ttlSeconds = 30; // 移动网络变化快，TTL 不宜太长
  static final _cache = <String, _DnsCacheEntry>{};
  
  /// 解析域名（带缓存）
  static Future<List<InternetAddress>?> lookup(String host) async {
    final existing = _cache[host];
    if (existing != null && !existing.isExpired) {
      return existing.addresses;
    }
    
    try {
      final addresses = await InternetAddress.lookup(host);
      _cache[host] = _DnsCacheEntry(
        host: host,
        addresses: addresses,
        timestamp: DateTime.now(),
        resolved: true,
      );
      return addresses;
    } on SocketException {
      _cache[host] = _DnsCacheEntry(
        host: host,
        timestamp: DateTime.now(),
        resolved: false,
      );
      return null;
    }
  }
  
  /// 快速检查 DNS 是否工作（30 秒内不再重复检测失败的域名）
  static Future<bool> quickCheck(String host) async {
    final existing = _cache[host];
    // 30 秒内刚失败过 → 直接返回 false，不重复 ping
    if (existing != null && !existing.resolved && !existing.isExpired) {
      return false;
    }
    final result = await lookup(host);
    return result != null && result.isNotEmpty;
  }
  
  /// 清空缓存（网络切换时调用）
  static void invalidate() => _cache.clear();
}
```

## 集成位置

- 在 `NetworkDetector` 中用 `DnsCache` 替代直接 ping
- `ping -c 1 -W 3` → `DnsCache.lookup(host)` + 超时后的 `InternetAddress.lookup`
- 网络切换事件（`connectivity_plus`）→ 调用 `DnsCache.invalidate()`

## 关键决策

| 参数 | 值 | 原因 |
|:---|:---|:---|
| TTL | 30s | 移动网络变化快，太长会导致 IP 过期 |
| 失败缓存 | 30s | 避免 DNS 挂了后反复重试，浪费用户时间 |
| 并发控制 | 不需要 | 单个用户在手机上不太可能并发大量 DNS 查询 |

## Firecrawl 原始实现

Firecrawl 使用 `cacheable-lookup` npm 包，它劫持 `https.globalAgent` 的 DNS 解析：
```typescript
// cacheableLookup.ts
import CacheableLookup from "cacheable-lookup";
import dns from "dns";
import { config } from "../../../config";

export const cacheableLookup =
  config.SENTRY_ENVIRONMENT === "dev"
    ? { lookup: dns.lookup, install: () => {} }
    : new CacheableLookup({});
```

Dart 没有 `globalAgent` 概念，所以用 `DnsCache` 类在应用层做缓存。
