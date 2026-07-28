# 📊 Sprint 0 — Milestone 0.5：性能基线 v1.0

> **建立时间：** 2026-07-28
> **基线版本：** v1.0
> **用途：** 后续每个 Sprint 的性能对比基准

---

## 1. 基线指标总览

### 1.1 目标值

| 类别 | 指标 | 目标值 | 测量方法 |
|------|------|-------|---------|
| **🚀 启动** | 冷启动时间 | < 3 秒 | `adb shell am start -W` |
| **🚀 启动** | 热启动时间 | < 1 秒 | `adb shell input keyevent HOME` → 重启动 |
| **💾 内存** | 空闲内存占用 | < 80 MB | `adb shell dumpsys meminfo` |
| **💾 内存** | AI 对话峰值 | < 150 MB | 连续 20 轮对话后测量 |
| **⚡ CPU** | 空闲 CPU 占用 | < 5% | `adb shell top` |
| **⚡ CPU** | AI 对话时 CPU | < 30% | 流式输出期间测量 |
| **🤖 AI** | 首 Token 延迟 | < 3 秒 | `curl` 流式首 chunk 到达时间 |
| **🤖 AI** | 平均响应时间 | < 10 秒 | 完整请求/响应耗时 |
| **🤖 AI** | 50 次请求成功率 | ≥ 99% | 连续 50 次调用 |
| **🔋 电池** | 连续 30 分钟耗电 | < 5% | Android BatteryManager API |

### 1.2 测试环境

| 项目 | 说明 |
|------|------|
| **设备型号** | 待填写（建议：Pixel 6 / 小米 13 / 三星 S23+） |
| **Android 版本** | 待填写（建议：Android 13–15） |
| **Termux 版本** | 待填写（`termux-info` 输出） |
| **网络环境** | 待填写（WiFi / 5G / 4G） |
| **DeepSeek 模型** | `deepseek-chat` |
| **mimo2codex 版本** | 待填写 |
| **测试日期** | 2026-07-28 |

---

## 2. 测量工具

### 2.1 性能打点基础设施

| 文件 | 说明 |
|------|------|
| `lib/core/performance/performance_tracker.dart` | Dart 端性能打点（启动/页面/AI 延迟） |
| `lib/core/performance/performance_provider.dart` | Riverpod Provider 封装 |
| `scripts/benchmark/measure_startup.sh` | ADB 冷/热启动时间测量脚本 |
| `scripts/benchmark/measure_memory.sh` | ADB 内存/CPU 占用测量脚本 |
| `scripts/benchmark/measure_ai_latency.sh` | AI 请求延迟测量脚本（curl） |

### 2.2 使用方式

```bash
# 1. 启动时间测量（5 次冷+热启动）
bash scripts/benchmark/measure_startup.sh 5

# 2. 内存/CPU 占用
bash scripts/benchmark/measure_memory.sh

# 3. AI 请求延迟（10 次）
bash scripts/benchmark/measure_ai_latency.sh 10
```

### 2.3 Dart 端集成

`PerformanceTracker.instance` 在以下时机自动打点：

| 事件 | 触发位置 | 时机 |
|------|---------|------|
| `app_start` | `main()` | 入口函数第一行 |
| `app_ready` | `CodexMobileApp.initState()` | 首帧渲染完成 |
| 页面加载 | 各页面 `initState` + `addPostFrameCallback` | 页面首次渲染 |
| AI 请求 | `AiService.chatStream()` | 请求发送/首 Token 到达/完成/失败 |

---

## 3. 基线数据采集表

> ⚠️ **以下数据需在真实 Android 设备上运行后填写。**
> 当前环境（Termux Android）无法直接运行 Flutter App，
> 请在开发机上连接真机后运行测量脚本。

### 3.1 启动性能

| 测试次数 | 冷启动 (ms) | 热启动 (ms) | 备注 |
|---------|------------|------------|------|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| **平均** | | | |
| **最小** | | | |
| **最大** | | | |

### 3.2 内存占用

| 状态 | PSS Total (KB) | Native Heap (KB) | Dalvik Heap (KB) | 备注 |
|------|---------------|-----------------|-----------------|------|
| 空闲（后台） | | | | |
| 首页显示 | | | | |
| AI 对话 | | | | |
| 部署中心 | | | | |
| 多页面切换 | | | | 切换 5 页后 |

### 3.3 CPU 占用

| 状态 | CPU % | 备注 |
|------|-------|------|
| 空闲（后台） | | |
| 首页显示 | | |
| AI 对话（空闲等待） | | |
| AI 对话（流式输出） | | |
| 页面切换动画 | | |

### 3.4 AI 请求延迟

| 测试次数 | 首 Token (ms) | 完整响应 (ms) | 成功? | 提示词 |
|---------|--------------|--------------|-------|--------|
| 1 | | | | "用一句话回答：1+1=?" |
| 2 | | | | "用一句话回答：1+1=?" |
| 3 | | | | "用一句话回答：1+1=?" |
| 4 | | | | "用一句话回答：1+1=?" |
| 5 | | | | "用一句话回答：1+1=?" |
| 6 | | | | "用一句话回答：1+1=?" |
| 7 | | | | "用一句话回答：1+1=?" |
| 8 | | | | "用一句话回答：1+1=?" |
| 9 | | | | "用一句话回答：1+1=?" |
| 10 | | | | "用一句话回答：1+1=?" |
| **平均** | | | | |
| **成功率** | | | **/10** | |

### 3.5 电池消耗

| 测试场景 | 持续时间 | 起始电量 | 结束电量 | 消耗 |
|---------|---------|---------|---------|------|
| AI 连续对话 | 30 分钟 | | | |
| 页面浏览 | 30 分钟 | | | |
| 空闲后台 | 30 分钟 | | | |

---

## 4. 性能阈值（硬性要求）

以下阈值后续 Sprint 中**禁止突破**：

| 指标 | 硬性阈值 | 说明 |
|------|---------|------|
| 冷启动时间 | > 5 秒 | 必须优化 |
| 空闲内存 | > 120 MB | 必须优化 |
| AI 请求成功率 | < 95% | 必须修复 |
| UI 卡顿 | 连续 3 帧 > 16ms | 必须优化 |
| 应用崩溃 | 任何场景 | 必须修复 |

---

## 5. 性能退化检查清单

每个 Sprint 完成后，对照以下清单检查：

- [ ] 冷启动时间 ≤ 基线值 × 1.2
- [ ] 热启动时间 ≤ 基线值 × 1.2
- [ ] 空闲内存 ≤ 基线值 + 20 MB
- [ ] AI 对话峰值内存 ≤ 基线值 + 30 MB
- [ ] AI 首 Token 延迟 ≤ 基线值 × 1.5
- [ ] AI 请求成功率 ≥ 99%
- [ ] 无新增崩溃
- [ ] 无 ANR (Application Not Responding)

---

## 6. 性能持续监控

### 6.1 CI 集成（后续 Sprint）

```yaml
# .github/workflows/benchmark.yml（计划中）
name: Performance Benchmark
on: [push]
jobs:
  benchmark:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
      - run: flutter build apk --debug
      - run: bash scripts/benchmark/measure_startup.sh 3
      - run: bash scripts/benchmark/measure_memory.sh
```

### 6.2 性能回归警报

当 CI 中发现以下情况时自动告警：

| 场景 | 告警级别 |
|------|---------|
| 冷启动退化 > 20% | ⚠️ Warning |
| 冷启动退化 > 50% | 🚫 Block |
| 空闲内存 > 120 MB | 🚫 Block |
| AI 成功率 < 95% | 🚫 Block |
| 出现 ANR | 🚫 Block |

---

## 7. 基线数据记录

### 7.1 首次基线填写

> **在开发机上连接真机后执行以下步骤：**

```bash
# 1. 构建 Debug APK
flutter build apk --debug

# 2. 安装到设备
adb install build/app/outputs/flutter-apk/app-debug.apk

# 3. 测量启动时间（5 次）
bash scripts/benchmark/measure_startup.sh 5

# 4. 测量内存/CPU
bash scripts/benchmark/measure_memory.sh

# 5. 确保代理运行后测 AI 延迟
bash scripts/benchmark/measure_ai_latency.sh 10

# 6. 将结果填入第 3 节表格
```

### 7.2 基线版本历史

| 版本 | 日期 | 设备 | Android | 备注 |
|------|------|------|---------|------|
| v1.0 | 2026-07-28 | TBD | TBD | Sprint 0 初始基线 |

---

## 8. 附录：性能优化建议

### 8.1 Flutter 性能最佳实践

- 使用 `const` 构造函数减少重建
- 避免 `Opacity` 使用 `AnimatedOpacity` 替代
- 列表使用 `ListView.builder` 而非 `ListView(children: [...])`
- 避免在 `build()` 中执行耗时操作
- 图片使用缓存和适当分辨率
- 使用 `RepaintBoundary` 隔离重绘区域

### 8.2 Riverpod 优化

- 使用 `ref.watch` 仅在需要时重建
- `StateNotifier` 状态更新避免全量重建
- 使用 `family` 修饰符参数化 Provider

### 8.3 AI 请求优化

- 连接复用（keep-alive）
- 增量渲染减少首 Token 延迟感知
- 响应缓存（相同问题重复请求）
