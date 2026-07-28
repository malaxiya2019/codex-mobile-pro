# 📦 Changelog

## [Unreleased]

## [Unreleased]

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
：代码编辑器与 GitHub 深度集成 ✅

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
