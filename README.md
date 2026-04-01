[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![设备](https://img.shields.io/badge/设备-ZTE%20U60%20Pro-green.svg)](https://www.zte.com.cn)

# ZTE U60 Pro 高级后台面板

Advanced Web Panel for ZTE U60 Pro 4G 路由器 —— 基于 ubus JSON-RPC 的单文件 HTML 管理界面，运行在 8888 端口，提供比原生 WebUI 更丰富的控制功能。

**单文件 ~50KB，无外部依赖**，手机/电脑自适应，支持 5G SA/NSA 切换、频段锁定、流量统计、温控管理等功能。

---

## 功能特点

| 功能 | 说明 |
|------|------|
| 📡 网络信息 | 运营商、连接类型、频段、带宽、Cell ID |
| 📶 信号详情 | 每个 NR/LTE CA 载波的 RSRP/RSRQ/SINR/RSSI/PCI/BW/频点 |
| 📊 流量统计 | 实时速度、当月流量、总流量 |
| 🌐 WAN 状态 | IPv4/IPv6 地址、网关、DNS（双栈完整信息） |
| 💻 系统状态 | CPU 温度/负载、内存、运行时间 |
| 🌡️ 温控开关 | 设备过热自动降速控制（开启/关闭） |
| 📻 网络制式 | 5G SA / 5G NSA / 4G+3G / 仅4G / 仅3G 切换 |
| 🔒 4G 频段锁 | B1-B71 共 24 个频段，支持单频/组合/手动输入 |
| 🔒 5G 频段锁 | N1-N79 共 21 个频段 |
| 📍 小区锁定 | 5G/4G 小区锁定/解锁（PCI + ARFCN） |
| 📶 WiFi 设置 | 发射功率、国家码、最大连接数 |
| 📋 详细信息 | WiFi 参数、硬件/软件、SIM 卡、WMS 全部内联展示 |

**特性：** 单文件 HTML · 响应式布局 · 密码缓存 + Session 自动续期 · 持久化安装 · 纯 JS SHA256

---

## 快速开始

### 方式一：一键安装（推荐）

```bash
bash master_install.sh [SSH用户名] [SSH密码]
# 示例：bash master_install.sh advanced admin123456
```

> 脚本会自动串联 ADB 调试 → SSH 部署 → 高级面板安装三步。

**真正的单行命令（无需 clone，直接下载运行）：**

```bash
# curl 版
curl -fsSL https://github.com/scoltzero/U60PRO_WEBUI/archive/refs/heads/main.tar.gz | tar xz && cd U60PRO_WEBUI-main && bash master_install.sh advanced admin123456

# wget 版
wget -qO- https://github.com/scoltzero/U60PRO_WEBUI/archive/refs/heads/main.tar.gz | tar xz && cd U60PRO_WEBUI-main && bash master_install.sh advanced admin123456
```

> 适用于临时使用或快速体验，正式维护建议 `git clone` 克隆本地。

### 方式二：分步执行

**步骤 1 — 启用 ADB 调试**

```bash
# 确保设备屏幕处于解锁状态
python3 scripts/adb/zte_u60_adb.py
```

**步骤 2 — 安装 SSH 服务**

```bash
bash scripts/ssh/install.sh [用户名] [密码]
# 示例：bash scripts/ssh/install.sh advanced admin123456
```

**步骤 3 — 安装高级后台面板**

```bash
bash scripts/web-panel/install.sh
```

安装完成后访问：**http://192.168.0.1:8888**

---

## 前提条件

- 设备已通过 USB 连接电脑，屏幕处于**解锁状态**
- 电脑已安装 `adb`（`brew install android-platform-tools`）
- 电脑已安装 Python 3 和 OpenSSL（macOS 自带）

---

## 项目结构

```
u60pro/
├── master_install.sh           # 一键安装串联脚本
├── README.md                   # 本文件
├── 高级后台安装教程.md         # 面板详细安装指南
├── LICENSE                     # MIT License
├── scripts/
│   ├── adb/
│   │   └── zte_u60_adb.py      # ADB 调试启用脚本
│   ├── ssh/
│   │   ├── install.sh          # SSH 完整安装脚本
│   │   ├── start.sh            # SSH 服务重启脚本
│   │   └── addkey.sh           # 公钥添加脚本
│   └── web-panel/
│       ├── install.sh          # 面板安装脚本
│       └── index.html          # 面板本体（单文件）
└── docs/
    ├── U60-Pro-SSH-安装指南.md     # SSH 快速安装指南
    └── U60-Pro-SSH-详细安装指南.md # SSH 完整技术文档
```

---

## 技术架构

```
浏览器
  └─→ http://192.168.0.1:8888
        └─→ uhttpd (radio 用户, :8888)
              └─→ /ubus/ 端点
                    └─→ ubus JSON-RPC
                          └─→ 路由器内部服务 (zwrt_*/zte_*)
```

**端口说明：** 使用 **8888** 而非常见的 6666，因为 Chrome/Firefox/Safari 会将 6666 列为不安全端口并拒绝连接。

**持久化：** 面板文件存于 `/overlay/home/scoltc/web-panel/`，二进制运行文件存于 `/overlay/dropbear/`，均不受重启影响。

---

## API 清单

面板通过 ubus JSON-RPC 调用设备服务：

| 功能 | ubus service | method |
|------|-------------|--------|
| 登录获取 salt | `zwrt_web` | `web_login_info` |
| 登录 | `zwrt_web` | `web_login` |
| 网络信息 | `zte_nwinfo_api` | `nwinfo_get_netinfo` |
| CPU 温度 | `zwrt_bsp.thermal` | `get_cpu_temp` |
| 温控开关 | `zwrt_bsp.thermal` | `get_policy` / `set_policy` |
| 设备信息 | `zwrt_mc.device.manager` | `get_device_info` |
| WAN 状态 | `zwrt_router.api` | `router_get_status` |
| 流量统计 | `zwrt_data` | `get_wwandst` |
| 制式切换 | `zte_nwinfo_api` | `nwinfo_set_netselect` |
| 4G 锁频 | `zte_nwinfo_api` | `nwinfo_set_gwl_bandlock` |
| 5G 锁频 | `zte_nwinfo_api` | `nwinfo_set_nrbandlock` |
| 4G 锁小区 | `zte_nwinfo_api` | `nwinfo_lock_lte_cell` |
| 5G 锁小区 | `zte_nwinfo_api` | `nwinfo_lock_nr_cell` |
| WiFi 配置 | `uci` / `zwrt_wlan` | `get` / `set` |
| SIM 信息 | `zwrt_zte_mdm.api` | `get_sim_info` |
| WMS 信息 | `zwrt_wms` | `zwrt_wms_get_wms_capacity` |

---

## 已知限制

- **`/overlay` 文件系统有 `noexec` 限制**：二进制文件必须复制到 `/tmp` 后执行，开机启动脚本在 rc.local 中必须用 `sh` 调用而非直接执行路径。
- **设备使用 mbedTLS 而非 OpenSSL**：标准 OpenSSH 二进制不兼容，本项目使用 Alpine Linux Dropbear v2020.81（仅依赖 libz.so.1）。
- **`/overlay` 的 `chown` 不生效**：用户 home 目录必须在 `/tmp` 下创建，启动脚本会自动处理。
- **ADB 调试需要屏幕解锁**：zte_u60_adb.py 通过 WebUI API 启用调试，设备屏幕必须处于解锁状态。

---

## 开源许可

本项目基于 **MIT License** 开源。

---

## 致谢

- [ZTE-Script-NG](https://github.com/tpoechtrager/ZTE-Web-Script) by Thomas Pöchtrager — ubus API 的发现与原始脚本，本项目面板的 API 调用即基于此提取重构。
