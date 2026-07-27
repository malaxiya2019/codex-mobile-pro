#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Codex Mobile Pro — 一键部署脚本
#  基于预编译二进制包安装，无需 npm
# 检测是否在 proot 容器中
if [ -f /run/proot.pid ] || [ "$(cat /proc/1/cmdline 2>/dev/null | tr "\0" " ")" != "/sbin/init " ]; then
    export PROOT=1
fi
#  支持 Termux (Android) / Linux 服务器
#  版本: 1.0.0
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------- 检查 root ----------
if [ "$EUID" = 0 ] && [ "$PROOT" != "1" ]; then
    err "请勿使用 root 用户运行此脚本！"
    exit 1
fi

HOME_DIR="$HOME"
CODE_DIR="${HOME_DIR}/.codex"
LOCAL_BIN="${HOME_DIR}/.local/bin"
LOCAL_LIB="${HOME_DIR}/.local/lib"
MIMO_DIR="${HOME_DIR}/.mimo2codex"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================================
#  1. 检测平台
# ============================================================
detect_platform() {
    # 1) 检查 proot 容器
    if [ -f /run/proot.pid ] 2>/dev/null; then
        echo "linux"; return
    fi
    # 2) 检查是否在容器中（非 init 进程）
    CMD1=$(cat /proc/1/cmdline 2>/dev/null | tr "\000" " " | head -c 60)
    if [ -n "$CMD1" ] && [ "$CMD1" != "/sbin/init " ] && [ "$CMD1" != "/init " ]; then
        echo "linux"; return
    fi
    # 3) Termux（需要 TERMUX_VERSION 环境变量确认）
    if [ -d "/data/data/com.termux" ] && [ -n "$TERMUX_VERSION" ]; then
        echo "termux"; return
    fi
    # 4) 普通 Linux
    if [ -f /etc/os-release ]; then echo "linux"; else echo "unknown"; fi
}
PLATFORM=$(detect_platform)
info "检测到平台: ${PLATFORM}"

# ============================================================
#  2. 安装基础依赖
# ============================================================
install_deps() {
    info ">>> 安装基础依赖..."

    case "$PLATFORM" in
        termux)
            pkg update -y
            pkg upgrade -y
            pkg install -y \
                nodejs-lts git python rust \
                binutils openssl-tool \
                ca-certificates lsof tmux
            ;;

        linux)
            if command -v apt &>/dev/null; then
                sudo apt update -y
                sudo apt install -y \
                    nodejs npm git curl wget \
                    python3 build-essential \
                    openssl ca-certificates lsof tmux \
                    pkg-config
            elif command -v yum &>/dev/null; then
                sudo yum install -y \
                    nodejs npm git curl wget \
                    python3 gcc gcc-c++ make \
                    openssl ca-certificates lsof tmux
            elif command -v pacman &>/dev/null; then
                sudo pacman -Sy --noconfirm \
                    nodejs npm git curl wget \
                    python3 base-devel \
                    openssl ca-certificates lsof tmux
            else
                err "不支持的包管理器！请手动安装 git, curl, nodejs, python"
                exit 1
            fi
            ;;
    esac
    ok "基础依赖安装完成"
}

# ============================================================
#  3. 部署 Codex 二进制
# ============================================================
install_codex_binary() {
    info ">>> 部署 Codex CLI..."

    mkdir -p "$LOCAL_LIB/codex" "$LOCAL_BIN"

    CODEX_PKG="codex-package-aarch64-unknown-linux-musl.tar.gz"

    # 优先从本地存储读取（已下载好的）
    if [ -f "/storage/emulated/0/Download/${CODEX_PKG}" ]; then
        info "从手机存储找到安装包..."
        tar -xzf "/storage/emulated/0/Download/${CODEX_PKG}" -C "$LOCAL_LIB/codex"
    elif [ -f "${SCRIPT_DIR}/${CODEX_PKG}" ]; then
        info "从项目目录找到安装包..."
        tar -xzf "${SCRIPT_DIR}/${CODEX_PKG}" -C "$LOCAL_LIB/codex"
    else
        warn "未找到预编译包，尝试 npm 安装备选方案..."
        npm install -g @openai/codex
        ok "npm 安装完成（备选方案）"
        return
    fi

    chmod +x "$LOCAL_LIB/codex/bin/codex" 2>/dev/null || true
    chmod +x "$LOCAL_LIB/codex/codex-path/rg" 2>/dev/null || true

    # 创建 resolv.conf（避免 Termux DNS 问题）
    cat > "$LOCAL_LIB/codex/resolv.conf" << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

    # 创建包装脚本（注入 SSL 证书路径和 DNS）
    cat > "$LOCAL_BIN/codex" << 'CODEXWRAPPER'
#!/bin/bash
CODEX_BIN="$HOME/.local/lib/codex/bin/codex"
CODEX_RESOLV_CONF="$HOME/.local/lib/codex/resolv.conf"
export SSL_CERT_FILE="/data/data/com.termux/files/usr/etc/tls/cert.pem"
exec "$CODEX_BIN" "$@" 9<"$CODEX_RESOLV_CONF"
CODEXWRAPPER

    chmod +x "$LOCAL_BIN/codex"

    # 路径加入 bashrc
    if ! grep -q "local/bin" "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    # 验证
    if command -v codex &>/dev/null; then
        ok "Codex CLI 已部署 ($(codex --version 2>/dev/null | head -1))"
    else
        warn "Codex 尚未在 PATH 中，请执行: source ~/.bashrc"
    fi
}

# ============================================================
#  4. 安装 mimo2codex (DeepSeek 代理)
# ============================================================
install_mimo2codex() {
    info ">>> 安装 mimo2codex..."

    mkdir -p "$MIMO_DIR"

    if command -v mimo2codex &>/dev/null; then
        warn "mimo2codex 已存在，版本: $(mimo2codex --version 2>/dev/null)"
        return
    fi

    # 编译绕过（Termux 需要）
    if [ "$PLATFORM" = "termux" ]; then
        NODE_VER=$(node -v | cut -d'v' -f2)
        NODE_GYP="${HOME}/.cache/node-gyp/${NODE_VER}/include/node/common.gypi"
        if [ -f "$NODE_GYP" ]; then
            sed -i "s/, '-I<(android_ndk_path)\/sources\/android\/cpufeatures'//g" "$NODE_GYP" 2>/dev/null || true
        fi
    fi

    npm install -g mimo2codex
    ok "mimo2codex 安装完成 ($(mimo2codex --version 2>/dev/null))"

    # .env 配置（稍后由 setup_codex_config 填写 API Key）
    touch "$MIMO_DIR/.env"
}

# ============================================================
#  5. 配置 API Key 和 Codex
# ============================================================
setup_codex_config() {
    info ">>> 配置 Codex + API Key..."

    mkdir -p "$CODE_DIR"

    # ---------- API Key ----------
    if [ ! -s "$MIMO_DIR/.env" ]; then
        echo ""
        info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        info "  DeepSeek API Key 配置"
        info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "请前往 https://platform.deepseek.com 注册并获取 API Key"
        echo ""
        read -rp "请输入你的 DeepSeek API Key (sk-...): " ds_key
        if [ -n "$ds_key" ]; then
            echo "DS_API_KEY=${ds_key}" > "$MIMO_DIR/.env"
            ok "API Key 已保存"
        else
            warn "未输入，稍后手动编辑 $MIMO_DIR/.env"
            echo "DS_API_KEY=你的API_KEY" > "$MIMO_DIR/.env"
        fi
    else
        ok "API Key 已存在"
    fi

    # ---------- Codex 配置 ----------
    cat > "$CODE_DIR/config.toml" << 'CONFIGEOF'
model = "deepseek-chat"
model_provider = "deepseek"
model_context_window = 128000
model_reasoning_effort = "high"

[model_providers.deepseek]
name = "DeepSeek (via mimo2codex)"
base_url = "http://127.0.0.1:8788/v1"
wire_api = "responses"
requires_openai_auth = false
env_key = "DEEPSEEK_API_KEY"

[projects."__HOME_DIR__"]
trust_level = "trusted"

[tui.model_availability_nux]
"gpt-5.5" = 4

[features]
apps = false
CONFIGEOF

    # 替换占位符为实际家目录路径
    sed -i "s|__HOME_DIR__|$HOME_DIR|g" "$CODE_DIR/config.toml"

    # 备份原配置
    if [ -f "$CODE_DIR/config.toml.bak" ]; then
        ok "已有备份配置"
    else
        cp "$CODE_DIR/config.toml" "$CODE_DIR/config.toml.bak" 2>/dev/null || true
    fi

    # ---------- auth.json (认证绕过) ----------
    echo '{"openai_key": "dummy"}' > "$CODE_DIR/auth.json"

    # ---------- 会话数据库 ----------
    touch "$CODE_DIR/sessions.db"

    ok "Codex 配置完成"
}

# ============================================================
#  6. Threadripper 会话监控
# ============================================================
install_threadripper() {
    info ">>> 安装 threadripper (会话监控)..."

    npm install -g better-sqlite3 2>/dev/null || warn "better-sqlite3 安装失败，不影响核心功能"

    mkdir -p "$LOCAL_BIN"

    cat > "$LOCAL_BIN/threadripper.js" << 'THREADEOF'
const fs = require('fs');
const CONFIG_PATH = `${process.env.HOME}/.codex/config.toml`;
let current = '';
function getCurrentProvider() {
  try {
    const config = fs.readFileSync(CONFIG_PATH, 'utf8');
    const match = config.match(/model_provider\s*=\s*"([^"]+)"/);
    return match ? match[1] : '';
  } catch { return ''; }
}
try {
  const Database = require('better-sqlite3');
  const DB_PATH = `${process.env.HOME}/.codex/sessions.db`;
  fs.watchFile(CONFIG_PATH, { interval: 1000 }, () => {
    const newProvider = getCurrentProvider();
    if (newProvider && newProvider !== current) {
      try {
        const db = new Database(DB_PATH);
        db.prepare('UPDATE sessions SET provider = ?').run(newProvider);
        db.close();
        console.log(`[Threadripper] 已更新会话 provider 为: ${newProvider}`);
        current = newProvider;
      } catch (err) {
        console.error('[Threadripper] 更新失败:', err.message);
      }
    }
  });
} catch(e) {
  console.log('[Threadripper] better-sqlite3 不可用，仅监控模式');
}
console.log('[Threadripper] 已启动，监控 config.toml 变化...');
process.stdin.resume();
THREADEOF

    ok "threadripper 已安装"
}

# ============================================================
#  7. 部署 Skills
# ============================================================
deploy_skills() {
    info ">>> 部署 Skills..."

    SKILLS_TARGET="${CODE_DIR}/skills"
    mkdir -p "$SKILLS_TARGET"

    if [ -d "${SCRIPT_DIR}/skills" ] && [ "$(ls -A "${SCRIPT_DIR}/skills" 2>/dev/null)" ]; then
        cp -r "${SCRIPT_DIR}/skills/"* "$SKILLS_TARGET/" 2>/dev/null || true
        ok "Skills 已部署"
    else
        warn "skills 目录为空，跳过"
    fi

    mkdir -p "${SKILLS_TARGET}/.system"
}

# ============================================================
#  8. Shell 配置 (快捷命令)
# ============================================================
setup_shell() {
    info ">>> 配置快捷命令..."

    local rc_file="$HOME/.bashrc"

    if [ -f "${SCRIPT_DIR}/config/bashrc-additions.sh" ]; then
        if ! grep -q "# Codex Mobile Pro" "$rc_file" 2>/dev/null; then
            cat "${SCRIPT_DIR}/config/bashrc-additions.sh" >> "$rc_file"
            ok "快捷命令已添加至 ~/.bashrc"
        else
            ok "快捷命令已存在"
        fi
    fi

    # 确保 PATH
    if ! grep -q "local/bin" "$rc_file" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
    fi
}

# ============================================================
#  9. 备份脚本
# ============================================================
setup_backup() {
    info ">>> 配置备份..."

    cp "${SCRIPT_DIR}/backup-codex.sh" "$HOME/.local/bin/codex-backup" 2>/dev/null || \
    cat > "$HOME/.local/bin/codex-backup" << 'BACKUPEOF'
#!/usr/bin/env bash
BACKUP_DIR="$HOME/codex-backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"
tar czf "${BACKUP_DIR}/codex-config-${DATE}.tar.gz" \
  -C "$HOME" .codex/config.toml .mimo2codex/.env .bashrc .zshrc 2>/dev/null || true
ls -t "$BACKUP_DIR"/codex-config-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm
echo "[OK] 备份完成: ${BACKUP_DIR}/codex-config-${DATE}.tar.gz"
BACKUPEOF
    chmod +x "$HOME/.local/bin/codex-backup"
    ok "备份脚本已安装 (codex-backup)"
}

# ============================================================
#  10. 完成信息
# ============================================================
print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}  🎉 Codex Mobile Pro 部署完成！${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  首次启动（需联网）："
    echo ""
    echo -e "  ${CYAN}cyo --zh${NC}        中文 YOLO 模式（推荐）"
    echo ""
    echo "  其他命令："
    echo -e "  ${CYAN}cy${NC}              标准启动"
    echo -e "  ${CYAN}codex-backup${NC}     备份配置"
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
    install_codex_binary
    install_mimo2codex
    setup_codex_config
    install_threadripper
    deploy_skills
    setup_shell
    setup_backup
    print_summary

    # 刷新
    # shellcheck source=/dev/null
    source "$HOME/.bashrc" 2>/dev/null || true
}

main "$@"
