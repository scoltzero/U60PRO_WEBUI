#!/bin/sh
# ============================================================
# ZTE U60 Pro 高级面板 一键安装脚本
# 
# 前提条件：
#   1. 已通过 ADB 获取路由器 SSH 访问权限
#   2. SSH 用户为 scoltc (uid=1001, radio 组)
#   3. /overlay/home/scoltc 目录可写
#
# 使用方法：
#   方式一 (ADB)：  adb push install.sh /tmp/ && adb shell 'sh /tmp/install.sh'
#   方式二 (SSH)：   将此脚本和 index.html 传到路由器后执行
#
# 端口：8888（避开浏览器屏蔽的 6666 端口）
# ============================================================

set -e

PORT=8888
PANEL_DIR="/overlay/home/scoltc/web-panel"
TMP_DIR="/tmp/zte-panel"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " ZTE U60 Pro 高级面板安装"
echo "========================================"
echo ""

# --- 检查环境 ---
echo "[1/5] 检查环境..."

if [ "$(id -u)" != "0" ]; then
    echo "⚠️  当前非 root 用户，部分操作可能需要通过 ADB 执行"
fi

if [ ! -S /var/run/ubus/ubus.sock ]; then
    echo "❌ 找不到 ubus socket，请确认在 U60 Pro 上运行"
    exit 1
fi

if [ ! -x /usr/sbin/uhttpd ]; then
    echo "❌ 找不到 uhttpd"
    exit 1
fi

echo "   ✅ 环境检查通过"

# --- 创建持久化目录 ---
echo "[2/5] 创建持久化目录..."

mkdir -p "$PANEL_DIR"
echo "   ✅ $PANEL_DIR"

# --- 安装页面文件 ---
echo "[3/5] 安装页面文件..."

# 检查是否有 index.html 在同目录
if [ -f "$SCRIPT_DIR/index.html" ]; then
    cp "$SCRIPT_DIR/index.html" "$PANEL_DIR/index.html"
    echo "   ✅ 从本地复制 index.html"
elif [ -f /tmp/index.html ]; then
    cp /tmp/index.html "$PANEL_DIR/index.html"
    echo "   ✅ 从 /tmp 复制 index.html"
else
    echo "❌ 找不到 index.html，请将 index.html 放在脚本同目录或 /tmp/ 下"
    exit 1
fi

# 创建 mobile 兼容文件（ZTE uhttpd 会按 UA 重写路径）
cp "$PANEL_DIR/index.html" "$PANEL_DIR/mobile.html"
cp "$PANEL_DIR/index.html" "$PANEL_DIR/moible.html"

echo "   ✅ 页面文件已安装（含手机兼容）"

# --- 创建启动脚本 ---
echo "[4/5] 创建启动脚本..."

cat > "$PANEL_DIR/start_panel.sh" << 'STARTUP'
#!/bin/sh
# ZTE 高级面板 - uhttpd on port 8888
PANEL_DIR="/overlay/home/scoltc/web-panel"
TMP_DIR="/tmp/zte-panel"
PORT=8888

# 检查是否已运行
if ps | grep uhttpd | grep -v grep | grep -q ":${PORT} "; then
    echo "[zte-panel] 端口 ${PORT} 已在运行，跳过启动"
    exit 0
fi

# 放行防火墙（如果未添加）
if ! iptables -C INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -p tcp --dport ${PORT} -j ACCEPT
    echo "[zte-panel] 防火墙已放行端口 ${PORT}"
fi

# 复制到 /tmp
mkdir -p "$TMP_DIR"
cp "$PANEL_DIR"/*.html "$TMP_DIR/"

# 启动 uhttpd (以 radio 用户)
start-stop-daemon -S -b -m -p /tmp/zte-panel.pid \
    -c 1001:1001 \
    -x /usr/sbin/uhttpd -- \
    -p 0.0.0.0:${PORT} \
    -h "$TMP_DIR" \
    -x /cgi-bin \
    -u /ubus \
    -U /var/run/ubus/ubus.sock \
    -X -f -D -R \
    -n 3 -N 100 \
    -t 3600 -T 30 \
    -k 20 -A 1

echo "[zte-panel] 已启动在端口 ${PORT}"
STARTUP

chmod +x "$PANEL_DIR/start_panel.sh"
echo "   ✅ 启动脚本已创建"

# --- 配置开机自启 ---
echo "[5/5] 配置开机自启..."

START_SSH="/overlay/dropbear/start_ssh.sh"
if [ -f "$START_SSH" ]; then
    if grep -q "start_panel" "$START_SSH"; then
        echo "   ✅ 自启动已存在，跳过"
    else
        sed -i "/^exit 0$/i\\
# 启动 ZTE 高级面板\\
sh $PANEL_DIR/start_panel.sh \&" "$START_SSH"
        echo "   ✅ 已添加到 start_ssh.sh 自启动"
    fi
else
    echo "   ⚠️  未找到 start_ssh.sh，请手动将以下命令添加到开机启动："
    echo "      sh $PANEL_DIR/start_panel.sh &"
fi

# --- 立即启动 ---
echo ""
echo "正在启动面板..."
sh "$PANEL_DIR/start_panel.sh"

echo ""
echo "========================================"
echo " ✅ 安装完成！"
echo "========================================"
echo ""
echo " 访问地址：http://192.168.0.1:8888"
echo " 手机/电脑均可访问（自适应布局）"
echo ""
echo " 使用路由器管理密码登录"
echo " 密码会缓存，session 过期自动重连"
echo ""
echo " 功能清单："
echo "   • 网络信息、信号详情（LTE/NR CA）"
echo "   • 流量统计（实时/月/总）"
echo "   • WAN 状态（IPv4/IPv6 双栈）、系统状态"
echo "   • 温控开关（过热自动降速）"
echo "   • 网络制式切换（5G SA/NSA/4G/3G）"
echo "   • 4G/5G 频段锁定"
echo "   • 4G/5G 小区锁定"
echo "   • WiFi 设置（功率/国家码/连接数）"
echo "   • WiFi/硬件/SIM/WMS 详细信息"
echo ""
echo " 卸载：rm -rf $PANEL_DIR"
echo "        并从 start_ssh.sh 移除自启动行"
echo "========================================"
