# 📦 Changelog

## [Unreleased]

### 🔬 Sprint 0 — Milestone 0.4：AI 通信验证 ✅

#### 🏗️ AI 核心层
- `core/ai/ai_message.dart` — 消息模型：ChatRole（4 角色）、ChatMessage、ChatCompletionRequest/Response、ChatChoice、ChatUsage
- `core/ai/sse_parser.dart` — SSE 流解析器，支持 byteTransformer 管道、parseLine 逐行解析、extractContent 提取增量
- `core/ai/ai_client.dart` — OpenAI 兼容 HTTP 客户端，支持流式/非流式、健康检查、7 类错误分类（401/403/429/502/503/5xx/网络超时）
- `core/ai/ai_service.dart` — AI 服务封装，指数退避重试（最多 3 次）、代理健康检查、流式回调

#### 🚀 AI 对话 UI
- `features/ai/providers/chat_provider.dart` — ChatState + ChatNotifier（流式 sendMessage、服务状态检查、清空对话）
- `features/ai/views/ai_chat_page.dart` — 完整对话页面：气泡消息、简易 Markdown/代码块渲染、流式状态指示器、服务状态提示栏、快速问题芯片、清空确认对话框

#### 🧭 路由与导航集成
- `core/router/route_names.dart` — 新增 `aiChat` 路由常量
- `core/router/app_router.dart` — 注册 `AiChatPage` 路由
- `features/home/views/home_page.dart` — 导航栏第 4 项 + AppBar 按钮 + 快捷卡片全部指向 AI 对话页

#### 🧪 单元测试
- `test/sse_parser_test.dart` — 18 用例：SSE 解析、extractContent、byteTransformer、ChatRole/ChatMessage/ChatCompletionResponse
- `test/ai_client_test.dart` — 11 用例：Mock HTTP 客户端测试（成功/错误分类/流式/健康检查）
- `test/ai_service_test.dart` — 8 用例：配置验证、状态枚举、服务生命周期、kSystemPrompt
- `test/chat_provider_test.dart` — 9 用例：ChatState 不可变、ChatNotifier 清空/空消息/setService

#### 📋 文档
- `docs/sprints/sprint-0/milestone-0.4-验证报告.md`

---

### 🔬 Sprint 0 — Milestone 0.3：依赖检测验证 ✅

#### 🏗️ 检测器体系
- `core/detector/detector.dart` — Detector 抽象基类
- `core/detector/detection_result.dart` — DetectionResult 模型 + DetectionStatus 枚举
- `core/detector/detector_service.dart` — 检测编排服务（并行/单条/统计）
- `core/detector/detectors/` — 10 个独立检测器
  - Flutter、Termux、Node.js、Git、Python 3、cURL
  - Codex CLI（三路径）、mimo2codex（含端口检测）、DeepSeek API Key、存储权限

#### 🚀 部署中心 UI
- `features/deploy/providers/deploy_provider.dart` — DeployStatus + DeployNotifier
- `features/deploy/views/deploy_page.dart` — 状态仪表盘（摘要卡片 + 结果列表 + 实时进度）

#### 🧪 单元测试
- `test/detector_service_test.dart` — Mock 检测器 + DetectorService + 统计

#### 📋 文档
- `docs/sprints/sprint-0/milestone-0.3-验证报告.md`

---


### 🔬 Sprint 0 — Milestone 0.2：Termux 通信验证 ✅

#### 🏗️ Android Native 层
- `TermuxBridge.kt` — 三策略降级命令执行桥
  - 策略1: Termux bash（`/data/data/com.termux/files/usr/bin/bash`）
  - 策略2: 系统 shell（`/system/bin/sh`）
  - 自动降级 + 详细诊断信息
  - 30 秒超时 + `destroyForcibly()` 强制终止
  - stdout / stderr / exitCode 完整捕获
  - 可写工作目录自动选择（cacheDir → filesDir → /data/local/tmp）
- `MainActivity.kt` — MethodChannel 注册（`com.codexmobile.app/termux`）

#### 📐 Flutter Service 层
- `core/termux/termux_service.dart` — Termux 通信服务
  - `TermuxResult` — 命令结果模型（`isSuccess`, `isTimeout`）
  - `TermuxEnvCheck` — 环境诊断模型（`termuxMode`, `fallbackAvailable`, `hasAnyShell`）
  - `TermuxService.execute()` — 执行命令
  - `TermuxService.checkEnvironment()` — 完整环境诊断

#### 🧪 测试页面
- `features/termux/views/termux_test_page.dart` — 通信验证 UI
  - 🔍 环境检查（Termux + 系统 shell 完整诊断）
  - 🚀 基础命令测试（10 条命令）
  - 🔣 特殊字符测试（10 种场景：$、"、'、\、`、|、中文、换行、重定向）
  - 🔥 批量压力测试（50 次连续调用 + 统计报表）
  - 🏁 完整验证套件（一键运行所有测试）
  - 🎨 彩色输出、进度条、快捷命令芯片

#### 🧪 单元测试
- `test/termux_service_test.dart` — 15 个测试用例
  - 正常执行、命令失败、超时、大量输出、中文编码、空输出
  - 环境检查：Termux 可用、降级模式、完全无环境
  - TermuxResult/EnvCheck 模型验证

#### 📋 文档
- `docs/sprints/sprint-0/milestone-0.2-验证报告.md` — 完整验证报告

---

### 🔬 Sprint 0 — Milestone 0.1：环境验证 ✅

#### 🏗️ Flutter 工程初始化
- `lib/main.dart` — 应用入口（ProviderScope, 竖屏锁定, 状态栏）
- `lib/app.dart` — MaterialApp.router + M3 主题
- `pubspec.yaml` — 依赖声明（Riverpod, GoRouter, http, flutter_markdown...）
- `analysis_options.yaml` — 严格 lint 规则
- `setup_flutter_project.sh` — 开发机 Flutter 脚手架初始化脚本

#### 🎨 Material 3 主题
- `lib/core/theme/app_theme.dart` — 亮色/暗色主题（`useMaterial3: true`）
- `lib/features/home/views/home_page.dart` — 首页演示页
  - M3 组件：Card, NavigationBar, FilledButton, SnackBar
  - Riverpod 集成：计数器交互演示
  - 环境信息展示

#### 📐 Riverpod 状态管理
- `lib/features/home/providers/counter_provider.dart` — 计数器 StateNotifier
- `lib/features/home/providers/home_state_provider.dart` — 首页状态

#### 🧪 测试
- `test/counter_provider_test.dart` — Provider 单元测试（4 个用例）
- `test/home_page_test.dart` — Widget 测试（M3 渲染 + 计数器交互）

#### ⚙️ Android 兼容配置
- `android/app/build.gradle` — `minSdk=29(10+)`, `targetSdk=35(15)`
- `android/app/src/main/AndroidManifest.xml` — 权限声明 + 前台服务
- `android/app/src/main/kotlin/.../MainActivity.kt` — Flutter Activity

#### 🏗️ 框架基础
- `lib/core/logger/log_service.dart` — 统一日志系统
- `lib/core/error/app_exception.dart` — 6 种异常类型
- `lib/core/error/result.dart` — Result 模式
- `lib/core/router/app_router.dart` — GoRouter 路由
- `lib/core/router/route_names.dart` — 路由常量

#### 📋 规划与文档
- `SPRINT_PLAN.md` — 完整 Sprint 计划
- `docs/ARCHITECTURE.md` — 架构文档（673 行）
- `docs/sprints/sprint-0/milestone-0.1-验证报告.md`

#### ⚙️ CI/CD
- `.github/workflows/ci.yml` — Analyze → Test → Build
