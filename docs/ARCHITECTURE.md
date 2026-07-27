# 🏗️ Codex Mobile Pro — 架构文档

> **版本：** v1.0
> **最后更新：** 2026-07-27
> **本文档定义了项目的整体架构、模块依赖关系、数据流和通信协议，是所有开发的架构依据。**

---

## 目录

1. [整体架构图](#1-整体架构图)
2. [分层职责](#2-分层职责)
3. [模块依赖关系](#3-模块依赖关系)
4. [数据流](#4-数据流)
5. [通信协议](#5-通信协议)
6. [插件扩展机制](#6-插件扩展机制)
7. [错误处理流程](#7-错误处理流程)
8. [目录规范](#8-目录规范)
9. [命名规范](#9-命名规范)
10. [架构决策记录](#10-架构决策记录)

---

## 1. 整体架构图

```
┌──────────────────────────────────────────────────────────────────┐
│                      Flutter App (Dart)                          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    UI 层 (Widgets)                        │   │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ │   │
│  │  │ Home │ │  AI  │ │ Term │ │ File │ │  Git │ │Deploy│ │   │
│  │  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
│                            ↕                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   ViewModel 层 (Riverpod)                 │   │
│  │  各模块的 StateNotifier / AsyncNotifier / FutureProvider   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                            ↕                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Service 层 (核心逻辑)                   │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐ │   │
│  │  │TermuxSvc│ │  AISvc  │ │  GitSvc │ │ DeploySvc  │ │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └────────────┘ │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────────┐   │   │
│  │  │FileSvc  │ │  LogSvc  │ │  ConfigSvc (AES)    │   │   │
│  │  └──────────┘ └──────────┘ └──────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                            ↕                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Platform 层 (Native Bridge)             │   │
│  │               MethodChannel / EventChannel                │   │
│  └──────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────┤
│                      Android Runtime (Kotlin/Java)                │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                CodexMobileBridge (MethodChannel)          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐ │   │
│  │  │ProcessRunner │  │FileAccessor  │  │NotificationMgr│ │   │
│  │  └──────────────┘  └──────────────┘  └───────────────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────┤
│                    Termux 运行环境 (Linux)                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           命令执行层                                       │   │
│  │  ┌──────────────────┐    ┌───────────────────────────┐   │   │
│  │  │  Shell (bash/zsh) │    │   Tmux (会话管理)         │   │   │
│  │  └──────────────────┘    └───────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           应用层                                           │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐ │   │
│  │  │  Codex CLI   │  │ mimo2codex   │  │  Git           │ │   │
│  │  │  (AI 编程)   │  │ (DeepSeek代 )│  │  (版本控制)    │ │   │
│  │  └──────────────┘  └──────────────┘  └────────────────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────┤
│                      远程服务 (互联网)                             │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              DeepSeek API (api.deepseek.com)              │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              GitHub API (api.github.com)                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. 分层职责

### 2.1 UI 层（Flutter Widgets）

| 职责 | 说明 |
|------|------|
| 页面渲染 | 使用 Material 3 Widget 构建界面 |
| 用户交互 | 处理点击、输入、手势等事件 |
| 状态展示 | 监听 ViewModel 状态并刷新 UI |
| 导航 | 使用 GoRouter 管理页面路由 |
| 主题 | 亮色/暗色主题自适应 |

**规则：**
- Widget 不得直接调用 Service 层
- Widget 只能通过 Riverpod Provider 读取状态
- Widget 只能通过 Riverpod Notifier 触发操作
- Widget 内部不持有业务逻辑

### 2.2 ViewModel 层（Riverpod）

| 职责 | 说明 |
|------|------|
| 状态管理 | 持有页面状态，驱动 UI 刷新 |
| 业务编排 | 调用 Service 层完成业务逻辑 |
| 生命周期 | 管理页面数据的加载/刷新/销毁 |

**规则：**
- ViewModel 不直接操作 Platform 层
- ViewModel 通过 Service 层访问数据和功能
- ViewModel 负责处理加载态、空态、错误态

### 2.3 Service 层（核心逻辑）

| 服务 | 职责 |
|------|------|
| `TermuxService` | 执行 Termux 命令、管理进程生命周期 |
| `AIService` | AI API 通信、流式解析、重试、错误处理 |
| `GitService` | Git 命令封装、GitHub API 通信 |
| `DeployService` | 环境检测、一键安装/升级 |
| `FileService` | 文件和目录操作、文件监视 |
| `LogService` | 统一日志记录、文件落盘、日志级别 |
| `ConfigService` | 配置读写、AES 加密/解密 |

### 2.4 Platform 层（Native Bridge）

| 组件 | 职责 |
|------|------|
| `CodexMobileBridge` | 统一 MethodChannel 入口 |
| `ProcessRunner` | 在 Termux 中启动和管理进程 |
| `FileAccessor` | 访问 Android 文件系统（含存储权限） |
| `NotificationManager` | 后台通知和前台服务 |

### 2.5 Termux 层

| 组件 | 说明 |
|------|------|
| Shell (bash) | 默认命令执行环境 |
| Tmux | 终端会话管理（可选） |
| Codex CLI | OpenAI Codex 命令行工具 |
| mimo2codex | DeepSeek API 本地代理 |

---

## 3. 模块依赖关系

```
                    ┌──────────────────────┐
                    │     config_service    │
                    │  (配置/AES 加密/解密)  │
                    └──────────┬───────────┘
                               │ 所有模块依赖
                               ▼
┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐
│   home    │  │    ai     │  │ terminal  │  │   file    │  │    git    │
│  模块     │  │   模块    │  │   模块     │  │   模块    │  │   模块    │
└─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
      │              │              │              │              │
      │        ┌─────▼──────┐       │              │              │
      │        │ ai_service  │       │              │              │
      │        │ (API 通信)  │       │              │              │
      │        └─────┬──────┘       │              │              │
      │              │              │              │              │
      │        ┌─────▼──────────────▼─────┐  ┌─────▼──────┐       │
      │        │    termux_service        │  │file_service │       │
      │        │  (命令执行/进程管理)      │  │            │       │
      │        └─────┬────────────────────┘  └────────────┘       │
      │              │                                            │
      │        ┌─────▼──────────────────────────────────────────┐ │
      │        │         deploy_service                         │ │
      │        │  (环境检测/安装/升级/状态管理)                  │ │
      │        └────────────────────────────────────────────────┘ │
      │                                                            │
      └──────────────────────┬─────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  log_service    │
                    │  (统一日志)      │
                    └─────────────────┘
```

**依赖规则：**
- 模块之间**禁止循环依赖**
- UI 模块可依赖 Service 模块，反之不行
- Service 模块可依赖 platform 层，反之不行
- `config_service` 和 `log_service` 是基础服务，所有模块可依赖
- `termux_service` 是核心基础设施，deploy/ai/file/git 都依赖它

---

## 4. 数据流

### 4.1 AI 对话数据流

```
用户输入
    │
    ▼
[AI Chat View] ──tap send──▶ [ChatProvider (Riverpod)]
                                        │
                                        ▼
                               [AIService.sendMessage()]
                                        │
                                        ▼
                            ┌─────────────────────┐
                            │ 检查 mimo2codex 状态 │─── 未运行 → [DeployService.startMimo()]
                            └─────────┬───────────┘
                                      │ 已运行
                                      ▼
                            ┌─────────────────────┐
                            │  POST /v1/chat/     │──── HTTP ───▶ mimo2codex:8788
                            │  completions (SSE)  │                    │
                            └─────────────────────┘                    ▼
                                      │                        DeepSeek API
                                      │                          (远程)
                                      ▼
                            ┌─────────────────────┐
                            │   逐 chunk 解析 SSE   │
                            │   stream: "data:..."  │
                            └─────────────────────┘
                                      │
                                      ▼
                            [ChatProvider.streamUpdate()]
                                      │
                                      ▼
                            [AI Chat View rebuild]
                            (打字机效果展示)
```

### 4.2 命令执行数据流

```
[Terminal View] ──type command──▶ [TerminalProvider]
                                        │
                                        ▼
                               [TermuxService.execute()]
                                        │
                                        ▼
                            ┌─────────────────────┐
                            │  MethodChannel      │
                            │  "codex_mobile/exec"│
                            └─────────────────────┘
                                        │
                                        ▼
                            ┌─────────────────────┐
                            │  ProcessRunner       │
                            │  (Kotlin)            │
                            │  ProcessBuilder(...) │
                            └─────────────────────┘
                                        │
                                        ▼
                            ┌─────────────────────┐
                            │  Termux Shell       │
                            │  (bash -c "...")    │
                            └─────────────────────┘
                                        │
                              stdout/stderr
                                        │
                                        ▼
                            ┌─────────────────────┐
                            │  EventChannel       │
                            │  实时流式输出        │
                            └─────────────────────┘
                                        │
                                        ▼
                            [TerminalProvider]
                            (逐行更新输出内容)
                                        │
                                        ▼
                            [Terminal View]
                            (实时显示)
```

### 4.3 环境检测数据流

```
[Deploy View] ──tap "检测"──▶ [DeployProvider]
                                    │
                                    ▼
                         [DeployService.detectAll()]
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              [NodeDetector]  [GitDetector]  [CodexDetector]
              which node      which git     which codex
              node --version  git --version codex --version
                    │               │               │
                    └───────────────┼───────────────┘
                                    ▼
                         [DeployProvider.state]
                         更新各组件状态
                                    │
                                    ▼
                         [Deploy View]
                         (状态图标刷新)
```

---

## 5. 通信协议

### 5.1 Flutter ↔ Android Native（MethodChannel）

```dart
// === MethodChannel 定义 ===
const platform = MethodChannel('codex_mobile/bridge');

// 命令执行
final result = await platform.invokeMethod('exec', {
  'command': 'ls -la',
  'workingDirectory': '/data/data/com.termux/files/home',
  'timeoutMs': 30000,
  'environment': {'PATH': '/data/data/com.termux/files/usr/bin:...'},
});

// 返回值格式
{
  'success': true,
  'stdout': '...',
  'stderr': '',
  'exitCode': 0,
}
```

### 5.2 Flutter ↔ Android Native（EventChannel）

```dart
// === EventChannel 定义（用于实时流） ===
const eventChannel = EventChannel('codex_mobile/stream');

// 监听命令实时输出
eventChannel.receiveBroadcastStream().listen((event) {
  // event: { 'type': 'stdout'|'stderr'|'exit', 'data': '...' }
});
```

### 5.3 App ↔ mimo2codex (HTTP)

```http
POST http://127.0.0.1:8788/v1/chat/completions
Content-Type: application/json
Authorization: Bearer sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

{
  "model": "deepseek-chat",
  "messages": [
    {"role": "system", "content": "你是一个 AI 编程助手。"},
    {"role": "user", "content": "用 Flutter 写一个按钮"}
  ],
  "stream": true,
  "temperature": 0.7,
  "max_tokens": 4096
}
```

**SSE 流式响应格式：**

```
data: {"choices":[{"delta":{"content":"这"},"index":0}]}

data: {"choices":[{"delta":{"content":"是"},"index":0}]}

data: [DONE]
```

### 5.4 App ↔ GitHub API (HTTPS)

```http
GET https://api.github.com/user/repos
Authorization: Bearer ghp_xxxxxxxxxxxxxxxxxxxxxx
Accept: application/vnd.github.v3+json
```

---

## 6. 插件扩展机制

### 6.1 插件定义

每个插件是一个遵循以下规范的目录：

```
plugins/
└── <plugin-name>/
    ├── plugin.json          # 插件元数据
    ├── lib/
    │   └── main.dart        # 插件入口
    └── assets/               # 资源文件（可选）
```

### 6.2 plugin.json 规范

```json
{
  "name": "flutter-helper",
  "version": "1.0.0",
  "description": "Flutter 开发辅助工具",
  "author": "",
  "entry": "lib/main.dart",
  "permissions": ["termux", "file", "network"],
  "hooks": {
    "onCreate": "handleCreate",
    "onDestroy": "handleDestroy",
    "onCommand": "handleCommand"
  }
}
```

### 6.3 插件生命周期

```
安装 ──→ 启用 ──→ 初始化 ──→ 运行 ──→ 销毁
                  │
                  ├── onCreate()   — 插件首次加载
                  ├── onCommand()  — 接收到命令
                  └── onDestroy()  — 插件卸载
```

### 6.4 插件 API

插件可以通过以下接口与主应用交互：

```dart
// 插件可用的内置 API
abstract class PluginAPI {
  Future<String> execTermux(String cmd);     // 执行 Termux 命令
  Future<String> aiChat(String message);     // AI 对话
  Future<void> showNotification(String msg); // 显示通知
  Future<String> readFile(String path);      // 读取文件
  Future<void> writeFile(String path, String content); // 写入文件
  void log(String message);                  // 记录日志
}
```

---

## 7. 错误处理流程

### 7.1 错误处理层级

```
┌──────────────────────────────────────────┐
│              UI 层                        │
│  展示错误信息 / 重试按钮 / 空态页面         │
└──────────────────┬───────────────────────┘
                   │ 抛出错误
┌──────────────────▼───────────────────────┐
│           ViewModel 层                    │
│  AsyncValue.error 状态管理                 │
│  错误类型判断 → 降级方案                    │
└──────────────────┬───────────────────────┘
                   │ 抛出异常
┌──────────────────▼───────────────────────┐
│           Service 层                      │
│  错误分类 + 重试机制                        │
│  Result<T> 返回类型（Success / Failure）   │
└──────────────────┬───────────────────────┘
                   │ 捕获异常
┌──────────────────▼───────────────────────┐
│           Platform 层                     │
│  底层异常 → 包装为 AppException           │
└──────────────────────────────────────────┘
```

### 7.2 错误分类

| 错误类型 | 代码 | 说明 | 处理方式 |
|----------|------|------|---------|
| `NetworkError` | `E_NET` | 网络连接失败 / 超时 | 自动重试 + 用户提示 |
| `APIError` | `E_API` | API 返回错误 / Key 无效 | 引导用户检查配置 |
| `ExecError` | `E_EXEC` | 命令执行失败 / 超时 | 展示 stderr |
| `FileError` | `E_FILE` | 文件读写失败 / 权限不足 | 引导授权 |
| `ConfigError` | `E_CFG` | 配置损坏 / 解密失败 | 重置配置 |
| `PermissionError` | `E_PERM` | 权限未授予 | 引导前往设置 |
| `UnknownError` | `E_UNK` | 未预期的错误 | 记录日志 + 展示"未知错误" |

### 7.3 Result 模式

```dart
// Service 层统一返回 Result 类型
abstract class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final AppException error;
  const Failure(this.error);
}
```

### 7.4 全局异常捕获

```dart
void main() {
  runZonedGuarded(() {
    FlutterError.onError = (details) {
      LogService.error('FlutterError', details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      LogService.error('PlatformError', error, stack);
      return true;
    };
    runApp(const CodexMobileApp());
  }, (error, stack) {
    LogService.error('Unhandled', error, stack);
  });
}
```

---

## 8. 目录规范

```
codex-mobile-pro/
├── android/                    # Android 原生代码
├── lib/
│   ├── main.dart               # 应用入口
│   ├── app.dart                # MaterialApp + 路由 + 主题
│   │
│   ├── core/                   # 核心基础设施
│   │   ├── theme/              # 主题配置
│   │   │   ├── app_theme.dart
│   │   │   ├── colors.dart
│   │   │   └── typography.dart
│   │   ├── logger/             # 日志系统
│   │   │   ├── log_service.dart
│   │   │   └── log_level.dart
│   │   ├── error/              # 异常处理
│   │   │   ├── app_exception.dart
│   │   │   ├── result.dart
│   │   │   └── error_handler.dart
│   │   ├── i18n/               # 国际化
│   │   │   ├── app_localizations.dart
│   │   │   ├── strings_zh.dart
│   │   │   └── strings_en.dart
│   │   ├── router/             # 路由
│   │   │   ├── app_router.dart
│   │   │   └── route_names.dart
│   │   ├── platform/           # Native Bridge
│   │   │   ├── termux_bridge.dart
│   │   │   └── platform_types.dart
│   │   └── config/             # 配置管理
│   │       └── config_service.dart
│   │
│   ├── features/               # 功能模块
│   │   ├── home/               # 首页
│   │   │   ├── models/
│   │   │   ├── providers/
│   │   │   ├── views/
│   │   │   └── widgets/
│   │   ├── ai/                 # AI 对话
│   │   │   ├── models/
│   │   │   ├── providers/
│   │   │   ├── services/
│   │   │   ├── views/
│   │   │   └── widgets/
│   │   ├── terminal/           # 终端
│   │   ├── file/               # 文件管理
│   │   ├── git/                # Git
│   │   ├── deploy/             # 部署中心
│   │   └── settings/           # 设置
│   │
│   └── shared/                 # 共享组件
│       ├── widgets/            # 通用 Widget
│       │   ├── status_card.dart
│       │   ├── loading_overlay.dart
│       │   ├── error_dialog.dart
│       │   └── code_block.dart
│       ├── models/             # 通用数据模型
│       │   ├── app_state.dart
│       │   └── workspace.dart
│       └── utils/              # 工具函数
│           ├── extensions.dart
│           ├── validators.dart
│           └── formatters.dart
│
├── test/                       # 单元测试 / Widget 测试
├── integration_test/           # 集成测试
├── docs/                       # 文档
├── assets/                     # 资源文件
├── plugins/                    # 插件仓库（预留）
│
├── pubspec.yaml
├── analysis_options.yaml
└── CHANGELOG.md
```

---

## 9. 命名规范

| 类别 | 规范 | 示例 |
|------|------|------|
| **文件/目录** | `snake_case` | `config_service.dart` |
| **Dart 类** | `PascalCase` | `TermuxService` |
| **Dart 方法** | `camelCase` | `executeCommand()` |
| **Dart 变量** | `camelCase` | `exitCode` |
| **Dart 常量** | `camelCase` | `defaultTimeout` |
| **Provider** | `camelCase` + 类型后缀 | `chatProvider`, `deployStateProvider` |
| **Widget 文件** | `snake_case` | `ai_chat_view.dart` |
| **模型类** | `PascalCase` | `ChatMessage`, `Workspace` |
| **枚举** | `PascalCase` | `AppStatus` |
| **枚举值** | `camelCase` | `AppStatus.online` |
| **测试文件** | `_test` 后缀 | `ai_service_test.dart` |
| **注释** | 中文 | `// 执行 Termux 命令` |

---

## 10. 架构决策记录 (ADR)

### ADR-001：使用 Riverpod 作为状态管理方案

| 项目 | 内容 |
|------|------|
| **状态** | ✅ 已采纳 |
| **理由** | 编译安全、无需 BuildContext 即可访问、支持异步状态、测试友好 |
| **替代方案** | BLoC（样板代码多）、Provider（已停止维护）、GetX（过度设计） |

### ADR-002：MethodChannel 作为 Flutter ↔ Native 通信方式

| 项目 | 内容 |
|------|------|
| **状态** | ✅ 已采纳 |
| **理由** | 官方推荐、类型安全、支持双向通信 |
| **替代方案** | Pigeon（需要代码生成，增加了复杂度） |

### ADR-003：模块采用 Feature-first 目录结构

| 项目 | 内容 |
|------|------|
| **状态** | ✅ 已采纳 |
| **理由** | 每个模块自包含，便于多人协作和按模块拆分测试 |
| **替代方案** | Layer-first（跨层耦合高，不利于模块独立演进） |

### ADR-004：Service 层返回 Result 类型而非抛出异常

| 项目 | 内容 |
|------|------|
| **状态** | ✅ 已采纳 |
| **理由** | 显式处理错误，调用方必须处理 Failure 情况，不会遗漏异常处理 |
| **替代方案** | try-catch（容易遗漏未捕获异常） |

### ADR-005：AI 请求通过本地 mimo2codex 代理转发

| 项目 | 内容 |
|------|------|
| **状态** | ✅ 已采纳 |
| **理由** | 国内直连无需翻墙、API Key 不出设备、兼容 OpenAI 标准接口 |
| **替代方案** | 直接调用 DeepSeek API（需要翻墙或 VPN） |

---

> **本文档将随项目迭代持续更新**
> **任何架构变更必须更新本文档 + 记录 ADR**
