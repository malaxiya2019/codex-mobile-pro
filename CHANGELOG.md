# 📦 Changelog

## [Unreleased]

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
