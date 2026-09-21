#!/bin/sh
# ============================================================
# xray-node 一键安装脚本（小白版）
#
# 小白用法（root 用户）：
#   1. SSH 连上你的服务器
#   2. 粘贴下面这一行，回车：
#      curl -fsSL -o /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/xray-node/main/install.sh && sh /tmp/xray-install.sh
#   3. 按提示回答几个问题（看不懂就一路回车用默认），装完自动给你节点链接
#
# 装完之后，想看节点随时输入：  jiedian
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[注意]${NC} %s\n" "$1"; }
err()  { printf "${RED}[出错]${NC} %s\n" "$1"; }
step() { printf "\n${CYAN}${BOLD}%s${NC}\n" "$1"; }
die()  { err "$1"; exit 1; }

ask() { # ask "提示文字" "默认值" 变量名
  _p="$1"; _d="$2"; _v="$3"
  if [ -n "$_d" ]; then
    printf "%s [默认 %s]: " "$_p" "$_d"
  else
    printf "%s: " "$_p"
  fi
  read -r _a
  if [ -z "$_a" ]; then _a="$_d"; fi
  eval "$_v=\$_a"
}

rand_hex() { # rand_hex 字节数 -> 十六进制串
  od -An -tx1 -N"$1" /dev/urandom 2>/dev/null | tr -d ' \n'
}

rand_port() { # 随机一个空闲端口 20000-59999
  _try=0
  while [ "$_try" -lt 50 ]; do
    _try=$((_try + 1))
    _p=$(awk 'BEGIN{srand(); print int(20000+rand()*40000)}')
    _used=0
    if command -v ss >/dev/null 2>&1; then
      ss -ltn 2>/dev/null | grep -q ":${_p} " && _used=1
    elif command -v netstat >/dev/null 2>&1; then
      netstat -ltn 2>/dev/null | grep -q ":${_p} " && _used=1
    fi
    if [ "$_used" -eq 0 ]; then printf "%s" "$_p"; return 0; fi
  done
  printf "%s" "$_p"
}

gen_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    tr 'A-Z' 'a-z' < /proc/sys/kernel/random/uuid | tr -d '\n'
  else
    rand_hex 16 | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/'
  fi
}

b64url() { # 标准输入 -> base64url（去换行、去 =）
  base64 2>/dev/null | tr -d '\n' | tr '+/' '-_' | tr -d '='
}

get_ip() { # get_ip 4|6 -> 打印公网 IP，失败返回非零
  _v="$1"
  if [ "$_v" = "6" ]; then _f="-6"; else _f="-4"; fi
  for _u in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com"; do
    _ip=$(curl -fsSL --max-time 10 $_f "$_u" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$_ip" ]; then printf "%s" "$_ip"; return 0; fi
  done
  return 1
}

# ---------- 1. 必须是 root ----------
if [ "$(id -u)" -ne 0 ]; then
  die "请用 root 用户运行（root 下直接运行，或在命令前加 sudo）"
fi

printf "\n${BOLD}==============================================${NC}\n"
printf "${BOLD}   Xray 节点一键安装（小白版）${NC}\n"
printf "${BOLD}==============================================${NC}\n"
printf "全程中文提问，看不懂就一路回车用默认。\n"

if [ -f /etc/xray-node/node.txt ]; then
  warn "检测到已经安装过节点，继续会覆盖重装。"
  ask "继续重装吗？(y/n)" "y" _re
  case "$_re" in y|Y|yes|YES) ;; *) echo "已取消"; exit 0;; esac
fi

# ---------- 2. 装依赖 ----------
step "[准备] 检查系统工具…"
if command -v apt-get >/dev/null 2>&1; then
  timeout 60 apt-get update -qq >/dev/null 2>&1
  timeout 120 apt-get install -y -qq curl unzip ca-certificates >/dev/null 2>&1
elif command -v apk >/dev/null 2>&1; then
  timeout 120 apk add --no-cache curl unzip ca-certificates >/dev/null 2>&1
elif command -v dnf >/dev/null 2>&1; then
  timeout 120 dnf install -y -q curl unzip ca-certificates >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
  timeout 120 yum install -y -q curl unzip ca-certificates >/dev/null 2>&1
elif command -v pacman >/dev/null 2>&1; then
  timeout 120 pacman -Sy --noconfirm --needed curl unzip ca-certificates >/dev/null 2>&1
fi
command -v curl >/dev/null 2>&1 || die "装不上 curl，请手动安装 curl 后重试"
command -v unzip >/dev/null 2>&1 || die "装不上 unzip，请手动安装 unzip 后重试"
info "系统工具就绪"

# ---------- 3. 问：IPv4 还是 IPv6 ----------
step "[1/4] 你的服务器用 IPv4 还是 IPv6？"
printf "  1) IPv4（大多数情况选这个）\n"
printf "  2) IPv6\n"
ask "请选择" "1" _ipver
case "$_ipver" in
  2) IPVER=6 ;;
  *) IPVER=4 ;;
esac
printf "正在检测公网 IP…\n"
if ! SERVER_IP=$(get_ip "$IPVER"); then
  warn "自动检测 IP 失败，请手动输入。"
  ask "请输入你的服务器公网 IP" "" SERVER_IP
  [ -z "$SERVER_IP" ] && die "没有 IP 装不了，先去查一下你的服务器 IP 再来"
fi
info "服务器 IP：$SERVER_IP"
# 按实际地址格式决定链接里是否加方括号（IPv6 必须加 []）
case "$SERVER_IP" in
  *:*) LINK_IP="[$SERVER_IP]" ;;
  *)   LINK_IP="$SERVER_IP" ;;
esac

# ---------- 4. 问：协议 ----------
step "[2/4] 选一个协议"
printf "  1) VLESS + REALITY + Vision（推荐，最难被识别）\n"
printf "  2) VMess + WebSocket（兼容性好，老客户端也支持）\n"
printf "  3) Trojan + REALITY（和 1 类似，换种协议）\n"
printf "  4) Shadowsocks（最简单，速度不错）\n"
ask "请选择" "1" _proto
case "$_proto" in
  2) PROTO="vmess" ;;
  3) PROTO="trojan" ;;
  4) PROTO="ss" ;;
  *) PROTO="vless" ;;
esac

# ---------- 5. 问：端口 ----------
step "[3/4] 节点用哪个端口？"
_DEF_PORT=$(rand_port)
ask "请输入端口（1-65535）" "$_DEF_PORT" PORT
case "$PORT" in
  ''|*[!0-9]*) warn "端口不是数字，用默认 $_DEF_PORT"; PORT="$_DEF_PORT" ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  warn "端口超出范围，用默认 $_DEF_PORT"; PORT="$_DEF_PORT"
fi
info "端口：$PORT"

# ---------- 6. REALITY 伪装域名 ----------
NEED_REALITY=0
case "$PROTO" in vless|trojan) NEED_REALITY=1 ;; esac
if [ "$NEED_REALITY" -eq 1 ]; then
  step "[4/4] REALITY 伪装成哪个网站？"
  printf "  1) www.samsung.com\n"
  printf "  2) www.apple.com\n"
  ask "请选择" "1" _dm
  case "$_dm" in
    2) REALITY_DOMAIN="www.apple.com" ;;
    *) REALITY_DOMAIN="www.samsung.com" ;;
  esac
  info "伪装域名：$REALITY_DOMAIN"
else
  step "[4/4] 这一步跳过（只有 REALITY 协议才需要选伪装域名）"
fi

# ---------- 7. 随机生成 UUID / 密码 ----------
step "[生成] 随机生成账号和密码…"
UUID=$(gen_uuid)
TROJAN_PASS=$(rand_hex 16)
if command -v openssl >/dev/null 2>&1; then
  SS_PASS=$(openssl rand -base64 16 2>/dev/null | tr -d '\n')
else
  SS_PASS=$(head -c 16 /dev/urandom 2>/dev/null | od -An -tu1 | awk '{for(i=1;i<=NF;i++) printf "%c",$i}' | base64 | tr -d '\n')
fi
WS_PATH="/$(rand_hex 4)"
info "账号密码已随机生成（装完会显示，平时输入 jiedian 也能看）"

# ---------- 8. 下载 Xray ----------
step "[下载] 获取 Xray 内核…"
case "$(uname -m)" in
  x86_64|amd64) XARCH="64" ;;
  aarch64|arm64) XARCH="arm64-v8a" ;;
  armv7l|armv7) XARCH="arm32-v7a" ;;
  *) die "不支持的 CPU 架构：$(uname -m)" ;;
esac
XRAY_BIN="/usr/local/bin/xray"
if [ -x "$XRAY_BIN" ] && "$XRAY_BIN" version >/dev/null 2>&1; then
  info "Xray 已存在，直接用现有的：$($XRAY_BIN version 2>/dev/null | head -1)"
else
  _url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XARCH}.zip"
  curl -fsSL --max-time 120 -o /tmp/xray.zip "$_url" || die "Xray 下载失败，检查服务器能否访问 github.com"
  mkdir -p /tmp/xray-dl && unzip -o -q /tmp/xray.zip -d /tmp/xray-dl xray || die "解压失败"
  install -m 0755 /tmp/xray-dl/xray "$XRAY_BIN" || die "安装 Xray 失败"
  rm -rf /tmp/xray.zip /tmp/xray-dl
  info "Xray 安装成功：$($XRAY_BIN version 2>/dev/null | head -1)"
fi

# ---------- 9. REALITY 密钥对 ----------
if [ "$NEED_REALITY" -eq 1 ]; then
  step "[密钥] 生成 REALITY 密钥…"
  _out=$("$XRAY_BIN" x25519 2>/dev/null)
  REALITY_PRIV=$(printf "%s" "$_out" | grep -i "private" | awk '{print $NF}' | tr -d '\r\n')
  REALITY_PUB=$(printf "%s" "$_out" | grep -i "public" | awk '{print $NF}' | tr -d '\r\n')
  [ -z "$REALITY_PRIV" ] || [ -z "$REALITY_PUB" ] && die "REALITY 密钥生成失败"
  REALITY_SID=$(rand_hex 4)
  info "REALITY 密钥已生成"
fi

# ---------- 10. 写配置文件 ----------
step "[配置] 写入 Xray 配置…"
mkdir -p /usr/local/etc/xray /etc/xray-node

case "$PROTO" in
  vless)
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DOMAIN:443",
          "xver": 0,
          "serverNames": [ "$REALITY_DOMAIN" ],
          "privateKey": "$REALITY_PRIV",
          "shortIds": [ "$REALITY_SID" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF
    ;;
  trojan)
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "trojan",
      "settings": {
        "clients": [ { "password": "$TROJAN_PASS" } ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DOMAIN:443",
          "xver": 0,
          "serverNames": [ "$REALITY_DOMAIN" ],
          "privateKey": "$REALITY_PRIV",
          "shortIds": [ "$REALITY_SID" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF
    ;;
  vmess)
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [ { "id": "$UUID", "alterId": 0 } ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF
    ;;
  ss)
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-128-gcm",
        "password": "$SS_PASS",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF
    ;;
esac

"$XRAY_BIN" -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1 \
  || die "配置文件校验没通过，请截图发我看看"
info "配置文件校验通过"

# ---------- 11. 开机自启 ----------
step "[服务] 设置开机自启…"
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
Type=simple
User=root
ExecStart=$XRAY_BIN -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable xray >/dev/null 2>&1
  systemctl restart xray >/dev/null 2>&1
  sleep 1
  if systemctl is-active --quiet xray; then
    info "xray 已启动，并设为开机自启"
  else
    warn "xray 好像没起来，运行 systemctl status xray 看看原因"
  fi
elif command -v rc-service >/dev/null 2>&1; then
  cat > /etc/init.d/xray <<'RCEOF'
#!/sbin/openrc-run
name="xray"
command="/usr/local/bin/xray"
command_args="-config /usr/local/etc/xray/config.json"
command_background="yes"
pidfile="/run/xray.pid"
depend() { need net; }
RCEOF
  chmod +x /etc/init.d/xray
  rc-update add xray default >/dev/null 2>&1
  rc-service xray restart >/dev/null 2>&1
  sleep 1
  if rc-service xray status >/dev/null 2>&1; then
    info "xray 已启动，并设为开机自启"
  else
    warn "xray 好像没起来，运行 rc-service xray status 看看原因"
  fi
else
  warn "没找到 systemd/OpenRC，改用后台方式启动（重启后需手动再跑一次脚本）"
  pkill -f "xray -config /usr/local/etc/xray/config.json" >/dev/null 2>&1
  nohup "$XRAY_BIN" -config /usr/local/etc/xray/config.json >/var/log/xray.log 2>&1 &
  sleep 1
  info "xray 已在后台启动"
fi

# ---------- 12. 放行端口 ----------
step "[网络] 放行端口…"
if command -v ufw >/dev/null 2>&1; then
  ufw allow "$PORT"/tcp >/dev/null 2>&1 && info "ufw 已放行 $PORT/tcp"
fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$PORT"/tcp >/dev/null 2>&1
  firewall-cmd --reload >/dev/null 2>&1 && info "firewalld 已放行 $PORT/tcp"
fi
if command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT >/dev/null 2>&1 \
    || iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT >/dev/null 2>&1
fi
warn "如果是云服务器（阿里云/腾讯云/AWS 等），还去控制台安全组放行 $PORT 端口"

# ---------- 13. 生成节点链接 ----------
step "[完成] 生成你的节点…"
case "$PROTO" in
  vless)
    LINK="vless://${UUID}@${LINK_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SID}&type=tcp#xray-node"
    PROTO_NAME="VLESS + REALITY + Vision"
    ;;
  trojan)
    LINK="trojan://${TROJAN_PASS}@${LINK_IP}:${PORT}?security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SID}&type=tcp#xray-node"
    PROTO_NAME="Trojan + REALITY"
    ;;
  vmess)
    _json="{\"v\":\"2\",\"ps\":\"xray-node\",\"add\":\"${SERVER_IP}\",\"port\":\"${PORT}\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"${WS_PATH}\",\"tls\":\"\"}"
    LINK="vmess://$(printf "%s" "$_json" | b64url)"
    PROTO_NAME="VMess + WebSocket"
    ;;
  ss)
    LINK="ss://$(printf "%s" "2022-blake3-aes-128-gcm:${SS_PASS}" | b64url)@${LINK_IP}:${PORT}#xray-node"
    PROTO_NAME="Shadowsocks"
    ;;
esac

# ---------- 14. 保存 + jiedian 命令 ----------
{
  printf "==============================================\n"
  printf " 你的节点（复制下面整行，粘贴到客户端导入）\n"
  printf "==============================================\n"
  printf "%s\n" "$LINK"
  printf -- "----------------------------------------------\n"
  printf "协议: %s\n" "$PROTO_NAME"
  printf "地址: %s\n" "$SERVER_IP"
  printf "端口: %s\n" "$PORT"
  case "$PROTO" in
    vless|vmess) printf "UUID: %s\n" "$UUID" ;;
    trojan)      printf "密码: %s\n" "$TROJAN_PASS" ;;
    ss)          printf "密码: %s\n" "$SS_PASS"; printf "加密: 2022-blake3-aes-128-gcm\n" ;;
  esac
  case "$PROTO" in
    vless|trojan) printf "伪装域名: %s\n" "$REALITY_DOMAIN" ;;
    vmess)        printf "WS 路径: %s\n" "$WS_PATH" ;;
  esac
  printf -- "----------------------------------------------\n"
  printf "以后想看节点，直接输入: jiedian\n"
  printf "==============================================\n"
} > /etc/xray-node/node.txt

cat > /usr/local/bin/jiedian <<'JDEOF'
#!/bin/sh
# 输入 jiedian，立刻显示你的节点
if [ -f /etc/xray-node/node.txt ]; then
  cat /etc/xray-node/node.txt
else
  echo "还没安装节点，请先运行一键安装脚本"
fi
JDEOF
chmod +x /usr/local/bin/jiedian
info "已安装 jiedian 命令：以后输入 jiedian 就能看节点"

# ---------- 15. 显示结果 ----------
printf "\n"
cat /etc/xray-node/node.txt
printf "\n${GREEN}${BOLD}安装完成！${NC}把上面那行链接复制到客户端就能用了。\n"
printf "客户端推荐：安卓 v2rayNG / NekoBox，苹果 Shadowrocket / Streisand，电脑 Nekoray / v2rayN\n"
