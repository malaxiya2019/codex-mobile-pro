---
name: firecrawl-patterns
description: 参考 Firecrawl 高性能爬虫系统架构模式来优化 codex-mobile-pro。使用场景：DNS 缓存与网络检测优化、多引擎 fallback 安装策略、结构化错误处理、镜像切换与备用下载源。当用户提到 Firecrawl、引擎降级、DNS 问题、安装失败、网络检测时触发。
---

# Firecrawl 架构模式

## 快速参考

遇到以下问题时，参考对应的 reference 文件：

| 问题 | 参考 |
|:---|:---|
| DNS 解析失败、网络检测慢 | [DNS 缓存模式](references/dns-caching.md) |
| 安装器只有一个方案、失败后无降级 | [多引擎 Fallback](references/engine-architecture.md) |
| 错误信息模糊、用户不知道怎么处理 | [结构化错误处理](references/error-handling.md) |
| 下载源被墙、域名解析失败 | [镜像切换策略](references/mirror-resolver.md) |
| 性能瓶颈、考虑原生加速 | [FFI 性能参考](references/native-ffi.md) |

## 核心原则

1. **先缓存后请求** — 所有网络操作（DNS、HTTP 检测）先查缓存，减少重复延迟
2. **多策略降级** — 每个目标（安装、检测）有多个方案，按 quality 排序，失败自动降级
3. **错误结构化** — 错误信息包含 code、userMessage、suggestions 三段，用户能按建议操作
4. **镜像优先** — 所有外网 URL 配置备用镜像，DNS 故障时自动切换

## 与 Firecrawl 的对照

Firecrawl 原始设计集中在 `apps/api/src/scraper/scrapeURL/engines/index.ts`（引擎调度）和 `apps/api/native/src/`（原生模块）。codex-mobile-pro 借鉴的是**设计模式**而非代码本身。

### 当前已落地

- ✅ `NetworkDetector.quickCheck()` — 安装前 DNS 预检
- ✅ `deploy_provider.dart` — 安装前网络预检 + 阻塞安装
- ✅ `InstallProgress` 流 — 安装进度通知

### 待优化（参考对应 reference）

- ⬜ DNS 缓存 → 见 `references/dns-caching.md`
- ⬜ 多引擎 InstallStrategy → 见 `references/engine-architecture.md`
- ⬜ 结构化 InstallError → 见 `references/error-handling.md`
- ⬜ MirrorResolver → 见 `references/mirror-resolver.md`
- ⬜ Flutter FFI 加速 → 见 `references/native-ffi.md`

## 关键源文件映射

| codex-mobile-pro 文件 | 对应 Firecrawl 参考 |
|:---|:---|
| `lib/core/detector/detectors/network_detector.dart` | `cacheableLookup.ts` + `dns.test.ts` |
| `lib/runtime/runtime_manager.dart` | `engines/index.ts` 的 `buildFallbackList()` |
| `lib/runtime/runtime_installer.dart` | `engines/index.ts` 的 `EngineScrapeResult` |
| `lib/runtime/runtime_manifest.dart` | 无直接对应（Firecrawl 无 manifest 概念） |
| `lib/runtime/ubuntu_runtime_installer.dart` | 无直接对应（移动端特有） |
