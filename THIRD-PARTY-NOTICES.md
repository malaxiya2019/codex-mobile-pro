# 第三方组件声明（Third-Party Notices）

> 本文件列出 codex-mobile-pro 中使用的所有第三方组件及其许可证。
> 项目自研代码（`lib/`、`tool/`、`config/` 等）采用 **MIT License**（见根目录 `LICENSE`）。
> **MIT 许可证只覆盖本项目自研代码，不覆盖下列任何第三方组件。**

如有任何权利方认为某组件侵犯其权益，请提交 GitHub/Gitee Issue 或联系项目作者，我们核实后会立即移除。

---

## 1. 核心二进制（随 APK 分发）

| 组件 | 来源 | 许可证 | 用途 |
|------|------|--------|------|
| `android/app/src/main/jniLibs/arm64-v8a/libproot.so` | [termux/proot](https://github.com/termux/proot)（PRoot，版权归 STMicroelectronics） | **GPL-2.0-or-later** | 用户态 chroot（Ubuntu rootfs 沙箱） |
| `android/app/src/main/jniLibs/arm64-v8a/libbusybox.so` | [meefik/busybox](https://github.com/meefik/busybox) 静态构建 | **GPL-2.0** | 内置 Unix 工具箱 |
| `assets/busybox-arm64` | 同上 | **GPL-2.0** | Flutter 侧解压工具（`busybox_provider.dart`） |
| `android/app/src/main/assets/busybox-arm64` | 同上 | **GPL-2.0** | Kotlin 原生侧 Shell（`PtyPlugin.kt`，向后兼容） |
| Ubuntu rootfs（运行时下载） | [termux/proot-distro](https://github.com/termux/proot-distro/releases) | 混合（各包独立许可，详见 `docs/UBUNTU_RUNTIME_SUPPLY_CHAIN.md`） | 沙箱内的完整 Linux 环境 |

> **GPL 说明**：以上组件均为独立程序，以"聚合分发"（aggregation）形式随 APK 提供，
> 不构成与 MIT 自研代码的合并作品。GPL-2.0 要求提供对应源码，获取地址：
> - PRoot：<https://github.com/proot-me/proot>
> - Termux proot 构建：<https://github.com/termux/proot>
> - BusyBox（meefik 构建）：<https://github.com/meefik/busybox>

---

## 2. Qwen-MM-Plugins（`skills/qwen-mm-plugins-*`，共 8 个）

| 组件 | 来源 | 许可证 |
|------|------|--------|
| `qwen-mm-plugins-core` | [QwenLM/Qwen-MM-Plugins](https://github.com/QwenLM/Qwen-MM-Plugins) | **Apache-2.0** |
| `qwen-mm-plugins-api` | 同上 | **Apache-2.0** |
| `qwen-mm-plugins-blender` | 同上 | **Apache-2.0** |
| `qwen-mm-plugins-edu-agent` | 同上 | **Apache-2.0** |
| `qwen-mm-plugins-freecad` | 同上 | **Apache-2.0** |
| `qwen-mm-plugins-search` | 同上 | **Apache-2.0** |
| `qwen-mm-plugins-video-edit` | 同上 | **Apache-2.0** |
| `qwen-mm-plugins-video-memory` | 同上 | **Apache-2.0** |

- 各插件目录内已附带 Apache-2.0 `LICENSE` 全文副本。
- 本项目基于官方仓库做了本地化整合（配置路径、依赖适配），属于 Apache-2.0 允许的修改与再分发；
  修改声明见 `skills/README.md`。

---

## 3. 字体（`skills/qwen-mm-plugins-video-edit/assets/fonts/`）

| 字体 | 许可证 |
|------|--------|
| LXGW WenKai（霞鹜文楷） | **MIT**（Copyright (c) 2021 Chawye Hsu） |
| Ma Shan Zheng（马善政楷体） | **OFL-1.1** |
| ZCOOL KuaiLe（站酷快乐体） | **OFL-1.1** |

---

## 4. 带许可证声明的 Skill

| Skill 目录 | 来源 | 许可证 |
|-----------|------|--------|
| `skills/.system/imagegen` | OpenAI 官方 skills | Apache-2.0 |
| `skills/.system/openai-docs` | OpenAI 官方 skills | Apache-2.0 |
| `skills/.system/skill-creator` | OpenAI 官方 skills | Apache-2.0 |
| `skills/.system/skill-installer` | OpenAI 官方 skills | Apache-2.0 |
| `skills/playwright` | 社区开源 | Apache-2.0 |
| `skills/taskmaster` | 社区开源 | MIT（Copyright (c) 2025） |
| `skills/simplecadapi` | 社区开源 | **AGPL-3.0**（见下） |

> ⚠️ **AGPL 特别说明**：`skills/simplecadapi` 采用 GNU AGPL-3.0，是项目中传染性最强的许可证。
> 它作为**独立 skill 目录**存在，未与本项目 MIT 自研代码合并；使用该 skill 时请遵守 AGPL-3.0 条款
> （包括网络服务场景下的源码提供义务）。如需彻底规避，可删除该目录，本项目主体不受影响。

---

## 5. 无许可证声明的社区 Skill

`skills/` 下其余 Skill（如 `git-guardrails-claude-code`、`design-an-interface`、`diagnosing-bugs`、
`deep-interview`、`task-boundary`、`rev-*` 系列、`grilling` 系列、`writing-*` 系列等）
来自各类社区开源项目/作者，**原目录未附带版权声明与许可证**，本项目仅作学习与整合用途，
版权归原作者所有。详见 `skills/README.md` 的声明。

---

## 6. 其它

- `pubspec.yaml` 中的 Flutter/Dart 第三方依赖均为标准包管理器依赖，许可证见各包自身声明。
- `.env.example` 仅含占位符，不含任何真实凭证。
- 本项目 git 历史经审计未发现敏感凭证提交。

---

*本文件由项目维护者维护，随项目许可证变更同步更新。最后更新：2026-08-14*
