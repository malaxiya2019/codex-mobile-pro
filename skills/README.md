# skills/ 目录声明

本目录是 codex-mobile-pro 内置的 Codex/Claude 技能集，随 App 部署到 rootfs `~/.codex/skills/`。

## 版权与许可证

- **项目自研技能**（`analyze`、`research`、`autoresearch`、`firecrawl-patterns`、`phoneharness`、
  `ultraqa`、`obsidian-vault`、`task-boundary`、`code-review`、`security-review` 等）随主项目采用
  **MIT License**（见根目录 `LICENSE`）。
- **Qwen-MM-Plugins（8 个 `qwen-mm-plugins-*`）**：来自
  [QwenLM/Qwen-MM-Plugins](https://github.com/QwenLM/Qwen-MM-Plugins)，**Apache-2.0**。
  本项目对其做了本地化整合（配置路径、依赖适配），各插件目录内已附带 Apache-2.0 `LICENSE` 副本。
- **带许可证声明的技能**：`.system/*`（4 个，Apache-2.0）、`playwright`（Apache-2.0）、
  `taskmaster`（MIT）、`simplecadapi`（**AGPL-3.0**）。
- **其余技能**（如 `git-guardrails-claude-code`、`grilling` 系列、`rev-*` 系列、`writing-*` 系列、
  `deep-interview`、`design-an-interface`、`diagnosing-bugs` 等）来自各类社区开源项目/作者，
  **原目录未附带版权声明与许可证**，版权归原作者所有。本项目仅作学习与整合，未声明任何所有权。

> 完整第三方清单见根目录 **[THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md)**。
> 如有任何权利方认为某技能侵犯其权益，请通过 GitHub/Gitee Issue 联系，核实后立即移除。

## 说明

- `skills.tar.gz`（`assets/skills.tar.gz`）由 `tool/update_qwen_mm_skills.sh --pack` 从本目录打包生成。
- 修改本目录内容后，请重新运行该脚本以同步到 App 内置包。
