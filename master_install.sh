#!/bin/bash
# =============================================================
# ZTE U60 Pro 完整安装流程（一键串联版）
#
# 使用方式：
#   方式一（完整流程）：
#     bash master_install.sh [SSH用户名] [SSH密码]
#     # 示例：bash master_install.sh advanced admin123456
#
#   方式二（分步执行）：
#     步骤1：python3 scripts/adb/zte_u60_adb.py        # 启用ADB调试
#     步骤2：bash scripts/ssh/install.sh [用户] [密码] # 安装SSH
#     步骤3：bash scripts/web-panel/install.sh          # 安装高级后台
#
# 流程说明：
#   1. zte_u60_adb.py   → 通过WebUI API启用USB调试模式
#   2. ssh/install.sh    → 下载Dropbear → 创建用户 → 配置开机自启
#   3. web-panel/install.sh → 部署index.html → 配置uhttpd → 开机自启
#
# 注意：执行前请确保设备屏幕处于解锁状态
# =============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_USER="${1:-advanced}"
SSH_PASS="${2:-admin123456}"

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   ZTE U60 Pro 完整安装流程                      ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "  SSH 用户：$SSH_USER"
echo "  SSH 密码：$SSH_PASS"
echo ""

# ---- 检查环境 ----
info "检查运行环境..."

if ! command -v python3 >/dev/null 2>&1; then
    error "未找到 python3，请先安装 Python 3"
fi

if ! command -v adb >/dev/null 2>&1; then
    error "未找到 adb，请先安装 Android Platform Tools（Homebrew: brew install android-platform-tools）"
fi

info "检查 ADB 连接..."
if ! adb devices | grep -q "device$"; then
    warn "未检测到 ADB 设备"
    warn "请确保："
    warn "  1. 设备已通过 USB 连接电脑"
    warn "  2. 设备屏幕已解锁"
    warn "  3. 路由器的 ADB 调试已开启（如未开启，运行 python3 scripts/adb/zte_u60_adb.py）"
    warn ""
    read -p "按回车继续尝试..." _
fi

echo ""

# ---- 步骤1：启用 ADB ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  步骤 1/3：启用 ADB 调试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "正在启用 ADB 调试模式..."
info "提示：确保设备屏幕处于解锁状态"
echo ""

if python3 "$SCRIPT_DIR/scripts/adb/zte_u60_adb.py"; then
    success "ADB 调试已启用"
else
    warn "ADB 启用脚本执行完成（请按设备屏幕提示操作）"
fi

echo ""
info "等待设备稳定..."
sleep 3

if adb shell "echo ok" 2>/dev/null | grep -q "ok"; then
    success "ADB Shell 可用"
else
    error "无法获取 ADB Shell 权限，请检查设备连接后重试"
fi

echo ""

# ---- 步骤2：安装 SSH ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  步骤 2/3：安装 SSH 服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "安装 SSH 服务（Dropbear）..."

if bash "$SCRIPT_DIR/scripts/ssh/install.sh" "$SSH_USER" "$SSH_PASS"; then
    success "SSH 服务安装完成"
else
    error "SSH 安装失败"
fi

echo ""

# ---- 步骤3：安装高级后台 ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  步骤 3/3：安装高级后台面板"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "安装高级后台面板..."

if adb push "$SCRIPT_DIR/scripts/web-panel/install.sh" /tmp/install_web_panel.sh >/dev/null 2>&1 && \
   adb push "$SCRIPT_DIR/scripts/web-panel/index.html" /tmp/index.html >/dev/null 2>&1; then
    info "文件已上传，正在执行安装脚本..."
    if adb shell "sh /tmp/install_web_panel.sh"; then
        success "高级后台面板安装完成"
    else
        error "高级后台面板安装失败"
    fi
else
    error "无法上传文件到设备，请检查 ADB 连接"
fi

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   ✅ 全部安装完成！                             ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "  SSH 连接：ssh $SSH_USER@192.168.0.1"
echo "  面板地址：http://192.168.0.1:8888"
echo ""
echo "  用户名：$SSH_USER"
echo "  密码：$SSH_PASS"
echo ""
