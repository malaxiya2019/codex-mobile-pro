#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

BACKUP_DIR="$HOME/codex-backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

echo -e "${CYAN}[备份]${NC} 备份 Codex 配置..."

tar czf "${BACKUP_DIR}/codex-config-${DATE}.tar.gz" \
    -C "$HOME" \
    .codex/config.toml \
    .codex/auth.json \
    .mimo2codex/.env \
    .bashrc \
    .zshrc \
    2>/dev/null || true

ls -t "$BACKUP_DIR"/codex-config-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm

echo -e "${GREEN}[OK]${NC}    备份完成 → ${BACKUP_DIR}/codex-config-${DATE}.tar.gz"
echo -e "${GREEN}[OK]${NC}    恢复: tar xzf ${BACKUP_DIR}/codex-config-${DATE}.tar.gz -C \$HOME"
