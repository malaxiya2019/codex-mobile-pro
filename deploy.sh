#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Codex Mobile Pro — 一键部署脚本
#  适用于 Termux (Android) / Linux 服务器
#  版本: 1.0.0
#  作者: sanbei101
# ============================================================

# ---------- 颜色 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------- 检查是否为 root ----------
if [ "$EUID" = 0 ]; then
    err "请勿使用 root 用户运行此脚本！"
    exit 1
fi

HOME_DIR="$HOME"
CODE_DIR="${HOME_DIR}/.codex"
LOCAL_BIN="${HOME_DIR}/.local/bin"
MIMO_DIR="${HOME_DIR}/.mimo2codex"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------- 检测平台 ----------
detect_platform() {
    if [ -d "/data/data/com.termux" ]; then
        echo "termux"
    elif [ -f /etc/os-release ]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

PLATFORM=$(detect_platform)
info "检测到平台: ${PLATFORM}"

# ---------- 安装基础依赖 ----------
install_deps() {
    info ">>> 安装基础依赖..."

    case "$PLATFORM" in
        termux)
            pkg update -y
            pkg upgrade -y
            pkg install -y \
                git curl wget \
                nodejs-lts \
                tmux proot-distro \
                build-essential \
                openssh
            ;;

        linux)
            if command -v apt &>/dev/null; then
                sudo apt update -y
                sudo apt install -y \
                    git curl wget \
                    nodejs npm \
                    tmux \
                    build-essential \
                    openssh-client
            elif command -v yum &>/dev/null; then
                sudo yum install -y \
                    git curl wget \
                    nodejs npm \
                    tmux \
                    gcc gcc-c++ make \
                    openssh-clients
            elif command -v pacman &>/dev/null; then
                sudo pacman -Sy --noconfirm \
                    git curl wget \
                    nodejs npm \
                    tmux \
                    base-devel \
                    openssh
            else
                err "不支持的包管理器！请手动安装 git, curl, nodejs"
                exit 1
            fi
            ;;
    esac

    ok "基础依赖安装完成"
}

# ---------- 安装 Node.js (Linux 补充) ----------
ensure_node() {
    if ! command -v node &>/dev/null; then
        warn "Node.js 未安装，尝试安装..."
        case "$PLATFORM" in
            linux)
                curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
                sudo apt install -y nodejs
                ;;
        esac
    fi
    ok "Node.js $(node --version)"
}

# ---------- 安装 Codex CLI ----------
install_codex() {
    info ">>> 安装 Codex CLI..."

    # 确保 ~/.local/bin 存在
    mkdir -p "$LOCAL_BIN"

    if command -v codex &>/dev/null; then
        warn "Codex CLI 已安装 (v$(codex --version 2>/dev/null | head -1))"
        read -rp "是否重新安装？(y/N): " reinstall
        if [[ "$reinstall" =~ ^[Yy]$ ]]; then
            npm uninstall -g @openai/codex 2>/dev/null || true
            npm install -g @openai/codex
        fi
    else
        # Termux 下用 npm 全局安装
        npm install -g @openai/codex
    fi

    # 创建软链接（如果不存在）
    if ! command -v codex &>/dev/null; then
        CODEX_BIN="$(npm root -g)/@openai/codex/cli.js"
        if [ -f "$CODEX_BIN" ]; then
            ln -sf "$CODEX_BIN" "$LOCAL_BIN/codex"
            chmod +x "$LOCAL_BIN/codex"
        fi
    fi

    ok "Codex CLI 安装完成"
}

# ---------- 安装 mimo2codex (DeepSeek 代理) ----------
install_mimo2codex() {
    info ">>> 安装 mimo2codex (DeepSeek API 代理)..."

    mkdir -p "$MIMO_DIR"

    # 检查是否已安装
    if command -v mimo2codex &>/dev/null; then
        warn "mimo2codex 已安装 (v$(mimo2codex --version 2>/dev/null))"
        return
    fi

    # 下载 mimo2codex
    if [ "$PLATFORM" = "termux" ]; then
        # Termux 从 GitHub release 下载
        MIMO_VERSION="0.5.28"
        MIMO_URL="https://github.com/mimo2codex/mimo2codex/releases/download/v${MIMO_VERSION}/mimo2codex-${MIMO_VERSION}-linux-arm64.tar.gz"

        info "下载 mimo2codex..."
        curl -sL "$MIMO_URL" -o /tmp/mimo2codex.tar.gz
        tar xzf /tmp/mimo2codex.tar.gz -C /tmp/
        cp /tmp/mimo2codex "$LOCAL_BIN/mimo2codex"
        chmod +x "$LOCAL_BIN/mimo2codex"
        rm -f /tmp/mimo2codex.tar.gz
    else
        # Linux 通用安装
        MIMO_VERSION="0.5.28"
        MIMO_URL="https://github.com/mimo2codex/mimo2codex/releases/download/v${MIMO_VERSION}/mimo2codex-${MIMO_VERSION}-linux-amd64.tar.gz"

        info "下载 mimo2codex..."
        curl -sL "$MIMO_URL" -o /tmp/mimo2codex.tar.gz
        tar xzf /tmp/mimo2codex.tar.gz -C /tmp/
        sudo cp /tmp/mimo2codex /usr/local/bin/mimo2codex
        sudo chmod +x /usr/local/bin/mimo2codex
        rm -f /tmp/mimo2codex.tar.gz
    fi

    ok "mimo2codex 安装完成"
}

# ---------- 配置 Codex ----------
setup_codex_config() {
    info ">>> 配置 Codex..."

    mkdir -p "$CODE_DIR"

    # 备份已有配置
    if [ -f "${CODE_DIR}/config.toml" ]; then
        cp "${CODE_DIR}/config.toml" "${CODE_DIR}/config.toml.bak.$(date +%s)"
        ok "已备份原配置 → config.toml.bak"
    fi

    # 复制预调优配置
    if [ -f "${SCRIPT_DIR}/config/codex-config.toml" ]; then
        cp "${SCRIPT_DIR}/config/codex-config.toml" "${CODE_DIR}/config.toml"
        ok "Codex 配置已部署"
    else
        warn "未找到 codex-config.toml，将使用默认配置"
    fi

    # 配置 DeepSeek API Key
    if [ ! -f "${MIMO_DIR}/.env" ]; then
        echo ""
        info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        info "  DeepSeek API Key 配置"
        info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "请前往 https://platform.deepseek.com 注册并获取 API Key"
        echo ""

        read -rp "请输入你的 DeepSeek API Key (sk-...): " ds_key

        if [ -n "$ds_key" ]; then
            echo "DS_API_KEY=${ds_key}" > "${MIMO_DIR}/.env"
            ok "API Key 已保存至 ${MIMO_DIR}/.env"
        else
            warn "未输入 API Key，稍后可通过编辑 ${MIMO_DIR}/.env 手动配置"
            echo "DS_API_KEY=你的API_KEY" > "${MIMO_DIR}/.env"
        fi
    else
        ok "API Key 已存在"
    fi
}

# ---------- 部署 Shell 配置 ----------
setup_shell() {
    info ">>> 配置 Shell 快捷命令..."

    local rc_file=""
    case "$SHELL" in
        */zsh) rc_file="${HOME_DIR}/.zshrc" ;;
        */bash) rc_file="${HOME_DIR}/.bashrc" ;;
        *) rc_file="${HOME_DIR}/.bashrc" ;;
    esac

    # 如果存在预制配置片段则追加
    if [ -f "${SCRIPT_DIR}/config/bashrc-additions.sh" ]; then
        # 检查是否已添加过
        if ! grep -q "# Codex Mobile Pro" "$rc_file" 2>/dev/null; then
            cat "${SCRIPT_DIR}/config/bashrc-additions.sh" >> "$rc_file"
            ok "Shell 配置已追加至 ${rc_file}"
        else
            ok "Shell 配置已存在，跳过"
        fi
    fi

    # 确保 ~/.local/bin 在 PATH 中
    if ! echo "$PATH" | grep -q "$LOCAL_BIN"; 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
    fi
}

# ---------- 部署 Skills ----------
deploy_skills() {
    info ">>> 部署 Skills..."

    SKILLS_TARGET="${CODE_DIR}/skills"

    if [ -d "${SCRIPT_DIR}/skills" ] && [ "$(ls -A "${SCRIPT_DIR}/skills" 2>/dev/null)" ]; then
        # 从打包目录复制
        cp -r "${SCRIPT_DIR}/skills/"* "$SKILLS_TARGET/"
        ok "Skills 已从打包目录部署"
    else
        warn "skills 目录为空，跳过"
    fi

    # 确保 .system 目录存在
    mkdir -p "${SKILLS_TARGET}/.system"
}

# ---------- 初始化数据目录 ----------
init_data() {
    info ">>> 初始化数据目录..."

    mkdir -p "${CODE_DIR}"/{log,memories,sessions,shell_snapshots,backup_logs,tmp,.tmp}
    touch "${CODE_DIR}/sessions.db" 2>/dev/null || true
}

# ---------- 配置备份 ----------
setup_backup() {
    info ">>> 配置定时备份..."

    BACKUP_SCRIPT="${HOME_DIR}/.local/bin/codex-backup"
    cat > "$BACKUP_SCRIPT" << 'BACKUPEOF'
#!/usr/bin/env bash
# Codex 配置备份脚本
BACKUP_DIR="$HOME/codex-backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

echo "[备份] 备份 Codex 配置..."
tar czf "${BACKUP_DIR}/codex-config-${DATE}.tar.gz" \
    -C "$HOME" \
    .codex/config.toml \
    .mimo2codex/.env \
    .bashrc \
    2>/dev/null

# 保留最近 7 个备份，删除旧的
ls -t "$BACKUP_DIR"/codex-config-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm

echo "[备份] 完成 → ${BACKUP_DIR}/codex-config-${DATE}.tar.gz"
echo "[备份] 恢复命令: tar xzf ${BACKUP_DIR}/codex-config-${DATE}.tar.gz -C \$HOME"
BACKUPEOF
    chmod +x "$BACKUP_DIR/codex-backup" 2>/dev/null || chmod +x "$BACKUP_SCRIPT"

    ok "备份脚本已创建: codex-backup"
}

# ---------- 安装完成信息 ----------
print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}  🎉 Codex Mobile Pro 部署完成！${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  启动命令："
    echo ""
    echo -e "  ${CYAN}cyo --zh${NC}       中文 YOLO 模式（推荐）"
    echo -e "  ${CYAN}cy${NC}             标准启动"
    echo -e "  ${CYAN}cs${NC}             安全模式（需确认）"
    echo ""
    echo "  首次启动前请确保："
    echo "  1. DeepSeek API Key 已配置 → ${MIMO_DIR}/.env"
    echo "  2. 网络已连接"
    echo ""
    echo "  备份命令："
    echo -e "  ${CYAN}codex-backup${NC}    备份配置"
    echo -e "  ${CYAN}bash codex-mobile-pro/restore-codex.sh${NC}  恢复配置"
    echo ""
    echo "  文档目录：${SCRIPT_DIR}/docs/"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ============================================================
#  主流程
# ============================================================
main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║       Codex Mobile Pro — 一键部署            ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    install_deps
    ensure_node
    install_codex
    install_mimo2codex
    setup_codex_config
    deploy_skills
    setup_shell
    init_data
    setup_backup
    print_summary

    # 刷新当前 shell
    if [ -f "$HOME/.bashrc" ]; then
        # shellcheck source=/dev/null
        source "$HOME/.bashrc" 2>/dev/null || true
    fi
}

main "$@"
