# 多引擎 Fallback 架构

> 来源：Firecrawl `apps/api/src/scraper/scrapeURL/engines/index.ts`

## 模式描述

同一功能接口下注册多个引擎实现，每个引擎有 `quality` 评分和 `features` 矩阵。
主调度器根据需求筛选引擎 → 按 quality 排序 → 逐个尝试 → 失败后自动 fallback。

## Firecrawl 原型

```typescript
// 引擎定义（简化）
type Engine = "fetch" | "fire-engine" | "playwright" | "pdf" | "document";

const engineOptions = {
  fetch:      { quality: 5,  features: { screenshot: false, pdf: false } },
  fireEngine: { quality: 50, features: { screenshot: true,  pdf: false } },
  pdf:        { quality: -20, features: { pdf: true } },
};

// 引擎选择：按 quality 降序 → 筛选 feature 匹配 → 逐个尝试
async function buildFallbackList(meta) {
  return engines
    .filter(e => e.features 满足 meta 需求)
    .sort((a, b) => b.quality - a.quality);
}
```

## codex-mobile-pro 适配

### InstallStrategy 接口

```dart
/// 安装引擎接口
abstract class InstallStrategy {
  /// 引擎唯一标识
  String get id;
  
  /// 优先级（100=最高，0=最低）
  int get quality;
  
  /// 支持的安装方式特征
  Set<InstallFeature> get features;
  
  /// 安装前预检（检查空间、架构、依赖等）
  Future<PrecheckResult> precheck(RuntimeTool tool);
  
  /// 执行安装
  Future<InstallResult> install(RuntimeTool tool, RuntimeEnvironment env);
}

/// 安装特征标志
enum InstallFeature {
  offline,        // 不需要网络（已有缓存）
  fast,           // 快速安装（<30s）
  reliable,       // 高成功率
  minimal,        // 占用空间小（<50MB）
  full,           // 完整安装（含所有功能）
}

/// 预检结果
class PrecheckResult {
  final bool canProceed;
  final String? reason;       // 不能安装的原因
  final String? spaceRequired;
  final List<String> warnings;
}
```

### 引擎注册示例（Node.js）

```dart
class NodeInstallStrategy implements InstallStrategy {
  @override
  String get id => 'node';
  
  /// Ubuntu apt 安装（quality: 100，需要 proot + 网络）
  static final ubuntuApt = _UbuntuAptStrategy();
  
  /// Termux .deb 安装（quality: 50，需要网络 + arm64）
  static final termuxDeb = _TermuxDebStrategy();
  
  /// 源码编译安装（quality: 10，需要 make + gcc，极慢但可靠）
  static final sourceBuild = _SourceBuildStrategy();
}

// 使用
final strategies = [
  ubuntuApt,    // quality=100 → 优先尝试
  termuxDeb,    // quality=50  → 降级方案
  sourceBuild,  // quality=10  → 兜底方案
];

for (final strategy in strategies.sortedByQuality()) {
  final precheck = await strategy.precheck(tool);
  if (!precheck.canProceed) continue;
  
  final result = await strategy.install(tool, env);
  if (result.success) return result;
  // 失败 → 自动尝试下一个
}
```

### 集成位置

- `RuntimeManager.installCodingRuntime()` 中嵌入引擎选择逻辑
- 每个 `RuntimeTool` 关联一组 `InstallStrategy`
- 当前优先用 `quality` 最高的策略，失败后自动降级

## 关键决策

| 设计点 | 决策 | 原因 |
|:---|:---|:---|
| quality 范围 | 0-100 | 简单，够用 |
| 失败后 | 自动降级到下一个可用引擎 | 用户无感知 |
| 预检失败 | 跳过该引擎，不报错 | 某个引擎不支持不意味着整体失败 |
| 全部失败 | 返回最后一个引擎的错误 | 用户需要知道为什么 |
