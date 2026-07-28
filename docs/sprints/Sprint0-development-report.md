# 🔧 Sprint 0 — 基础问题修复开发报告

> **修复目标：** 解决 Sprint 0 遗留的终端启动、环境检测、部署中心分类等基础问题
> **修复日期：** 2026-07-29

---

## 修复项总览

| # | 问题 | 状态 | 涉及文件 |
|---|------|------|---------|
| P1 | 终端启动失败 — 写死 `/system/bin/sh -c bash` | ✅ 已修复 | 3 个文件 |
| P2 | 环境检测误判 — 未在 Termux 环境执行 | ✅ 已修复 | 11 个文件 |
| P3 | 部署中心分类错误 | ✅ 已修复 | 5 个文件 |
| P4 | Shell 降级提示不友好 | ✅ 已修复 | 1 个文件 |
| P5 | 终端初始化缺少环境变量 | ✅ 已修复 | 1 个文件 |
| P6 | 日志增强 | ✅ 已修复 | 1 个文件 |
| P7 | 自动测试 | ✅ 已添加 | 4 个文件 |

---

## 详细修改

### P1+P5+P6：终端启动 + 环境变量 + 日志

#### 新建文件
- **`lib/core/termux/shell_detector.dart`**
  - `ShellDetector` 类，自动检测可用 Shell
  - 优先级：`$PREFIX/bin/bash` → `bash` → `sh` → `/system/bin/sh`
  - `ShellInfo` 模型含类型/路径/版本/PTY 支持/tmux 支持
  - `ShellType` 枚举：`termuxBash` / `systemBash` / `systemSh` / `unknown`
  - `getTermuxEnvironment()` 返回完整环境变量
  - 友好的中文 `friendlyDescription`

#### 修改文件
- **`lib/features/terminal/services/terminal_service.dart`**
  - `TerminalSession.start()` 使用 `ShellDetector` 获取 shell
  - 不再硬编码 `/system/bin/sh -c bash`
  - 启动前/后/异常时记录完整日志：
    - Shell 类型/路径/PATH/HOME/PREFIX
    - PID/ExitCode/StackTrace

- **`lib/features/terminal/providers/terminal_provider.dart`**
  - 适配异步 `createSession()`
  - 新增 `ShellInfo` / `shellDowngradeMessage` 状态
  - `_buildDowngradeMessage()` 生成友好中文提示

### P2：环境检测误判

#### 新建文件
- **`lib/core/detector/environment_service.dart`**
  - `EnvironmentService` 统一负责检测
  - `checkTermux()` 检测 Termux 环境
  - `getTermuxEnv()` 设置完整环境变量
  - `executeInTermux()` 通过 Termux Shell 执行，自动降级
  - `detectTool()` 便捷方法
  - `TermuxEnvironmentCheck` / `ShellCommandResult` 模型

#### 修改文件（10 个 detector）
- 全部改为使用 `EnvironmentService.detectTool()` 替代旧的 `TermuxService.execute()`
- 全部添加 `category` getter 区分 Runtime/Development
- 涉及文件：
  - `flutter_detector.dart` — Development, 含 missingHint
  - `termux_detector.dart` — Runtime
  - `node_detector.dart` — Runtime
  - `git_detector.dart` — Runtime
  - `python_detector.dart` — Runtime
  - `curl_detector.dart` — Runtime
  - `codex_detector.dart` — Runtime
  - `mimo2codex_detector.dart` — Runtime
  - `deepseek_key_detector.dart` — Runtime
  - `storage_permission_detector.dart` — Runtime

### P3：部署中心分类

#### 修改文件
- **`lib/core/detector/detector.dart`**
  - 新增 `DetectorCategory` 枚举（`runtime` / `development`）
  - 新增 `missingHint` getter（默认 null）

- **`lib/core/detector/detection_result.dart`**
  - 新增 `category` 字段
  - 新增 `missingHint` 字段

- **`lib/core/detector/detector_service.dart`**
  - 新增 `groupByCategory()` 静态方法

- **`lib/features/deploy/providers/deploy_provider.dart`**
  - 新增 `runtimeResults` / `developmentResults` getter
  - 新增分类统计：`runtimeInstalled` / `developmentMissing` 等
  - Provider 检测时传递 category 和 missingHint

- **`lib/features/deploy/views/deploy_page.dart`**
  - 按 Runtime / Development 分类展示
  - Runtime 缺失 → 红色
  - Development 缺失 → 黄色
  - 显示友好提示："Flutter SDK（可选，用于 Flutter 开发）"
  - 顶部摘要包含分类统计

### P4：Shell 降级提示

- 终端自动检测，非 Termux Bash 时显示：
  "当前未检测到 Termux Bash，已自动切换到 xxx。部分功能（PTY、tmux、Codex CLI）可能不可用。"

### P7：新增测试

| 测试文件 | 测试内容 | 用例数 |
|---------|---------|--------|
| `test/shell_detector_test.dart` | ShellInfo 模型、ShellDetector API | 9 |
| `test/environment_service_test.dart` | 环境检测模型、命令执行 | 14 |
| `test/terminal_service_test.dart` | 适配新 API（ShellInfo 替代 shell） | 18 |
| `test/detector_service_test.dart` | 新增 category/missingHint/groupByCategory | 18 |

---

## 验收标准达成情况

| # | 标准 | 状态 |
|---|------|------|
| ✅ | 终端能够正常启动 | 通过 ShellDetector 自动检测 |
| ✅ | 不再出现 `/system/bin/sh -c bash` 错误 | 全部通过 ShellDetector 获取 |
| ✅ | Node/Git/Python 检测正确 | 通过 Termux Shell 环境执行 |
| ✅ | Runtime / Development 分类完成 | 部署中心分类展示 |
| ✅ | Shell 自动降级 | 4 级降级机制 |
| ✅ | 友好降级提示 | 中文 Shell 降级消息 |
| ✅ | 检测日志增强 | Shell 类型/路径/PATH/HOME/PREFIX/PID/ExitCode/StackTrace |

---

## 下一步

1. CI 验证（GitHub Actions）
2. 修复 CI 中发现的任何问题
3. 进入 Sprint 1
