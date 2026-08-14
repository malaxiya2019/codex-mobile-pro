# V2EX 发帖文案（「分享创造」节点）

## 标题
分享创造：在手机上跑了个能用的 AI 编程助手，Termux 一键部署，MIT 开源

## 正文

一直在手机 Termux 上折腾 codex，但坑实在太多了：装个原生依赖要手动编译、node-gyp 在 Android 上直接摆烂（`sys.platform` 误判成 android）、PTY 尺寸不对 TUI 就乱、中文在终端里全是乱码……折腾久了就想干脆把整条链路做成一个 App，于是有了这个项目。

**能干嘛：**

- 手机上跑 Codex / DeepSeek，中文交互，国内直连不用翻墙
- Flutter App，内置终端（自己写的 ANSI/PTY 渲染）、AI 对话、代码编辑、文件管理
- 自带 70 个预装 Skills：代码审查、TDD、调试、逆向、多模态……装完即用
- 一键备份恢复、自动更新、崩溃日志采集

**踩过的坑（都是真金白银换的）：**

- node-gyp 在 Termux 上系统性失效 → 跳过 postinstall，原生模块全部手动 clang++ 编译（node-pty、koffi 都手搓过）
- Termux SELinux 禁止 `fs.link()` → 硬链接改 rename
- PTY 尺寸不对 → 花了一整轮排查，最后发现是 TUI 设计问题不是 PTY 问题
- ANSI 渲染乱码 → 重写成画布化 + UTF-8 累积解码

**现状：** 功能能跑，代码质量我自己觉得还行（60+ 测试文件、CI 在跑），GitHub 0 star 但无所谓，先把东西做出来再说。

MIT 开源，免费。如果你也在手机上折腾 agent，欢迎来提 issue 或者拍砖：

https://github.com/malaxiya2019/codex-mobile-pro

---
## 发帖注意
- 发在「分享创造」节点
- 正文/标题都不要出现「求 star」「点个 star」，易判广告删帖，链接自然带出即可
