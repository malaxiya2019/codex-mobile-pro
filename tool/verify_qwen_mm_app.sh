#!/usr/bin/env bash
# ====================================================================
#  Qwen-MM-Plugins 真机验证脚本（App 更新后，在部署完成的终端里跑）
#
#  逐项核对方案2「GitHub 闭环」在真机上的落地，与 CI qwen-mm-verify
#  job（.github/workflows/ci.yml）用同源命令：
#    1. uvx 可用                     → rootfs /usr/local/bin/uvx
#    2. 8 个 skills 落盘             → ~/.codex/skills/qwen-mm-plugins-*
#    3. 7 段 MCP server 配置         → ~/.codex/config.toml [mcp_servers.qwen-mm-plugins-*]
#    4. 运行级实拉（最硬的一步）     → uvx --from "qwen-mm-plugins[cap] @ git+…@tag" cap --check-system
#    5. 共享配置 / ffmpeg            → ~/.qwen-mm-plugins/config、/usr/bin/ffmpeg（信息级）
#
#  用法：
#    bash tool/verify_qwen_mm_app.sh             # 快速抽查（core + search 实拉）
#    bash tool/verify_qwen_mm_app.sh --all       # 全量 7 个 MCP --check-system（较慢）
#    bash tool/verify_qwen_mm_app.sh --skip-run  # 只查落盘，不实拉（无网络/慢网）
#    CODEX_HOME=/path/.codex bash tool/verify_qwen_mm_app.sh  # 非默认 home 时覆盖
#
#  退出码：0 = 关键项全部通过；1 = 有关键项失败；2 = 用法错误
# ====================================================================
set -uo pipefail

REPO="https://github.com/QwenLM/Qwen-MM-Plugins.git"
# cap:tag — 与 CI/安装器 capRefs 同源，tag 实证自上游 .mcp.json（search 已修 v1.0.2）
CAPS=(
  "core:qwen-mm-plugins-core-v1.0.1"
  "api:qwen-mm-plugins-api-v1.0.1"
  "search:qwen-mm-plugins-search-v1.0.2"
  "video-memory:qwen-mm-plugins-video-memory-v1.0.1"
  "video-edit:qwen-mm-plugins-video-edit-v1.0.1"
  "blender:qwen-mm-plugins-blender-v1.0.1"
  "freecad:qwen-mm-plugins-freecad-v1.0.1"
)
# blender/freecad 依赖桌面系统程序（Blender/FreeCAD/GL），无头环境按上游语义容忍
TOLERANT=" blender freecad "
EXPECT_SKILLS=8
EXPECT_MCP=7

MODE="quick"          # quick | all | skip-run
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
while [ $# -gt 0 ]; do
  case "$1" in
    --all)      MODE="all"; shift ;;
    --skip-run) MODE="skip-run"; shift ;;
    -h|--help)  grep -E '^#   ' "$0" | sed 's/^#   //'; exit 0 ;;
    *) echo "未知参数: $1（见脚本头部用法）" >&2; exit 2 ;;
  esac
done

# 日志目录（Termux /tmp 可能不可写，放 $HOME 下 mktemp）
LOGDIR="$(mktemp -d "$HOME/qwen-mm-verify.XXXXXX" 2>/dev/null || echo "$HOME")"

PASS=0; FAIL=0; WARN=0; FAILED_ITEMS=()
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); FAILED_ITEMS+=("$1"); }

echo "═══════════════════════════════════════════════════"
echo "  Qwen-MM-Plugins 真机验证（${MODE} 模式）"
echo "  HOME=$HOME  CODEX_HOME=$CODEX_HOME"
echo "═══════════════════════════════════════════════════"

# ── 0. 环境探测（信息级）──────────────────────────────
echo
echo "[0/6] 环境探测"
echo "  ℹ️  用户=$(id -un 2>/dev/null || echo ?)  架构=$(uname -m 2>/dev/null || echo ?)"
echo "  ℹ️  请在「部署完成的 App 终端（rootfs）」内运行；proot 宿主侧路径不同会误报"

# ── 1. uvx 可用 ────────────────────────────────────────
echo
echo "[1/6] uvx 可用性"
UVX=""
for cand in /usr/local/bin/uvx uvx; do
  if command -v "$cand" >/dev/null 2>&1; then UVX="$(command -v "$cand")"; break; fi
done
if [ -n "$UVX" ]; then
  ver="$("$UVX" --version 2>&1 || true)"
  pass "uvx 可用: $UVX ($ver)"
else
  fail "uvx 未找到（安装器应 pip 装到 /usr/local/bin/uvx；若未部署先跑一键部署）"
fi

# ── 2. 8 个 skills 落盘 ────────────────────────────────
echo
echo "[2/6] skills 落盘（期望 $EXPECT_SKILLS 个）"
if [ -d "$CODEX_HOME/skills" ]; then
  dirs=()
  for d in "$CODEX_HOME"/skills/qwen-mm-plugins-*; do
    [ -d "$d" ] && dirs+=("$(basename "$d")")
  done
  n=${#dirs[@]}
  echo "  ℹ️  实际目录: ${dirs[*]:-（无）}"
  if [ "$n" -eq "$EXPECT_SKILLS" ]; then
    pass "qwen-mm-plugins-* 目录数 = $n"
  else
    fail "qwen-mm-plugins-* 目录数 = $n（期望 $EXPECT_SKILLS）"
  fi
  missing=""
  for name in api blender core edu-agent freecad search video-edit video-memory; do
    [ -f "$CODEX_HOME/skills/qwen-mm-plugins-$name/SKILL.md" ] || missing="$missing $name"
  done
  if [ -z "$missing" ]; then
    pass "8 个 SKILL.md 全部就位"
  else
    fail "SKILL.md 缺失:$missing"
  fi
else
  fail "skills 目录不存在: $CODEX_HOME/skills"
fi

# ── 3. 7 段 MCP server 配置 ────────────────────────────
echo
echo "[3/6] MCP server 配置（期望 $EXPECT_MCP 段）"
CONFIG="$CODEX_HOME/config.toml"
if [ -f "$CONFIG" ]; then
  n="$(grep -c '^\[mcp_servers\.qwen-mm-plugins-' "$CONFIG" || true)"
  echo "  ℹ️  $CONFIG"
  if [ "$n" -eq "$EXPECT_MCP" ]; then
    pass "mcp_servers.qwen-mm-plugins-* 段数 = $n"
  else
    fail "mcp_servers.qwen-mm-plugins-* 段数 = $n（期望 $EXPECT_MCP）"
  fi
  for cap in core api search video-memory video-edit blender freecad; do
    grep -q "\[mcp_servers.qwen-mm-plugins-$cap\]" "$CONFIG" || { fail "缺少 MCP 段: qwen-mm-plugins-$cap"; }
  done
else
  fail "config.toml 不存在: $CONFIG"
fi

# ── 4. 运行级实拉 --check-system ───────────────────────
echo
echo "[4/6] 运行级实拉 uvx --check-system"
if [ "$MODE" = "skip-run" ]; then
  warn "已跳过实拉（--skip-run），仅落盘检查"
elif [ -z "$UVX" ]; then
  fail "uvx 不可用，无法实拉（先修第 1 步）"
else
  if [ "$MODE" = "quick" ]; then
    RUN_CAPS=("core:qwen-mm-plugins-core-v1.0.1" "search:qwen-mm-plugins-search-v1.0.2")
    echo "  ℹ️  快速模式抽查: core search（--all 跑全部 7 个）"
  else
    RUN_CAPS=("${CAPS[@]}")
  fi
  for entry in "${RUN_CAPS[@]}"; do
    cap="${entry%%:*}"; tag="${entry#*:}"
    echo "  ─ [$cap] $tag ─"
    if "$UVX" --from "qwen-mm-plugins[$cap] @ git+$REPO@$tag" "qwen-mm-plugins-$cap" --check-system >"$LOGDIR/$cap.log" 2>&1; then
      pass "$cap --check-system 通过"
    else
      code=$?
      if [[ "$TOLERANT" == *" $cap "* ]]; then
        warn "$cap 报告系统依赖缺失（无头/缺桌面程序，容忍，exit=$code；详见 $LOGDIR/$cap.log）"
      else
        fail "$cap --check-system 失败 (exit=$code；详见 $LOGDIR/$cap.log)"
      fi
    fi
  done
fi

# ── 5. 共享配置 / ffmpeg（信息级）──────────────────────
echo
echo "[5/6] 共享配置 / 媒体依赖（信息级，不阻断）"
QWENCFG="${QWEN_MM_CONFIG:-$HOME/.qwen-mm-plugins/config}"
if [ -f "$QWENCFG" ]; then
  echo "  ℹ️  共享配置存在: $QWENCFG"
  filled=0
  while IFS= read -r k; do
    v="$(grep -E "^$k=" "$QWENCFG" | head -1 | cut -d= -f2-)"
    if [ -n "$v" ]; then echo "  ✔ $k 已填"; filled=1; fi
  done <<< "$(grep -E '^[A-Z_]+=' "$QWENCFG" | cut -d= -f1)"
  [ "$filled" -eq 0 ] && echo "  ℹ️  凭证均为空模板（api/search 需填 key 才可用，core 免 key）"
else
  echo "  ℹ️  共享配置不存在: $QWENCFG（不影响 core 免 key 能力）"
fi
if command -v ffmpeg >/dev/null 2>&1; then
  echo "  ℹ️  ffmpeg: $(ffmpeg -version 2>/dev/null | head -1 || echo '（版本未知）')"
else
  echo "  ℹ️  ffmpeg 未装（core/video-memory 媒体能力可能受限；部署器会尽力 apt 安装）"
fi

# ── 6. 端到端读图（人工指引）───────────────────────────
echo
echo "[6/6] 端到端读图（人工步骤，CLI 无独立读图命令）"
echo "  ℹ️  在 App 的 Codex 对话里发一张图，让 core 能力描述内容即可闭环。"
echo "  ℹ️  core 免 key；api/search 需先在 $QWENCFG 填 DASHSCOPE/SERPER/EXA/TAVILY 凭证。"

# ── 汇总 ───────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════"
echo "  结果: ✅ $PASS 项通过 / ❌ $FAIL 项失败 / ⚠️  $WARN 项容忍"
echo "  日志目录: $LOGDIR（--all 全量时每个 cap 一份 .log）"
if [ "$FAIL" -eq 0 ]; then
  echo "  🎉 方案2 闭环：关键项全部通过（$MODE 模式）"
  exit 0
else
  printf '  失败项:\n'
  for item in "${FAILED_ITEMS[@]}"; do echo "    ❌ $item"; done
  exit 1
fi
