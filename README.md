# 📱 Codex Mobile Pro

> **手机上的 AI 编程助手 — 一键部署，中文交互，国内直连**

在 Android 手机（Termux）或 Linux 服务器上一键搭建 Codex AI 编程环境，使用 DeepSeek API 直连，无需翻墙。

---

## ✨ 特性

| 特性 | 说明 |
|------|------|
| 🚀 **一键部署** | 跑一个命令，全自动安装 |
| 🇨🇳 **中文交互** | 内置中文提示词，自动用中文回答 |
| 🔌 **国内直连** | DeepSeek API + mimo2codex 代理，无需翻墙 |
| 📦 **43 个预装 Skills** | 代码审查、TDD、调试、研究...开箱即用 |
| 🛡️ **备份恢复** | 一键备份/恢复配置，不怕丢 |
| ⚡ **YOLO 模式** | `cyo --zh` 秒开，自动唤醒代理 |

---

## 🎯 适用人群

- 国内开发者、学生党
- 想在手机上用 AI 写代码
- 不想折腾环境配置
- 需要中文交互的 AI 编程助手

---

## 🖥️ 快速开始

```bash
# 1. 进入项目目录
cd ~/codex-mobile-pro

# 2. 一键安装
bash deploy.sh

# 3. 启动（中文模式）
cyo --zh
```

> 详细教程 → [docs/快速上手.md](docs/快速上手.md)

---

## 📦 包含内容

```
codex-mobile-pro/
├── deploy.sh              # 一键安装脚本
├── backup-codex.sh        # 备份脚本
├── restore-codex.sh       # 恢复脚本
├── bin/
│   └── codex-zh           # 中文快捷启动
├── config/
│   ├── codex-config.toml  # Codex 配置
│   └── bashrc-additions.sh # Shell 快捷命令
├── docs/
│   ├── 快速上手.md
│   ├── 常见问题.md
│   └── 进阶玩法.md
└── skills/                # 预装 Skills 包
```

---

## 💰 购买

本产品为付费内容，售价 **29.9 元**，包含：

- ✅ 一键部署脚本
- ✅ 全套配置（Codex + mimo2codex 代理）
- ✅ 43 个预装 Skills
- ✅ 中文文档
- ✅ 持续更新
- ✅ 微信群答疑

👉 **[前往面包多购买](https://mbd.pub)**

---

## 📄 许可

仅供个人学习使用，禁止二次分发。
