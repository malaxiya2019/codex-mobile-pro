#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

BACKUP_DIR="$HOME/codex-backups"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║       Codex Mobile Pro — 配置恢复            ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

if [ ! -d "$BACKUP_DIR" ]; then
    err "未找到备份目录: $BACKUP_DIR"
    exit 1
fi

BACKUPS=($(ls -t "$BACKUP_DIR"/codex-config-*.tar.gz 2>/dev/null))
if [ ${#BACKUPS[@]} -eq 0 ]; then
    err "未找到备份文件！"
    exit 1
fi

echo "可用的备份："
echo ""
for i in "${!BACKUPS[@]}"; do
    FILE="${BACKUPS[$i]}"
    SIZE=$(du -h "$FILE" | cut -f1)
    echo "  [$((i+1))] $(basename "$FILE")  (${SIZE})"
done
echo ""

read -rp "选择要恢复的备份编号 [1-${#BACKUPS[@]}]: " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#BACKUPS[@]}" ]; then
    err "无效选择"
    exit 1
fi

SELECTED="${BACKUPS[$((choice-1))]}"

info "即将恢复: $(basename "$SELECTED")"
read -rp "覆盖当前配置？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "已取消"
    exit 0
fi

# 先备份当前配置
CURRENT_BACKUP="${BACKUP_DIR}/codex-config-$(date +%Y%m%d_%H%M%S)-before-restore.tar.gz"
tar czf "$CURRENT_BACKUP" \
    -C "$HOME" .codex/config.toml .codex/auth.json .mimo2codex/.env .bashrc 2>/dev/null || true
ok "已备份当前配置 → $(basename "$CURRENT_BACKUP")"

tar xzf "$SELECTED" -C "$HOME"
ok "恢复完成: $(basename "$SELECTED")"
echo ""
echo -e "请执行: ${CYAN}source ~/.bashrc${NC}"
