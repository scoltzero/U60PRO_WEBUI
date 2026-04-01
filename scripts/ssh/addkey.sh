#!/bin/bash
# =============================================================
# U60 Pro 添加公钥认证脚本
# 使用方式：bash ~/u60-ssh-addkey.sh [公钥文件路径]
# 示例：bash ~/u60-ssh-addkey.sh ~/.ssh/id_rsa.pub
# =============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

PUBKEY_FILE="${1:-$HOME/.ssh/id_rsa.pub}"
SSH_USER="scoltc"

[ -f "$PUBKEY_FILE" ] || error "公钥文件不存在：$PUBKEY_FILE"
command -v adb >/dev/null || error "未找到 adb"
adb devices | grep -q "device$" || error "未检测到 ADB 设备"

PUBKEY=$(cat "$PUBKEY_FILE")
info "添加公钥：$PUBKEY_FILE"

adb shell "
  mkdir -p /overlay/home/${SSH_USER}/.ssh
  chmod 700 /overlay/home/${SSH_USER}/.ssh
  echo '${PUBKEY}' >> /overlay/home/${SSH_USER}/.ssh/authorized_keys
  chmod 644 /overlay/home/${SSH_USER}/.ssh/authorized_keys

  # 同步到运行时目录
  mkdir -p /tmp/home/${SSH_USER}/.ssh
  cp /overlay/home/${SSH_USER}/.ssh/authorized_keys /tmp/home/${SSH_USER}/.ssh/
  chmod 644 /tmp/home/${SSH_USER}/.ssh/authorized_keys
"

success "公钥已添加，现在可以用密钥登录"
echo ""
echo "  ssh -i ${PUBKEY_FILE%.pub} u60pro"
echo ""
