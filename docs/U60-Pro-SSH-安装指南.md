# ZTE U60 Pro — SSH 安装指南

> **适用设备**：ZTE U60 Pro 4G 路由器  
> **系统**：OpenWrt 23.05.4 定制版（aarch64）  
> **难度**：⭐⭐☆☆☆

---

## 🚀 快速开始（推荐）

如果你只是想快速搞定，直接用一键脚本：

### 前提条件
- 设备已通过 USB 连接电脑，ADB 调试已开启
- 电脑已安装 `adb`（[下载地址]()）

### 一键安装

```bash
bash ~/u60-ssh-install.sh [用户名] [密码]

# 示例：
bash ~/u60-ssh-install.sh scoltc 86558781
```

安装完成后直接连接：

```bash
ssh u60pro
# 输入密码即可登录
```

---

## 📦 脚本说明

| 脚本 | 用途 |
|------|------|
| `~/u60-ssh-install.sh` | **首次安装**：下载、配置、一键完成全部步骤 |
| `~/u60-ssh-start.sh` | **重新启动**：设备已安装，SSH 挂了时手动拉起 |
| `~/u60-ssh-addkey.sh` | **添加公钥**：配置免密码登录 |

---

## 💻 SSH 客户端配置

安装脚本会自动写入 `~/.ssh/config`，之后直接用：

```bash
ssh u60pro          # 密码登录
```

> ⚠️ **注意**：必须用 `ssh u60pro` 这种别名形式，直接用 `ssh scoltc@192.168.0.1` 会忽略配置文件，导致反复询问密钥密码。

如需手动写入配置：

```bash
cat >> ~/.ssh/config << 'EOF'

Host u60pro
    HostName 192.168.0.1
    Port 22
    User scoltc
    PreferredAuthentications password
    PubkeyAuthentication no
    StrictHostKeyChecking no
EOF
```

---

## 🔑 登录方式

### 密码登录（默认）

```bash
ssh u60pro
# 密码: 86558781
```

任何电脑都能直接用，无需额外配置。

### 公钥登录（免密码）

如果不想每次输密码，用脚本添加公钥：

```bash
bash ~/u60-ssh-addkey.sh ~/.ssh/id_rsa.pub
```

之后登录无需输入任何密码：

```bash
ssh -i ~/.ssh/id_rsa u60pro
```

> 如果你的私钥本身有密码保护，推荐用 `ssh-agent` 管理：
> ```bash
> ssh-add ~/.ssh/id_rsa   # 只需输入一次密钥密码
> ssh u60pro              # 之后不再询问
> ```

---

## 🐛 故障排查

### SSH 连不上

```bash
# 1. 检查 SSH 服务是否在运行
adb shell "ps | grep dropbear | grep -v grep"

# 2. 不在运行？手动拉起
bash ~/u60-ssh-start.sh

# 3. 还不行？查看端口
adb shell "cat /proc/net/tcp | awk '{print \$2}' | grep -i '0016'"
# 有输出 = 端口已监听
```

### 重启后 SSH 失效

设备首次开机后 SSH 服务会自动启动（约 10 秒），如果没有：

```bash
# 连接 ADB 后手动启动
adb shell "sh /overlay/dropbear/start_ssh.sh"
```

### 密码被拒绝

```bash
# 重置密码（将 86558781 改成你想要的）
adb shell "
  HASH=\$(openssl passwd -1 '86558781')
  grep -v '^scoltc:' /etc/shadow > /tmp/s.tmp
  echo \"scoltc:\$HASH:20544:0:99999:7:::\" >> /tmp/s.tmp
  cp /tmp/s.tmp /etc/shadow
"
```

---

## 📋 连接信息速查

| 项目 | 值 |
|------|-----|
| 连接命令 | `ssh u60pro` |
| 地址 | `192.168.0.1:22` |
| 用户名 | `scoltc` |
| 密码 | `86558781` |

---

## 🔧 技术背景（可选阅读）

<details>
<summary>为什么不能直接用 OpenSSH？</summary>

设备固件使用 **mbedTLS** 加密库，而标准 OpenSSH 二进制依赖 **OpenSSL**，两者不兼容。

尝试过但失败的方案：

| 方案 | 失败原因 |
|------|---------|
| 原装 OpenSSH | 依赖 libcrypto.so.3（OpenSSL），设备没有 |
| Android 版 dropbear | 依赖 Bionic linker，设备是 musl |
| Alpine dropbear v2024 | 依赖 libutmps → libskarnet 链 |
| **Alpine dropbear v2020.81** | ✅ 只依赖 libz.so.1，设备有 |

</details>

<details>
<summary>设备文件系统结构</summary>

```
/dev/root   → SquashFS（只读，系统基础文件）
/overlay    → 可写分区（~3.8MB）  ← noexec 挂载，不能直接执行二进制
/zteoverlay → 大数据分区（~94MB）
/tmp        → 内存盘（重启清空）  ← 二进制必须放这里运行
```

**关键限制**：
- `/overlay` 有 `noexec`，脚本不能直接执行，rc.local 里必须写 `sh /overlay/.../start_ssh.sh`
- `/overlay` 的 `chown` 不生效，用户家目录必须在 `/tmp` 里创建
- `/tmp` 重启后清空，所以每次开机都要重新复制二进制文件

</details>

<details>
<summary>开机启动原理</summary>

```
设备开机
  └→ rc.local 执行
       └→ sh /overlay/dropbear/start_ssh.sh
            ├─ 复制 dropbear 到 /tmp
            ├─ 复制 host keys 到 /tmp/etc/ssh/
            ├─ 在 /tmp 创建用户 home 目录
            └─ 后台启动 dropbear（括号防止被 procd SIGTERM）
```

**为什么要用括号 `(command &)` 而不是 `command &`？**

OpenWrt 使用 procd 作为 init 系统，它会向子进程发送 SIGTERM 信号。用括号创建子 shell 后再后台运行，可以让进程脱离 procd 的进程组管理。

</details>

---

## 📚 参考链接

- [Dropbear 官方文档]()
- [Alpine Linux 软件包]()
- [OpenWrt 官方文档]()

---

*最后更新：2026-04-01*
