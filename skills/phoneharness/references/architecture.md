# PhoneHarness 架构参考

来源：github.com/PhoneHarness/PhoneHarness（main 分支）。运行时 Python 包名 `phoneharness`，环境变量前缀 `PHONEHARNESS_*`。参考论文 arXiv 2606.14832，数据集 phoneharness.github.io / HF `PhoneHarness/phoneharness-bench`。

## 目录结构

```text
phoneharness/
├── agent/            # loop.py（M0a 探针）、m1.py-m4.py、message.py（ToolResult/PathRef/ErrorType）
├── backend/          # adb.py（AdbBackend 双通道）、local.py（LocalBackend）
├── cli.py            # 子命令入口：console / server / m0a-probe / m0b-probe / m1-run / m2-run / m3-run / m4-run / skill-check / replay-view
├── console.py        # CLI-first Agent Console（REPL），默认入口，单模型统一 CLI+GUI 编排
├── server.py         # stdlib HTTP server（:8920），APK 集成用
├── replay.py         # 文本回放
├── controllers/seed_gui.py  # Seed GUI controller（Seed XML 协议，0-1000 坐标）
├── model/client.py   # OpenAI-compatible client（OpenAICompatClient）
├── probe/m0b.py      # 后端探针
├── skills/           # injector.py（把 YAML skill 注入 system prompt）、loader.py
├── task/journal.py   # 任务日志
├── tools/            # 工具实现 + registry.py（ToolRegistry，剔除 additionalProperties 兼容 Gemini）
└── util/trace.py     # ArtifactStore：NDJSON trace 写入
```

## 端口与通信

| 组件 | 位置 | 默认 |
|---|---|---|
| PhoneHarness server | 模拟器 Termux | 设备端口 `8920`（adb forward host:8920 -> device:8920） |
| gui_proxy | host | `127.0.0.1:8919` |
| 模型 endpoint | host | OpenAI-compatible，经 `OPENAI_BASE_URL` 配置 |
| 多 slot | host+模拟器 | slot N：emulator-5554+N*2、server :8920+N*10、gui :8919+N*10 |

gui_proxy 端点（HTTP，JSON）：`/screenshot`、`/screenshot/raw`、`/tap`、`/swipe`、`/type`、`/ui_dump`、`/launch?package=<pkg>`。设备访问 host 用 `10.0.2.2`。

## 工具实现要点

- `shell_exec.py`：`ShellExecTool`，描述明确禁止用 shell 做 GUI 操作；`_REAL_APP_BOOTSTRAP_REWRITES` 把 com.phoneuse.m* 映射为真实包名（小红书/美团/哔哩哔哩/豆瓣）。
- `load_skill.py`：`LoadSkillTool`，skill 目录 = `$HOME/skills` 或仓库 `skills/`；跳过 `index`、`available_apis`、`file_output_paths`；`list` 列出全部。
- `mcp_bench.py`：`MCPBenchCLITool` 从 `configs/mcp_bench/cli_tools.json` 读 command_template 并子进程执行；skill 工具走 `python3 -c` import+call。
- `seed_gui_subtask.py`：`run_seed_gui_subtask`，goal + max_steps（默认 25），包装 Seed GUI controller。
- `registry.py`：`ToolRegistry`，`to_openai_tools()` 递归剥离 `additionalProperties`（Gemini API 拒绝该字段）。
- `gui/proxy_client.py`：`GUIProxyClient`，薄 HTTP 客户端，默认 `http://10.0.2.2:8919`，统一 JSON 返回、错误归一化为 `{"ok": false, "error": ...}`。

## Backend 双通道（AdbBackend）

- Channel 1（run-as → proot Ubuntu）：`exec_ubuntu`、`exec_ubuntu_python`、`copy_*`、`stat_ubuntu_path`、`ensure_ubuntu_dir`。有文件系统与 proot 访问，**无网络**（API 36+ SELinux runas_app 限制）。
- Channel 2（SSH → Termux）：`exec_termux`（默认 `--channel ssh`）。有网络（INTERNET 权限），**无 proot**（SSH 会话 getcwd 不兼容）。
- `BackendCommandResult`：argv/exit_code/stdout/stderr/resolved_path；`BackendTimeoutError`。

## CLI 子命令

- `m0a-probe`：模型↔工具 roundtrip 探针（echo_args）。
- `m0b-probe`：后端（adb）roundtrip 探针。
- `m1-run` / `m2-run`：host 侧单轮/多轮 run。
- `m3-run` / `m4-run`：on-device 变体。
- `replay-view`：文本回放渲染。

## 与本机 codex-mobile-pro 的关联

两者同为 Termux/Android 代理运行时。可借鉴：

1. **deterministic-first 路由**：可精确执行路径（shell 命令、MCP）优先，GUI 兜底——对应部署中心的 capability 检测应避免"每个模块各自判断"。
2. **副作用验证器**：按真实副作用评分而非过程动作——对应 Runtime 验证应检查真实产物（node --version 等）。
3. **trace 分级审计**：JSONL + HTML viewer，失败五分类——便于定位 30% 卡死这类问题属于环境故障还是工具失败。
