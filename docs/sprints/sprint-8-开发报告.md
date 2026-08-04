# Sprint 8 开发报告 — AI 编程增强

> **Sprint 周期：** 2026-07-28
> **状态：** ✅ 完成

---

## 一、概述

Sprint 8 按规划书完成「AI 编程增强」：将 Sprint 7 分散的 AI 能力收口为统一服务层，并补齐 AI 对话引擎。实际落地 **3 个 Milestone + 1 个功能批次**（与 CHANGELOG 一致）：

1. **AIProviderManager（M1）** — 多 AI Provider 注册 / 健康检查 / 自动选择
2. **AI Chat Engine（M2）** — 流式对话引擎（IChatEngine 架构）
3. **ChatProvider 迁移（M3）** — 对话页迁移到 IChatEngine + AIProviderManager
4. **AI 编程四件套（feat(sprint-8)）** — 修 Bug / 重构建议 / 生成测试 / Commit Message

最终所有 AI 能力统一由 `CodeAssistService` 暴露，编辑器页与 Git 操作台共享。

---

## 二、模块实现详情

### 模块一：AI Provider 管理（Milestone 1）✅

- `lib/features/ai/providers/ai_provider_manager.dart`
  - `AIProviderManager` — Provider 注册表 + 健康检查 + 自动选择
  - `_selectProvider()` 按注册顺序选择首个就绪 Provider（`_findNextReadyProvider`）
  - 健康检查 Timer + 优雅释放（`dispose`）
  - 默认注册 `DeepSeekProvider`（本地 mimo zero-auth，无需 API Key）

### 模块二：AI Chat Engine（Milestone 2）✅

- `lib/features/ai/services/chat_engine.dart`
  - `IChatEngine` — 流式对话抽象接口（systemPrompt / streamChat）
  - 基于 `IChatEngine` 的流式实现：SSE 解析 → 逐 chunk 回调 → 会话上下文累积
- `lib/features/ai/providers/chat_provider.dart`（255 行）
  - `chatEngineProvider` / `aiProviderManagerProvider` — Riverpod 注入
  - `ChatState` / `ChatLoadingState` — 对话 UI 状态

### 模块三：ChatProvider 架构迁移（Milestone 3）✅

- `lib/features/ai/providers/chat_provider.dart` — 从直连 AI Client 迁移到 `IChatEngine`
  - 对话页不再关心底层 Provider/协议，只消费 `ChatState` 流
  - `aiProviderManagerProvider` 内注册默认 DeepSeek + `unawaited(initialize())` + `ref.onDispose(dispose)`
- 配套修复：AI 对话页「未收到有效回复」空流问题（空流根因 = `_registrations` 为空，无任何代码调用 `register()`，见 08-02 会话记录）

### 模块四：AI 统一服务层 — CodeAssistService ✅

- `lib/features/ai/services/code_assist_service.dart`（554 行）
  - `CodeAssistService` — 统一 AI 辅助入口（注入 IChatEngine，不依赖具体 Provider）
  - 数据模型：`AiAssistResult` / `CodeReviewReport` / `CodeIssue` / `CommitMessageResult`
  - 方法：`fixBug` / `explainCode` / `refactorCode` / `generateTest` / `generateCommitMessage` / `codeReview`

#### AI 修 Bug
- `CodeAssistService.fixBug` — 粘贴错误日志 → 根因分析 + 修复代码
- `lib/features/editor/extensions/fix_error.dart`（315 行，Sprint 7 已有，Sprint 8 收口到统一服务）

#### AI 重构
- `CodeAssistService.refactorCode` + `lib/features/editor/extensions/refactor_code.dart`（178 行）
  - `RefactorResult` — 重构说明 / 重构后完整代码 / 变更点列表

#### AI 生成测试
- `CodeAssistService.generateTest` + `lib/features/editor/extensions/generate_test.dart`（155 行）
  - `TestGenResult` — 生成的 flutter_test 代码 / 建议文件名 / 错误标记

#### AI 生成 Commit Message
- `CodeAssistService.generateCommitMessage` — git diff → 规范化 commit message（类型 + 摘要 + 明细）
- `lib/features/git/views/git_operations_page.dart` — 提交对话框新增「AI 生成」按钮

### 模块五：AI 对话页 ✅

- `lib/features/ai/views/ai_chat_page.dart`（518 行）
  - 流式对话 UI：消息列表 / 流式渲染 / 发送与中断
  - 与编辑器 AI 功能共用 `CodeAssistService` 底层引擎

---

## 三、新增/主要变更文件清单

| 文件 | 行数 | 说明 |
|------|------|------|
| `lib/features/ai/services/code_assist_service.dart` | 554 | 统一 AI 辅助服务层（修 Bug/重构/测试/Commit/审查/解释） |
| `lib/features/ai/services/chat_engine.dart` | — | IChatEngine 流式对话引擎 |
| `lib/features/ai/providers/chat_provider.dart` | 255 | ChatProvider 迁移 IChatEngine + AIProviderManager 注册 |
| `lib/features/ai/providers/ai_provider_manager.dart` | — | 多 Provider 注册/健康检查/自动选择 |
| `lib/features/ai/views/ai_chat_page.dart` | 518 | AI 对话页 |
| `lib/features/editor/extensions/refactor_code.dart` | 178 | AI 重构引擎 |
| `lib/features/editor/extensions/generate_test.dart` | 155 | AI 测试生成引擎 |
| `lib/features/editor/views/editor_page.dart` | — | 新增 4 个 AI 功能按钮 + BottomSheet |
| `lib/features/git/views/git_operations_page.dart` | — | 提交对话框 AI 生成 Commit Message |

> 里程碑提交：`7ce943d`（M1）、`57d08f6`（M2）、`9730043`（M3）、`31c5402`（feat(sprint-8) 四件套）
> 另有大量 `Sprint 8 RC` 提交（CI 修复：analyze 0 error 0 warning、测试失败收敛）

---

## 四、测试覆盖

- `test/ai_provider_manager_test.dart` — Provider 注册 / 自动选择 / 释放
- `test/chat_engine_test.dart` — 流式对话引擎
- `test/chat_provider_test.dart` — ChatProvider 状态流转 + `aiProviderManagerProvider` 注册与 dispose（后续 08-02 补充 2 用例）
- `test/ai_client_test.dart` / `test/ai_service_test.dart` — AI 客户端与服务层
- `test/code_review_test.dart` — 审查模型（Sprint 7 移交）
- 全量验证：`flutter test` 通过 + `flutter analyze` 0 error 0 warning（CI 全绿）

---

## 五、架构说明

### 对话链路

```
ai_chat_page
   │  ChatState 流
   ▼
chat_provider (Riverpod)
   │  IChatEngine 注入
   ▼
ChatEngine ──► SSE 解析 ──► 逐 chunk 回调
   ▲
CodeAssistService（编辑器 AI 功能同源复用）
   │  fixBug / refactorCode / generateTest / generateCommitMessage / codeReview / explainCode
   ▼
AIProviderManager ── 注册表 ──► DeepSeekProvider（本地 mimo，zero-auth）
```

### 关键点

- **单一引擎、多入口**：对话页与编辑器 AI 功能共用 `IChatEngine`，Provider 层解耦，换模型只改注册表。
- **状态全部 Riverpod 化**：`ChatState` 单向数据流，UI 不持有引擎引用。

---

## 六、设计决策

1. **服务层下沉**：Sprint 7 的编辑器扩展各自直连 AI Client，Sprint 8 统一收口到 `CodeAssistService`（构造注入 IChatEngine），消除重复的提示词拼装与错误处理。
2. **引擎抽象**：`IChatEngine` 接口化后，对话页与辅助功能都面向接口编程，DeepSeek/mimo 只是注册表里的一个实现。
3. **默认 Provider 零配置**：DeepSeekProvider 指向本地 mimo（http://127.0.0.1:8788/v1，apiKey=dummy），用户安装 mimo 后开箱即用，无需填 Key。
4. **RC 期间 CI 优先**：`Sprint 8 RC` 系列提交专门收敛 analyze warnings 与测试失败，保证 0 error / 0 warning 的基线不被破坏。

---

## 七、后续计划

- 对话上下文（Workspace Context System）注入 —— 已由 `Sprint 9 - Milestone 1` 承接（workspace_context_test / workspace_model_test）
- 编辑器内联补全升级为流式输出（Sprint 7 预留接口已就位）
- 崩溃后自动上报诊断信息，AI 辅助定位（可选增强）
