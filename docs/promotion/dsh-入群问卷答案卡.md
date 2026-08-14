# DSH 入群问卷答案卡（「加入 DeepSeek Harness 用户交流群」）

> 来源：官方飞书问卷（trtgsjkv6r.feishu.cn/share/base/form/shrcnIt5twSVdLGD52KJBckGCgg）
> 性质：**企微入群问卷**（不是 API 额度申请问卷）。填完入群 → 群里再问 API 额度/接入支持。
> 8 个字段，标注 ✅=可直接抄，🔒=需本人提供。

| # | 问题 | 建议答案 | 状态 |
|---|------|----------|------|
| 1 | 你目前使用 DeepSeek Harness 到哪一步？ | **还没有实际使用过**（单选） | ✅ 诚实，刚开源 1 天，多数人都是这状态 |
| 2 | 您的微信昵称是？ | （填你自己的微信昵称） | 🔒 隐私 |
| 3 | 您的微信绑定手机号是？ | （填你自己的） | 🔒 隐私 |
| 4 | 您的职业是？ | **技术/研发**（单选；备选：创业者/独立开发者） | ✅ |
| 5 | 微信绑定手机号（疑似重复项） | 与 #3 一致 | 🔒 隐私 |
| 6 | 您的职业是？-其他-补充内容 | 留空（#4 不选"其他"就不用填） | ✅ |
| 7 | 您最近拿 Harness 做过什么任务？结果怎么样？ | 见下方「正文」 | ✅ 已拟好 |
| 8 | 请添加小助手，备注「昵称 + Harness 社区」 | 先扫二维码加好友，再勾选"已申请并添加" | 🔒 需本人操作 |

---

## 字段 7 正文（版本 A，主推）

> 我长期在自研的轻量级 agent harness（codex-mobile-pro，GitHub: malaxiya2019，MIT 开源，跑在手机 Termux 和 Linux 上）上跑任务，最近实打实干完的事：
> 1. **真机跑通**：在手机 Termux 和 Linux 服务器上把 Codex/DeepSeek 编程 agent 完整跑起来，中文交互、国内直连不用翻墙，这套 harness 现在就是我日常主力开发工具；
> 2. **啃了一堆硬骨头**：Termux 上 node-gyp 失效 → 改手搓 clang++ 编译原生模块；ANSI 渲染乱码 → 重写成画布化 + UTF-8 累积解码；PTY 尺寸异常 → 逐轮排查根因；
> 3. **插件体系**：整合 70 个预装 skills（代码审查/TDD/调试/逆向/多模态），并做完第三方插件版权合规（THIRD-PARTY-NOTICES 全套声明）。
> 结果：全部跑通，60+ 测试文件 CI 在跑，我每天都在用它写代码。现在 DSH 开源了，特别想第一时间把 DSH 的插件生态接进我这套 harness。

## 字段 7 正文（版本 B，短平快）

> 天天拿自研的 agent harness（codex-mobile-pro，GitHub: malaxiya2019，手机和 Linux 都能跑）干活：真机跑通 Codex/DeepSeek、修 TUI 的 ANSI/PTY/中文乱码一堆硬骨头、整合 70 个 skills。结果都跑通了，现在 DSH 开源了想第一时间接入。

## 一致性提醒
- 字段 1 仍选「还没有实际使用过」——那题选项明确限定 "DeepSeek Harness"，别编。
- 字段 7 写其他 harness 干过的活，与字段 1 不冲突（一个问 DSH 本体，一个问 harness 经验）。


## 添加小助手步骤（字段 8 前置动作，必须本人做）

1. 打开 DSH 仓库 README.zh.md：https://github.com/deepseek-ai/deepseek-harness
2. 底部「企微小助手」二维码，用微信扫一扫添加
3. 好友申请备注写：**你的微信昵称 + Harness 社区**
4. 加成功后回来勾选字段 8 的"已申请并添加"
   （二维码图片已下载到 `~/dsh-wecom-assistant.png` 可直接扫）

## 提交方式
- 若能提供微信昵称 + 手机号，可尝试脚本自动提交（见 `tool/submit_dsh_form.py`，不保证过验证）
- 更稳：打开问卷链接，照本卡 1 分钟手填
