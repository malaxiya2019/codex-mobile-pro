# ============================================================
#  Codex Mobile Pro — Shell 快捷命令
#  追加到 ~/.bashrc 或 ~/.zshrc 使用
# ============================================================

export PATH="$HOME/.local/bin:$PATH"

# ---------- 基础命令 ----------
alias c='codex'

# ---------- 启动模式 ----------
alias cs='codex --ask-for-approval on-request'         # 安全模式
alias ct='tmux new -A -s codex'                        # Tmux 会话
alias cp-status='ps aux | grep -E "mimo2codex|codex" | grep -v grep'

# ---------- 快捷操作 ----------
alias wip='git add -A && git commit -m "WIP: $(date +%H:%M)" --allow-empty'

# ---------- 备份 ----------
alias cb='bash ~/.local/bin/codex-backup'
alias cr='bash ~/codex-mobile-pro/restore-codex.sh'

# ============================================================
#  cy — 智能启动（自动唤醒 mimo2codex + threadripper）
# ============================================================
cy() {
    if ! lsof -i :8788 >/dev/null 2>&1; then
        echo "[cy] mimo2codex 未启动，正在后台唤醒..."
        nohup mimo2codex --model ds --port 8788 \
        > ~/mimo2codex.log 2>&1 &
        sleep 1.5
    fi

    export NODE_PATH="$(npm root -g):$NODE_PATH"
    codex "$@"
}

# ============================================================
#  cyo — YOLO 模式 + 自动恢复
#  cyo --zh  = 中文模式
#  cyo --en  = 英文模式
# ============================================================
cyo() {
    # 1. 自动启动 mimo2codex
    if ! lsof -i :8788 >/dev/null 2>&1; then
        echo "[cyo] 检测到 mimo2codex 未启动，正在全自动唤醒..."
        nohup mimo2codex --model ds --port 8788 \
        > ~/mimo2codex.log 2>&1 &
        sleep 1.5
    fi

    # 2. Node 环境
    export NODE_PATH="$(npm root -g):$NODE_PATH"

    # 3. 中文提示
    local ZH_PROMPT="以后所有自然语言使用简体中文回答。
分析、计划、修改说明、总结均使用中文。
代码、命令、文件路径、日志保持原文。"

    # 4. 参数处理
    case "$1" in
        --zh)
            shift
            echo "[cyo] 中文 YOLO 模式"
            CODEX_SANDBOX_NETWORK_DISABLED=0 \
            codex \
            --dangerously-bypass-approvals-and-sandbox \
            "$ZH_PROMPT" "$@"
            ;;
        --en)
            shift
            echo "[cyo] English YOLO mode"
            CODEX_SANDBOX_NETWORK_DISABLED=0 \
            codex \
            --dangerously-bypass-approvals-and-sandbox \
            "$@"
            ;;
        *)
            CODEX_SANDBOX_NETWORK_DISABLED=0 \
            codex \
            --dangerously-bypass-approvals-and-sandbox \
            "$@"
            ;;
    esac
}

# ============================================================
#  环境变量
# ============================================================
export OPENAI_BASE_URL="http://127.0.0.1:8788/v1"
