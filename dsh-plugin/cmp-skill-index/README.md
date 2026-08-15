# cmp-skill-index

DSH（DeepSeek Harness）工具插件：把 **codex-mobile-pro** 内置的 70 条 skill 索引发给 agent，让模型能按名检索、复用已有技能（code review、TDD、安全排查、逆向、Obsidian 笔记、浏览器自动化……）。

纯 JS、零构建：**源码即交付物**，git 安装无需 `allowBuilds`。

## 安装

GitHub 安装（推荐，免 npm registry）：

```sh
dsh plugin --profile demo add github:malaxiya2019/dsh-cmp-skill-index
```

本地 bundle 安装：

```sh
# 在插件目录
npm pack                       # 产出 cmp-skill-index-0.1.0.tgz
dsh plugin --profile demo add ./cmp-skill-index-0.1.0.tgz
```

安装后插件自动激活（bundle patch 插入 `cmp-skill-index` 行）。

## 提供的工具

| 工具 | 参数 | 返回 |
|------|------|------|
| `list_skills` | 无 | 全部 70 条 skill 的 `{name, description}` 数组 |
| `search_skills` | `query`（必填）、`limit`（默认 20，上限 50） | 按 name+description 大小写不敏感匹配的结果数组 |

示例：

```
search_skills(query: "frida")     → [rev-frida, rev-ios-dump]
search_skills(query: "obsidian")  → [obsidian-vault]
```

## 开发 / 验证

```sh
npm install --no-save @deepseek-ai/dsh-tools @deepseek-ai/cordis
node scripts/smoke.js       # 用真实 defineTool 校验注册 + 数据
```

数据来源与再生成：

```sh
node scripts/gen-data.mjs <codex-mobile-pro 的 skills 目录>
# 重新生成 data/skills.js + data/skills.json（从各 skill 的 SKILL.md 提取 name/description）
```

## 许可

MIT（详见 LICENSE）。数据提取自 [malaxiya2019/codex-mobile-pro](https://github.com/malaxiya2019/codex-mobile-pro)（MIT 开源）。
