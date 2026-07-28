# Sprint 0 — Milestone 0.4 验证报告：AI 通信验证

> **日期：** 2026-07-28
> **状态：** ✅ 通过

---

## 1. 验证目标

| 目标 | 说明 |
|------|------|
| M0.4.1 | AI 客户端核心层（消息模型、SSE 解析、HTTP 客户端） |
| M0.4.2 | AI 服务层（健康检查、重试机制、流式/非流式） |
| M0.4.3 | AI 对话 UI（气泡聊天、Markdown 渲染、流式状态） |
| M0.4.4 | 路由注册与导航集成（导航栏+快捷卡片跳转） |

---

## 2. 交付物清单

### 2.1 核心层 (`lib/core/ai/`)

| 文件 | 行数 | 说明 |
|------|------|------|
| `ai_message.dart` | 159 | ChatRole、ChatMessage、ChatCompletionRequest/Response、ChatChoice、ChatUsage |
| `sse_parser.dart` | 136 | SseParser（byteTransformer + parseLine + extractContent）、SseEvent |
| `ai_client.dart` | 197 | AiClient（chat/chatStream/healthCheck）、AiClientConfig、AiClientException（7 类错误） |
| `ai_service.dart` | 213 | AiService（chat/chatStream/checkStatus + 指数退避重试）、AiConfig、AiServiceStatus |

### 2.2 UI 层 (`lib/features/ai/`)

| 文件 | 行数 | 说明 |
|------|------|------|
| `providers/chat_provider.dart` | 187 | ChatState + ChatNotifier（流式 sendMessage、checkService、clearChat） |
| `views/ai_chat_page.dart` | 413 | 完整 AI 对话页面（气泡消息、简易 Markdown/代码渲染、服务状态指示） |

### 2.3 路由集成

| 文件 | 变更 |
|------|------|
| `route_names.dart` | 新增 `aiChat = '/ai-chat'` |
| `app_router.dart` | 注册 `AiChatPage` 路由 |
| `home_page.dart` | 导航栏 + AppBar + 快捷卡片添加 AI 入口 |

### 2.4 单元测试

| 文件 | 用例数 | 说明 |
|------|--------|------|
| `test/sse_parser_test.dart` | 18 | SSE 解析、extractContent、byteTransformer、SseEvent、ChatRole/ChatMessage/ChatCompletionResponse |
| `test/ai_client_test.dart` | 11 | chat（成功/401/429/502/5xx）、chatStream（成功/401）、healthCheck（200/404/异常）、Exception.toString |
| `test/ai_service_test.dart` | 8 | AiConfig、AiServiceStatus、AiService 生命周期、kSystemPrompt |
| `test/chat_provider_test.dart` | 9 | ChatState（copyWith/cleared/不可变）、ChatNotifier（清空/空消息/setService）、ChatLoadingState |
| **合计** | **46** | |

---

## 3. 架构设计决策

### 3.1 分层设计

```
┌─────────────────────────┐
│   AiChatPage (UI 层)     │  ← ConsumerStatefulWidget
├─────────────────────────┤
│   ChatNotifier (状态层)   │  ← Riverpod StateNotifier
├─────────────────────────┤
│   AiService (服务层)      │  ← 重试 + 健康检查
├─────────────────────────┤
│   AiClient (客户端层)     │  ← HTTP + SSE 流
├─────────────────────────┤
│   http 包               │  ← 真实 HTTP 调用
└─────────────────────────┘
```

### 3.2 错误分类体系

```
HTTP 401/403  → ApiClientErrorType.api        → "API Key 无效"
HTTP 429      → ApiClientErrorType.rateLimit  → "请求过于频繁"
HTTP 502/503  → ApiClientErrorType.proxyDown  → "代理不可用"
HTTP 5xx      → ApiClientErrorType.server     → "服务端错误"
网络超时       → ApiClientErrorType.timeout    → "请求超时"
连接失败       → ApiClientErrorType.network    → "网络连接失败"
```

### 3.3 重试策略

- **最大重试次数：** 3 次
- **退避算法：** 指数退避（1s → 2s → 4s）
- **不可重试错误：** API Key 无效（401/403）不重试
- **429 特殊处理：** 加倍等待时间

### 3.4 API 代理配置

| 参数 | 值 |
|------|-----|
| Base URL | `http://127.0.0.1:8788/v1` |
| 模型 | `deepseek-chat` |
| 请求超时 | 30s |
| 连接超时 | 5s |
| 健康检查端点 | `GET /health` |

---

## 4. 测试结果

### 4.1 SSE 解析测试 ✅

| 测试 | 结果 |
|------|------|
| 解析有效 `data:` 行 | ✅ 通过 |
| 解析 `[DONE]` 标记 | ✅ 通过 |
| 空行/注释行返回 null | ✅ 通过 |
| 无效 JSON 返回 error 事件 | ✅ 通过 |
| `extractContent` 从有效 JSON 提取 | ✅ 通过 |
| `extractContent` 空 choices | ✅ 通过 |
| `byteTransformer` 完整流转换 | ✅ 通过 |

### 4.2 AI 客户端测试 ✅

| 测试 | 结果 |
|------|------|
| 非流式请求成功 | ✅ 通过 |
| 401 → api 错误 | ✅ 通过 |
| 429 → rateLimit 错误 | ✅ 通过 |
| 502/503 → proxyDown 错误 | ✅ 通过 |
| 5xx → server 错误 | ✅ 通过 |
| 流式请求返回 SSE 事件 | ✅ 通过 |
| 流式 401 返回异常 | ✅ 通过 |
| 健康检查 200 → true | ✅ 通过 |
| 健康检查非 200 → false | ✅ 通过 |
| 健康检查异常 → false | ✅ 通过 |

### 4.3 AI 服务测试 ✅

| 测试 | 结果 |
|------|------|
| 默认配置正确 | ✅ 通过 |
| 自定义配置 | ✅ 通过 |
| 服务生命周期 | ✅ 通过 |
| dispose 安全 | ✅ 通过 |
| kSystemPrompt 定义 | ✅ 通过 |

### 4.4 状态管理测试 ✅

| 测试 | 结果 |
|------|------|
| 初始状态默认值 | ✅ 通过 |
| copyWith 更新字段 | ✅ 通过 |
| cleared 清空消息 | ✅ 通过 |
| 多次 copyWith 不可变 | ✅ 通过 |
| 初始状态 proxyDown | ✅ 通过 |
| clearChat 清空 | ✅ 通过 |
| 空消息不发送 | ✅ 通过 |
| setService 注入 | ✅ 通过 |

---

## 5. 代码统计

```
────────────────────────────────────────────
Language                  Files   Lines
────────────────────────────────────────────
Dart (core)                   4     705
Dart (UI)                     2     600
Dart (test)                   4     321 (测试代码)
────────────────────────────────────────────
新增总计                     10    1626
```

---

## 6. 验证结论

| 检查项 | 结果 |
|--------|------|
| 核心模型定义完整 | ✅ |
| SSE 流式解析正确 | ✅ |
| HTTP 客户端（流式+非流式） | ✅ |
| 7 类错误分类 | ✅ |
| 指数退避重试 | ✅ |
| 健康检查 | ✅ |
| 对话状态管理 | ✅ |
| 气泡 UI + 简易 Markdown 渲染 | ✅ |
| 路由注册 | ✅ |
| 首页导航集成 | ✅ |
| 单元测试（46 用例） | ✅ |

**结论：** ✅ M0.4 所有交付物已完成，AI 通信验证通过。

---

## 7. 后续 Sprint 建议

- M0.5: 性能基线测试（页面渲染性能、API 响应延迟）
- Sprint 1: 使用 `flutter_markdown` 替换简易渲染
- Sprint 2: 对话历史持久化（SharedPreferences/SQLite）
- Sprint 3: 多对话管理 + 上下文长度控制
