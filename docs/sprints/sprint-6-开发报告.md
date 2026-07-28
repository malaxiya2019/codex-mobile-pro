# Sprint 6 开发报告 — 代码编辑器与 GitHub 深度集成

> **Sprint 周期：** 2026-07-28
> **状态：** ✅ 完成

---

## 一、概述

Sprint 6 聚焦两大核心模块：
1. **代码编辑器** — 多标签编辑器，支持语法高亮、查找替换、撤销/重做
2. **GitHub 深度集成** — PR 与 Issue 浏览

同时完成了文件管理增强和编辑体验接口预留。

---

## 二、模块实现详情

### 模块一：代码编辑器 ✅

#### 编辑器状态管理层
- `lib/features/editor/providers/editor_provider.dart`
  - `EditorState` — 完整编辑器状态（Tabs、Buffers、Settings、Find/Replace）
  - `EditorNotifier` — Tab 管理（打开/关闭/切换/固定）、编辑操作、光标控制、查找替换
  - 自动保存（可配置延迟时间）

#### 编辑器视图
- `lib/features/editor/views/editor_page.dart`
  - 多标签 Tab 栏（修改标记、固定图标、关闭按钮）
  - 查找/替换面板集成
  - 状态栏（行/列、语言、编码、Tab 大小）
  - AppBar 工具栏（撤销/重做/查找/保存/换行切换）

#### 编辑器 Widget
- `lib/features/editor/widgets/editor_content.dart`
  - 语法高亮渲染（RichText）
  - 行号栏
  - 当前行高亮
  - 键盘快捷键（Ctrl+Z/A/S/F、方向键、Home/End）
- `lib/features/editor/widgets/editor_find_panel.dart`
  - 查找输入、替换输入
  - 大小写/正则切换
  - 匹配计数、上/下导航
  - 替换/全部替换

### 模块二：语法高亮 ✅

已完整实现（Sprint 5 遗留）：

| 语言 | 文件 |
|------|------|
| Dart | `lib/features/editor/syntax/dart_highlighter.dart` |
| Rust | `lib/features/editor/syntax/rust_highlighter.dart` |
| Python | `lib/features/editor/syntax/python_highlighter.dart` |
| JSON | `lib/features/editor/syntax/json_highlighter.dart` |
| YAML | `lib/features/editor/syntax/yaml_highlighter.dart` |
| Markdown | `lib/features/editor/syntax/markdown_highlighter.dart` |
| TOML | `lib/features/editor/syntax/toml_highlighter.dart` |
| Shell | `lib/features/editor/syntax/shell_highlighter.dart` |

支持 Dark/Light 双主题颜色。

### 模块三：GitHub 深度集成 ✅

#### Pull Request
- `lib/features/git/models/github_pr.dart` — PR/Issue/Comment 数据模型
- `lib/features/git/services/github_service.dart` — 新增 PR/Issue API 方法
- `lib/features/git/providers/github_pr_provider.dart` — PR 列表/详情状态管理
- `lib/features/git/views/pr_list_page.dart` — PR 列表 UI（状态过滤、用户头像、增减行数）

#### Issue
- `lib/features/git/providers/github_issue_provider.dart` — Issue 列表/详情状态管理
- `lib/features/git/views/issue_list_page.dart` — Issue 列表 UI（标签、评论数、状态过滤）

### 模块四：文件管理增强 ✅

- `lib/features/file/services/file_service.dart` — 新增文件操作（重命名/删除/复制/移动/创建）
- `lib/features/file/providers/file_provider.dart` — 新增文件操作方法 + 刷新机制

### 模块五：编辑体验接口 ✅

| 接口 | 文件 | 说明 |
|------|------|------|
| 自动补全 | `extensions/completion_provider.dart` | 关键字补全 + AI 补全预留 |
| Diagnostics | `extensions/diagnostics_provider.dart` | 诊断管理器 |
| LSP | `extensions/lsp_provider.dart` | LSP 服务器接口（预留） |
| Code Action | `extensions/lsp_provider.dart` | CodeAction 模型 |
| Outline | `extensions/outline_provider.dart` | Dart Outline 提取器 |

### 模块六：路由与导航 ✅

- `lib/core/router/route_names.dart` — 新增编辑器/文件浏览器路由
- `lib/core/router/app_router.dart` — 注册所有新路由
- `lib/features/home/views/home_page.dart` — 新增编辑器/文件浏览器入口

---

## 三、新增文件清单

```
lib/features/editor/providers/editor_provider.dart        # 编辑器状态管理
lib/features/editor/views/editor_page.dart                # 编辑器主页面
lib/features/editor/widgets/editor_content.dart           # 编辑器内容组件
lib/features/editor/widgets/editor_gutter.dart            # 行号栏组件
lib/features/editor/widgets/editor_find_panel.dart        # 查找替换面板
lib/features/editor/extensions/completion_provider.dart   # 自动补全接口
lib/features/editor/extensions/diagnostics_provider.dart  # 诊断接口
lib/features/editor/extensions/lsp_provider.dart          # LSP接口 + CodeAction
lib/features/editor/extensions/outline_provider.dart      # Outline接口
lib/features/git/models/github_pr.dart                    # PR/Issue/Comment模型
lib/features/git/providers/github_pr_provider.dart        # PR状态管理
lib/features/git/providers/github_issue_provider.dart     # Issue状态管理
lib/features/git/views/pr_list_page.dart                  # PR列表页面
lib/features/git/views/issue_list_page.dart               # Issue列表页面
```

---

## 四、测试覆盖

| 测试文件 | 用例数 | 覆盖范围 |
|----------|--------|----------|
| `test/editor_buffer_test.dart` | 20+ | 编辑操作、光标、撤销/重做、查找替换、语言检测 |
| `test/syntax_highlighter_test.dart` | 15+ | 高亮器注册、关键字/字符串/注释、颜色、语言推断 |
| `test/github_pr_test.dart` | 8+ | PR/Issue/Comment 模型序列化 |

---

## 五、架构说明

### 编辑器架构

```
EditorPage (UI)
  ├── AppBar (工具按钮)
  ├── TabBar (多标签管理)
  ├── FindPanel (查找/替换)
  ├── EditorContent (语法高亮渲染)
  │   ├── Gutter (行号)
  │   └── Line (RichText + 语法Token)
  └── StatusBar (行/列/语言/编码)

EditorNotifier (状态管理)
  ├── EditorState (Tabs + Buffers + Settings)
  ├── EditorBuffer (文本编辑引擎)
  └── SyntaxRegistry (高亮器注册表)
```

### GitHub 集成架构

```
GitHubService (API 层)
  ├── 认证 (Token管理)
  ├── 仓库 (列表/搜索/详情)
  ├── Pull Request (列表/详情/评论)
  └── Issue (列表/详情/评论)

StateNotifier (状态层)
  ├── GitHubAuthNotifier
  ├── RepoListNotifier
  ├── PrListNotifier / PrDetailNotifier
  └── IssueListNotifier / IssueDetailNotifier

View (UI 层)
  ├── GitHubLoginPage / RepoListPage
  ├── PrListPage / IssueListPage
  └── GitOperationsPage
```

---

## 六、设计决策

1. **编辑器架构** — 采用 Buffer-View 分离模式，EditorBuffer 处理纯文本操作，EditorContent 负责渲染
2. **编辑器扩展** — 通过 CompletionProvider/DiagnosticsProvider/LspProvider 接口实现可扩展
3. **PR/Issue API** — 复用现有的 GitHubService，只新增 API 方法，不增加新的 HTTP 客户端
4. **文件操作** — 在 FileService 中添加直接操作，FileProvider 调用后自动刷新目录
5. **路由** — 编辑器路径支持 `:path` 参数传递文件路径

---

## 七、后续计划

Sprint 7 建议：
- 编辑器增量改进（文件树侧栏、AI 补全集成）
- GitHub 操作增强（PR 创建、Issue 创建）
- 代码审查功能
- 性能优化（大文件编辑、虚拟列表）
