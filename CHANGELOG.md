# 📦 Changelog

## [Unreleased]

### 🏗️ Sprint 4：部署中心完善 + 内置终端 ✅

#### 🔧 环境管理器增强
- `features/deploy/services/environment_manager.dart` — 统一 Environment Manager：Flutter/Rust/Python 环境详情获取、一键安装、环境摘要、模块化设计

#### 💻 内置终端系统 (PTY)
- `features/terminal/services/terminal_service.dart` — TerminalSession（会话/PTY/实时 I/O/缓冲区/生命周期）、TerminalService（多会话管理）
- `features/terminal/providers/terminal_provider.dart` — TerminalNotifier 状态管理（创建/关闭/切换/写入/中断）
- `features/terminal/views/terminal_page.dart` — 多标签终端 UI（Tab 栏/终端输出/命令输入/状态栏）

#### ⚡ 快捷命令管理
- `features/terminal/services/command_manager.dart` — QuickCommand 模型、CommandCategory（5 类）、27 条预置命令（Flutter 7/Rust 6/Python 5/Git 6/通用 6）、参数模板、收藏功能
- `features/terminal/widgets/quick_commands_panel.dart` — 快捷命令面板（Tab 分类/收藏/点击执行）

#### 🔗 路由注册
- `route_names.dart` / `app_router.dart` / `route_guard.dart` — 终端路由注册

#### 🌐 国际化扩展
- `lib/core/i18n/strings.dart` — 新增 16 条字符串（终端 + 快捷命令 + 环境管理）

#### 🧪 测试
- `test/terminal_service_test.dart` — 16 个用例（会话/输出/缓冲区/销毁/服务）
- `test/command_manager_test.dart` — 17 个用例（模型/参数/分类/预置/收藏）
- `test/environment_manager_test.dart` — 12 个用例（环境模型/安装/检测/摘要）

---

### 🏗️ Sprint 3：项目管理和文件系统 ✅
### 🏗️ Sprint 2：工作区管理 ✅
### 🏗️ Sprint 1：项目框架 ✅
