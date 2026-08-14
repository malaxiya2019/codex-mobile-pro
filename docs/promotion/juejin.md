# 掘金发帖文案（文章版，建议配手机截图）

## 标题
手机上用 Codex + DeepSeek 写代码：我把整条链路做成了一个 Flutter App

## 开头切入
> 场景：通勤路上突然想改个 bug，身边没电脑。以前我只能在手机上开个 Termux 瞎戳，现在……

## 正文结构（每节配一张手机截图）

### 1. 为什么做
Termux 跑 codex 的 4 个致命体验问题：
- 依赖编译地狱：node-gyp 在 Android 上 `sys.platform` 误判，原生模块全要手动 clang++
- 翻墙：很多链路卡在代理配置
- 中文乱码：终端 ANSI/UTF-8 渲染在手机上各种崩
- TUI 布局：小屏幕信息密度一塌糊涂

### 2. App 长什么样
四大块：
- 内置终端：自研 ANSI/PTY 画布化渲染
- AI 对话：气泡/流式双界面，支持图片附件（Gemini 视觉直连）
- 代码编辑：语法高亮 + 自动补全 + 诊断
- 文件管理：工作区、Git 操作、备份恢复

### 3. 最难啃的骨头（全文精华，值得写深）
- node-pty@1.1.0 手动编译（clang++ + node-addon-api）
- koffi 手动 cmake+ninja 编译
- Termux SELinux 禁 `fs.link()` → 改 rename
- ANSI 渲染重写成画布化 + UTF-8 累积解码
- PTY 尺寸排查：最后发现是 TUI 设计问题（MIN_DASHBOARD_WIDTH），不是 PTY 尺寸丢失

### 4. 一键部署
`bash deploy.sh` 干完所有事：装依赖、配环境、部署 70 个 skills、设中文快捷命令 `cyo --zh`。

### 5. 开源地址
MIT，免费，欢迎贡献与提 issue：https://github.com/malaxiya2019/codex-mobile-pro

---
## 平台注意
- 掘金标题别带「分享」「开源」字样，用「怎么做」的结果导向标题转化更好
- 第 3 节是攒关注主力，技术细节展开写，代码/报错信息原样贴
