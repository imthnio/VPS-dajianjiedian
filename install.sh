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
# 不想要了，输入 xiezai 一键卸载干净
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

# gh_api_dl <仓库> <文件名> <输出路径>
# 走 GitHub API 下载 release 文件：api.github.com 比 github.com 稳得多，
# API 返回 302 跳到 release-assets，下得快。成功返回 0，失败返回非零。
gh_api_dl() {
  _gh_repo="$1"; _gh_asset="$2"; _gh_out="$3"
  _gh_rel=$(curl -fsSL --max-time 20 "https://api.github.com/repos/${_gh_repo}/releases/latest" 2>/dev/null) || return 1
  [ -n "$_gh_rel" ] || return 1
  _gh_aid=$(printf "%s\n" "$_gh_rel" | grep -B10 -F "\"name\": \"${_gh_asset}\"" | grep '"id"' | tail -1 | grep -o '[0-9][0-9]*' | head -1)
  [ -n "$_gh_aid" ] || return 1
  curl -fSL --progress-bar --connect-timeout 20 --speed-time 30 --speed-limit 1000 --retry 2 --retry-delay 3 \
    -H "Accept: application/octet-stream" \
    -o "$_gh_out" "https://api.github.com/repos/${_gh_repo}/releases/assets/${_gh_aid}"
}

# pick_dldir: 选一个磁盘上的下载目录（/tmp 可能是内存盘，大文件下载会爆内存）
# 优先 /var/tmp，其次 $HOME，最后才 /tmp。打印目录路径，失败返回非零。
pick_dldir() {
  for _cand in /var/tmp "$HOME" /tmp; do
    if [ -d "$_cand" ] && [ -w "$_cand" ]; then
      _dd="${_cand}/xray-node-dl"
      if mkdir -p "$_dd" 2>/dev/null; then
        printf "%s" "$_dd"
        return 0
      fi
    fi
  done
  return 1
}

# mark_our_bin <名字>: 记录这个内核是脚本自己下载安装的，卸载时才删
# （用户机器上本来就有的不删，避免误删）
mark_our_bin() {
  mkdir -p /etc/xray-node 2>/dev/null
  grep -qx "$1" /etc/xray-node/our_bins 2>/dev/null || echo "$1" >> /etc/xray-node/our_bins
}

# wait_for_port <端口> <tcp|udp> <超时秒>: 等端口进入监听，成功返回 0
wait_for_port() {
  _wp="$1"; _wproto="${2:-tcp}"; _wtimeout="${3:-15}"
  _wtry=0
  while [ "$_wtry" -lt "$_wtimeout" ]; do
    if command -v ss >/dev/null 2>&1; then
      if [ "$_wproto" = "udp" ]; then
        ss -uln 2>/dev/null | grep -q ":${_wp} " && return 0
      else
        ss -ltn 2>/dev/null | grep -q ":${_wp} " && return 0
      fi
    elif command -v netstat >/dev/null 2>&1; then
      if [ "$_wproto" = "udp" ]; then
        netstat -uln 2>/dev/null | grep -q ":${_wp} " && return 0
      else
        netstat -ltn 2>/dev/null | grep -q ":${_wp} " && return 0
      fi
    else
      return 0  # 没有 ss/netstat，无法检查，视为通过
    fi
    sleep 1
    _wtry=$((_wtry + 1))
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

# ---------- 2. 装依赖（缺啥装啥，都有就直接跳过） ----------
step "[准备] 检查系统工具…"
_need_install=0
command -v curl >/dev/null 2>&1 || _need_install=1
command -v unzip >/dev/null 2>&1 || _need_install=1
if [ "$_need_install" -eq 1 ]; then
  printf "缺少 curl / unzip，正在自动安装（每一步都有进度提示，不会卡住不动）…\n"
  export DEBIAN_FRONTEND=noninteractive
  _dep_log="/tmp/xray-dep-apt.log"
  # _apt_do <描述> <单次超时秒> -- <apt-get 参数…>
  # 刚开机的机器常被系统自动更新占着 dpkg 锁：不等锁就硬装会白白超时失败。
  # 这里检测到锁就等 20 秒重试并报进度，而不是静默卡死。
  _apt_do() {
    _ad="$1"; _ato="$2"; shift 2
    [ "$1" = "--" ] && shift
    _an=0
    while [ "$_an" -lt 10 ]; do
      printf "%s…\n" "$_ad"
      if timeout "$_ato" apt-get "$@" >"$_dep_log" 2>&1; then return 0; fi
      if grep -qi "could not get lock\|unable to lock\|waiting for.*lock" "$_dep_log" 2>/dev/null; then
        _an=$((_an + 1))
        printf "系统自动更新正占着软件源，20 秒后重试（%s/10）…\n" "$_an"
        sleep 20
      else
        return 1
      fi
    done
    return 1
  }
  # _dep_fail：装失败时把吞掉的报错吐出来，而不是只留一句"装不上"
  _dep_fail() {
    warn "这一步没成功，最后看到的报错："
    tail -n 5 "$_dep_log" 2>/dev/null | sed 's/^/  /'
  }
  if command -v apt-get >/dev/null 2>&1; then
    _apt_do "正在更新软件源" 60 -- update -qq \
      || warn "软件源更新失败，用已有索引继续装（多数情况不影响）"
    _apt_do "正在安装 curl / unzip" 300 -- install -y -qq curl unzip ca-certificates \
      || _dep_fail
  elif command -v apk >/dev/null 2>&1; then
    printf "正在安装 curl / unzip…\n"
    timeout 300 apk add --no-cache curl unzip ca-certificates >"$_dep_log" 2>&1 || _dep_fail
  elif command -v dnf >/dev/null 2>&1; then
    printf "正在安装 curl / unzip…\n"
    timeout 300 dnf install -y -q curl unzip ca-certificates >"$_dep_log" 2>&1 || _dep_fail
  elif command -v yum >/dev/null 2>&1; then
    printf "正在安装 curl / unzip…\n"
    timeout 300 yum install -y -q curl unzip ca-certificates >"$_dep_log" 2>&1 || _dep_fail
  elif command -v pacman >/dev/null 2>&1; then
    printf "正在安装 curl / unzip…\n"
    timeout 300 pacman -Sy --noconfirm --needed curl unzip ca-certificates >"$_dep_log" 2>&1 || _dep_fail
  fi
  rm -f "$_dep_log"
  unset DEBIAN_FRONTEND
else
  info "curl / unzip 都有，直接跳过安装"
fi
command -v curl >/dev/null 2>&1 || die "装不上 curl，请手动安装 curl 后重试"
command -v unzip >/dev/null 2>&1 || die "装不上 unzip，请手动安装 unzip 后重试"
info "系统工具就绪"

# ---------- 3. 问：IPv4 还是 IPv6 ----------
step "[1/4] 节点里填你服务器的哪个公网地址？"
printf "  1) IPv4 地址（服务器有公网 IPv4 就选这个，大多数情况都是）\n"
printf "  2) IPv6 地址（只有纯 IPv6、没有 IPv4 的服务器才选这个）\n"
printf "不知道选哪个就回车用默认 1。\n"
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
printf "  5) AnyTLS + REALITY（新协议，表现不错）\n"
printf "  6) Hysteria2（UDP，速度快，弱网表现好）\n"
printf "  7) TUIC（UDP，低延迟）\n"
ask "请选择" "1" _proto
case "$_proto" in
  2) PROTO="vmess" ;;
  3) PROTO="trojan" ;;
  4) PROTO="ss" ;;
  5) PROTO="anytls" ;;
  6) PROTO="hy2" ;;
  7) PROTO="tuic" ;;
  *) PROTO="vless" ;;
esac
# 1-4 用 Xray 内核，5-7 用 sing-box 内核
case "$PROTO" in
  anytls|hy2|tuic) CORE="sing-box" ;;
  *) CORE="xray" ;;
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
case "$PROTO" in vless|trojan|anytls) NEED_REALITY=1 ;; esac
if [ "$NEED_REALITY" -eq 1 ]; then
  step "[4/4] REALITY 伪装成哪个网站？"
  printf "  1) www.samsung.com（三星官网，零干扰，最稳）\n"
  printf "  2) www.cisco.com（思科官网，TLS 极稳）\n"
  printf "  3) itunes.apple.com（苹果音乐服务）\n"
  printf "  4) www.python.org（Python 官网，技术站小众）\n"
  printf "  5) m.media-amazon.com（亚马逊图片站）\n"
  printf "  6) images-na.ssl-images-amazon.com（亚马逊图片 CDN）\n"
  printf "  7) download-installer.cdn.mozilla.net（火狐下载站）\n"
  printf "  8) www.lovelive-anime.jp（日本动画官网，小众）\n"
  printf "  9) academy.nvidia.com（英伟达学院，备选用）\n"
  printf " 10) lol.secure.dyn.riotcdn.net（游戏补丁 CDN，备选用）\n"
  printf "不知道选哪个就回车用默认 1。\n"
  ask "请选择" "1" _dm
  case "$_dm" in
    2)  REALITY_DOMAIN="www.cisco.com" ;;
    3)  REALITY_DOMAIN="itunes.apple.com" ;;
    4)  REALITY_DOMAIN="www.python.org" ;;
    5)  REALITY_DOMAIN="m.media-amazon.com" ;;
    6)  REALITY_DOMAIN="images-na.ssl-images-amazon.com" ;;
    7)  REALITY_DOMAIN="download-installer.cdn.mozilla.net" ;;
    8)  REALITY_DOMAIN="www.lovelive-anime.jp" ;;
    9)  REALITY_DOMAIN="academy.nvidia.com" ;;
    10) REALITY_DOMAIN="lol.secure.dyn.riotcdn.net" ;;
    *)  REALITY_DOMAIN="www.samsung.com" ;;
  esac
  info "伪装域名：$REALITY_DOMAIN"
else
  step "[4/4] 这一步跳过（只有 REALITY 协议才需要选伪装域名）"
fi

# ---------- 7. 随机生成 UUID / 密码 ----------
step "[生成] 随机生成账号和密码…"
UUID=$(gen_uuid)
TROJAN_PASS=$(rand_hex 16)
ANYTLS_PASS=$(rand_hex 16)
HY2_PASS=$(rand_hex 16)
TUIC_PASS=$(rand_hex 16)
if command -v openssl >/dev/null 2>&1; then
  SS_PASS=$(openssl rand -base64 16 2>/dev/null | tr -d '\n')
else
  SS_PASS=$(head -c 16 /dev/urandom 2>/dev/null | od -An -tu1 | awk '{for(i=1;i<=NF;i++) printf "%c",$i}' | base64 | tr -d '\n')
fi
WS_PATH="/$(rand_hex 4)"
info "账号密码已随机生成（装完会显示，平时输入 jiedian 也能看）"

# ---------- 8. 下载内核 ----------
case "$(uname -m)" in
  x86_64|amd64) MACH="amd64" ;;
  aarch64|arm64) MACH="arm64" ;;
  armv7l|armv7) MACH="armv7" ;;
  *) die "不支持的 CPU 架构：$(uname -m)" ;;
esac

if [ "$CORE" = "xray" ]; then
  step "[下载] 获取 Xray 内核…"
  case "$MACH" in
    amd64) XARCH="64" ;;
    arm64) XARCH="arm64-v8a" ;;
    armv7) XARCH="arm32-v7a" ;;
  esac
  XRAY_BIN="/usr/local/bin/xray"
  if [ -x "$XRAY_BIN" ] && "$XRAY_BIN" version >/dev/null 2>&1; then
    info "Xray 已存在，直接用现有的：$($XRAY_BIN version 2>/dev/null | head -1)"
  else
    DL_DIR=$(pick_dldir) || die "找不到可写的下载目录"
    # 磁盘上已有完整可用的包就直接用（上次下载完但被中断的情况，不用重新下载）
    if [ -s "$DL_DIR/xray.zip" ] && unzip -t -q "$DL_DIR/xray.zip" >/dev/null 2>&1; then
      info "安装包已在本地，直接使用（跳过下载）"
    else
      rm -f "$DL_DIR/xray.zip"
      _xasset="Xray-linux-${XARCH}.zip"
      _dl_ok=0
      # 路线 A：GitHub API（api.github.com 稳，302 跳到 release-assets 下得快）
      info "尝试下载：GitHub API"
      if gh_api_dl "XTLS/Xray-core" "$_xasset" "$DL_DIR/xray.zip"; then
        _dl_ok=1
      else
        warn "API 路线失败，换 github.com 直链试试…"
        rm -f "$DL_DIR/xray.zip"
        # 路线 B：github.com 直链（版本直链优先，/latest/download 兜底）
        _xver=$(curl -fsSL --max-time 20 https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null \
          | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
        for _url in \
          ${_xver:+https://github.com/XTLS/Xray-core/releases/download/v${_xver}/Xray-linux-${XARCH}.zip} \
          "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XARCH}.zip" \
        ; do
          [ -z "$_url" ] && continue
          info "尝试下载：$_url"
          if curl -fSL --progress-bar --connect-timeout 20 --speed-time 30 --speed-limit 1000 --retry 2 --retry-delay 3 -o "$DL_DIR/xray.zip" "$_url"; then
            _dl_ok=1
            break
          fi
          warn "这个地址下载失败，换下一个地址试试…"
          rm -f "$DL_DIR/xray.zip"
        done
      fi
      [ "$_dl_ok" -eq 1 ] || die "Xray 下载失败：到 GitHub 的网络不稳定，稍等几分钟后重跑脚本试试"
    fi
    # 完整性校验：包坏了直接报错，不往下装半截文件
    unzip -t -q "$DL_DIR/xray.zip" >/dev/null 2>&1 || die "下载的安装包已损坏，请重跑脚本重新下载"
    rm -rf "$DL_DIR/xray-dl" && mkdir -p "$DL_DIR/xray-dl"
    unzip -o "$DL_DIR/xray.zip" -d "$DL_DIR/xray-dl" xray || die "解压失败"
    [ -s "$DL_DIR/xray-dl/xray" ] || die "解压后没找到 xray 文件"
    install -m 0755 "$DL_DIR/xray-dl/xray" "$XRAY_BIN" || die "安装 Xray 失败"
    "$XRAY_BIN" version >/dev/null 2>&1 || die "装完的 Xray 跑不起来，安装包可能有问题"
    mark_our_bin "xray"
    rm -rf "$DL_DIR"
    info "Xray 安装成功：$($XRAY_BIN version 2>/dev/null | head -1)"
  fi
else
  step "[下载] 获取 sing-box 内核…"
  # Alpine 是 musl，其它系统用默认版本
  _suffix=""
  [ -f /etc/alpine-release ] && _suffix="-musl"
  SB_BIN="/usr/local/bin/sing-box"
  if [ -x "$SB_BIN" ] && "$SB_BIN" version >/dev/null 2>&1; then
    info "sing-box 已存在，直接用现有的：$($SB_BIN version 2>/dev/null | head -1)"
  else
    DL_DIR=$(pick_dldir) || die "找不到可写的下载目录"
    _ver=$(curl -fsSL --max-time 20 https://api.github.com/repos/SagerNet/sing-box/releases/latest \
      | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
    [ -z "$_ver" ] && die "获取 sing-box 最新版本失败，检查服务器能否访问 api.github.com"
    _url="https://github.com/SagerNet/sing-box/releases/download/v${_ver}/sing-box-${_ver}-linux-${MACH}${_suffix}.tar.gz"
    # 磁盘上已有完整可用的包就直接用（上次下载完但被中断的情况，不用重新下载）
    if [ -s "$DL_DIR/sb.tar.gz" ] && tar tzf "$DL_DIR/sb.tar.gz" >/dev/null 2>&1; then
      info "安装包已在本地，直接使用（跳过下载）"
    else
      rm -f "$DL_DIR/sb.tar.gz"
      _sasset="sing-box-${_ver}-linux-${MACH}${_suffix}.tar.gz"
      _dl_ok=0
      # 路线 A：GitHub API（api.github.com 稳，302 跳到 release-assets 下得快）
      info "尝试下载：GitHub API"
      if gh_api_dl "SagerNet/sing-box" "$_sasset" "$DL_DIR/sb.tar.gz"; then
        _dl_ok=1
      else
        warn "API 路线失败，换 github.com 直链试试…"
        rm -f "$DL_DIR/sb.tar.gz"
        # 路线 B：github.com 版本直链兜底
        _url="https://github.com/SagerNet/sing-box/releases/download/v${_ver}/sing-box-${_ver}-linux-${MACH}${_suffix}.tar.gz"
        info "尝试下载：$_url"
        if curl -fSL --progress-bar --connect-timeout 20 --speed-time 30 --speed-limit 1000 --retry 2 --retry-delay 3 -o "$DL_DIR/sb.tar.gz" "$_url"; then
          _dl_ok=1
        fi
      fi
      [ "$_dl_ok" -eq 1 ] || die "sing-box 下载失败：到 GitHub 的网络不稳定，稍等几分钟后重跑脚本试试"
    fi
    # 完整性校验：包坏了直接报错，不往下装半截文件
    tar tzf "$DL_DIR/sb.tar.gz" >/dev/null 2>&1 || die "下载的安装包已损坏，请重跑脚本重新下载"
    rm -rf "$DL_DIR/sb-dl" && mkdir -p "$DL_DIR/sb-dl"
    tar xzf "$DL_DIR/sb.tar.gz" -C "$DL_DIR/sb-dl" || die "解压失败"
    [ -s "$DL_DIR/sb-dl/sing-box-${_ver}-linux-${MACH}${_suffix}/sing-box" ] || die "解压后没找到 sing-box 文件"
    install -m 0755 "$DL_DIR/sb-dl/sing-box-${_ver}-linux-${MACH}${_suffix}/sing-box" "$SB_BIN" || die "安装 sing-box 失败"
    "$SB_BIN" version >/dev/null 2>&1 || die "装完的 sing-box 跑不起来，安装包可能有问题"
    mark_our_bin "sing-box"
    rm -rf "$DL_DIR"
    info "sing-box 安装成功：$($SB_BIN version 2>/dev/null | head -1)"
  fi
fi

# ---------- 9. REALITY 密钥对 ----------
if [ "$NEED_REALITY" -eq 1 ]; then
  step "[密钥] 生成 REALITY 密钥…"
  if [ "$CORE" = "xray" ]; then
    _out=$("$XRAY_BIN" x25519 2>/dev/null)
    REALITY_PRIV=$(printf "%s" "$_out" | grep -i "private" | awk '{print $NF}' | tr -d '\r\n')
    REALITY_PUB=$(printf "%s" "$_out" | grep -i "public" | awk '{print $NF}' | tr -d '\r\n')
  else
    # sing-box 自带 reality-keypair 生成，不需要 openssl
    _out=$("$SB_BIN" generate reality-keypair 2>/dev/null)
    REALITY_PRIV=$(printf "%s" "$_out" | grep -i "privatekey" | awk '{print $NF}' | tr -d '\r\n')
    REALITY_PUB=$(printf "%s" "$_out" | grep -i "publickey" | awk '{print $NF}' | tr -d '\r\n')
  fi
  [ -z "$REALITY_PRIV" ] || [ -z "$REALITY_PUB" ] && die "REALITY 密钥生成失败"
  REALITY_SID=$(rand_hex 4)
  info "REALITY 密钥已生成"
fi

# ---------- 9b. 自签证书（Hysteria2 / TUIC 需要） ----------
if [ "$PROTO" = "hy2" ] || [ "$PROTO" = "tuic" ]; then
  step "[证书] 生成自签证书…"
  mkdir -p /usr/local/etc/sing-box
  # sing-box 自带 tls-keypair 生成自签证书，不需要 openssl；有效期 120 个月
  "$SB_BIN" generate tls-keypair www.samsung.com --months 120 > /tmp/sb-tls.pem 2>/dev/null \
    || die "自签证书生成失败"
  awk '/BEGIN PRIVATE KEY/{p=1} p{print} /END PRIVATE KEY/{p=0}' /tmp/sb-tls.pem > /usr/local/etc/sing-box/key.pem
  awk '/BEGIN CERTIFICATE/{p=1} p{print} /END CERTIFICATE/{p=0}' /tmp/sb-tls.pem > /usr/local/etc/sing-box/cert.pem
  rm -f /tmp/sb-tls.pem
  [ -s /usr/local/etc/sing-box/key.pem ] && [ -s /usr/local/etc/sing-box/cert.pem ] \
    || die "自签证书生成失败"
  info "自签证书已生成"
fi

# ---------- 10. 写配置文件 ----------
step "[配置] 写入配置…"
mkdir -p /etc/xray-node

if [ "$CORE" = "xray" ]; then
mkdir -p /usr/local/etc/xray
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

else
# ---------- sing-box 配置（AnyTLS / Hysteria2 / TUIC） ----------
mkdir -p /usr/local/etc/sing-box
SB_CONF="/usr/local/etc/sing-box/config.json"
case "$PROTO" in
  anytls)
    cat > "$SB_CONF" <<EOF
{
  "log": { "level": "warning" },
  "inbounds": [
    {
      "type": "anytls",
      "listen": "::",
      "listen_port": $PORT,
      "users": [ { "name": "xray-node", "password": "$ANYTLS_PASS" } ],
      "tls": {
        "enabled": true,
        "server_name": "$REALITY_DOMAIN",
        "reality": {
          "enabled": true,
          "handshake": { "server": "$REALITY_DOMAIN", "server_port": 443 },
          "private_key": "$REALITY_PRIV",
          "short_id": [ "$REALITY_SID" ]
        }
      }
    }
  ],
  "outbounds": [ { "type": "direct" } ]
}
EOF
    ;;
  hy2)
    cat > "$SB_CONF" <<EOF
{
  "log": { "level": "warning" },
  "inbounds": [
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": $PORT,
      "users": [ { "name": "xray-node", "password": "$HY2_PASS" } ],
      "masquerade": "https://www.samsung.com/",
      "tls": {
        "enabled": true,
        "server_name": "www.samsung.com",
        "certificate_path": "/usr/local/etc/sing-box/cert.pem",
        "key_path": "/usr/local/etc/sing-box/key.pem"
      }
    }
  ],
  "outbounds": [ { "type": "direct" } ]
}
EOF
    ;;
  tuic)
    cat > "$SB_CONF" <<EOF
{
  "log": { "level": "warning" },
  "inbounds": [
    {
      "type": "tuic",
      "listen": "::",
      "listen_port": $PORT,
      "users": [ { "name": "xray-node", "uuid": "$UUID", "password": "$TUIC_PASS" } ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "server_name": "www.samsung.com",
        "alpn": [ "h3" ],
        "certificate_path": "/usr/local/etc/sing-box/cert.pem",
        "key_path": "/usr/local/etc/sing-box/key.pem"
      }
    }
  ],
  "outbounds": [ { "type": "direct" } ]
}
EOF
    ;;
esac
"$SB_BIN" check -c "$SB_CONF" >/dev/null 2>&1 \
  || die "配置文件校验没通过，请截图发我看看"
info "配置文件校验通过"
fi

# ---------- 11. 开机自启 ----------
if [ "$CORE" = "xray" ]; then
  SVC="xray"; SVC_BIN="$XRAY_BIN"; SVC_ARGS="-config /usr/local/etc/xray/config.json"
else
  SVC="sing-box"; SVC_BIN="$SB_BIN"; SVC_ARGS="run -c /usr/local/etc/sing-box/config.json"
fi
step "[服务] 设置开机自启…"
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/${SVC}.service <<EOF
[Unit]
Description=${SVC} Service
After=network.target
[Service]
Type=simple
User=root
ExecStart=${SVC_BIN} ${SVC_ARGS}
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SVC" >/dev/null 2>&1
  systemctl restart "$SVC" >/dev/null 2>&1
  sleep 1
  if systemctl is-active --quiet "$SVC"; then
    info "$SVC 已启动，并设为开机自启"
  else
    warn "$SVC 好像没起来，运行 systemctl status $SVC 看看原因"
  fi
elif command -v rc-service >/dev/null 2>&1; then
  cat > /etc/init.d/${SVC} <<RCEOF
#!/sbin/openrc-run
name="${SVC}"
description="${SVC} proxy service"
command="${SVC_BIN}"
command_args="${SVC_ARGS}"
command_background="yes"
pidfile="/run/${SVC}.pid"
output_log="/var/log/${SVC}.log"
error_log="/var/log/${SVC}.log"
retry="SIGTERM/5/SIGKILL/5"
depend() { need net; }
start_pre() {
    # 进程已死但 pidfile 还在（比如被 OOM 杀掉），先清理，否则 OpenRC 会误判
    if [ -f "\$pidfile" ]; then
        _ppid=\$(cat "\$pidfile" 2>/dev/null)
        if [ -n "\$_ppid" ] && ! kill -0 "\$_ppid" 2>/dev/null; then
            rm -f "\$pidfile"
        fi
    fi
    checkpath -f -m 0644 -o root:root "\$output_log"
}
RCEOF
  chmod +x /etc/init.d/${SVC}
  rc-update add "$SVC" default >/dev/null 2>&1
  # 先清掉可能残留的旧状态，再启动（比 restart 更稳）
  rc-service "$SVC" zap >/dev/null 2>&1
  rc-service "$SVC" start >/dev/null 2>&1
  sleep 1
  if rc-service "$SVC" status >/dev/null 2>&1; then
    info "$SVC 已启动，并设为开机自启"
  else
    warn "$SVC 好像没起来，运行 rc-service $SVC status 看看原因"
  fi
else
  warn "没找到 systemd/OpenRC，改用后台方式启动（重启后需手动再跑一次脚本）"
  pkill -f "${SVC_BIN} ${SVC_ARGS}" >/dev/null 2>&1
  nohup $SVC_BIN $SVC_ARGS >/var/log/${SVC}.log 2>&1 &
  sleep 1
  info "$SVC 已在后台启动"
fi

# ---------- 11b. 硬检查：端口必须真的在监听 ----------
# 服务显示"已启动"不代表真在工作，端口没监听节点就是坏的，直接报错不忽悠
_SVC_PROTO="tcp"
case "$PROTO" in hy2|tuic) _SVC_PROTO="udp" ;; esac
if wait_for_port "$PORT" "$_SVC_PROTO" 15; then
  info "端口 $PORT/$_SVC_PROTO 已在监听，服务真正跑起来了"
else
  die "服务没能监听端口 $PORT：节点装坏了。请先运行 rc-service $SVC status（或 systemctl status $SVC）看原因，修好再重跑脚本"
fi

# ---------- 12. 放行端口 ----------
step "[网络] 放行端口…"
_FW_PROTO="tcp"
case "$PROTO" in hy2|tuic) _FW_PROTO="udp" ;; esac
# 记下来给 xiezai 用：卸载时把加过的规则原样删掉
mkdir -p /etc/xray-node 2>/dev/null
echo "$PORT $_FW_PROTO" > /etc/xray-node/fw_info
if command -v ufw >/dev/null 2>&1; then
  ufw allow "$PORT"/"$_FW_PROTO" >/dev/null 2>&1 && info "ufw 已放行 $PORT/$_FW_PROTO"
fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$PORT"/"$_FW_PROTO" >/dev/null 2>&1
  firewall-cmd --reload >/dev/null 2>&1 && info "firewalld 已放行 $PORT/$_FW_PROTO"
fi
if command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p "$_FW_PROTO" --dport "$PORT" -j ACCEPT >/dev/null 2>&1 \
    || iptables -I INPUT -p "$_FW_PROTO" --dport "$PORT" -j ACCEPT >/dev/null 2>&1
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
  anytls)
    LINK="anytls://${ANYTLS_PASS}@${LINK_IP}:${PORT}?security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SID}&type=tcp#xray-node"
    PROTO_NAME="AnyTLS + REALITY"
    ;;
  hy2)
    LINK="hysteria2://${HY2_PASS}@${LINK_IP}:${PORT}/?sni=www.samsung.com&insecure=1#xray-node"
    PROTO_NAME="Hysteria2"
    ;;
  tuic)
    LINK="tuic://${UUID}:${TUIC_PASS}@${LINK_IP}:${PORT}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.samsung.com&allow_insecure=1#xray-node"
    PROTO_NAME="TUIC"
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
    anytls)      printf "密码: %s\n" "$ANYTLS_PASS" ;;
    hy2)         printf "密码: %s\n" "$HY2_PASS" ;;
    tuic)        printf "UUID: %s\n" "$UUID"; printf "密码: %s\n" "$TUIC_PASS" ;;
  esac
  case "$PROTO" in
    vless|trojan|anytls) printf "伪装域名: %s\n" "$REALITY_DOMAIN" ;;
    vmess)        printf "WS 路径: %s\n" "$WS_PATH" ;;
    hy2|tuic)     printf "SNI: www.samsung.com（自签证书，客户端已设跳过验证）\n" ;;
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

cat > /usr/local/bin/xiezai <<'XZEOF'
#!/bin/sh
# 输入 xiezai，一键卸载 xray-node：停掉服务，删掉节点和所有相关配置
echo "正在卸载 xray-node…"

# 停掉并移除开机自启（xray / sing-box 都处理）
for _s in xray sing-box; do
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl stop "$_s" >/dev/null 2>&1
    systemctl disable "$_s" >/dev/null 2>&1
    rm -f "/etc/systemd/system/${_s}.service"
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$_s" stop >/dev/null 2>&1
    rc-update del "$_s" default >/dev/null 2>&1
    rm -f "/etc/init.d/${_s}"
  fi
done
[ -d /run/systemd/system ] && systemctl daemon-reload >/dev/null 2>&1
pkill -f "xray -config /usr/local/etc/xray/config.json" >/dev/null 2>&1
pkill -f "sing-box run -c /usr/local/etc/sing-box/config.json" >/dev/null 2>&1
pkill -x xray >/dev/null 2>&1
pkill -x sing-box >/dev/null 2>&1
sleep 1

# 撤销安装时加的防火墙规则（只删我们加过的那条）
if [ -f /etc/xray-node/fw_info ]; then
  read -r _fport _fproto < /etc/xray-node/fw_info
  if [ -n "$_fport" ] && [ -n "$_fproto" ]; then
    if command -v ufw >/dev/null 2>&1; then
      ufw delete allow "$_fport"/"$_fproto" >/dev/null 2>&1
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
      firewall-cmd --permanent --remove-port="$_fport"/"$_fproto" >/dev/null 2>&1
      firewall-cmd --reload >/dev/null 2>&1
    fi
    if command -v iptables >/dev/null 2>&1; then
      while iptables -C INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1; do
        iptables -D INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1
      done
    fi
    echo "已撤销端口 $_fport/$_fproto 的防火墙放行"
  fi
fi

# 只删脚本自己下载安装的内核（our_bins 里记着）；
# 用户机器上本来就有的 xray/sing-box 不碰，避免误删
# 注意：必须在删 /etc/xray-node 之前读
if [ -f /etc/xray-node/our_bins ]; then
  while read -r _b; do
    case "$_b" in
      xray|sing-box) rm -f "/usr/local/bin/$_b" && echo "已删除脚本安装的 $_b" ;;
    esac
  done < /etc/xray-node/our_bins
fi

# 删掉配置、节点、日志
rm -rf /usr/local/etc/xray /usr/local/etc/sing-box /etc/xray-node
rm -f /var/log/xray.log /var/log/sing-box.log

rm -f /usr/local/bin/jiedian
rm -f /usr/local/bin/xiezai

echo "卸载完成：节点、配置、开机自启、防火墙规则都已清除干净。"
XZEOF
chmod +x /usr/local/bin/xiezai
info "已安装 xiezai 命令：输入 xiezai 可一键卸载干净"

# ---------- 14b. BBR 加速：检测，没开就自动开 ----------
step "检查 BBR 加速…"
_BBR_ON=0
if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
  _BBR_ON=1
  info "BBR 已经开启，不用动"
fi
if [ "$_BBR_ON" = "0" ]; then
  # 内核本身支持 BBR：直接 sysctl 打开，立即生效、不用重启、不用下载
  if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    if sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 && \
       sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
      printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-bbr.conf
      sysctl --system >/dev/null 2>&1 || true
      if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
        _BBR_ON=1
        info "BBR 已自动开启（立即生效，已写入开机配置）"
      fi
    fi
    [ "$_BBR_ON" = "0" ] && warn "BBR 开启失败（可能是容器内无权改内核参数），不影响节点使用"
  else
    # 内核太老不支持 BBR：用 teddysun 的 bbr.sh 升级内核来开
    warn "当前内核不支持 BBR，尝试用 bbr.sh 升级内核开启…"
    _bbr_dir="$(mktemp -d 2>/dev/null || echo /tmp)"
    _bbr_host="github.com"
    _bbr_path="/teddysun/across/raw/master/bbr.sh"
    _bbr_url="https://${_bbr_host}${_bbr_path}"
    # wget 默认重试 20 次、单次读超时 900 秒，网络黑洞时会卡十几分钟：必须加超时。
    # 没 wget 就用 curl（前面已保证装好），都不行就跳过，不挡节点安装。
    _bbr_ok=0
    if command -v wget >/dev/null 2>&1; then
      wget --no-check-certificate --timeout=20 --tries=2 -q -O "$_bbr_dir/bbr.sh" "$_bbr_url" 2>/dev/null \
        && [ -s "$_bbr_dir/bbr.sh" ] && _bbr_ok=1
    elif command -v curl >/dev/null 2>&1; then
      curl -fsSL --max-time 40 -o "$_bbr_dir/bbr.sh" "$_bbr_url" 2>/dev/null \
        && [ -s "$_bbr_dir/bbr.sh" ] && _bbr_ok=1
    fi
    if [ "$_bbr_ok" = "1" ]; then
      chmod +x "$_bbr_dir/bbr.sh"
      info "正在运行 bbr.sh，按它的提示操作（完成后可能需要重启）"
      ( cd "$_bbr_dir" && sh ./bbr.sh )
    else
      warn "bbr.sh 下载失败，BBR 没开成，不影响节点使用；以后可手动下载 bbr.sh 运行"
    fi
    rm -rf "$_bbr_dir"
  fi
fi

# ---------- 15. 显示结果 ----------
printf "\n"
cat /etc/xray-node/node.txt
printf "\n${GREEN}${BOLD}安装完成！${NC}把上面那行链接复制到客户端就能用了。\n"
printf "以后看节点输入 jiedian，不想要了输入 xiezai 一键卸载。\n"
