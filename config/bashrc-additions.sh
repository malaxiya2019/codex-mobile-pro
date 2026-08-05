# ============================================================
#  Codex Mobile Pro — Shell 快捷命令
#  追加到 ~/.bashrc 或 ~/.zshrc
# ============================================================

export PATH="$HOME/.local/bin:$PATH"

# ---------- DeepSeek API Key（codex 直连，配置中心保存的 key） ----------
if [ -f "$HOME/.mimo2codex/.env" ]; then
    export DEEPSEEK_API_KEY="$(grep '^DS_API_KEY=' "$HOME/.mimo2codex/.env" | head -1 | cut -d= -f2- | tr -d '\r\n')"
fi

# ---------- 基础 ----------
alias c='codex'
alias cp-status='ps aux | grep -E "mimo2codex|codex|threadripper" | grep -v grep'

# ---------- Tmux 会话 ----------
alias ct='tmux new -A -s codex'

# ---------- 安全模式 ----------
alias cs='codex --ask-for-approval on-request'

# ---------- Git 快捷 ----------
alias wip='git add -A && git commit -m "WIP: $(date +%H:%M)" --allow-empty'

# ---------- 备份 ----------
alias cb='codex-backup'

# ============================================================
#  mimo2codex + threadripper 启动/停止
# ============================================================
mimo_start() {
    if lsof -i :8788 >/dev/null 2>&1; then
        echo "[mimo] 已在运行 (PID: $(lsof -t -i :8788))"
    else
        echo "[mimo] 启动 mimo2codex..."
        nohup mimo2codex --model ds --port 8788 > ~/mimo2codex.log 2>&1 &
        sleep 2
        echo "[mimo] 已启动 (PID: $!)"
    fi
}

mimo_stop() {
    if lsof -i :8788 >/dev/null 2>&1; then
        kill $(lsof -t -i :8788) 2>/dev/null
        echo "[mimo] 已停止"
    fi
}

thread_start() {
    if pgrep -f "threadripper.js" >/dev/null 2>&1; then
        echo "[thread] 已在运行"
    else
        nohup node ~/.local/bin/threadripper.js > ~/threadripper.log 2>&1 &
        echo "[thread] 已启动"
    fi
}

# ============================================================
#  cy — 智能启动 Codex
# ============================================================
cy() {
    # DeepSeek 直连模式，无需 mimo2codex 代理
    codex "$@"
}

# ============================================================
#  cyo — YOLO 模式（跳过安全确认）
#  cyo --zh  = 中文模式
#  cyo --en  = 英文模式
# ============================================================
cyo() {
    # DeepSeek 直连模式，无需 mimo2codex 代理
    thread_start

    local ZH_PROMPT="以后所有自然语言使用简体中文回答。
分析、计划、修改说明、总结均使用中文。
代码、命令、文件路径、日志保持原文。"

    case "$1" in
        --zh)
            shift
            echo "[cyo] 中文 YOLO 模式"
            CODEX_SANDBOX_NETWORK_DISABLED=0 \
            codex --dangerously-bypass-approvals-and-sandbox \
            "$ZH_PROMPT" "$@"
            ;;
        --en)
            shift
            echo "[cyo] English YOLO mode"
            CODEX_SANDBOX_NETWORK_DISABLED=0 \
            codex --dangerously-bypass-approvals-and-sandbox \
            "$@"
            ;;
        *)
            CODEX_SANDBOX_NETWORK_DISABLED=0 \
            codex --dangerously-bypass-approvals-and-sandbox \
            "$@"
            ;;
    esac
}
