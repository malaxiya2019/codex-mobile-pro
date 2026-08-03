# Sprint 9 开发报告 — 发布版

> **Sprint 周期：** 2026-08-02 ~ 2026-08-03
> **状态：** ✅ 完成

---

## 一、概述

Sprint 9 聚焦发布前的「最后一公里」，按规划书完成 6 大功能：

1. **自动更新** — GitHub Release 检查 → APK 下载 → 系统安装器
2. **备份恢复** — 配置（主题/语言/终端/GitHub/工作区/项目）一键备份与恢复
3. **性能优化** — 大文件编辑器语法高亮 tokenize 缓存
4. **崩溃采集** — 崩溃日志 CRASH 标识 + 生产环境友好错误页
5. **日志中心** — 统一查看 / 级别过滤 / 崩溃过滤 / 导出 / 清除
6. **关于页面** — 版本号 / 开源许可 / 仓库链接

同时完成配套修复：AI 对话页空流（AIProviderManager 注册默认 DeepSeek）、about 页测试基建收敛。

---

## 二、模块实现详情

### 模块一：自动更新 ✅

#### Release 检查
- `lib/features/settings/services/update_checker.dart`
  - `UpdateChecker` — GET `https://api.github.com/repos/malaxiya2019/codex-mobile-pro/releases/latest`（公共仓库免 token，User-Agent=codex-mobile-pro）
  - `VersionCompare` — 语义化版本比较（剥 v 前缀）
  - 404 = 无 Release → 无更新；版本不高于当前 → 无更新；可注入 http.Client

#### APK 下载
- `lib/features/settings/services/update_downloader.dart`
  - 流式下载 APK 到 `<文档目录>/updates/`，带进度回调（contentLength 可能为 0）

#### 系统安装器
- `android/app/src/main/kotlin/com/codexmobile/app/UpdateInstallerPlugin.kt`
  - MethodChannel `com.codexmobile.app/update` → FileProvider content URI → `ACTION_VIEW`(application/vnd.android.package-archive)
  - `FLAG_GRANT_READ_URI_PERMISSION` + `FLAG_ACTIVITY_NEW_TASK`
- `android/app/src/main/AndroidManifest.xml` — `REQUEST_INSTALL_PACKAGES` 权限 + FileProvider（authorities `com.codexmobile.app.fileprovider`）
- `android/app/src/main/res/xml/file_paths.xml` — updates/ + backups/ + cache 路径映射
- `lib/core/update/update_installer_channel.dart` — Dart 侧 MethodChannel 封装 installApk

#### UI
- `lib/features/settings/views/update_settings_page.dart` — 检查 → 下载（进度条）→ 安装；路由 `/update`；首页「检查更新」入口

### 模块二：备份恢复 ✅

- `lib/core/config/backup_service.dart` — 备份/恢复核心（纯 Dart 可测）
  - **白名单 keys**：`theme_mode` / `font_family` / `font_scale`、`app_locale`、`terminal_*`（fontFamily/fontSize/背景/光标/前景/themeMode/cursorBlink）、`auth_token` / `github_token`、`workspaces` / `current_workspace_id`、`projects`
  - **导出**：JSON → 文档目录 `backups/`（恢复源）+ 复制到 Download（复用 LogExportChannel，失败仅告警）
  - **恢复**：按类型写回 SharedPreferences（String/bool/int/double，嵌套类型 JSON 字符串）；已加载 Provider 不热更新，提示重启 App
  - **审计要点**：全仓配置实际都在 SharedPreferences（含 auth_token/github_token）→ 备份 = 导出 prefs
- `lib/features/settings/views/backup_settings_page.dart` — 备份按钮 + 备份列表（时间倒序）+ 恢复确认对话框
- 路由 `/backup` + 首页「备份与恢复」入口

### 模块三：性能优化 ✅

- `lib/features/editor/widgets/editor_content.dart`
  - `_tokenCache`（`Map<String, List<SyntaxToken>>`，LRU 上限 1024）
  - `_highlight()` 方法：缓存 key = `'$isFirstLine|$text'`（首行与后续行语义不同，避免串缓存）
  - `_buildLine` 改用缓存：大文件滚动时可见行反复 tokenize 的卡顿消除
  - 顺带修正：首行现在正确传入 `isFirstLine: index == 0`（原先所有行都按默认 false 处理）

### 模块四：崩溃采集 ✅

- `lib/core/logger/log_service.dart` — 新增 `crash()`：崩溃日志带 `CRASH` 标识写入
- `lib/core/logger/error_handler.dart` — 三处异常捕获改用 `crash()`；生产模式 + `enableCrashUi` 时经全局 navigator push `ErrorPage`（复用现有页面，防重复弹窗）
- `lib/core/navigation/global_navigator_key.dart` — **新建** 全局 navigatorKey（GoRouter root navigator + 错误处理器共用）
- `lib/core/router/app_router.dart` — `GoRouter(navigatorKey: globalNavigatorKey)`（MaterialApp.router 无 navigatorKey 参数，必须挂 GoRouter）

### 模块五：日志中心 ✅

- `lib/core/logger/log_service.dart` — 新增 `readAllLogs()`（含轮转文件）与 `exportLogsToDownload()`（flush → readAll → MediaStore 写 Download；非 Android 写 systemTemp 便于测试）
- `lib/core/logger/log_file_writer.dart` — 新增 `readAll()`：合并轮转文件，最旧 → 最新（`app.log.{N-1}` → … → `app.log.0` → `app.log`）
- `lib/features/settings/services/log_parser.dart` — **新建** 纯函数解析/过滤（级别过滤 + 崩溃过滤）
- `lib/features/settings/views/log_center_page.dart` — **新建** 日志中心页（构造参数 `logsLoader` 注入便于测试）
- `android/app/src/main/kotlin/com/codexmobile/app/LogExportPlugin.kt` — **新建** MethodChannel `com.codexmobile.app/log/export`，`writeToDownload` 用 MediaStore.Downloads + RELATIVE_PATH（targetSdk 36 免运行时权限），写入失败自动删除占位记录
- `lib/core/logger/log_export_channel.dart` — **新建** Dart 侧通道封装
- 路由 `RouteNames.logCenter = '/log-center'`；首页「导出日志」入口改为「日志中心」

### 模块六：关于页面 ✅

- `lib/features/settings/views/about_settings_page.dart` — 版本号 / 开源许可 / 仓库 URL
- `lib/core/config/app_info.dart` — 应用信息常量（版本 1.0.0+1、仓库、许可）
- 路由 `/about` + 首页功能入口「关于」

### 配套修复 ✅

- `2169281` fix(ai)：AIProviderManager 注册默认 DeepSeek provider，修复对话页「未收到有效回复」（空流）——`chat_provider.dart` 中注册 `DeepSeekProvider(priority: primary)` + fire-and-forget initialize + dispose 清理
- `668cf3f` / `f1aee2d` fix(ci/test)：about 页测试 Clipboard import 与 mocktail Uri fallback 收敛

---

## 三、新增文件清单

```
lib/core/update/update_installer_channel.dart          # APK 安装通道封装
lib/core/config/backup_service.dart                    # 配置备份/恢复核心
lib/core/navigation/global_navigator_key.dart          # 全局 navigatorKey
lib/core/logger/log_export_channel.dart                # 日志导出通道封装
lib/core/config/app_info.dart                          # 应用信息常量
lib/features/settings/services/update_checker.dart     # Release 检查 + 版本比较
lib/features/settings/services/update_downloader.dart  # APK 流式下载
lib/features/settings/services/log_parser.dart         # 日志解析/过滤纯函数
lib/features/settings/views/update_settings_page.dart  # 更新页
lib/features/settings/views/backup_settings_page.dart  # 备份恢复页
lib/features/settings/views/log_center_page.dart       # 日志中心页
lib/features/settings/views/about_settings_page.dart   # 关于页
android/.../UpdateInstallerPlugin.kt                   # 系统安装器通道
android/.../LogExportPlugin.kt                         # 日志导出到 Download
android/.../res/xml/file_paths.xml                     # FileProvider 路径映射
```

## 四、测试覆盖

| 测试文件 | 用例数 | 覆盖范围 |
|----------|--------|----------|
| `test/update_checker_test.dart` | 11 | 版本比较 / Release 检查 / User-Agent / 404 / 无更新 |
| `test/backup_service_test.dart` | 5 | 白名单过滤 / 导出 JSON / 列表排序 / 恢复保类型 / 空备份安全 |
| `test/log_service_test.dart` | 22 | 级别写入 / 轮转 / readAll / crash 标识 / 导出 Download |
| `test/log_parser_test.dart` | 10 | 行解析 / 级别过滤 / 崩溃过滤 |
| `test/log_center_page_test.dart` | 3 | 空态 / 过滤交互 |
| `test/error_handler_test.dart` | 14 | 全局捕获 / 生产弹窗 / debug 不弹 / 无 key 不崩 |
| `test/about_settings_page_test.dart` | 2 | 版本信息渲染 |
| `test/editor_content_cache_test.dart` | 3 | 缓存命中 / isFirstLine key / 缓存失效 |

---

## 五、架构说明

### 更新流程

```
UpdateSettingsPage (UI)
  ├── UpdateChecker (Release 检查 + 版本比较)
  ├── UpdateDownloader (APK 流式下载 → updates/)
  └── UpdateInstallerPlugin (MethodChannel)
        └── FileProvider content URI → ACTION_VIEW 系统安装器
```

### 日志链路

```
LogService (crash / readAllLogs / exportLogsToDownload)
  ├── LogFileWriter (落盘 + 轮转 + readAll 合并)
  ├── LogParser (纯函数过滤)
  └── LogCenterPage (UI: 级别/崩溃过滤 + 导出/清除)
        └── LogExportPlugin (MediaStore → Download)
```

### 崩溃友好界面

```
GlobalErrorHandler
  ├── crash() → 落盘（CRASH 标识）
  └── enableCrashUi + 生产模式 → globalNavigatorKey → ErrorPage
```

---

## 六、设计决策

1. **自动更新走 GitHub Release** — 公共仓库免 token，tag 命名 `vX.Y.Z` + APK asset；安装用 FileProvider（Android 7+ 不可再暴露 file:// URI）
2. **备份 = 导出 SharedPreferences** — 审计确认全仓配置（含 token）实际都存 prefs；按类型安全写回，不做 Provider 热更新（避免状态语义漂移），提示重启
3. **tokenize 缓存** — key 含 `isFirstLine` 前缀（同一文本首行与后续行高亮语义不同）；LRU 上限防内存膨胀
4. **日志中心可测性** — `LogCenterPage` 通过构造参数注入 `logsLoader`，纯函数解析层与 UI 解耦
5. **崩溃弹窗复用现有 ErrorPage** — 不新造页面；navigatorKey 挂 GoRouter（MaterialApp.router 无 navigatorKey 参数）
6. **Android 平台通道收口** — 所有 MethodChannel（update/export）都经 Dart 侧封装类，Kotlin 侧职责单一

---

## 七、后续计划

- 真机验证：发 v1.0.1 tag（附 APK asset）→ 更新页走通 检查 → 下载 → 安装（首次安装需系统授权「未知来源」）
- 崩溃上报（可选）：crash 落盘已就绪，上报通道可后续接入
- 发布流程：打 tag + 上传 CI 构建的 release APK
