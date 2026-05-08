#!/bin/bash
# Sing-box + Hysteria2 一键部署脚本
# 用法:
#   sudo bash deploy.sh           # 全新部署（默认）
#   sudo bash deploy.sh doctor    # 健康检查
#   sudo bash deploy.sh info      # 显示客户端链接
#   sudo bash deploy.sh update    # 升级 sing-box
#
# 环境变量（可选）:
#   PORT=443           监听端口（默认 443，UDP）
#   SNI=www.bing.com   伪装 SNI
#   PASSWORD=xxx       Hysteria2 密码（默认随机生成）
#   USER_NAME=...      要配 NOPASSWD sudo 的用户（默认探测当前 SSH 用户）

set -euo pipefail

PORT="${PORT:-443}"
SNI="${SNI:-www.bing.com}"
SING_VER="1.13.11"
CFG=/etc/sing-box/config.json
CERT_DIR=/etc/sing-box/cert
CLIENT_FILE=/root/sing-box-client.txt

# ---------- 工具函数 ----------
log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[1;31m[-]\033[0m $*" >&2; }

need_root() { [[ $EUID -eq 0 ]] || { err "需要 root: sudo bash $0 $*"; exit 1; }; }

detect_user() {
    # 优先用 SUDO_USER；否则探测有 ssh 公钥的非 root 用户
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
        echo "$SUDO_USER"; return
    fi
    for u in $(awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd); do
        [[ -s "/home/$u/.ssh/authorized_keys" ]] && { echo "$u"; return; }
    done
}

# ---------- 子命令 ----------

install_singbox() {
    local force="${1:-}"
    if [[ -z "$force" ]] && command -v sing-box >/dev/null 2>&1; then
        log "sing-box 已安装: $(sing-box version | head -1)"; return
    fi
    log "下载 sing-box ${SING_VER} ..."
    local urls=(
        "https://github.com/SagerNet/sing-box/releases/download/v${SING_VER}/sing-box_${SING_VER}_linux_amd64.deb"
        "https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/v${SING_VER}/sing-box_${SING_VER}_linux_amd64.deb"
    )
    cd /tmp
    for u in "${urls[@]}"; do
        log "  尝试: $u"
        if curl -fL --max-time 60 -o sing-box.deb "$u" && [[ $(stat -c%s sing-box.deb) -gt 1000000 ]]; then
            dpkg -i sing-box.deb && rm -f sing-box.deb && return 0
        fi
        rm -f sing-box.deb
    done
    err "sing-box 下载失败"; exit 1
}

setup_swap() {
    if [[ -f /swapfile ]] || [[ "$(free -m | awk '/^Swap:/ {print $2}')" != "0" ]]; then
        log "swap 已存在，跳过"; return
    fi
    local mem=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
    [[ $mem -ge 2048 ]] && { log "内存 ${mem}MB 充足，无需 swap"; return; }
    log "创建 1G swap..."
    fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
    chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sysctl -w vm.swappiness=10 >/dev/null
    grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
}

setup_sysctl() {
    log "调优 TCP/UDP 内核参数..."
    cat > /etc/sysctl.d/99-singbox.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
EOF
    sysctl -p /etc/sysctl.d/99-singbox.conf >/dev/null
}

setup_cert() {
    [[ -f $CERT_DIR/cert.pem ]] && { log "证书已存在，跳过"; return; }
    log "生成自签证书 (CN=${SNI}) ..."
    mkdir -p $CERT_DIR
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout $CERT_DIR/private.key -out $CERT_DIR/cert.pem \
        -subj "/CN=${SNI}" -days 36500 2>/dev/null
    chown -R sing-box:sing-box $CERT_DIR
    chmod 644 $CERT_DIR/cert.pem
    chmod 600 $CERT_DIR/private.key
}

write_config() {
    if [[ -f $CFG ]] && grep -q hysteria2 $CFG; then
        log "配置文件已存在，跳过（如需重置请先删 $CFG）"; return
    fi
    local pwd="${PASSWORD:-$(openssl rand -base64 16 | tr -d '/+=' | head -c 22)}"
    log "写入配置 $CFG ..."
    mkdir -p /etc/sing-box
    cat > $CFG <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [ { "password": "${pwd}" } ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_DIR}/cert.pem",
        "key_path": "${CERT_DIR}/private.key"
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
    sing-box check -c $CFG
    setcap 'cap_net_bind_service=+ep' "$(command -v sing-box)" 2>/dev/null || true
}

start_service() {
    log "启动 sing-box ..."
    systemctl enable sing-box >/dev/null 2>&1
    systemctl restart sing-box
    sleep 2
    if ! systemctl is-active --quiet sing-box; then
        err "sing-box 启动失败"
        journalctl -u sing-box -n 20 --no-pager
        exit 1
    fi
}

setup_nopasswd() {
    local u
    u="${USER_NAME:-$(detect_user)}"
    [[ -z "$u" ]] && { warn "未检测到普通用户，跳过 NOPASSWD 配置"; return; }
    local f=/etc/sudoers.d/90-${u}-nopasswd
    [[ -f "$f" ]] && { log "$u NOPASSWD 已配置"; return; }
    log "为 $u 配置 NOPASSWD sudo ..."
    echo "$u ALL=(ALL) NOPASSWD: ALL" > "$f"
    chmod 440 "$f"
    visudo -cf "$f" >/dev/null
}

setup_auto_update() {
    log "配置自动更新 (sing-box / 系统补丁 / deploy.sh)..."

    # 1) 把当前脚本固定到 /usr/local/bin/deploy.sh
    install -m 755 "$0" /usr/local/bin/deploy.sh 2>/dev/null \
        || cp "$(realpath "$0")" /usr/local/bin/deploy.sh && chmod +x /usr/local/bin/deploy.sh

    # 2) cron: 每周升级 sing-box, 每日自更新 deploy.sh
    cat > /etc/cron.d/singbox-auto-update <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 每天 03:17 拉取最新 deploy.sh
17 3 * * *   root  curl -fsSL --max-time 30 https://raw.githubusercontent.com/zhaopengxin/V2Ray/main/deploy.sh -o /usr/local/bin/deploy.sh.new 2>/dev/null && [ -s /usr/local/bin/deploy.sh.new ] && mv /usr/local/bin/deploy.sh.new /usr/local/bin/deploy.sh && chmod +x /usr/local/bin/deploy.sh

# 每周日 05:17 升级 sing-box
17 5 * * 0   root  /usr/local/bin/deploy.sh update >> /var/log/singbox-update.log 2>&1
EOF

    # 3) Ubuntu/Debian 系统安全补丁自动安装
    if command -v apt-get >/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades apt-listchanges >/dev/null 2>&1 || true
        cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
        # 默认只装 security 通道，不动其他
        systemctl enable unattended-upgrades >/dev/null 2>&1 || true
    fi
}

emit_link() {
    local pwd ip link
    pwd=$(grep -oP '"password":\s*"\K[^"]+' $CFG | head -1)
    ip=$(curl -s --max-time 5 ifconfig.me || hostname -I | awk '{print $1}')
    link="hysteria2://${pwd}@${ip}:${PORT}/?sni=${SNI}&insecure=1#hy2-${ip}"
    cat > $CLIENT_FILE <<EOF
$link

Type     : Hysteria2
Address  : $ip
Port     : $PORT  (UDP)
Password : $pwd
SNI      : $SNI
ALPN     : h3
Insecure : true
EOF
    echo
    echo "===================== 客户端链接 ====================="
    echo "$link"
    echo "======================================================"
    echo
    echo "已保存到 $CLIENT_FILE"
    echo
    warn "请确保云厂商防火墙/NSG 放行 UDP/${PORT} 入站"
    echo "  Azure CLI:  az network nsg rule create --resource-group <RG> --nsg-name <NSG> \\"
    echo "              --name Allow-UDP-${PORT} --priority 1011 --protocol Udp \\"
    echo "              --destination-port-ranges ${PORT} --access Allow --direction Inbound"
}

cmd_install() {
    need_root
    log "=== Sing-box + Hysteria2 部署开始 ==="
    log "端口=${PORT}  SNI=${SNI}"
    apt-get update -qq && apt-get install -y -qq curl openssl
    install_singbox
    setup_swap
    setup_sysctl
    setup_cert
    write_config
    start_service
    setup_nopasswd
    setup_auto_update
    log "=== 部署完成 ==="
    emit_link
}

cmd_doctor() {
    echo "============== Sing-box Doctor =============="
    echo "时间: $(date)"
    echo
    echo "--- service ---"
    s=$(systemctl is-active sing-box 2>/dev/null)
    [[ "$s" = active ]] && echo "  [OK]   sing-box: active" || echo "  [FAIL] sing-box: $s"
    echo
    echo "--- 监听端口 ---"
    ss -ulnp 2>/dev/null | grep ":${PORT}" | sed 's/^/  /' || echo "  (UDP/$PORT 未监听)"
    echo
    echo "--- 最近 5 分钟连接数 ---"
    n=$(journalctl -u sing-box --since "5 minutes ago" --no-pager 2>/dev/null | grep -c "inbound connection from" || echo 0)
    echo "  $n"
    echo
    echo "--- 内存/Swap ---"
    free -h | sed 's/^/  /'
    echo
    echo "--- 磁盘 ---"
    df -h / | sed 's/^/  /'
    echo
    echo "--- 最近 24h OOM ---"
    oom=$(journalctl -k --since "24 hours ago" 2>/dev/null | grep -iE 'killed process|out of memory' | tail -3)
    [[ -z "$oom" ]] && echo "  (无)" || echo "$oom" | sed 's/^/  /'
    echo
    echo "--- sing-box version ---"
    sing-box version 2>/dev/null | head -1 | sed 's/^/  /'
    echo "============================================"
}

cmd_info() {
    if [[ -f $CFG ]] && grep -q hysteria2 $CFG; then
        # 从当前 config 实时生成（保证准确）
        emit_link
    elif [[ -f $CLIENT_FILE ]]; then
        cat $CLIENT_FILE
    else
        err "未找到配置或客户端文件，先跑 install"; exit 1
    fi
}

cmd_update() {
    need_root
    log "升级 sing-box 到最新版..."
    SING_VER=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -oP '"tag_name":\s*"v\K[^"]+' | head -1)
    [[ -z "$SING_VER" ]] && { err "无法获取最新版本号"; exit 1; }
    local cur=$(sing-box version 2>/dev/null | grep -oP 'version \K[\d.]+' | head -1)
    log "当前版本: ${cur:-未安装}  → 最新: ${SING_VER}"
    [[ "$cur" = "$SING_VER" ]] && { log "已是最新，跳过"; return; }
    install_singbox force
    systemctl restart sing-box
    sleep 2
    systemctl is-active --quiet sing-box && log "升级完成: $(sing-box version | head -1)" || err "升级后启动失败"
}

# ---------- 入口 ----------
action="${1:-install}"
case "$action" in
    install|"") cmd_install ;;
    doctor)     cmd_doctor ;;
    info)       cmd_info ;;
    update)     cmd_update ;;
    *) echo "用法: $0 [install|doctor|info|update]"; exit 1 ;;
esac
