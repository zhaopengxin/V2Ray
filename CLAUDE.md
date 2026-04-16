# V2Ray 一键部署脚本

## 简介

V2Ray 一键安装脚本，支持 VMESS/VLESS/Trojan 协议，Nginx TLS + WebSocket 反向代理。

## 部署架构

```
客户端 → Nginx (TLS 443) → V2Ray (本地端口) → 出站
```

## 使用方法

```bash
# 上传到服务器后执行
chmod +x setup.sh
sudo bash setup.sh
```

脚本为交互式菜单，按提示操作即可。

## 脚本增强功能

在原版基础上增加了以下可靠性改进：

- **自动 Swap**: 内存 < 1GB 时自动创建 1GB swap，防止 OOM
- **Nginx Watchdog**: 每 5 分钟检测 nginx 状态，异常自动拉起
- **服务自愈**: v2ray 服务配置 `Restart=always`，崩溃后自动重启
- **证书续签修复**: acme.sh PostHook 从 `restart` 改为 `start`，避免内存不足时续签失败导致 nginx 停机
