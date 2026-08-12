# PhoneHarness Benchmark 参考

来源：`benchmark/` 目录。公开数据：HF dataset `PhoneHarness/phoneharness-bench`。

## 评测入口

```bash
# 单模拟器（向后兼容）
python3 benchmark/run_hybrid_bench.py --sheet 4app_new

# 6 个模拟器并行
python3 benchmark/run_hybrid_bench.py --sheet 4app_new --slots 6

# 单任务指定 slot
python3 benchmark/run_hybrid_bench.py --sheet 4app_new --task SC09_001 --slots 1

# 只跑 keep=1 任务
python3 benchmark/run_hybrid_bench.py --sheet 4app_new --slots 6 --keep-only
```

Task sheets 在 `benchmark/tasks/hybrid_bench_base_verifiers_by_sheet/`：`30app_new.yaml`、`68app_new.yaml`、`4app_new.yaml`、`safety_bench.yaml`。

Slot 映射：slot 0 = emulator-5554 + server :8920 + gui :8919；slot 1 = emulator-5556 + :8930 + :8929；依此类推。也支持 `--slot-specs id:serial:server_port:gui_port`。

runner 逻辑：读 sheet → 经 phoneharness `/run` 端点跑任务 → 用 sheet 里的 `base_verifier` 验证 → 并发写 trace 到 `benchmark/traces/hybrid_bench/`。

## Grader 用法

```bash
python3 benchmark/grader.py --trace-dir ./traces/doubao-2.0-pro
python3 benchmark/grader.py --trace-dir ./traces/doubao-2.0-pro --device emulator-5556
python3 benchmark/grader.py --compare ./traces/a ./traces/b ./traces/c
```

- 输入：每条任务一个 `.ndjson`（如 `C1.ndjson`）。
- 兼容两种事件格式：新格式 `{"type": "tool_call", ...}`；server 格式 `{"event": "tool_call", "name": ..., "arguments": ...}`。
- 输出：逐条评分 + 聚合指标；支持多模型 `--compare`。

## Rubrics 五维评分（0/1，满分 5）

| 维度 | 含义 |
|---|---|
| completion | 最终产物存在且正确（文件 glob + 解析校验：pptx 页数、xlsx 行数、docx 段落等） |
| tool_selection | 是否选对关键工具（trace 里匹配 github/python-pptx/OCR 等） |
| param_accuracy | 关键参数正确（表头关键词、数据行数、slide 关键词） |
| no_hallucination | 没有编造工具/伪造结果（trace 与产物交叉比对，如 PPT 项目名 ≥60% 出现在 GitHub API 响应） |
| efficiency | 步数 ≤ max_steps（无冗余循环） |

`rubrics.yaml` 要点：

- glob 不绑定文件名（模型可能用中英文任意命名），按类型+后缀匹配，辅以 trace 中 done event 验证。
- 交叉验证示例：C1 竞品调研→PPT（GitHub API 项目列表 vs PPT 项目名）；C2 发票 OCR→费用报表（OCR 输出 vs Excel/Word 数据，Word 总金额 = Excel 各行金额之和，允许模拟数据但需声明）；C3 周报→加密 PDF。

## 任务示例（rubrics 节选）

- **C1**：竞品调研→PPT。要求 min_slides 2、min_project_count 3、slide 含 mobile/agent/star 关键词、GitHub API 调用、python-pptx 使用、max_steps 6。
- **C2**：发票 OCR→费用报表。要求 xlsx（min_rows 3、表头含日期/项目/金额）+ docx（min_paragraphs 3）、tesseract/openpyxl/docx 工具、max_steps 6。
- **C3**：周报→加密 PDF。max_steps 12。

## 失败分类（trace 审计视角）

trace 驱动分级：模型推理错误 / GUI 定位错误 / 环境故障 / 工具失败 / 验证器不匹配。审计 trace 时先确认失败属于哪一类，避免把验证器 mismatch 当模型错误。
