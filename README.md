# V2Ray 一键部署脚本

一键部署 V2Ray 代理服务的 Bash 脚本，支持 10 种协议组合，自动完成 Nginx 反代、TLS 证书申请、BBR 加速等全部配置。

基于 [梯子博客](https://tizi.blog/) 原版脚本，增加了小内存服务器稳定性增强。

## 目录

- [工作原理](#工作原理)
- [支持的协议](#支持的协议)
- [快速开始](#快速开始)
- [使用方法](#使用方法)
- [安装流程详解](#安装流程详解)
- [稳定性增强](#稳定性增强)
- [CDN 中转](#cdn-中转cloudflare)
- [最佳实践](#最佳实践)
- [故障排查](#故障排查)
- [关键文件路径](#关键文件路径)

---

## 工作原理

### 核心架构

需要 TLS 的协议（选项 3-10）采用 Nginx 反向代理架构：

```
客户端 ──TLS──▶ Nginx (:443) ──WS/TCP──▶ V2Ray (本地端口) ──▶ 目标网站
                    │
                    └──▶ 伪装网站（反代小说站）
```

不需要 TLS 的协议（选项 1、2、5）V2Ray 直接监听端口，无需 Nginx。

### 各组件职责

| 组件 | 职责 |
|------|------|
| **Nginx** | TLS 终止、WebSocket 反向代理、伪装网站 |
| **V2Ray** | 代理协议处理（VMess/VLESS/Trojan） |
| **acme.sh** | Let's Encrypt 证书自动申请与续签 |
| **BBR** | TCP 拥塞控制算法，提升传输速度 |

### 为什么难以被识别？

1. 外部只能看到标准 HTTPS 流量，指向一个正常网站
2. 代理数据藏在特定的 WebSocket 路径中
3. 直接访问域名会看到一个小说网站（反代伪装）
4. TLS 证书是正规 Let's Encrypt 签发，和普通网站无异

---

## 支持的协议

| # | 协议组合 | 需域名 | 需 Nginx | 可过 CDN | 推荐度 |
|---|---------|:-----:|:-------:|:-------:|:-----:|
| 1 | VMess | - | - | - | ⭐ |
| 2 | VMess + mKCP | - | - | - | ⭐⭐ |
| 3 | VMess + TCP + TLS | ✅ | - | - | ⭐⭐ |
| 4 | VMess + WS + TLS | ✅ | ✅ | ✅ | ⭐⭐⭐⭐ |
| 5 | VLESS + mKCP | - | - | - | ⭐ |
| 6 | VLESS + TCP + TLS | ✅ | - | - | ⭐⭐⭐ |
| 7 | **VLESS + WS + TLS** | ✅ | ✅ | ✅ | ⭐⭐⭐⭐⭐ |
| 8 | VLESS + TCP + XTLS | ✅ | - | - | ⭐⭐⭐⭐ |
| 9 | Trojan | ✅ | - | - | ⭐⭐⭐⭐ |
| 10 | Trojan + XTLS | ✅ | - | - | ⭐⭐⭐⭐ |

### 协议对比

| 协议 | 加密方式 | 认证方式 | 特点 |
|------|---------|---------|------|
| **VMess** | 自带加密 + TLS（双重） | UUID | 生态最成熟，客户端支持最广 |
| **VLESS** | 仅依赖 TLS（无双重加密） | UUID | 更轻量，性能更好 |
| **Trojan** | 仅依赖 TLS | 密码 | 设计简洁，原生伪装为 HTTPS |

### 传输方式对比

| 传输 | 原理 | 优点 | 缺点 |
|------|------|------|------|
| **TCP** | 直接 TCP 连接 | 延迟低 | 不能过 CDN |
| **WebSocket** | HTTP 升级为 WS | 可过 CDN，伪装好 | 多一层封装开销 |
| **mKCP** | 基于 UDP 的 KCP | 抗丢包，不需域名 | UDP 可能被 QoS 限速 |
| **XTLS** | TLS 透传优化 | 性能最佳 | 已停止维护，不能过 CDN |

### 如何选择？

| 需求场景 | 推荐方案 |
|---------|---------|
| 长期稳定 + 可过 CDN | **7 (VLESS + WS + TLS)** |
| 客户端兼容性优先 | 4 (VMess + WS + TLS) |
| 极致性能 | 8 (VLESS + TCP + XTLS) |
| 简洁配置 + 密码认证 | 9 (Trojan) |
| 差网络 / 移动网络 | 2 (VMess + mKCP) |
| 没有域名（临时用） | 1 或 2 |

---

## 快速开始

### 前提条件

- 一台境外 VPS（Ubuntu 18+ / CentOS 7+ / Debian 9+）
- root 权限
- 需要 TLS 时：一个域名，A 记录已指向服务器 IP

### 一键安装

```bash
# 上传脚本到服务器
scp setup.sh root@your-server:~/

# 执行
chmod +x setup.sh
sudo bash setup.sh
```

按菜单选择协议编号，跟随提示输入域名、端口等信息，脚本自动完成全部部署。

---

## 使用方法

### 交互式菜单

直接运行 `sudo bash setup.sh` 会显示菜单：

```
  1.  安装V2ray-VMESS
  2.  安装V2ray-VMESS+mKCP
  3.  安装V2ray-VMESS+TCP+TLS
  4.  安装V2ray-VMESS+WS+TLS (推荐)
  5.  安装V2ray-VLESS+mKCP
  6.  安装V2ray-VLESS+TCP+TLS
  7.  安装V2ray-VLESS+WS+TLS (可过cdn)
  8.  安装V2ray-VLESS+TCP+XTLS (推荐)
  9.  安装trojan (推荐)
  10. 安装trojan+XTLS (推荐)
  11. 更新V2ray
  12. 卸载V2ray
  13. 启动V2ray        14. 重启V2ray
  15. 停止V2ray        16. 查看V2ray配置
  17. 查看V2ray日志
```

### 命令行模式

```bash
sudo bash setup.sh start       # 启动
sudo bash setup.sh stop        # 停止
sudo bash setup.sh restart     # 重启
sudo bash setup.sh showInfo    # 查看配置和连接信息
sudo bash setup.sh showLog     # 查看运行日志
sudo bash setup.sh update      # 更新 V2Ray
sudo bash setup.sh uninstall   # 卸载
```

---

## 安装流程详解

选择协议后，脚本依次执行：

```
收集信息 → 安装依赖 → 安装 Nginx → 配置防火墙 → 申请证书
    → 配置 Nginx → 安装 V2Ray → 生成配置 → 安装 BBR → 启动服务
```

| 步骤 | 说明 |
|------|------|
| 收集信息 | 交互输入域名、端口、密码/UUID、WS 路径等 |
| 安装依赖 | wget、vim、unzip、openssl、gcc 等 |
| 安装 Nginx | 仅 WS/TLS 需要，支持宝塔环境 |
| 配置防火墙 | 自动适配 firewalld / iptables / ufw |
| 申请证书 | acme.sh 申请 Let's Encrypt ECC 证书 |
| 配置 Nginx | TLS 终止 + WebSocket 反代 + 伪装站点 |
| 安装 V2Ray | 下载 v2fly v4.33.0，注册 systemd 服务 |
| 生成配置 | 根据协议写入 `/etc/v2ray/config.json` |
| 安装 BBR | 可选，TCP BBR 拥塞控制加速 |

---

## 稳定性增强

针对小内存 VPS（< 1GB RAM）的可靠性改进，解决原版脚本在低配服务器上的稳定性问题：

### 1. 自动创建 Swap

**问题**：小内存机器运行 Nginx + V2Ray 容易 OOM，尤其在证书续签时。

**方案**：检测内存 < 1GB 时自动创建 1GB swap 文件。

### 2. Nginx Watchdog

**问题**：acme.sh 证书续签会 stop Nginx，如果 restart 失败（内存不足），Nginx 就一直停着。

**方案**：cron 每 5 分钟检测，未运行则自动拉起：

```cron
*/5 * * * * systemctl is-active --quiet nginx || systemctl start nginx
```

### 3. V2Ray 服务自愈

**问题**：V2Ray 偶尔崩溃后不会自动恢复。

**方案**：systemd 配置 `Restart=always` + `RestartSec=5s`。

### 4. 证书续签修复

**问题**：acme.sh PostHook 用 `restart`（= stop + start），小内存 stop 后 start 可能因内存不足失败。

**方案**：PostHook 改为 `start`，仅在未运行时启动，更安全。

---

## CDN 中转（Cloudflare）

WS + TLS 方案（选项 4、7）支持通过 Cloudflare CDN 中转。**平时直连，IP 被墙时启用 CDN 应急恢复。**

### 工作方式

```
直连：客户端 ──────────────────▶ 服务器 ──▶ V2Ray
CDN： 客户端 ──▶ Cloudflare ──▶ 服务器 ──▶ V2Ray
```

### IP 被墙的恢复策略

| 方式 | 操作 | 性能影响 |
|------|------|---------|
| **换 IP（首选）** | 云厂商后台换 IP → 更新 DNS | 无损 |
| 套 CDN（备用） | Cloudflare 云朵点橙色 | 延迟 +20-100ms，速度 -10%~50% |

### Cloudflare 配置

1. 注册 [Cloudflare](https://cloudflare.com)，添加域名
2. 修改域名 NS 为 Cloudflare 分配的地址
3. 添加 A 记录指向服务器 IP，云朵设为**灰色**（DNS only = 直连）
4. SSL/TLS 模式选 **Full (Strict)**
5. 需要 CDN 时，将云朵点为**橙色**（Proxied）

### 优选 IP（可选）

CDN 速度慢时，可用 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 筛选最快的 Cloudflare 节点 IP，在客户端替换连接地址（域名填在 SNI/Host）。

---

## 最佳实践

### 服务器选择

- 内存 ≥ 512MB（脚本会自动补 swap，但原生内存越大越稳定）
- 推荐 Ubuntu 20.04+
- 80、443 端口未被占用

### 域名配置

- A 记录**先解析再安装**，否则证书申请会失败
- 如需 CDN 中转，选 WS + TLS 组合

### 安全建议

- 始终通过 Nginx 反代，不要将 V2Ray 端口直接暴露公网
- 定期更新：`sudo bash setup.sh update`
- 证书由 acme.sh 自动续签，无需手动干预

### 自有证书

将 `v2ray.pem` 和 `v2ray.key` 放到服务器 `~/` 目录下，脚本会自动检测并使用，跳过 acme.sh 证书申请。

---

## 故障排查

```bash
# 服务状态
systemctl status v2ray nginx

# V2Ray 日志
journalctl -u v2ray -n 50

# Nginx 日志
journalctl -u nginx -n 50
tail -f /var/log/nginx/error.log

# 端口检查
ss -tlnp | grep -E '443|80'

# 证书有效期
~/.acme.sh/acme.sh --list
```

| 现象 | 可能原因 | 解决方法 |
|------|---------|---------|
| Nginx 反复停止 | 内存不足 + 证书续签 restart 失败 | 检查 swap 是否创建，watchdog cron 是否存在 |
| 证书申请失败 | 域名未解析 / 80 端口被占 | 确认 DNS 解析，`ss -tlnp \| grep :80` |
| V2Ray 启动失败 | 配置文件语法错误 | `journalctl -u v2ray -n 20` 查看具体报错 |
| 客户端连不上 | 防火墙未放行 / 端口错误 | 检查 `ufw status` 或 `iptables -nL` |

---

## 关键文件路径

| 文件 | 路径 |
|------|------|
| V2Ray 配置 | `/etc/v2ray/config.json` |
| V2Ray 程序 | `/usr/bin/v2ray/v2ray` |
| V2Ray 服务 | `/etc/systemd/system/v2ray.service` |
| Nginx 站点配置 | `/etc/nginx/conf.d/<域名>.conf` |
| TLS 证书 | `/etc/v2ray/<域名>.pem` |
| TLS 私钥 | `/etc/v2ray/<域名>.key` |
| acme.sh | `/root/.acme.sh/` |

---

## 致谢

原版脚本来自 [梯子博客](https://tizi.blog/)，本仓库在其基础上进行了稳定性增强。
