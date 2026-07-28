# 📦 Changelog

## [Unreleased]

### 🏗️ Sprint 1：项目框架 ✅

#### 🎨 主题系统完善
- `core/theme/theme_provider.dart` — 主题状态管理（StateNotifier）：亮色/暗色/跟随系统、字体配置（Roboto/Noto Sans SC/等宽）、缩放滑块（0.8–1.5）、SharedPreferences 持久化
- `core/theme/app_theme.dart` — 统一 Card/Input/NavigationBar/SnackBar/Dialog/AppBar/Chip 主题配置
- `features/settings/views/theme_settings_page.dart` — 主题设置页面（模式选择 + 字体配置 + 预览）
- AppBar 一键切换亮暗

#### 📝 日志系统增强
- `core/logger/log_file_writer.dart` — 日志文件写入器：目录自动创建、文件大小轮转（1MB）、保留 5 个轮转文件、高频写入缓冲（100行/5秒防抖）
- `core/logger/log_service.dart` — 集成 FileWriter，新增 exception/堆栈截断/getRecentLogs/clearLogs/getTotalLogSize

#### 🛡️ 全局异常处理
- `core/error/error_handler.dart` — 三层捕获：FlutterError.onError → PlatformDispatcher.onError → runZonedGuarded，调试/生产双模式，外部回调
- `core/error/error_page.dart` — 友好错误页面（调试模式显示详细错误+堆栈 + 生产模式友好提示 + 重试/返回按钮）
- `main.dart` — 集成 GlobalErrorHandler + runZonedGuarded

#### 🌐 国际化
- `core/i18n/app_locale.dart` — 语言枚举（zh_CN/en_US）+ LocaleNotifier（切换/持久化）
- `core/i18n/strings.dart` — 约 60 个字符串集中管理（通用/首页/导航/AI/主题/Termux/部署/错误）
- `features/settings/views/locale_settings_page.dart` — 语言设置页面 + 预览
- `app.dart` — 集成 supportedLocales 和 locale 配置
- AppBar 一键切换语言

#### 🔒 路由守卫
- `core/router/route_guard.dart` — 权限体系：PermissionLevel（4 级）、UserRole（4 级）、AuthState/AuthNotifier、RoutePermissions（页面权限映射 + GoRouter redirect 重定向）
- `core/router/app_router.dart` — 集成 redirect 守卫
- 预留：login/logout、Token 管理、会员系统接口

#### 🧪 测试（新增 55 用例）
- `test/theme_provider_test.dart` — 13 用例
- `test/log_service_test.dart` — 10 用例
- `test/error_handler_test.dart` — 10 用例
- `test/locale_test.dart` — 10 用例
- `test/route_guard_test.dart` — 12 用例

#### 📋 文档
- `docs/sprints/sprint-1-开发报告.md`

---

### 🔬 Sprint 0 — Milestone 0.5：性能基线 ✅

#### 📊 性能打点基础设施
- `core/performance/performance_tracker.dart` — 性能事件跟踪器
- `core/performance/performance_provider.dart` — Riverpod Provider 封装
- `main.dart` / `app.dart` — 集成 app_start + app_ready 打点
- `scripts/benchmark/*.sh` — 3 个 ADB 测量脚本
- `test/performance_tracker_test.dart` — 9 用例
- `test/performance_benchmark_test.dart` — 10 用例
- `docs/sprints/sprint-0/milestone-0.5-性能基线.md`

### 🔬 Sprint 0 — Milestone 0.4：AI 通信验证 ✅
### 🔬 Sprint 0 — Milestone 0.3：依赖检测验证 ✅
### 🔬 Sprint 0 — Milestone 0.2：Termux 通信验证 ✅
### 🔬 Sprint 0 — Milestone 0.1：环境验证 ✅
