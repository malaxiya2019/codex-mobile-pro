---
name: phoneharness
description: Android 手机代理（phone agent）的混合动作编排框架与基准评测参考。当用户需要评测或构建 Android 手机代理、设计 CLI+GUI+MCP 混合动作编排 loop、按真实副作用（文件、系统设置、app 状态、安全）而非点击轨迹评分、审计 JSONL trace 并分类失败、搭建 Android 模拟器 + Termux 评测环境，或借鉴 PhoneHarness 的 deterministic-first 路由与 trace-backed grading 架构时使用。
---

# PhoneHarness

## Overview

PhoneHarness（github.com/PhoneHarness/PhoneHarness）是一套手机代理运行时编排框架 + benchmark。它让 phone agent 在同一 agent loop 中混合调用三类操作面：

- **CLI**：`shell_exec` / `python_exec`（设备 Termux/Linux 环境执行）
- **GUI**：截图、tap、swipe、type（经 host 侧 gui_proxy，0-1000 归一化坐标）
- **MCP/skills**：`load_skill`（渐进式技能加载）、`mcp_bench`（MCP-Bench 工具包装）

评测按**可验证的副作用**（文件、系统设置、app 状态、安全检查）评分，而不是只看下一步点击。默认 **delegated** 模式：外层 orchestration 模型规划并调用工具，专用 GUI worker 模型负责截图定位的像素级操作。

## 何时使用

- 评测/对比多个 phone agent 模型（CLI、GUI、MCP 三操作面）
- 设计 phone agent 混合动作编排 loop、工具注册表、路由策略
- 按副作用设计 verifier（文件 glob、解析校验、trace 交叉比对）
- 审计 JSONL trace，把失败分为模型推理错 / GUI 定位错 / 环境故障 / 工具失败 / 验证器不匹配
- 搭建可复现的 Android 模拟器 + Termux 评测环境（Pixel 6 / API 33 / 32G data）
- 借鉴其架构改进 codex-mobile-pro 的 Runtime 编排（同为 Termux/Android 代理运行时）

## 核心架构

```text
Host (macOS/Linux)                            Android Emulator + Termux
├── OpenAI-compatible model endpoint          ├── phoneharness server :8920
├── gui_proxy :8919 + slot*10                 ├── shell_exec / python_exec
│   screenshot, tap, swipe, type              ├── load_skill -> host tool proxy
└── trace viewers                             └── run_seed_gui_subtask -> GUI worker
```

delegated 模式调用链：

```text
orchestration model (--model)
  ├── CLI 与设备操作（shell_exec / python_exec）
  ├── MCP / skill 支撑的 host 工具
  └── run_seed_gui_subtask(...)
        └── GUI model (--gui-model) —— 截图定位的 app 操作
```

## 快速启动

前置：`docs/emulator-setup.md` 的可复现环境（Pixel 6 / API 33 / 32G AVD + Termux + Termux:API + ADBKeyboard）。

```bash
# 1. 模型凭证（OpenAI-compatible chat-completions）
export OPENAI_BASE_URL="<openai-compatible-base-url>"
export OPENAI_API_KEY="<api-key>"
export PHONEHARNESS_GUI_API_URL="<可选 GUI 模型 base-url>"
export PHONEHARNESS_GUI_API_KEY="<可选 GUI 模型 api-key>"

# 2. 设备端 server（Termux，HTTP :8920，供 APK 集成）
python3 -m phoneharness server --port 8920 \
  --model "<orchestration-model>" --gui-model "<gui-model>" \
  --base-url "$OPENAI_BASE_URL" --api-key "$OPENAI_API_KEY" \
  --skill-file skills/routing.yaml --skill-file skills/index.yaml \
  --skill-file skills/file_output_paths.yaml

# 3. 交互式 console（Termux REPL，可见逐步执行）
python3 -m phoneharness console \
  --model "<orchestration-model>" --gui-model "<gui-model>" \
  --base-url "$OPENAI_BASE_URL" --api-key "$OPENAI_API_KEY"

# 4. 审计 trace
python3 scripts/trace2html.py path/to/trace.jsonl
python3 scripts/trace2html_all.py path/to/trace-directory
```

HTTP server 端点：`GET /health`、`GET /clear`、`POST /run`（`application/x-ndjson`，多轮对话，`{"input": "...", "clear": true}` 开启新会话）。stdlib only，无 FastAPI/uvicorn/flask。

## 工具清单

| 工具 | 说明 |
|---|---|
| `shell_exec` | Termux/Linux shell；**禁止**通过它做 GUI 操作（`input tap`、`screencap`、`uiautomator` 等必须走 GUI 工具） |
| `python_exec` | 设备端 python3 |
| `load_skill` | 按需加载 YAML skill（`list` 列全部，按名加载）；从 `$HOME/skills` 或仓库 `skills/` 读取 |
| `mcp_bench` | 包装 `configs/mcp_bench/*.json` 的 CLI 工具（command_template 子进程）与 skill 工具（python3 子进程） |
| `run_seed_gui_subtask` | 高层 GUI 子任务（多步导航/表单），内部走 Seed GUI controller，0-1000 坐标 |
| `gui_tap / gui_swipe / gui_type_text / gui_screenshot / gui_ui_dump / gui_keyevent` | 经 host gui_proxy 的低层 GUI 原语 |

skills/ YAML 路由卡片：`routing.yaml`（首轮注入，deterministic-first 表格）、`device.yaml`（手机能力手册，每条标注 mode+risk+completion）、`environment.yaml`、`file.yaml`、`github.yaml`、`websearch.yaml`。

## 关键设计模式

1. **Deterministic-first 路由**：有精确可执行路径的任务（查电量、设字体、改亮度等）优先 CLI/MCP 完成；真实 app 操作强制 `run_seed_gui_subtask`（先 `curl /launch?package=<pkg>` 启动真实包，再委托 GUI 子任务），不拿 CLI/web 结果冒充 app 内完成。
2. **Delegated GUI**：外层只规划，GUI worker 负责像素级截图操作；也可 `--gui-mode flat` 直接暴露低层 gui_* 工具。
3. **Trace-backed grading**：JSONL trace + HTML viewer；五维 0/1 评分（completion / tool_selection / param_accuracy / no_hallucination / efficiency）。
4. **Backend 双通道**（adb 后端）：channel 1 run-as→proot Ubuntu（有文件系统，无网络）；channel 2 SSH→Termux（有网络，无 proot）。

## 参考文档

- [architecture.md](references/architecture.md) — 目录结构、端口与通信、后端双通道、replay/m0-m4 探针
- [benchmark.md](references/benchmark.md) — benchmark 运行方式、grader 用法、rubrics 五维评分、task sheets
- [emulator-setup.md](references/emulator-setup.md) — 参考 AVD、脚本、运行时布局、vdisplay-helper 虚拟显示
