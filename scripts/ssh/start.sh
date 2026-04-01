#!/bin/bash
# =============================================================
# U60 Pro SSH 快速启动脚本（设备已安装好，仅需重新启动 SSH）
# 使用方式：bash ~/u60-ssh-start.sh
# =============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

command -v adb >/dev/null || error "未找到 adb"
adb devices | grep -q "device$" || error "未检测到 ADB 设备，请先连接"

info "启动 U60 Pro SSH 服务..."
adb shell "killall dropbear 2>/dev/null; sleep 1; sh /overlay/dropbear/start_ssh.sh"
sleep 2

if adb shell "ps | grep dropbear | grep -v grep" | grep -q dropbear; then
  success "SSH 服务已启动，可以连接了"
  echo ""
  echo "  ssh u60pro"
  echo ""
else
  error "启动失败，请检查设备状态"
fi
