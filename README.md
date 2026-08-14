# 📱 Codex Mobile Pro

> **手机/电脑上的 AI 编程助手 — 一键部署，中文交互，国内直连**
> 支持 Termux (Android) / Ubuntu / Linux 服务器

![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Termux%20%7C%20Ubuntu%20%7C%20Linux-lightgrey.svg)
![Language: Dart](https://img.shields.io/badge/language-Dart-blue.svg)

---

## ✨ 特性

| 特性 | 说明 |
|------|------|
| 🚀 **一键部署** | 跑一个命令，全自动安装 |
| 🇨🇳 **中文交互** | 内置中文提示词，自动用中文回答 |
| 🔌 **国内直连** | 默认 DeepSeek API，可换官方 / 自建代理，无需翻墙 |
| 📦 **70 个预装 Skills** | 代码审查、TDD、调试、研究、逆向、多模态...开箱即用 |
| 📱 **Flutter App** | 内置终端 / AI 对话 / 代码编辑 / 文件管理，手机上就是 IDE |
| 🛡️ **备份恢复** | 一键备份/恢复配置，不怕丢 |
| ⚡ **YOLO 模式** | `cyo --zh` 秒开，自动唤醒代理 |
| 🔄 **自动更新** | GitHub Release 检查 + APK 增量下载安装 |

---

## 🖥️ 快速开始

### 📱 Termux (Android)

```bash
# 1. 进入项目目录
cd ~/codex-mobile-pro

# 2. 一键安装
bash deploy.sh

# 3. 启动（中文模式）
cyo --zh
```

### 🐧 Ubuntu / Linux

```bash
# 1. 进入项目目录
cd ~/codex-mobile-pro

# 2. 一键安装（自动使用 sudo）
bash deploy.sh

# 3. 重新加载 shell 配置
source ~/.bashrc

# 4. 启动（中文模式）
cyo --zh
```

> 详细教程 → [docs/快速上手.md](docs/快速上手.md)
> 常见问题 → [docs/常见问题.md](docs/常见问题.md)
> 进阶玩法 → [docs/进阶玩法.md](docs/进阶玩法.md)
> 架构设计 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## 📦 项目结构

```
codex-mobile-pro/
├── deploy.sh              # 一键安装脚本 (Termux/Linux 自适应)
├── backup-codex.sh        # 备份脚本
├── restore-codex.sh       # 恢复脚本
├── lib/                   # Flutter App 源码（终端/AI/编辑/文件）
├── bin/
│   └── codex-zh           # 中文快捷启动
├── config/
│   ├── codex-config.toml  # Codex 配置（自动适配路径）
│   └── bashrc-additions.sh # Shell 快捷命令
├── docs/
│   ├── 快速上手.md
│   ├── 常见问题.md
│   └── 进阶玩法.md
└── skills/                # 70 个预装 Skills
```

---

## 🤝 贡献

欢迎任何形式的贡献：提 Issue、修 Bug、加 Skills、改文档、分享使用经验。

1. Fork 本仓库
2. 创建你的分支：`git checkout -b feat/xxx`
3. 提交改动：`git commit -m "feat: ..."`
4. 推送到你的分支后开 Pull Request

> 开发进度与规划见 [SPRINT_PLAN.md](SPRINT_PLAN.md)，更新日志见 [CHANGELOG.md](CHANGELOG.md)。

---

## 📄 许可

本项目基于 **MIT License** 开源（见 [LICENSE](LICENSE)），免费使用，随意修改与分发，保留版权声明即可。

> ⚠️ 第三方组件保留各自许可：
> - `assets/busybox-arm64` — [meefik/busybox](https://github.com/meefik/busybox) 静态构建，**GPL-2.0**
> - 内置 `skills/` 中的部分技能来自上游开源项目，均保留原作者许可声明
> - 其余第三方依赖见 `pubspec.yaml`

---
**⭐ 如果这个项目帮到了你，点个 Star 就是最大的支持！**
