# 📦 Changelog

## [Unreleased]

### 🏗️ Sprint 9：发布版 ✅

#### 🔄 自动更新
- `lib/features/settings/services/update_checker.dart` — **新建** GitHub Release 检查（公共仓库免 token，tag 版本比较，首个 APK asset 定位）
- `lib/features/settings/services/update_downloader.dart` — **新建** APK 流式下载（进度回调，可注入 http.Client）
- `lib/core/update/update_installer_channel.dart` — **新建** Dart 侧 MethodChannel 封装 installApk
- `android/app/src/main/kotlin/.../UpdateInstallerPlugin.kt` — **新建** FileProvider content URI → 系统安装器（ACTION_VIEW + GRANT_READ_URI_PERMISSION）
- `android/.../AndroidManifest.xml` — 新增 REQUEST_INSTALL_PACKAGES 权限 + FileProvider
- `lib/features/settings/views/update_settings_page.dart` — **新建** 更新页（检查 → 下载进度 → 安装）

#### 💾 备份恢复
- `lib/core/config/backup_service.dart` — **新建** 配置备份/恢复核心（主题/语言/终端/GitHub Token/工作区/项目白名单，JSON 导出 + 类型安全写回）
- `lib/features/settings/views/backup_settings_page.dart` — **新建** 备份页（备份按钮/历史列表/恢复确认）

#### ⚡ 性能优化
- `lib/features/editor/widgets/editor_content.dart` — 语法高亮 Token 缓存（LRU 1024，isFirstLine 参与缓存 key），大文件滚动不再重复 tokenize

#### 💥 崩溃采集
- `lib/core/logger/log_service.dart` — 新增 `crash()` 崩溃日志（CRASH 标识）
- `lib/core/logger/error_handler.dart` — 三处异常捕获改用 crash()；生产模式 + enableCrashUi 时经全局 navigator 弹友好 ErrorPage
- `lib/core/navigation/global_navigator_key.dart` — **新建** 全局 navigatorKey（GoRouter + 错误处理器共用）

#### 📋 日志中心
- `lib/core/logger/log_service.dart` — 新增 `readAllLogs()`（含轮转文件）与 `exportLogsToDownload()`（MediaStore 写 Download）
- `lib/core/logger/log_file_writer.dart` — 新增 `readAll()` 合并轮转文件（最旧 → 最新）
- `lib/features/settings/services/log_parser.dart` — **新建** 日志解析/级别过滤纯函数
- `lib/features/settings/views/log_center_page.dart` — **新建** 日志中心页（级别过滤/崩溃过滤/导出/清除）
- `android/.../LogExportPlugin.kt` — **新建** MethodChannel 导出到 Download（targetSdk 36 免运行时权限）

#### ℹ️ 关于页面
- `lib/features/settings/views/about_settings_page.dart` — **新建** 关于页（版本号/开源许可/仓库链接）
- `lib/core/config/app_info.dart` — **新建** 应用信息常量（版本 1.0.0+1）

#### 🧪 测试
- `test/update_checker_test.dart` — 10 个用例（版本比较/Release 检查/User-Agent）
- `test/backup_service_test.dart` — 5 个用例（白名单过滤/导出/排序/恢复保类型/空备份）
- `test/log_parser_test.dart` + `test/log_center_page_test.dart` — 日志解析与日志中心 UI
- `test/editor_content_cache_test.dart` — 3 个用例（缓存命中/isFirstLine key/缓存失效）
- `test/log_service_test.dart` / `test/error_handler_test.dart` / `test/about_settings_page_test.dart` — 扩展

#### 📋 文档
- `docs/sprints/sprint-9-开发报告.md` — 完整开发报告
- `docs/sprints/sprint-9-测试报告.md` — 测试报告
- `CHANGELOG.md` — 更新日志

---

### 🏗️ Sprint 8：AI 编程增强 ✅

#### 🤖 AI Chat Engine
- `lib/features/ai/providers/ai_provider_manager.dart` — 多 Provider 注册/健康检查/自动选择（DeepSeek 默认注册）
- `lib/features/ai/services/chat_engine.dart` — IChatEngine 流式对话架构
- `lib/features/ai/providers/chat_provider.dart` — ChatProvider 迁移到 IChatEngine，AIProviderManager 注册默认 DeepSeek provider（本地 mimo zero-auth）

#### ✨ AI 编程功能
- 修 Bug / 解释代码 / 重构建议 / 生成测试 / Commit Message（`feat(sprint-8)` 系列提交）
- AI 内联补全、代码生成

#### 🧪 测试
- AI 相关单元测试与 ChatProvider 架构迁移测试

---

### 🏗️ Sprint 7：AI 补全与 GitHub Workflow ✅

#### ✨ AI Inline Completion
- 编辑器 AI 内联补全引擎（Milestone 1）

#### 💡 AI 辅助
- 解释代码（Explain Code，Milestone 2）
- 修复错误 + 代码生成（Fix Error + Generate Code，Milestone 3+4）

#### 🔗 GitHub Workflow
- GitHub Workflow Provider 化（Milestone 5）

---

### 🔧 Sprint 0：基础环境修复

#### 🐛 终端启动问题修复（P1+P4+P5+P6）
- `lib/core/termux/shell_detector.dart` — **新建** `ShellDetector` 类，自动检测可用 Shell
  - 优先级：Termux Bash → bash → sh → /system/bin/sh
  - 提供 `ShellInfo`、`ShellType` 枚举、友好的中文描述
  - 提供 `getTermuxEnvironment()` 确保环境变量正确加载
- `lib/features/terminal/services/terminal_service.dart` — **重写** 不再硬编码 `/system/bin/sh -c bash`
  - 全部通过 `ShellDetector.detect()` 获取 Shell 路径
  - 增加完整诊断日志：Shell 类型/路径/PATH/HOME/PREFIX/PID/ExitCode/StackTrace
- `lib/features/terminal/providers/terminal_provider.dart` — **重写** 适配异步创建
  - 新增 `ShellInfo`/`shellDowngradeMessage` 状态
  - 友好中文降级提示

#### 🐛 环境检测误判修复（P2）
- `lib/core/detector/environment_service.dart` — **新建** `EnvironmentService`
  - 所有检测通过 Termux Shell 环境执行，而非 Android App 自身 PATH
  - 自动检测 Termux 环境，设置完整环境变量
  - 自动降级机制
- 所有 10 个 `detectors/*.dart` — **重写** 改用 `EnvironmentService.detectTool()`
  - 全部添加 `category` getter，区分 Runtime/Development

#### 💄 部署中心分类修复（P3）
- `lib/core/detector/detector.dart` — **更新** 新增 `DetectorCategory` 枚举、`missingHint` 字段（默认 null）
- `lib/core/detector/detection_result.dart` — **更新** 新增 `category`、`missingHint` 字段
- `lib/core/detector/detector_service.dart` — **更新** 新增 `groupByCategory()` 静态方法
- `lib/features/deploy/providers/deploy_provider.dart` — **更新** 新增 Runtime/Development 分类统计
- `lib/features/deploy/views/deploy_page.dart` — **重写** 分类展示：
  - Runtime 缺失 → 红色，Development 缺失 → 黄色
  - 显示 "Flutter SDK（可选，用于 Flutter 开发）" 友好提示
  - 状态摘要区分 Runtime/Dev 统计

#### 🧪 新增测试（P7）
- `test/shell_detector_test.dart` — **新建** Shell 检测模型测试
- `test/environment_service_test.dart` — **新建** 环境服务测试
- `test/terminal_service_test.dart` — **更新** 适配新 TerminalSession API
- `test/detector_service_test.dart` — **更新** 添加 category/missingHint 测试

#### 📝 文档
- 更新 CHANGELOG.md
- 更新 Sprint 0 开发报告

---

### 🏗️ Sprint 6：代码编辑器与 GitHub 深度集成 ✅

#### 📝 代码编辑器
- `features/editor/providers/editor_provider.dart` — 编辑器状态管理（Tab/光标/编辑/查找替换/自动保存）
- `features/editor/views/editor_page.dart` — 多标签编辑器页面（Tab栏/工具栏/状态栏）
- `features/editor/widgets/editor_content.dart` — 语法高亮渲染引擎（RichText + Token 着色）
- `features/editor/widgets/editor_gutter.dart` — 行号栏组件
- `features/editor/widgets/editor_find_panel.dart` — 查找/替换面板（大小写/正则/逐个替换/全部替换）

#### ✨ 编辑体验接口
- `features/editor/extensions/completion_provider.dart` — 自动补全接口（关键字补全 + AI 补全预留）
- `features/editor/extensions/diagnostics_provider.dart` — 诊断管理器接口
- `features/editor/extensions/lsp_provider.dart` — LSP 服务器接口 + CodeAction 模型
- `features/editor/extensions/outline_provider.dart` — Dart Outline 提取器

#### 🔗 GitHub 深度集成
- `features/git/models/github_pr.dart` — PR/Issue/Comment 数据模型
- `features/git/services/github_service.dart` — 新增 PR/Issue API 方法
- `features/git/providers/github_pr_provider.dart` — PR 列表/详情状态管理
- `features/git/providers/github_issue_provider.dart` — Issue 列表/详情状态管理
- `features/git/views/pr_list_page.dart` — PR 列表页面（状态过滤/头像/增减行数）
- `features/git/views/issue_list_page.dart` — Issue 列表页面（标签/评论数/状态过滤）

#### 📁 文件管理增强
- `features/file/services/file_service.dart` — 新增重命名/删除/复制/移动/创建操作
- `features/file/providers/file_provider.dart` — 新增文件操作方法 + 自动刷新

#### 🧪 测试
- `test/editor_buffer_test.dart` — 20 个用例（编辑操作/光标/撤销重做/查找替换/语言检测）
- `test/syntax_highlighter_test.dart` — 15 个用例（高亮器注册/关键字/字符串/注释/颜色/语言推断）
- `test/github_pr_test.dart` — 8 个用例（PR/Issue/Comment 模型序列化）

#### 📋 文档
- `docs/sprints/sprint-6-开发报告.md` — 完整开发报告
- `docs/sprints/sprint-6-测试报告.md` — 测试报告
- `CHANGELOG.md` — 更新日志

---

### 🏗️ Sprint 5：内置终端增强 + GitHub 集成 ✅

#### 💻 终端增强
- `features/terminal/services/ansi_parser.dart` — ANSI 转义序列解析器（标准16色/256色/TrueColor/粗体/斜体/下划线/反色/删除线）
- `features/terminal/widgets/terminal_output.dart` — ANSI 渲染富文本组件
- `features/terminal/providers/terminal_provider.dart` — 命令历史记录（↑↓键导航，每会话独立历史）
- `features/terminal/views/terminal_page.dart` — ↑↓键导航历史命令、ANSI 输出渲染

#### 🔗 GitHub 集成
- `features/git/models/git_repository.dart` — Git 数据模型（仓库/分支/提交/变更/状态）
- `features/git/services/git_service.dart` — Git CLI 封装（16个操作：clone/push/pull/branch/commit/stash/diff/log等）
- `features/git/services/github_service.dart` — GitHub API 服务（Token认证/用户信息/仓库列表/搜索）
- `features/git/providers/git_provider.dart` — 认证/仓库列表/Git 状态 Provider
- `features/git/views/github_login_page.dart` — GitHub Token 登录页
- `features/git/views/repo_list_page.dart` — 仓库列表页（卡片/搜索/下拉刷新）
- `features/git/views/git_operations_page.dart` — Git 操作页（信息/Clone/状态/分支/提交历史）

#### 🔗 路由与导航
- `route_names.dart` / `app_router.dart` / `route_guard.dart` — GitHub 路由注册
- `home_page.dart` — 导航栏新增终端/GitHub入口

#### 🌐 国际化扩展
- `lib/core/i18n/strings.dart` — 新增 19 条 Git 相关字符串

#### 🧪 测试
- `test/ansi_parser_test.dart` — 20 个用例（纯文本/颜色/样式/256色/光标/OSC/退格）
- `test/git_service_test.dart` — 16 个用例（模型/状态/分支/提交/服务）

---

### 🏗️ Sprint 4：部署中心完善 + 内置终端 ✅

#### 🔧 环境管理器增强
- `features/deploy/services/environment_manager.dart` — 统一 Environment Manager

#### 💻 内置终端系统 (PTY)
- `features/terminal/services/terminal_service.dart` — 终端会话管理
- `features/terminal/providers/terminal_provider.dart` — 终端状态管理
- `features/terminal/views/terminal_page.dart` — 多标签终端 UI

#### ⚡ 快捷命令管理
- `features/terminal/services/command_manager.dart` — 27条预置命令
- `features/terminal/widgets/quick_commands_panel.dart` — 快捷命令面板

#### 🧪 测试
- `test/terminal_service_test.dart` — 16 个用例
- `test/command_manager_test.dart` — 17 个用例
- `test/environment_manager_test.dart` — 12 个用例

---

### 🏗️ Sprint 3：项目管理和文件系统 ✅
### 🏗️ Sprint 2：工作区管理 ✅
### 🏗️ Sprint 1：项目框架 ✅
