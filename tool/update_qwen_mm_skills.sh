#!/usr/bin/env bash
# ====================================================================
#  Qwen-MM-Plugins skills 同步工具（「在 GitHub 里搞」）
#
#  从 GitHub 拉取 Qwen 官方 Qwen-MM-Plugins 仓库，把 8 个多模态能力
#  的 skill/ 目录并入本仓库 skills/qwen-mm-plugins-*，并重建
#  assets/skills.tar.gz（App 部署时由 _deploySkills 解压到 rootfs
#  ~/.codex/skills/，与宿主 skills 同机制）。
#
#  用法：
#    bash tool/update_qwen_mm_skills.sh           # 拉取上游 + 重建 tar.gz
#    bash tool/update_qwen_mm_skills.sh --fetch   # 仅拉取上游并更新技能目录
#    bash tool/update_qwen_mm_skills.sh --pack    # 仅重建 assets/skills.tar.gz
#    bash tool/update_qwen_mm_skills.sh --ref <tag>  # 拉取指定发布 tag
# ====================================================================
set -euo pipefail

REPO_URL="https://github.com/QwenLM/Qwen-MM-Plugins.git"
CAPS=(core api search video-memory video-edit blender freecad edu-agent)
MANIFEST="docs/qwen-mm-plugins-sync.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$SCRIPT_DIR"

MODE="all"
REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fetch) MODE="fetch"; shift ;;
    --pack)  MODE="pack"; shift ;;
    --ref)   REF="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

fetch() {
  echo "[qwen-mm] 拉取上游 ${REPO_URL} (${REF:-main}) ..."
  local TMP
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/qwen-mm.XXXXXX")"
  if [ -n "$REF" ]; then
    git clone --depth 1 --branch "$REF" "$REPO_URL" "$TMP/repo" 2>/dev/null || {
      echo "❌ 拉取 tag $REF 失败（回退 main）"; git clone --depth 1 "$REPO_URL" "$TMP/repo"; }
  else
    git clone --depth 1 "$REPO_URL" "$TMP/repo"
  fi

  local COMMIT
  COMMIT="$(cd "$TMP/repo" && git rev-parse HEAD)"
  local DATE
  DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  for cap in "${CAPS[@]}"; do
    local src="$TMP/repo/src/capabilities/$cap/skill"
    if [ ! -d "$src" ]; then echo "⚠️  上游无 $cap/skill，跳过"; continue; fi
    # 清理旧目录（脚本内允许 rm -rf：目标是明确的仓库内技能目录）
    rm -rf "skills/qwen-mm-plugins-$cap"
    mkdir -p "skills/qwen-mm-plugins-$cap"
    cp -r "$src/." "skills/qwen-mm-plugins-$cap/"
    local n; n="$(find "skills/qwen-mm-plugins-$cap" -type f | wc -l)"
    echo "  ✔ qwen-mm-plugins-$cap ($n 文件)"
  done

  # 写入同步 manifest
  mkdir -p docs
  cat > "$MANIFEST" << EOF
# Qwen-MM-Plugins Skills 同步记录

> 本目录 skills/qwen-mm-plugins-* 由 [QwenLM/Qwen-MM-Plugins]($REPO_URL)
> 自动同步，由 \`tool/update_qwen_mm_skills.sh\` 维护。请勿手工编辑技能内容。

- 上游引用: ${REPO_URL}
- 同步 ref: ${REF:-main}
- 上游 commit: \`${COMMIT}\`
- 同步时间: ${DATE}

## 能力清单（8）

| 技能目录 | 能力 | MCP server |
|---|---|---|
| qwen-mm-plugins-core | 本地读图/视频/文档/3D（免 key） | qwen-mm-plugins-core |
| qwen-mm-plugins-api | DashScope 云端 VL/OCR/ASR/grounding | qwen-mm-plugins-api |
| qwen-mm-plugins-search | 网页搜索/抽取/反向图搜 | qwen-mm-plugins-search |
| qwen-mm-plugins-video-memory | 长视频分层记忆问答 | qwen-mm-plugins-video-memory |
| qwen-mm-plugins-video-edit | 音视频生成与剪辑工作流 | qwen-mm-plugins-video-edit |
| qwen-mm-plugins-blender | Blender 建模/材质/渲染 | qwen-mm-plugins-blender |
| qwen-mm-plugins-freecad | FreeCAD 参数化 CAD/FEM | qwen-mm-plugins-freecad |
| qwen-mm-plugins-edu-agent | 中文数理讲解视频（纯 Skill） | （无） |

## 重新同步

\`\`\`bash
bash tool/update_qwen_mm_skills.sh           # main 最新
bash tool/update_qwen_mm_skills.sh --ref qwen-mm-plugins-core-v1.0.1   # 指定 tag
\`\`\`
EOF
  echo "  ✔ manifest: $MANIFEST (commit $COMMIT)"
  # 清理临时克隆
  rm -rf "$TMP"
}

pack() {
  echo "[qwen-mm] 重建 assets/skills.tar.gz ..."
  local before after
  before="$(du -sk skills | cut -f1)"
  tar -czf assets/skills.tar.gz -C skills .
  after="$(du -sh assets/skills.tar.gz | cut -f1)"
  local n; n="$(tar tzf assets/skills.tar.gz | grep -c '^\./qwen-mm-plugins-')"
  echo "  ✔ skills/ ${before}KB → assets/skills.tar.gz ${after}"
  echo "  ✔ 含 qwen-mm-plugins-* 条目: $n"
  echo "  总条目: $(tar tzf assets/skills.tar.gz | wc -l)"
}

case "$MODE" in
  fetch) fetch ;;
  pack)  pack ;;
  all)   fetch; pack ;;
esac
echo "[qwen-mm] 完成"
