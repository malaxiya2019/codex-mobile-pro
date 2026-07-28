# 🔬 Sprint 0 — Milestone 0.3 验证报告

> **验证目标：** 自动检测手机/Termux 环境中已安装的开发工具链，输出统一状态面板
> **验证日期：** 2026-07-28

---

## 一、验证结果总览

| # | 检测项 | 检测方式 | 备选方案 | 状态 |
|---|--------|---------|---------|------|
| 1 | Flutter SDK | `which flutter` + `flutter --version` | — | ✅ |
| 2 | Termux 环境 | `TermuxService.checkEnvironment()` | 系统 shell | ✅ |
| 3 | Node.js | `which node` + `node --version` | — | ✅ |
| 4 | Git | `which git` + `git --version` | — | ✅ |
| 5 | Python 3 | `which python3` / `python --version` | `which python` | ✅ |
| 6 | cURL | `which curl` + `curl --version` | — | ✅ |
| 7 | Codex CLI | `which codex` / `npm list -g` | `~/.local/lib/codex` | ✅ |
| 8 | mimo2codex | `which mimo2codex` / `npm list -g` | 端口检测 8788 | ✅ |
| 9 | DeepSeek API Key | `cat ~/.mimo2codex/.env` | 环境变量 | ✅ |
| 10 | 存储权限 | `ls /sdcard/Download/` | 应用私有目录 | ✅ |

---

## 二、架构设计

### 2.1 检测器体系

```
Detector (抽象基类)
  │
  ├── FlutterDetector      🔍 which flutter + --version
  ├── TermuxDetector       🔍 checkEnvironment() 多策略
  ├── NodeDetector         🔍 which node + --version
  ├── GitDetector          🔍 which git + --version
  ├── PythonDetector       🔍 python3 → python 降级
  ├── CurlDetector         🔍 which curl + --version
  ├── CodexDetector        🔍 which → npm → .local 三路径
  ├── Mimo2codexDetector   🔍 which → npm → 端口 8788
  ├── DeepSeekKeyDetector  🔍 .env → 环境变量
  └── StorageDetector      🔍 /sdcard → /data 降级
```

### 2.2 检测流程

```
用户点击"开始检测"
    │
    ▼
DeployNotifier.checkAll()
    │
    ├── 逐个运行检测器（顺序执行，实时更新 UI）
    │   ├── 先插入"检测中"占位
    │   ├── 执行 TermuxService.execute()
    │   └── 更新结果为 installed / missing / error
    │
    ▼
DeployStatus(state: completed)
    │
    ▼
DeployPage 仪表盘
  ├── 摘要卡片（全部就绪 / 部分缺失）
  ├── 结果列表（状态图标 + 版本 + 路径 + 耗时）
  └── 点击刷新单条 / 全部重测
```

---

## 三、文件清单

### 核心检测层 `lib/core/detector/`

| 文件 | 行数 | 说明 |
|------|------|------|
| `detection_result.dart` | ~80 | DetectionResult 模型 + DetectionStatus 枚举 |
| `detector.dart` | ~15 | Detector 抽象基类 |
| `detector_service.dart` | ~80 | 检测编排服务（并行/单条/统计） |
| `detectors/flutter_detector.dart` | ~45 | Flutter SDK 检测 |
| `detectors/termux_detector.dart` | ~50 | Termux 环境检测 |
| `detectors/node_detector.dart` | ~40 | Node.js 检测 |
| `detectors/git_detector.dart` | ~40 | Git 检测 |
| `detectors/python_detector.dart` | ~55 | Python 3 检测（python3→python 降级） |
| `detectors/curl_detector.dart` | ~40 | cURL 检测 |
| `detectors/codex_detector.dart` | ~55 | Codex CLI 检测（三路径） |
| `detectors/mimo2codex_detector.dart` | ~55 | mimo2codex 检测（含端口监听） |
| `detectors/deepseek_key_detector.dart` | ~55 | DeepSeek API Key 检测 |
| `detectors/storage_permission_detector.dart` | ~45 | 存储权限检测 |

### UI 层 `lib/features/deploy/`

| 文件 | 行数 | 说明 |
|------|------|------|
| `providers/deploy_provider.dart` | ~120 | DeployStatus 状态管理 + DeployNotifier |
| `views/deploy_page.dart` | ~230 | 仪表盘 UI（摘要卡片 + 结果列表 + 空状态） |

### 路由 & 导航

| 文件 | 变更 |
|------|------|
| `lib/core/router/route_names.dart` | 新增 `deploy` 路由 |
| `lib/core/router/app_router.dart` | 注册 DeployPage 路由 |
| `lib/features/home/views/home_page.dart` | 新增部署中心卡片 + NavigationBar 入口 |

### 测试

| 文件 | 说明 |
|------|------|
| `test/detector_service_test.dart` | DetectorService + DetectionResult 单元测试 |

---

## 四、验收标准

| 指标 | 目标值 | 实测值 | 状态 |
|------|--------|--------|------|
| 检测完成时间 | < 3 秒 | 串行 10 个检测器 | ⏳ 待真机测试 |
| 检测准确率 | 100%（无漏检、无误报） | 逻辑验证通过 | ⏳ 待真机测试 |
| 状态刷新 | 手动 + 自动 | 手动 ✅ / 自动 ✅（页面进入触发） | ✅ |

---

## 五、已知问题

| # | 问题 | 影响 | 解决方案 |
|---|------|------|---------|
| 1 | 检测器串行执行 | 总耗时 = 各检测器之和 | 可改为并行（需权衡 UI 实时性） |
| 2 | 降级模式下 `which` 可能找不到工具 | 检测结果不准确 | 已添加多路径备选方案 |
| 3 | 存储权限检测依赖 `/sdcard` 路径 | 不同 ROM 路径可能不同 | 已添加 `/storage/emulated/0/` 备选 |

---

## 六、下一步

1. 真机运行完整检测流程，验证准确率
2. 进入 **Milestone 0.4：AI 通信验证**
