# 📦 Changelog

## [Unreleased]

### 🏗️ Sprint 2：工作区管理 ✅

#### 📁 工作区数据模型
- `features/workspace/workspace_model.dart` — Workspace/ProjectRef/WorkspaceTemplate 数据模型，完整 JSON 序列化

#### ⚡ 工作区状态管理
- `features/workspace/workspace_provider.dart` — `WorkspaceNotifier`：CRUD 操作、当前工作区切换、SharedPreferences 持久化、项目管理

#### 🖥️ 工作区管理 UI
- `features/workspace/views/workspace_list_page.dart` — 工作区列表页（卡片布局、模板图标、当前标记、空状态引导、删除确认）
- `features/workspace/views/workspace_create_dialog.dart` — 创建对话框（命名 + 5 种模板选择）

#### 🏠 首页仪表盘增强
- `lib/features/home/views/home_page.dart` — 工作区信息卡片（当前工作区/空状态）、快捷操作芯片、AI 状态显示

#### 🔗 路由注册
- `lib/core/router/route_names.dart` — 新增工作区路由路径
- `lib/core/router/app_router.dart` — 注册 WorkspaceListPage 路由
- `lib/core/router/route_guard.dart` — 工作区路由权限配置

#### 🌐 国际化扩展
- `lib/core/i18n/strings.dart` — 新增 17 条工作区相关字符串

#### 🧪 测试
- `test/workspace_model_test.dart` — 22 个用例（模型/序列化/容错）
- `test/workspace_provider_test.dart` — 14 个用例（CRUD/切换/持久化）

---

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
