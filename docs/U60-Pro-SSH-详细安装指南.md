# ZTE U60 Pro — SSH（mbedTLS 兼容版）详细安装指南

> 适用设备：ZTE U60 Pro 4G 调制解调器路由器  
> 系统：OpenWrt 23.05.4 定制版  
> 架构：ARM aarch64（MediaTek d05 双核）  
> 问题根源：设备使用 **mbedTLS** 而非 OpenSSL，标准 OpenSSH 二进制不兼容

---

## 📋 前提条件

- 设备已开启 ADB 调试
- 电脑已安装 `adb` 工具
- 电脑已安装 SSH 客户端（macOS/Linux 自带）

---

## 🔍 问题说明

设备预装的 OpenSSH 二进制文件（位于 `/overlay`）是为 **OpenSSL** 编译的，但 ZTE 固件使用的是 **mbedTLS** 库。两者不兼容，导致 sshd 无法运行。

**mbedTLS vs OpenSSL**：

| 特性 | mbedTLS | OpenSSL |
|------|---------|---------|
| 大小 | <1MB | 10-20MB |
| 许可 | Apache 2.0 | Apache + SSLeay |
| 设计目标 | 嵌入式优化 | 通用 |

---

## ✅ 解决方案：Alpine Linux Dropbear

**为什么选 Dropbear v2020.81？**

测试过的方案：

- ❌ OpenSSH（需要 OpenSSL，设备只有 mbedTLS）
- ❌ Android dropbear（二进制需要 Bionic linker，与 musl 不兼容）
- ❌ Alpine dropbear v2024.86（需要 libutmps→libskarnet 依赖链）
- ✅ **Alpine dropbear v2020.81（仅依赖 libz.so.1）**

---

## 📦 安装步骤

### 第一步：连接设备

```bash
# 确认 ADB 连接
adb devices

# 通过 USB 连接
adb shell
```

或通过网络连接（如果已配置网络 ADB）：

```bash
adb tcpip 5555
adb connect 192.168.0.1
adb shell
```

---

### 第二步：下载 Dropbear 二进制

**在电脑上执行：**

```bash
cd /tmp
mkdir -p u60-pro-ssh && cd u60-pro-ssh

# 下载 Alpine Linux v3.15 的 Dropbear v2020.81（aarch64 musl）
curl -L -o dropbear-2020.81.apk \
  "https://dl-cdn.alpinelinux.org/alpine/v3.15/main/aarch64/dropbear-2020.81-r0.apk"

# 解压 APK（APK 本质是 tar.gz）
tar -xzf dropbear-2020.81.apk
ls -la usr/sbin/
```

**输出应包含：**

```
dropbear
dropbearkey
dbclient
dropbearconvert
```

---

### 第三步：上传到设备

```bash
# 上传二进制文件到 /tmp
adb push usr/sbin/dropbear /tmp/dropbear
adb push usr/sbin/dropbearkey /tmp/dropbearkey
```

**检查依赖（确认只需要 libz）：**

```bash
adb shell "ldd /tmp/dropbear"
```

**正确输出：**

```
libz.so.1 => /lib/libz.so.1
libc.musl-aarch64.so.1 => /lib/ld-musl-aarch64.so.1
```

---

### 第四步：生成 Host Keys

```bash
adb shell "
mkdir -p /tmp/etc/ssh
cp /tmp/dropbear /tmp/dropbearkey_bin
chmod 755 /tmp/dropbearkey_bin

LD_LIBRARY_PATH=/tmp /tmp/dropbearkey_bin -t rsa    -f /tmp/etc/ssh/ssh_host_rsa_key
LD_LIBRARY_PATH=/tmp /tmp/dropbearkey_bin -t ecdsa  -f /tmp/etc/ssh/ssh_host_ecdsa_key
LD_LIBRARY_PATH=/tmp /tmp/dropbearkey_bin -t ed25519 -f /tmp/etc/ssh/ssh_host_ed25519_key
chmod 600 /tmp/etc/ssh/ssh_host_*
"
```

---

### 第五步：创建用户并设置密码

**创建用户：**

```bash
adb shell "
# 写入 passwd
echo 'scoltc:x:1001:1001:scoltc:/overlay/home/scoltc:/bin/ash' >> /etc/passwd
echo 'scoltc:!:20544:0:99999:7:::' >> /etc/shadow

# 创建家目录
mkdir -p /overlay/home/scoltc/.ssh
chmod 700 /overlay/home/scoltc/.ssh
"
```

**设置密码：**

```bash
adb shell "
PASSWORD='86558781'
HASH=\$(openssl passwd -1 \"\$PASSWORD\")
grep -v '^scoltc:' /etc/shadow > /tmp/shadow.tmp
echo \"scoltc:\$HASH:20544:0:99999:7:::\" >> /tmp/shadow.tmp
cp /tmp/shadow.tmp /etc/shadow
"
```

---

### 第六步：（可选）配置公钥认证

如果需要公钥认证（免密码），添加公钥：

```bash
# 生成无密码密钥（推荐，避免输入密钥密码）
ssh-keygen -t rsa -f ~/.ssh/id_rsa_u60 -N ""

# 上传公钥到设备
PUBKEY=$(cat ~/.ssh/id_rsa_u60.pub)
adb shell "echo '$PUBKEY' >> /overlay/home/scoltc/.ssh/authorized_keys"
```

---

### 第七步：持久化配置（重启后保留）

```bash
# 创建持久化目录
adb shell "mkdir -p /overlay/dropbear"

# 复制二进制和 host keys 到持久化存储
adb shell "
cp /tmp/dropbear /overlay/dropbear/dropbear2020
cp /tmp/dropbearkey /overlay/dropbear/dropbearkey2020
cp /lib/libz.so.1 /overlay/dropbear/libz.so.1 2>/dev/null || true
cp /tmp/etc/ssh/ssh_host_* /overlay/dropbear/
chmod 755 /overlay/dropbear/dropbear2020
chmod 600 /overlay/dropbear/ssh_host_*
"
```

---

### 第八步：创建开机启动脚本

```bash
adb shell "cat > /overlay/dropbear/start_ssh.sh << 'SCRIPT'
#!/bin/sh
# 防止 procd/init 系统用 SIGTERM 杀掉进程
trap '' SIGTERM

# 复制二进制到 /tmp（/overlay 有 noexec 限制，必须在 /tmp 执行）
cp /overlay/dropbear/dropbear2020 /tmp/dropbear
cp /overlay/dropbear/libz.so.1 /tmp/libz.so.1 2>/dev/null || true
chmod 755 /tmp/dropbear

# 复制 host keys
mkdir -p /tmp/etc/ssh
cp /overlay/dropbear/ssh_host_* /tmp/etc/ssh/
chmod 600 /tmp/etc/ssh/ssh_host_*

# 解决 overlay 文件系统 chown 限制
# /overlay 的 chown 不生效，必须在 /tmp 下创建用户目录
mkdir -p /tmp/home/scoltc/.ssh
chmod 701 /tmp/home/scoltc
chmod 700 /tmp/home/scoltc/.ssh
if [ -f /overlay/home/scoltc/.ssh/authorized_keys ]; then
    cp /overlay/home/scoltc/.ssh/authorized_keys /tmp/home/scoltc/.ssh/
    chmod 644 /tmp/home/scoltc/.ssh/authorized_keys
fi

# 修正 passwd 中 home 路径（指向 /tmp 下的目录）
grep -v '^scoltc:' /etc/passwd > /tmp/passwd.tmp
echo 'scoltc:x:1001:1001:scoltc:/tmp/home/scoltc:/bin/ash' >> /tmp/passwd.tmp
cp /tmp/passwd.tmp /etc/passwd

# 使用括号后台运行，防止被 procd 的 SIGTERM 杀掉
(LD_LIBRARY_PATH=/tmp /tmp/dropbear \
    -r /tmp/etc/ssh/ssh_host_rsa_key \
    -r /tmp/etc/ssh/ssh_host_ecdsa_key \
    -r /tmp/etc/ssh/ssh_host_ed25519_key \
    -p 22 &)
SCRIPT

chmod 755 /overlay/dropbear/start_ssh.sh"
```

---

### 第九步：配置开机自启

```bash
adb shell "
# 关键：必须用 sh 调用，因为 /overlay 有 noexec 限制，无法直接执行脚本
# 错误写法：/overlay/dropbear/start_ssh.sh &
# 正确写法：sh /overlay/dropbear/start_ssh.sh &

# 移除旧条目
grep -v 'start_ssh\|dropbear' /etc/rc.local > /tmp/rc.tmp
sed -i 's|exit 0|sh /overlay/dropbear/start_ssh.sh \&\nexit 0|' /tmp/rc.tmp
cp /tmp/rc.tmp /etc/rc.local
"
```

---

### 第十步：首次启动并测试

```bash
# 首次手动启动
adb shell "sh /overlay/dropbear/start_ssh.sh"

# 验证服务在运行
adb shell "ps | grep dropbear | grep -v grep"
```

---

## 💻 SSH 客户端配置

在 `~/.ssh/config` 中添加配置，避免每次被追问密钥密码：

```bash
cat >> ~/.ssh/config << 'EOF'

# ZTE U60 Pro
Host u60pro
    HostName 192.168.0.1
    Port 22
    User scoltc
    PreferredAuthentications password
    PubkeyAuthentication no
    StrictHostKeyChecking no
EOF
```

> ⚠️ **注意**：必须用 `ssh u60pro` 这种别名连接，直接用 `ssh scoltc@192.168.0.1` 会忽略上述配置。

**连接命令：**

```bash
ssh u60pro          # 密码登录
```

**参数说明：**

| 参数 | 含义 |
|------|------|
| `PreferredAuthentications password` | 只用密码认证，不先尝试密钥 |
| `PubkeyAuthentication no` | 完全禁用公钥认证 |
| `StrictHostKeyChecking no` | 首次连接不验证 host key |

---

## 🔑 登录认证方式

### 密码登录（推荐）

```bash
ssh u60pro
# 密码: 86558781
```

**重置密码：**

```bash
adb shell "
HASH=\$(openssl passwd -1 '你的新密码')
grep -v '^scoltc:' /etc/shadow > /tmp/s.tmp
echo \"scoltc:\$HASH:20544:0:99999:7:::\" >> /tmp/s.tmp
cp /tmp/s.tmp /etc/shadow
"
```

### 公钥登录（免密码）

**1. 生成无密码密钥：**

```bash
ssh-keygen -t rsa -f ~/.ssh/id_rsa_u60 -N ""
```

**2. 上传公钥：**

```bash
bash ~/u60-ssh-addkey.sh ~/.ssh/id_rsa_u60.pub
```

**3. 连接：**

```bash
ssh -i ~/.ssh/id_rsa_u60 u60pro
```

**使用 ssh-agent（私钥有密码时）：**

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa   # 只输入一次密钥密码
ssh u60pro              # 之后不再询问
```

---

## 🔧 关键技术要点

### 1. 解决 overlay 文件系统 chown 限制

**问题**：`/overlay` 挂载时有 `noexec` 限制，且 chown 操作不生效

**解决**：在 `/tmp`（内存盘）中创建用户目录

```bash
mkdir -p /tmp/home/scoltc/.ssh
chmod 701 /tmp/home/scoltc       # 允许其他用户进入目录
chmod 700 /tmp/home/scoltc/.ssh  # 只有所有者可读写
chmod 644 /tmp/home/scoltc/.ssh/authorized_keys  # 全局可读

# 修改 passwd 让用户 home 指向 /tmp
grep -v '^scoltc:' /etc/passwd > /tmp/p.tmp
echo 'scoltc:x:1001:1001:scoltc:/tmp/home/scoltc:/bin/ash' >> /tmp/p.tmp
cp /tmp/p.tmp /etc/passwd
```

### 2. 防止 procd 杀掉 dropbear 进程

**问题**：OpenWrt 使用 procd 管理进程，会向不受管理的进程发送 SIGTERM

**解决**：

```bash
trap '' SIGTERM          # 忽略 SIGTERM 信号
(command &)             # 括号创建子 shell，脱离 procd 进程组
```

### 3. rc.local 必须用 sh 调用脚本

**问题**：`/overlay` 有 noexec 挂载选项，内核拒绝直接执行其中的脚本

```bash
# ❌ 错误：内核直接执行脚本，被 noexec 拒绝
/overlay/dropbear/start_ssh.sh &

# ✅ 正确：用 sh 解释执行，绕过 noexec
sh /overlay/dropbear/start_ssh.sh &
```

---

## 📊 连接信息速查

| 项目 | 值 |
|------|-----|
| 连接命令 | `ssh u60pro` |
| 地址 | `192.168.0.1:22` |
| 用户名 | `scoltc` |
| 密码 | `86558781` |
| dropbear 二进制 | `/overlay/dropbear/dropbear2020` |
| host keys | `/overlay/dropbear/ssh_host_*` |
| 启动脚本 | `/overlay/dropbear/start_ssh.sh` |

---

## 🐛 常见问题

### Connection refused

```bash
adb shell "ps | grep dropbear | grep -v grep"   # 检查进程
adb shell "sh /overlay/dropbear/start_ssh.sh"   # 手动启动
```

### Permission denied (password)

```bash
# 重置密码
adb shell "
HASH=\$(openssl passwd -1 '86558781')
grep -v '^scoltc:' /etc/shadow > /tmp/s.tmp
echo \"scoltc:\$HASH:20544:0:99999:7:::\" >> /tmp/s.tmp
cp /tmp/s.tmp /etc/shadow
"
```

### 重启后 SSH 不自动启动

```bash
# 检查 rc.local 是否正确
adb shell "grep start_ssh /etc/rc.local"
# 应该输出：sh /overlay/dropbear/start_ssh.sh &

# 手动修复
adb shell "sed -i 's|/overlay/dropbear/start_ssh.sh|sh /overlay/dropbear/start_ssh.sh|' /etc/rc.local"
```

---

## 📝 设备技术信息

```
架构：ARM aarch64（MediaTek d05 双核）
内存：~1.6GB
基带：Qualcomm SDX75（5G/LTE）
系统：OpenWrt 23.05.4 定制版
加密库：mbedTLS（非 OpenSSL）
```

**文件系统结构：**

```
/dev/root     → SquashFS（只读）
/overlay      → 可写分区（~3.8MB）— noexec 挂载
/zteoverlay   → 大数据分区（~94MB）
/tmp          → 内存盘（重启清空）— 二进制在这里运行
```

---

## 📚 参考链接

- [Dropbear 官方网站](https://matt.ucc.asn.au/dropbear/dropbear.html)
- [Alpine Linux 包仓库](https://pkgs.alpinelinux.org/)
- [OpenWrt 官方文档](https://openwrt.org/docs/start)

---

*最后更新：2026-04-01*
