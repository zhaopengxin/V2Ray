# Sing-box (Hysteria2) 一键部署

## 简介

Sing-box + Hysteria2 一键部署脚本。新机器上传 `deploy.sh` 后 `sudo bash deploy.sh` 即可。

## 部署架构

```
客户端 → Hysteria2 over UDP/443 → sing-box → 出站
```

单进程、零证书、零域名。

## 用法

```bash
# 全新部署
sudo bash deploy.sh

# 体检
sudo bash deploy.sh doctor

# 显示客户端链接
sudo bash deploy.sh info

# 升级 sing-box
sudo bash deploy.sh update
```

## 自定义参数（环境变量）

- `PORT=443`           监听 UDP 端口
- `SNI=www.bing.com`   自签证书 CN
- `PASSWORD=xxx`       Hysteria2 密码（默认随机）

## 脚本干了什么

1. 装 sing-box（多源下载兜底）
2. 内存 < 2G 自动建 1G swap
3. 内核调优（BBR / fq / TCP fastopen=3）
4. 生成自签证书 + 写 sing-box 配置
5. setcap 允许非 root 绑 :443
6. 当前 SSH 用户配 NOPASSWD sudo
7. systemd 启动 + 自启
8. 输出客户端导入链接，存 `/root/sing-box-client.txt`

## 部署后必做

云厂商安全组放行 **UDP/443** 入站（Azure 用 az cli 一键开）。

---

## 当前生产节点（2026-05 重建）

旧的 4 台 ssr*（B1ls/B1s 香港+美西，RG `OTHERS`）已弃用，原���：
- B1ls 网卡只有 ~30Mbps，CPU 突发 baseline 5%，根本跑不快
- 2 台在美西（westus/westus3），跨太平洋 RTT 150-200ms

**新方案：1 主 1 备，RG `vpn`**

| 节点 | SKU | 区域 | IP | 月费 | 用途 |
|---|---|---|---|---|---|
| **vpn-jp** | B2s_v2 | japaneast | 20.89.49.190 | ~$35 | 主力，2c/8G/6.25Gbps + 加速网络 |
| **vpn-us** | B1s | eastus2 | 20.10.176.97 | ~$7.6 | 美国 IP 专用（OpenAI/Claude API） |

实测出口带宽（VM → Hetzner 100MB）：
- vpn-jp: 201 Mbps
- vpn-us: 248 Mbps

旧 4 台等用户自己删（用户原话："我自己删除"）。

## 自动化部署（cloud-init）

`cloud-init-vpn.yaml` 让新 VM 开机自动 `git clone V2Ray && bash deploy.sh install`，全程无人值守。新建 VM 命令模板：

```bash
az vm create \
  --resource-group vpn \
  --name vpn-xxx \
  --location <region> \
  --image Ubuntu2404 \
  --size Standard_B2s_v2 \
  --admin-username zhaopengxin \
  --ssh-key-values ~/.ssh/id_ed25519.pub \
  --custom-data D:/ai/V2Ray/cloud-init-vpn.yaml \
  --public-ip-sku Standard \
  --nsg-rule SSH

# 之后必须开 UDP/443
az network nsg rule create -g vpn --nsg-name vpn-xxxNSG \
  --name Allow-UDP-443 --priority 1010 --protocol Udp \
  --destination-port-ranges 443 --access Allow --direction Inbound
```

## Clash 配置

`clash-config.yaml`（在 .gitignore，含密码）：
- 默认 `🚀 节点选择 → ♻️ 自动选择`，url-test 在 jp/us 间挑最快
- OpenAI/Anthropic 流量**强制走美国节点**（GEOSITE,openai → 🇺🇸 美国节点）
- 国内 IP/GEOSITE,cn 直连
- IP-CIDR 防环路（自动加节点 IP）

## SSH

- 4 台旧 VM + 2 台新 VM 全部用 ed25519 公钥登录（`~/.ssh/id_ed25519`）
- NOPASSWD sudo 已配
- 用户名固定 `zhaopengxin`

---

## Claude Code 协作约定（用户偏好）

- **全局已开 `bypassPermissions`**（`C:\Users\zhaop\.claude\settings.json`），所有工具调用静默放行
- ask 列表保留：`rm`/`git push -f`/`az vm delete`/`sudo apt purge` 等仍弹窗确认
- deny 列表硬拦截：`rm -rf /`、`mkfs`、`curl|sh` 等
- **不要再用 `AskUserQuestion` 弹"选 A 还是 B"**——拿到数据直接给结论 + 直接执行；多个合理方向时自己拍板，注明"如果想换 X 我可以改"
- 只有**不可逆破坏性操作**前才停下确认（删 VM、改密码、`git push --force`、批量改密码）
- 用户曾因密码被无声轮换搞挂全部 client，**改密码/重启服务前必须确认**

## 已知历史教训

- v2ray + nginx + acme.sh 旧栈淘汰原因：nginx OOM 在证书续签时挂掉，整夜不可用
- B1ls 是性能玩具，永远别再用
- 美西区域跨境拥塞严重，亚太节点首选 japaneast（价格 + 链路双优）
- settings.json 里曾经混入 GitHub PAT 和明文 SSH 密码（已清洗）——以后任何包含敏感字符串的命令**别让 Claude 直接执行**，用环境变量或文件传
