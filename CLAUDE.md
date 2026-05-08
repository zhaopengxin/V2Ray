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
