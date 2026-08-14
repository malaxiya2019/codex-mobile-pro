# DSH（DeepSeek Harness）接入申请 / 介绍信

> 目的：拿 API 额度 + 第一时间接入 DSH 生态。
> 状态判断：**内测招募（8/1-8/2 私信崔添翼）已结束**，DSH 已于 8/13 晚全面开放（MIT 开源 + v0.1 开发者预览公测）。
> 所以这不是"申请内测资格"的信，而是"**生态开发者接入/合作申请**"——重点是我能提供什么，再谈 API 额度。

---

## 一、现状速览（先看这个，别搞错姿势）

| 时间 | 事件 | 对你的意义 |
|------|------|-----------|
| 8/1-8/2 | 崔添翼在 X 发内测招募帖：面向 Agent Harness 开源项目作者，附 GitHub ID + 代表作，入选赠 API 额度 | 招募阶段已过，私信这条基本失效 |
| 8/13 晚 | DSH v0.1 开发者预览版全面开放 + MIT 开源；**同一天 API 最高涨价 12 倍**（8/17 起峰谷定价，闲时半价） | 正好是你"想挣 token 钱 / 不想付费"的背景，官方也在拉生态 |
| 8/14 现在 | 官方正式入口：飞书入群问卷 + 企微小助手 + GitHub Discussions + Discord | 走这些渠道，邮件正文当"自我介绍材料"用 |

**官方入口清单：**
- 飞书入群问卷（首选，填 GitHub ID + 代表作）：https://trtgsjkv6r.feishu.cn/share/base/form/shrcnIt5twSVdLGD52KJBckGCgg
- GitHub Discussions（发帖自我介绍）：https://github.com/deepseek-ai/deepseek-harness/discussions
- 企微小助手扫码入群（群里有官方团队，可直接问）：https://github.com/deepseek-ai/deepseek-harness （README.zh.md 底部有二维码）
- Discord：https://discord.gg/Ycq5dCaS4
- 仓库：https://github.com/deepseek-ai/deepseek-harness

---

## 二、邮件正文（版本 A：给官方 / 飞书问卷 / Discussions 用）

> 简体中文、大白话，可直接复制。飞书问卷只让填短文本就把「正文」精简成加粗那句。

**标题：codex-mobile-pro：一个想第一时间接入 DSH 插件生态的 Agent Harness 开源项目**

---

你好，DeepSeek Harness 团队：

我是开源项目 **codex-mobile-pro** 的作者，GitHub ID：**malaxiya2019**。从 8 月初崔添翼老师那条内测招募帖一路关注 DSH 到今天正式开源，非常兴奋，特别想参与进来。

**我做的项目一句话介绍：**
> codex-mobile-pro 是一个 **MIT 开源的轻量级 Agent Harness**——一键部署 Codex / DeepSeek CLI Agent，自带自研的 Flutter 终端（内置 ANSI/PTY 渲染、AI 对话、代码编辑、文件管理），预装 **70 个 skills**（代码审查、TDD、调试、研究、逆向、多模态……开箱即用）。它跑在 Termux（Android）上，也跑普通 Linux 服务器，手机上就是随身 IDE。

**为什么我觉得和 DSH 天然契合：**

1. **同赛道**：我也是 Agent Harness 类开源项目，正是你们内测招募里优先筛的那类作者；我已经跟着 DSH 的设计思路在调整项目方向。
2. **"一切皆插件"同构**：DSH 是 Cordis 驱动的"一切皆插件"架构；我们的 70 个 skills / tools 结构，天然可以映射成 DSH 插件。我整理过第三方插件的合规声明（THIRD-PARTY-NOTICES），对插件化生态的规范有实际经验。
3. **多端落地 + 终端渲染**：DSH 现在主要在桌面 Web UI + npm 上。codex-mobile-pro 把整套 agent 链路在**手机 Termux 和普通 Linux 服务器上都跑通了**（自研 ANSI/PTY 终端渲染、中文交互、国内直连）——如果 DSH 想覆盖更多端，这块经验我能直接贡献。

**项目现状（不吹，说实话）：**
- 2026-07-27 建仓，**每天在提交、活跃维护**，最近一次推送就是昨天
- 本地真实自用跑通：手机 Termux 和 Linux 服务器上跑 Codex / DeepSeek，不是概念项目
- 60+ 测试文件、CI 在跑；刚开源（8/14），GitHub 还在 0 star，正处推广期
- 完整第三方组件合规声明（MIT + GPL/AGPL/Apache 清单）已备好

**我想请求的：**
1. 能否给 **API 额度 / 接入支持**？（8/17 新价格出来后，个人开发者确实有压力）
2. 我很愿意在 DSH 稳定后**第一时间接入**，或直接承接**插件迁移 / 多端适配**这类共建工作，需要我怎么配合都行。

联系方式就是 GitHub 账号（malaxiya2019），仓库：
**https://github.com/malaxiya2019/codex-mobile-pro**

随时可以约时间细聊，祝 DSH 公测顺利。

---

## 三、极简版（版本 B：X / 私信崔添翼用，两三句话）

崔老师好，我是 Agent Harness 开源项目 codex-mobile-pro 的作者（GitHub: malaxiya2019），MIT 开源、每天维护、70 个 skills、自研 ANSI/PTY 终端渲染，完整跑通 Codex/DeepSeek（手机 Termux 和 Linux 都行）。从内测招募跟到 8/13 开源，特别想参与 DSH 插件生态——能给个 API 额度或接入支持吗？仓库：github.com/malaxiya2019/codex-mobile-pro

---

## 四、投递指引（按优先级）

1. **飞书入群问卷**（首选）：打开上面链接，GitHub ID 填 `malaxiya2019`，代表作/项目栏贴「版本 A」里加粗那句 + 仓库链接。
2. **企微小助手**：README.zh.md 底部扫码 → 加助手 → 填问卷 → 入企微群。群里直接问 API 额度 / 接入支持，最直接。
3. **GitHub Discussions**：发一帖，标题《codex-mobile-pro：想接入 DSH 插件生态的 Agent Harness 项目》，正文贴「版本 A」全文，结尾补一句"很愿意参与插件生态共建"。
4. **Discord**：入群后发同样的自我介绍，英文短版更好。
5. **崔添翼 X 私信**：用「版本 B」，别发长文，私信容易被吞。

## 五、注意事项

- **别一上来伸手要钱**：正文把"我能提供什么"放前面，"API 额度"放最后当请求，用"接入支持/合作"包装。
- **别吹 star**：0 star 是事实，主打"真实自用 + 每天维护 + 技术契合"，反而显得诚实。
- **联系方式**：只用 GitHub ID（malaxiya2019）+ 仓库链接，**不要用 liang2050@example.com 这种占位邮箱**。
- **版权已合规**：THIRD-PARTY-NOTICES.md / skills/README / qwen-mm-plugins LICENSE 都齐了，官方如果要看插件合规不会露怯。
