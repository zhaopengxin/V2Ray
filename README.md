# Sing-box (Hysteria2) 一键部署

Sing-box + Hysteria2 一键部署脚本，单进程、零证书、UDP/443 直连。

## 部署架构

```
客户端 → Hysteria2 over UDP/443 (QUIC + TLS) → sing-box → 出站
```

跟传统 v2ray + nginx + acme 比：
- 故障面从 4 个组件 → 1 个进程
- 不再需要域名 / 证书续签
- 单连吞吐 ~500-1000 Mbps（QUIC + BBR）

---

## 仓库文件说明

| 文件 | 用途 |
|---|---|
| `deploy.sh` | 主脚本，全新部署 / 管理服务 |
| `cloud-init-vpn.yaml` | Azure 新建 VM 时传入 `--custom-data`，开机自动部署，无需登录 |
| `sr_top500_banlist.conf` | 可选黑名单，供 Clash 等客户端导入 |
| `clash-config.yaml` | Clash 客户端配置（含密码，已加入 .gitignore，不提交） |
| `setup.sh` | 旧版 v2ray + nginx 脚本（已弃用，保留备查） |

---

## 方式一：手动部署（单台机器）

### 全新机器一键部署

```bash
chmod +x deploy.sh
sudo bash deploy.sh
```

完成后输出客户端链接：

```
hysteria2://<password>@<ip>:443/?sni=www.bing.com&insecure=1#hy2-<ip>
```

链接会保存到 `/root/sing-box-client.txt`；如果从 git clone 的项目目录执行，也会复制一份到 `deploy.sh` 同目录下的 `sing-box-client.txt`。

粘贴到 Clash Verge Rev / Shadowrocket / V2rayN 即可。

### 自定义参数

```bash
PORT=8443 SNI=www.apple.com sudo bash deploy.sh
```

### 子命令

```bash
sudo bash deploy.sh doctor   # 健康检查（服务/端口/连接/内存/OOM）
sudo bash deploy.sh info     # 显示客户端链接
sudo bash deploy.sh update   # 升级 sing-box 到最新版
```

---

## 方式二：Azure 新建 VM 自动部署（cloud-init）

`cloud-init-vpn.yaml` 会在 VM 首次开机时自动 `git clone` 并执行 `deploy.sh install`，全程无人值守。

### 新建 VM 命令

```bash
az vm create \
  --resource-group vpn \
  --name vpn-xxx \
  --location japaneast \
  --image Ubuntu2404 \
  --size Standard_B2s_v2 \
  --admin-username zhaopengxin \
  --ssh-key-values ~/.ssh/id_ed25519.pub \
  --custom-data D:/ai/V2Ray/cloud-init-vpn.yaml \
  --public-ip-sku Standard \
  --nsg-rule SSH
```

### 开放 UDP/443

```bash
az network nsg rule create -g vpn --nsg-name vpn-xxxNSG \
  --name Allow-UDP-443 --priority 1010 --protocol Udp \
  --destination-port-ranges 443 --access Allow --direction Inbound
```

### 查看部署日志

```bash
ssh zhaopengxin@<ip> "tail -f /root/bootstrap.log"
```

部署完成后客户端链接存放在 `/home/zhaopengxin/sing-box-client.txt`。

---

## 脚本做了什么

| 步骤 | 说明 |
|---|---|
| 装 sing-box | 多源下载兜底（GitHub / ghproxy） |
| 创建 swap | 内存 < 2G 自动建 1G swap，`swappiness=10` |
| 内核调优 | BBR + FQ + TCP Fast Open=3 + 扩大读写缓冲 |
| 自签证书 | CN=$SNI，100 年有效期，无需续签 |
| 写配置 | Hysteria2 + 随机密码 + ALPN=h3 |
| setcap | 允许非 root 绑定 :443 |
| NOPASSWD sudo | 当前 SSH 用户免密 sudo |
| systemd 自启 | enable + restart 自动恢复 |
| 自动更新 | 每日同步脚本、每周检查 sing-box 新版本，并安装系统安全补丁 |

---

## 自动更新与错峰

安装时按主机名和 `/etc/machine-id` 的 SHA-256 哈希生成更新计划，写入 `/etc/cron.d/singbox-auto-update`，时间为 UTC。不使用内网 IP，因为不同虚拟网络中的节点可能使用相同的内网 IP。哈希分配用于分散时间，主备节点仍应核对计划，明确错开升级窗口。

已有节点的 cron 不会随脚本日更自动重新生成；调整计划时直接编辑该 cron 文件，cron 会自动重新读取，无需重启 sing-box，也不要为此重新执行 `install`。当前日本节点为周一 13:05、美国节点为周三 13:35，均为北京时间。

每日同步脚本不会重启 VPN；每周仅在 sing-box 有新版本时升级并重启。Ubuntu 自动安全补丁由系统自己的计划任务控制，不受上述 sing-box 升级时间控制。

---

## 客户端

| 平台 | 推荐客户端 |
|---|---|
| Windows | **Clash Verge Rev**（开源） |
| iOS | Shadowrocket（付费） |
| Android | sing-box 官方 / Karing |
| macOS | Clash Verge Rev |

`clash-config.yaml` 参考配置（本地文件，不在仓库中）：
- jp/us 双节点 + URL-Test 自动选最快
- OpenAI/Anthropic 流量强制走美国节点
- GeoSite-CN / GeoIP-CN 双判定，国内直连
- 节点 IP 直连（防环路）

---

## 防火墙提醒

部署后**云厂商安全组必须放行 UDP/$PORT 入站**，否则客户端无法连接。

---

## 历史

旧版基于 v2ray 4.33 + nginx + acme.sh 的 setup.sh 已弃用。原因：
- v2ray 4.33 (2020) 性能差、协议老
- nginx + 证书续签会因 OOM 在续签时挂掉，整夜不可用
- 多组件维护复杂

新版 sing-box 1.13 + Hysteria2，所有问题一并解决。
