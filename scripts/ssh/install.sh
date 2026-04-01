#!/bin/bash
# =============================================================
# U60 Pro SSH 一键安装脚本
# 使用方式（从项目根目录运行）：
#   bash scripts/ssh/install.sh [用户名] [密码]
# 示例：bash scripts/ssh/install.sh advanced admin123456
# =============================================================

set -e

# 切换到脚本所在目录，确保相对路径正确
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SSH_USER="${1:-scoltc}"
SSH_PASS="${2:-86558781}"
WORK_DIR="/tmp/u60-ssh-$$"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ZTE U60 Pro SSH 一键安装               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 检查 adb
command -v adb >/dev/null || error "未找到 adb，请先安装 Android Platform Tools"

# 检查设备连接
info "检查 ADB 设备连接..."
adb devices | grep -q "device$" || error "未检测到 ADB 设备，请先连接设备"
success "设备已连接"

# 创建工作目录
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

# 下载 Dropbear
info "下载 Alpine Dropbear v2020.81 (aarch64)..."
curl -fsSL -o dropbear.apk \
  "https://dl-cdn.alpinelinux.org/alpine/v3.15/main/aarch64/dropbear-2020.81-r0.apk" \
  || error "下载失败，请检查网络"
tar -xzf dropbear.apk
success "下载完成"

# 上传二进制
info "上传二进制文件到设备..."
adb push usr/sbin/dropbear /tmp/dropbear2020_tmp
adb push usr/sbin/dropbearkey /tmp/dropbearkey2020_tmp

adb shell "
  mkdir -p /overlay/dropbear
  cp /tmp/dropbear2020_tmp /overlay/dropbear/dropbear2020
  cp /tmp/dropbearkey2020_tmp /overlay/dropbear/dropbearkey2020
  cp /lib/libz.so.1 /overlay/dropbear/libz.so.1 2>/dev/null || true
  chmod 755 /overlay/dropbear/dropbear2020 /overlay/dropbear/dropbearkey2020
  rm -f /tmp/dropbear2020_tmp /tmp/dropbearkey2020_tmp
"
success "二进制文件已上传"

# 生成 host keys
info "生成 SSH Host Keys..."
adb shell "
  cp /overlay/dropbear/dropbear2020 /tmp/dropbear_tmp
  cp /overlay/dropbear/libz.so.1 /tmp/libz.so.1 2>/dev/null || true
  chmod 755 /tmp/dropbear_tmp
  LD_LIBRARY_PATH=/tmp /tmp/dropbear_tmp --help 2>/dev/null || true

  mkdir -p /overlay/dropbear/etc/ssh
  LD_LIBRARY_PATH=/tmp /tmp/dropbear_tmp -r /overlay/dropbear/etc/ssh/ssh_host_rsa_key_tmp 2>/dev/null || true

  cp /overlay/dropbear/dropbearkey2020 /tmp/dropbearkey_tmp
  chmod 755 /tmp/dropbearkey_tmp
  LD_LIBRARY_PATH=/tmp /tmp/dropbearkey_tmp -t rsa   -f /overlay/dropbear/ssh_host_rsa_key
  LD_LIBRARY_PATH=/tmp /tmp/dropbearkey_tmp -t ecdsa -f /overlay/dropbear/ssh_host_ecdsa_key
  LD_LIBRARY_PATH=/tmp /tmp/dropbearkey_tmp -t ed25519 -f /overlay/dropbear/ssh_host_ed25519_key
  chmod 600 /overlay/dropbear/ssh_host_*
  rm -f /tmp/dropbear_tmp /tmp/dropbearkey_tmp /tmp/libz.so.1
"
success "Host Keys 已生成"

# 创建用户
info "创建用户 $SSH_USER..."
adb shell "
  # 创建用户（如不存在）
  if ! grep -q '^${SSH_USER}:' /etc/passwd; then
    echo '${SSH_USER}:x:1001:1001:${SSH_USER}:/overlay/home/${SSH_USER}:/bin/ash' >> /etc/passwd
    echo '${SSH_USER}:!:20544:0:99999:7:::' >> /etc/shadow
  fi
  mkdir -p /overlay/home/${SSH_USER}/.ssh
  chmod 700 /overlay/home/${SSH_USER}/.ssh
"
success "用户 $SSH_USER 已创建"

# 设置密码
info "设置密码..."
adb shell "
  HASH=\$(openssl passwd -1 '${SSH_PASS}')
  grep -v '^${SSH_USER}:' /etc/shadow > /tmp/shadow.tmp
  echo '${SSH_USER}:'\"$HASH\"':20544:0:99999:7:::' >> /tmp/shadow.tmp
  cp /tmp/shadow.tmp /etc/shadow
  rm /tmp/shadow.tmp
"
success "密码已设置"

# 写入启动脚本
info "写入开机启动脚本..."
adb shell "cat > /overlay/dropbear/start_ssh.sh << 'SCRIPT'
#!/bin/sh
trap '' SIGTERM

# 复制二进制到 /tmp（/overlay 有 noexec 限制）
cp /overlay/dropbear/dropbear2020 /tmp/dropbear
cp /overlay/dropbear/libz.so.1 /tmp/libz.so.1 2>/dev/null || true
chmod 755 /tmp/dropbear

# 复制 host keys
mkdir -p /tmp/etc/ssh
cp /overlay/dropbear/ssh_host_* /tmp/etc/ssh/
chmod 600 /tmp/etc/ssh/ssh_host_*

# 创建用户 home（解决 overlay chown 限制）
mkdir -p /tmp/home/${SSH_USER}/.ssh
chmod 701 /tmp/home/${SSH_USER}
chmod 700 /tmp/home/${SSH_USER}/.ssh
if [ -f /overlay/home/${SSH_USER}/.ssh/authorized_keys ]; then
  cp /overlay/home/${SSH_USER}/.ssh/authorized_keys /tmp/home/${SSH_USER}/.ssh/
  chmod 644 /tmp/home/${SSH_USER}/.ssh/authorized_keys
fi

# 修正 passwd 中的 home 路径
grep -v '^${SSH_USER}:' /etc/passwd > /tmp/passwd.tmp
echo '${SSH_USER}:x:1001:1001:${SSH_USER}:/tmp/home/${SSH_USER}:/bin/ash' >> /tmp/passwd.tmp
cp /tmp/passwd.tmp /etc/passwd

# 启动 dropbear
(LD_LIBRARY_PATH=/tmp /tmp/dropbear \
    -r /tmp/etc/ssh/ssh_host_rsa_key \
    -r /tmp/etc/ssh/ssh_host_ecdsa_key \
    -r /tmp/etc/ssh/ssh_host_ed25519_key \
    -p 22 &)
SCRIPT
chmod 755 /overlay/dropbear/start_ssh.sh"

# 配置 rc.local 开机自启
info "配置开机自启..."
adb shell "
  # 移除旧的 ssh 启动条目
  grep -v 'start_ssh\|dropbear' /etc/rc.local > /tmp/rc.tmp
  # 在 exit 0 前插入启动命令
  sed -i 's|exit 0|sh /overlay/dropbear/start_ssh.sh \&\nexit 0|' /tmp/rc.tmp
  cp /tmp/rc.tmp /etc/rc.local
  rm /tmp/rc.tmp
"
success "开机自启已配置"

# 首次启动
info "首次启动 SSH 服务..."
adb shell "sh /overlay/dropbear/start_ssh.sh" &
sleep 3
DROPBEAR_PID=$(adb shell "ps | grep dropbear | grep -v grep" 2>/dev/null)
if [ -n "$DROPBEAR_PID" ]; then
  success "SSH 服务已启动"
else
  warn "SSH 服务可能未正常启动，请手动检查"
fi

# 配置客户端
info "配置本机 SSH 客户端..."
DEVICE_IP=$(adb shell "ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" | tr -d '\r')
[ -z "$DEVICE_IP" ] && DEVICE_IP="192.168.0.1"

# 避免重复写入
if ! grep -q "Host u60pro" ~/.ssh/config 2>/dev/null; then
  mkdir -p ~/.ssh
  cat >> ~/.ssh/config << EOF

# ZTE U60 Pro
Host u60pro
    HostName $DEVICE_IP
    Port 22
    User $SSH_USER
    PreferredAuthentications password
    PubkeyAuthentication no
    StrictHostKeyChecking no
EOF
  success "SSH 客户端配置已写入 ~/.ssh/config"
else
  warn "~/.ssh/config 中已存在 u60pro 配置，跳过"
fi

# 清理
cd / && rm -rf "$WORK_DIR"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   安装完成！                             ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  连接命令：ssh u60pro"
echo "  用户名：  $SSH_USER"
echo "  密码：    $SSH_PASS"
echo "  地址：    $DEVICE_IP:22"
echo ""
