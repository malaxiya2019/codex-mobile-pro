# 📦 Changelog

## [Unreleased]

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

---

*格式规范：[语义化版本](https://semver.org/lang/zh-CN/)*
