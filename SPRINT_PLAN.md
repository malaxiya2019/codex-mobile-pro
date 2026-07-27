# 📋 Codex Mobile Pro — Sprint 迭代计划

> **总览：** 10 个 Sprint，从技术验证到发布版
> **原则：** 每个 Sprint 都是可运行、可验证的版本，完成后才进入下一个 Sprint
> **代码量预估：** 20,000 ~ 30,000 行

---

## 开发守则

1. **每完成一个 Sprint 才允许进入下一个 Sprint**
2. **禁止一次性生成大量代码** — 每个任务增量提交
3. **每个 Sprint 必须输出：**
   - ✅ 编译通过（Debug 模式，无新增严重警告）
   - ✅ 《Sprint 开发报告》（`docs/sprints/sprint-N-开发报告.md`）
   - ✅ 《Sprint 测试报告》（`docs/sprints/sprint-N-测试报告.md`）
   - ✅ 更新 `CHANGELOG.md`
4. **未经确认，不得擅自修改已完成模块的架构**
5. **每个 Sprint 必须对比 Sprint 0 建立的性能基线**，确保性能不退化

---

## Sprint 总览

| Sprint | 名称 | 预计工作量 | 核心交付物 |
|--------|------|-----------|-----------|
| **Sprint 0** | 🔬 技术验证 (PoC) | 5~7 天 | 5 个 Milestone 全部通过 |
| **Sprint 1** | 🏗️ 项目框架 | 3~5 天 | Flutter 工程骨架 |
| **Sprint 2** | 🏠 首页 + 工作区 | 3~5 天 | 首页卡片、工作区管理 |
| **Sprint 3** | 🚀 部署中心 | 3~5 天 | 环境检测、一键安装 |
| **Sprint 4** | 💬 AI 对话 | 5~7 天 | 流式聊天、代码高亮 |
| **Sprint 5** | 💻 内置终端 | 3~5 天 | PTY、多标签、快捷命令 |
| **Sprint 6** | 📁 文件管理 | 3~5 天 | 文件树、编辑器、搜索 |
| **Sprint 7** | 🔗 GitHub 集成 | 3~5 天 | Clone/Push/Pull/分支 |
| **Sprint 8** | 🤖 AI 编程增强 | 5~7 天 | 修 Bug/Review/重构/Commit |
| **Sprint 9** | 📦 发布版 | 3~5 天 | 自动更新、优化、崩溃采集 |

---

## Sprint 0：🔬 技术验证（PoC）

> **这是整个项目最关键的一个 Sprint，将拆分为 5 个 Milestone 依次验证。**
> **所有 Milestone 全部通过，才能进入 Sprint 1。**
> **后续每个 Sprint 的性能数据必须与此 Sprint 建立的基线对比，不得退化。**

```
Sprint 0 里程碑路线：

M0.1 ──→ M0.2 ──→ M0.3 ──→ M0.4 ──→ M0.5
 环境      Termux    依赖        AI      性能
验证      通信验证   检测      通信验证   基线
 ✅        ✅        ✅        ✅        ✅
                    ↓
              进入 Sprint 1 🏗️
```

---

### Milestone 0.1：环境验证

> **目标：Flutter 工程可正常运行在 Android 10~15 设备上**

#### 验证清单

| # | 验证项 | 通过标准 |
|---|--------|---------|
| 1 | Flutter 工程初始化 | `flutter create` 成功，工程结构完整 |
| 2 | Android 10~15 兼容 | `minSdkVersion 21`, `targetSdkVersion 35` |
| 3 | Material 3 正常显示 | `useMaterial3: true`，基础组件渲染正常 |
| 4 | Riverpod 集成成功 | 添加 `flutter_riverpod` 依赖，编写一个简单的 Provider 并正常读取 |
| 5 | Debug 构建通过 | `flutter build apk --debug` 成功，APK 生成 |
| 6 | Release 构建通过 | `flutter build apk --release` 成功 |

#### 验收标准

| 指标 | 目标值 |
|------|--------|
| 首次安装 App 成功 | ✅ 通过 |
| 冷启动时间 | < 3 秒 |
| 运行稳定性 | 无崩溃 |
| 页面切换 | 无白屏、无卡顿 |

#### 任务

```
sprint-0/milestone-0.1/
├── TASK-01-flutter-init.md         # Flutter 工程初始化
├── TASK-02-android-compat.md       # Android 版本兼容配置
├── TASK-03-material3-setup.md      # Material 3 主题配置
├── TASK-04-riverpod-setup.md       # Riverpod 状态管理集成
├── TASK-05-build-verify.md         # Debug/Release 构建验证
└── TASK-06-cold-start-test.md      # 冷启动时间测试
```

---

### Milestone 0.2：Termux 通信验证（最关键）

> **目标：验证 Flutter App 与 Termux 命令行环境的双向通信能力**
> **这是整个项目的技术基石——如果 App 无法可靠地与 Termux 通信，后续所有模块都无从谈起**

#### 验证清单

| # | 验证项 | 通过标准 |
|---|--------|---------|
| 1 | Flutter 能启动 Termux 命令 | 通过 `Process.run` / `Process.start` 调用 Termux 内的 shell 命令 |
| 2 | 执行 `pwd` | 返回 `/data/data/com.termux/files/home` |
| 3 | 执行 `ls` | 返回正确的目录列表 |
| 4 | 读取标准输出（stdout） | 完整获取、无截断、无乱码 |
| 5 | 读取标准错误（stderr） | 错误命令能正常捕获 stderr |
| 6 | 获取退出码 | 正常命令返回 0，异常命令返回非 0 |
| 7 | 长时间运行命令 | `sleep 5` 等命令能等待完成 |
| 8 | 环境变量传递 | 能读取 Termux 内的 `$HOME`、`$PATH` 等变量 |

#### 验收标准

| 指标 | 目标值 |
|------|--------|
| 成功执行命令数 | ≥ 10 条不同命令 |
| 输出完整性 | 完整、无乱码、无截断 |
| 连续测试 | 连续 50 次调用，成功率 100% |

#### 边界情况测试

| 场景 | 预期行为 |
|------|---------|
| 命令不存在 | stderr 有提示，退出码非 0 |
| 命令超时 | 可配置超时，超时后终止进程 |
| 命令含中文输出 | 无乱码 |
| 大量输出（>1MB） | 无 OOM，无截断 |
| 特殊字符 | `$`, `"`, `'`, `\`, ```, `|` 能正确处理 |

#### 任务

```
sprint-0/milestone-0.2/
├── TASK-01-termux-command-bridge.md    # 命令执行桥接层
├── TASK-02-stdout-stderr-capture.md    # 标准输出/错误捕获
├── TASK-03-exit-code-handling.md       # 退出码处理
├── TASK-04-timeout-mechanism.md        # 超时机制
├── TASK-05-special-char-test.md        # 特殊字符兼容
└── TASK-06-bulk-cmd-test.md            # 批量命令测试（50 次）
```

---

### Milestone 0.3：依赖检测验证

> **目标：自动检测手机/Termux 环境中已安装的开发工具链，输出统一状态面板**

#### 检测项

| # | 检测项 | 检测方式 | 备选方案 |
|---|--------|---------|---------|
| 1 | Flutter SDK | `which flutter` / `flutter --version` | — |
| 2 | Termux 环境 | 检查 `/data/data/com.termux` 目录 | — |
| 3 | Node.js | `which node` / `node --version` | — |
| 4 | Git | `which git` / `git --version` | — |
| 5 | Python 3 | `which python3` / `python3 --version` | `which python` |
| 6 | Curl | `which curl` | — |
| 7 | Codex CLI | `which codex` / `codex --version` | `npm list -g @openai/codex` |
| 8 | mimo2codex | `which mimo2codex` | 检查 `~/.local/bin/mimo2codex` |
| 9 | DeepSeek API Key | 检查 `~/.mimo2codex/.env` | 检查环境变量 `DEEPSEEK_API_KEY` |
| 10 | 存储权限 | 检查 `/sdcard/Download` 是否可读 | — |

#### 统一状态输出

```
┌─────────────────────────────┐
│  系统状态仪表盘              │
├─────────────────────────────┤
│ ✅ Flutter      v3.xx.x     │
│ ✅ Termux       OK          │
│ ✅ Node.js      v22.x.x     │
│ ✅ Git          v2.x.x      │
│ ✅ Python 3     v3.x.x      │
│ ✅ Curl         OK          │
│ ✅ Codex CLI    v0.x.x      │
│ ✅ mimo2codex   v1.x.x      │
│ ✅ DeepSeek API 已配置       │
│ ✅ 存储权限     已授权       │
└─────────────────────────────┘
```

#### 验收标准

| 指标 | 目标值 |
|------|--------|
| 检测完成时间 | < 3 秒 |
| 检测准确率 | 100%（无漏检、无误报） |
| 状态刷新 | 支持手动刷新 + 页面进入时自动刷新 |

#### 任务

```
sprint-0/milestone-0.3/
├── TASK-01-env-detector-base.md        # 环境检测基类
├── TASK-02-individual-detectors.md     # 各工具独立检测器
├── TASK-03-status-panel-ui.md          # 状态面板 UI
├── TASK-04-auto-refresh.md             # 自动刷新机制
└── TASK-05-accuracy-test.md            # 准确率测试
```

---

### Milestone 0.4：AI 通信验证

> **目标：验证 App 与本地 mimo2codex 代理 + 远程 DeepSeek API 的通信链路**

#### 验证清单

| # | 验证项 | 通过标准 |
|---|--------|---------|
| 1 | 启动 mimo2codex | `mimo2codex --model ds --port 8788` 启动成功 |
| 2 | 健康检查 | `GET http://127.0.0.1:8788/health` 返回 200 |
| 3 | 普通请求 | `POST /v1/chat/completions` 返回完整响应 |
| 4 | 流式请求 | SSE 流式返回内容，逐 chunk 接收 |
| 5 | 超时处理 | 网络超时后抛出清晰异常，不崩溃 |
| 6 | 网络异常处理 | 断网/代理挂掉后优雅降级 |
| 7 | 自动重试 | 失败后自动重试（可配置重试次数和间隔） |
| 8 | 中文响应 | 中文问题返回中文回答 |
| 9 | Markdown 响应 | 返回内容含 Markdown 格式代码块 |

#### 验收标准

| 指标 | 目标值 |
|------|--------|
| 连续请求成功率 | ≥ 99%（50 次测试） |
| 首 Token 延迟 | < 3 秒 |
| 流式中断恢复 | 中断后重连成功 |
| 超时处理 | < 30 秒无响应触发超时 |

#### 错误处理矩阵

| 错误场景 | 表现 | 恢复策略 |
|----------|------|---------|
| mimo2codex 未启动 | 显示"代理未运行"提示 | 引导用户启动 |
| DeepSeek API Key 无效 | 显示"API Key 无效" | 引导重新配置 |
| 网络不可用 | 显示"网络不可用" | 监听网络状态变化自动恢复 |
| 请求超时 | 显示"请求超时，已重试 N 次" | 自动重试最多 3 次 |
| 服务端错误（5xx） | 显示"服务异常" | 自动重试 + 指数退避 |
| 频率限制（429） | 显示"请求过于频繁" | 等待后重试 |

#### 任务

```
sprint-0/milestone-0.4/
├── TASK-01-mimo2codex-lifecycle.md     # mimo2codex 启动/停止/状态管理
├── TASK-02-api-client-base.md          # OpenAI 兼容 API 客户端
├── TASK-03-streaming-parser.md         # SSE 流式解析器
├── TASK-04-error-handling.md           # 错误处理矩阵
├── TASK-05-retry-mechanism.md          # 自动重试 + 指数退避
├── TASK-06-timeout-control.md          # 超时控制
└── TASK-07-bulk-request-test.md        # 50 次批量测试
```

---

### Milestone 0.5：性能基线

> **目标：建立 App 性能基线数据，供后续每个 Sprint 对比参考**
> **后续任何 Sprint 如果导致性能显著退化，必须优化后才能合并**

#### 基线指标

| 类别 | 指标 | 测量方法 | 目标值 |
|------|------|---------|-------|
| **启动** | App 冷启动时间 | `adb logcat` 抓 ActivityManager 日志 | < 3 秒 |
| **启动** | App 热启动时间 | 按 Home 键后立即重新打开 | < 1 秒 |
| **内存** | 空闲内存占用 | `adb shell dumpsys meminfo` | < 80 MB |
| **内存** | AI 对话时内存峰值 | 连续对话 20 轮后测量 | < 150 MB |
| **CPU** | 空闲 CPU 占用 | `top` / `htop` 读取 | < 5% |
| **CPU** | AI 对话时 CPU 占用 | 流式输出期间测量 | < 30% |
| **AI** | 首 Token 延迟 | API 请求到第一个 token 的时间 | < 3 秒 |
| **AI** | 平均响应时间 | 完整请求/响应的平均耗时 | < 10 秒（较长回答） |
| **AI** | 50 次请求成功率 | 连续 50 次 API 调用 | ≥ 99% |
| **电池** | 连续 30 分钟耗电量 | Android BatteryManager API | < 5% |

#### 基线记录文档格式

```markdown
## 性能基线 v1.0 — Sprint 0
测试设备: [设备型号]
Android 版本: [版本号]
Termux 版本: [版本号]
测试日期: [日期]

### 启动性能
- 冷启动: [时间] 秒
- 热启动: [时间] 秒

### 内存占用
- 空闲: [数值] MB
- AI 对话峰值: [数值] MB

...（完整记录）
```

#### 任务

```
sprint-0/milestone-0.5/
├── TASK-01-baseline-tooling.md         # 性能测量工具/脚本
├── TASK-02-startup-time-measure.md     # 启动时间测量
├── TASK-03-memory-cpu-measure.md       # 内存/CPU 测量
├── TASK-04-ai-latency-measure.md       # AI 延迟测量
├── TASK-05-battery-measure.md          # 电池消耗测量
└── TASK-06-baseline-report.md          # 基线报告输出
```

---

### Sprint 0 交付物汇总

| 交付物 | 说明 |
|--------|------|
| `docs/sprints/sprint-0-验证报告.md` | 5 个 Milestone 的完整验证结果 |
| `docs/sprints/sprint-0-性能基线.md` | 性能基线数据 |
| `docs/sprints/sprint-0-测试报告.md` | 测试覆盖与结果 |
| `CHANGELOG.md` | Sprint 0 变更记录 |

---

## Sprint 1：🏗️ 项目框架

> **核心目标：搭建 Flutter 工程骨架，确立架构规范**

### 任务

| # | 任务 | 说明 |
|---|------|------|
| 1.1 | 目录结构搭建 | 按模块分包（lib/features/*） |
| 1.2 | 主题系统完善 | 亮色/暗色主题、字体配置（Sprint 0 已初始化） |
| 1.3 | 日志系统 | 统一日志记录（Logger + 文件落盘） |
| 1.4 | 异常处理 | 全局错误捕获、Crash 报告 |
| 1.5 | 国际化 | 中/英文语言包 |
| 1.6 | 路由框架 | 各模块路由注册、导航守卫 |

### 交付物
- 可编译运行的 Flutter App（含完整框架代码）
- `docs/sprints/sprint-1-开发报告.md`
- `docs/sprints/sprint-1-测试报告.md`
- `CHANGELOG.md` 更新
- **性能对比**：与 Sprint 0 基线对比，确保不退化

---

## Sprint 2：🏠 首页 + 工作区

> **核心目标：首页仪表盘 + 多工作区管理**

### 功能列表
- **首页卡片**
  - AI 状态（Online / Offline）
  - 模型信息（DeepSeek Chat）
  - 当前/最近项目
  - 快捷操作（新建项目 / 打开项目 / AI 编程 / 终端）
- **工作区管理**
  - 多工作区创建/切换/删除
  - 每个工作区独立的项目列表
  - 预设模板（Flutter / Rust / Python / 学习 / 实验）

### 交付物
- 首页 + 工作区功能完整可交互
- Sprint 开发报告 + 测试报告
- CHANGELOG 更新
- 性能对比（与基线）

---

## Sprint 3：🚀 部署中心

> **核心目标：环境检测 + 一键部署 Codex + mimo2codex**

### 功能列表
- **环境检测**（复用 Sprint 0 M0.3 的检测逻辑）
  - 检测项：Node / Git / Python / Curl / Termux / Storage / Codex / mimo2codex
  - 状态图标（✅ 已安装 / ⚠️ 未安装 / ❌ 缺失）
  - 一键修复缺失项
- **一键部署 Codex**
  - 检测已存在的 Codex 安装
  - 安装/升级 Codex CLI
  - 配置 DeepSeek API Key（AES 加密存储）
- **一键部署 mimo2codex**
  - 安装/升级 mimo2codex 代理
  - 配置代理参数
  - 启动/停止/重启代理
- **部署状态面板**
  - 各组件运行状态实时显示
  - 一键诊断

### 交付物
- 部署中心可完整走通：环境检测 → 安装 → 配置 → 启动
- Sprint 开发报告 + 测试报告
- CHANGELOG 更新

---

## Sprint 4：💬 AI 对话

> **核心目标：完整的 AI 聊天交互界面**

### 功能列表
- **对话界面**
  - 消息列表（用户消息 + AI 回复）
  - 流式输出（打字机效果）
  - Markdown 渲染
  - 代码高亮（支持 Dart/Rust/Python/Java/C++/HTML/CSS/JSON/YAML）
  - 代码复制按钮
- **会话管理**
  - 新建会话
  - 历史会话列表（按时间分组）
  - 删除/清空会话
  - 会话标题自动生成（基于首条消息）
- **输入区域**
  - 多行输入框
  - 发送按钮
  - 快捷键（Enter 发送，Shift+Enter 换行）
- **上下文管理**
  - 支持文件引用（@文件名）
  - 支持工作区代码上下文

### 交付物
- 完整可用的 AI 对话页面
- 连接真实 DeepSeek API 测试通过
- Sprint 开发报告 + 测试报告
- CHANGELOG 更新

---

## Sprint 5：💻 内置终端

> **核心目标：App 内嵌终端，支持多标签和 tmux**

### 功能列表
- **终端模拟**
  - 基于 `flutter_terminal` 或 `termux-widget` 协议
  - PTY（伪终端）支持
  - ANSI 颜色转义序列支持
- **多标签**
  - 新建/关闭标签
  - 标签切换（左右滑动或点击）
  - 标签重命名（双击）
- **交互功能**
  - 复制/粘贴
  - 快捷命令面板（预设命令列表）
  - 文本选择
  - 字体大小调整
- **集成**
  - 一键从 AI 对话跳转到终端
  - 终端输出可发送到 AI 对话

### 交付物
- 可交互的内置终端
- 多标签切换正常
- Sprint 开发报告 + 测试报告
- CHANGELOG 更新

---

## Sprint 6：📁 文件管理

> **核心目标：文件浏览器 + 编辑器 + 搜索**

### 功能列表
- **文件树**
  - 目录展开/折叠
  - 文件图标（按类型）
  - 右键菜单（新建/重命名/删除/复制）
  - 文件搜索/过滤
- **文件编辑器**
  - 语法高亮（支持 Dart/Rust/Python/Java/C++/Markdown/JSON/YAML/HTML/CSS）
  - 多标签编辑
  - 保存/撤销/重做
  - 行号显示
- **收藏/最近文件**
  - 文件收藏
  - 最近打开文件列表
- **文件操作**
  - 新建文件/目录
  - 重命名
  - 删除（到回收站或直接删除）
  - 文件信息查看

### 交付物
- 文件树可浏览工作区目录
- 编辑器可编辑/保存文件
- Sprint 开发报告 + 测试报告
- CHANGELOG 更新

---

## Sprint 7：🔗 GitHub 集成

> **核心目标：Git 操作 + GitHub 登录**

### 功能列表
- **GitHub 登录**
  - OAuth 设备授权码流程
  - Token 安全存储
  - 登录状态管理
- **仓库管理**
  - 查看个人仓库列表
  - Clone 仓库到工作区
  - 仓库信息查看
- **Git 操作**
  - `git status` 查看变更
  - `git add` / `git restore` 暂存/撤销
  - `git commit`（可配合 AI 生成 Commit Message）
  - `git push` / `git pull`
  - 分支管理（创建/切换/合并/删除）
  - Tag 管理
- **Git 可视化**
  - 文件变更列表
  - Diff 查看器（行级高亮）
  - 提交历史列表

### 交付物
- GitHub 登录 + 仓库 Clone 完整流程
- 基本 Git 操作可用
- Sprint 开发报告 + 测试报告
- CHANGELOG 更新

---

## Sprint 8：🤖 AI 编程增强

> **核心目标：AI 辅助编程功能集成**

### 功能列表
- **AI 修 Bug**
  - 选中代码/粘贴报错日志 → AI 分析原因 + 给出修复方案
  - 支持一键应用修复
- **AI 解释代码**
  - 选中代码 → AI 生成中文/英文解释
- **AI 重构**
  - 选中代码 → AI 提供重构建议
  - 支持：提取函数、重命名、模块化、拆文件
- **AI 生成 Commit Message**
  - 分析 `git diff` → 自动生成 Commit Message
  - 支持中/英文
- **AI 代码审查**
  - 选中代码或文件 → AI 分析性能/质量/安全/重复/复杂度
- **AI 生成测试**
  - 选中函数/类 → AI 生成单元测试

### 交付物
- 各 AI 功能在对话和菜单中可用
- 端到端测试通过（使用真实 DeepSeek API）
- Sprint 开发报告 + 测试报告
- CHANGELOG 更新

---

## Sprint 9：📦 发布版

> **核心目标：完成发布前的最后一公里**

### 功能列表
- **自动更新**
  - 检查 GitHub Release 新版本
  - 后台下载 APK
  - 安装提示
- **备份恢复**
  - 配置（API Key / 主题 / 工作区）备份到文件
  - 一键恢复
- **性能优化**
  - 启动速度优化
  - 内存使用优化
  - 大文件编辑器性能
- **崩溃采集**
  - 全局异常捕获
  - Crash 日志本地保存
  - 可选的崩溃上报
- **日志中心**
  - 统一查看 App 日志
  - 日志级别过滤
  - 日志导出
- **关于页面**
  - 版本号
  - 开源许可
  - 更新日志入口

### 交付物
- 可发布的 APK
- 《发布报告》
- 《最终测试报告》
- 完整的 `CHANGELOG.md`

---

## 技术架构参考

```
┌─────────────────────────────────────────────────┐
│              Flutter App (Material 3)             │
│  ┌─────┬──────┬──────┬──────┬──────┬──────┐      │
│  │ Home│  AI  │ Term │ File │  Git │Deploy│      │
│  └─────┴──────┴──────┴──────┴──────┴──────┘      │
│  ┌──────────────────────────────────────────┐     │
│  │           Riverpod (状态管理)              │     │
│  └──────────────────────────────────────────┘     │
├─────────────────────────────────────────────────┤
│          Native Bridge (Method Channel)           │
├─────────────────────────────────────────────────┤
│          Termux Service (命令行环境)              │
│  ┌──────────────┐  ┌──────────────────────┐      │
│  │  Codex CLI   │  │   mimo2codex (代理)   │      │
│  └──────────────┘  └──────────────────────┘      │
│  ┌──────────────────────────────────────────┐     │
│  │         DeepSeek API (远程)               │     │
│  └──────────────────────────────────────────┘     │
└─────────────────────────────────────────────────┘
```

---

## 版本与里程碑

```
Sprint 0 ──→ Sprint 1 ──→ Sprint 2 ──→ Sprint 3 ──→ Sprint 4
   │            │            │            │            │
   ▼            ▼            ▼            ▼            ▼
  PoC ✅     骨架 🏗️     首页 🏠     部署 🚀      AI 💬

Sprint 5 ──→ Sprint 6 ──→ Sprint 7 ──→ Sprint 8 ──→ Sprint 9
   │            │            │            │            │
   ▼            ▼            ▼            ▼            ▼
 终端 💻     文件 📁     GitHub 🔗    AI 增强 🤖    发布 📦

                                ┌─────────────────────┐
                                │   V1.0 MVP 发布 🎉   │
                                └─────────────────────┘
```

---

> **本规划基于《Codex Mobile Pro 开发规划书 V1.0》拆解**
> **最后更新：2026-07-27**
