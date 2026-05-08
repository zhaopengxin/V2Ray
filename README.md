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

## 使用

### 全新机器一键部署

```bash
chmod +x deploy.sh
sudo bash deploy.sh
```

完成后输出客户端链接：

```
hysteria2://<password>@<ip>:443/?sni=www.bing.com&insecure=1#hy2-<ip>
```

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

## 客户端

| 平台 | 推荐 GUI |
|---|---|
| Windows | **Clash Verge Rev** （开源） |
| iOS | Shadowrocket（付费） |
| Android | sing-box 官方 / Karing |
| Mac | Clash Verge Rev |

参考 Clash YAML 配置见 `clash-config.yaml`：
- 4 节点 + URL-Test 自动选最快
- GeoSite-CN / GeoIP-CN 双判定，国内直连
- 自动广告拦截
- 节点 IP 直连（防环路）

## 防火墙提醒

部署后**云厂商安全组必须放行 UDP/$PORT 入站**。Azure CLI 示例：

```bash
az network nsg rule create \
  --resource-group <RG> --nsg-name <NSG> \
  --name Allow-UDP-443 --priority 1011 \
  --protocol Udp --destination-port-ranges 443 \
  --access Allow --direction Inbound
```

## 历史

旧版基于 v2ray 4.33 + nginx + acme.sh 的 setup.sh 已弃用。原因：
- v2ray 4.33 (2020) 性能差、协议老
- nginx + 证书续签会因 OOM 在续签时挂掉，整夜不可用
- 多组件维护复杂

新版 sing-box 1.13 + Hysteria2，所有问题一并解决。
