#!/bin/sh
# ============================================================
# xray-node 一键安装脚本（小白版）
#
# 小白用法（root 用户）：
#   1. SSH 连上你的服务器
#   2. 粘贴 README 里的那一行安装命令，回车。
#      没有 curl、也没有 wget 时，这一行会先装上再继续。
#   3. 按提示回答几个问题（看不懂就一路回车用默认），装完自动给你节点链接
#
# 装完之后，想看所有节点随时输入：  jiedian
# 输入 shanjiedian 进入节点管理：查看节点、删除单个节点，或全部卸载
#
# 节点分两种，装的时候先选：
#   永久节点：一直有效
#   定时节点：1 小时、2 小时、6 小时、24 小时、48 小时、72 小时或 1 周
# 同一个菜单里可以关闭或开启 IPv6。关掉之后，这台服务器只通过 IPv4
# 访问网站和 App，效果和没有 IPv6 一样，重启后也保持关闭。
# 定时节点到点后大约一分钟内彻底失效：停服务、作废链接、删配置和防火墙规则。
# 服务器中途重启也不会让它复活。其它节点不动。
#
# ---------------- 名词小词典（看不懂下面的注释先看这里） ----------------
# 节点：你自己的一台“翻墙服务器入口”。手机/电脑上的客户端连上它，再由它替你上网。
# 协议：客户端和服务器之间“说话的方式”，比如 VLESS、VMess、Trojan、Shadowsocks、
#       AnyTLS、Hysteria2、TUIC。不同协议伪装方式、速度、兼容性不一样。
# 内核：真正干活的程序。本脚本按协议自动选：Xray、sing-box 或官方 hysteria。
#       脚本只负责下载它、写好配置、让它开机自己跑起来。
# REALITY：一种伪装技术。别人探测你的服务器时，看到的是一个真实大网站
#       （比如 www.samsung.com）的正常 HTTPS 握手，所以不需要自己买域名和证书。
# UUID / 密码：节点的“钥匙”。随机生成，谁拿到链接谁就能用，不要乱发给别人。
# 分享链接：vless://、hysteria2:// 这种一整行文字，把地址、端口、钥匙都打包在里面，
#       复制到客户端里“从剪贴板导入”就能用，不用一项项手填。
# 端口：服务器上的“门牌号”（1-65535）。节点要占一个空闲端口，别的程序不能同时用。
# 防火墙：服务器上管“哪些门能进”的规则（ufw、firewalld、iptables 都是防火墙工具）。
#       端口不放行，客户端就连不进来。云服务器控制台里的“安全组”是另一层防火墙，
#       脚本改不到，要你自己去控制台放行。
# systemd 服务：Linux 管“后台程序”的系统。把节点注册成服务后，程序挂了会自动拉起，
#       服务器重启后也会自动启动。Alpine 等系统用的是 OpenRC，作用一样。
# 定时节点：到时间后自动彻底删除的节点，适合临时给别人用。
# 节点名：客户端里显示的名字，自动写成“地区+协议”，比如 香港Vless-Reality、美国Hysteria2。
#       地区按服务器公网 IP 查；同名的会在后面加 2、3…
# 端口跳跃：Hysteria2 的客户端在好几个 UDP 端口之间换着连，单个端口被限速或封掉时不容易断。
#       服务器上只有主端口真的在听，其它端口靠 nat 转发过去。
# nat 转发：Linux 防火墙的一项功能，把发到某个端口的包改成发到另一个端口（REDIRECT）。
# 母鸡 / 小鸡：母鸡是独立服务器或开虚拟机的宿主机（比如装了 PVE 的独服）；小鸡是从母鸡上
#       分出来的 VPS（KVM、OpenVZ、LXC、NAT 小鸡等）。KVM 小鸡和母鸡一般都能做端口跳跃；
#       OpenVZ、LXC 小鸡常常没有 nat 转发的权限，脚本会先试，做不了就说明原因并关掉跳跃。
# 混淆（salamander）：Hysteria2 给每个包再加一层“乱码”，让它看起来不像 QUIC。
#       开了以后客户端也必须填同一个混淆密码。
# 拦截 QUIC（阻止 QUIC / block-quic）：QUIC 是走 UDP 443 端口的新版网页协议。代理走 QUIC 常常更慢、
#       更容易断。这是客户端 App 里的开关（服务器上不拦）：打开后浏览器和 App 自动改走普通的 TCP。
#       脚本给 Loon / Surge 生成的节点行已经写好这个开关，粘贴导入后自动打开。
# 镜像 / NAT64：只有 IPv6 的机器连不上只有 IPv4 的 github.com。镜像是“替你转一手”的网站；
#       NAT64 是一种公共 DNS，让 IPv6 机器也能借道访问 IPv4 网站。脚本下载时临时用一下，用完还原。
# 校验值（SHA256）：文件的“指纹”。下载完和官方公布的指纹对一下，一样才说明文件没被改过。
# 巡检：每分钟自动查一次的小程序 xray-node-watch。防火墙服务重启会把端口跳跃的转发规则清掉，
#   它发现少了就自动补回去；用自己的域名申请证书时，它只在申请/续期期间打开 TCP 80（或 443），平时关着。
# WireGuard 落地（wg-luodi）：另一个脚本 VPS-WireGuard-luodi。装了它以后，你指定的端口上的节点
#   上网时用 WireGuard 落地机的 IP，其它端口照旧用服务器自己的 IP。本脚本只在节点启动前叫它一声
#   （wg-luodi hook），没装就什么都不做。
# 所有节点都放在 /etc/xray-node/nodes/<编号>/ 目录里，一个节点一个目录，互不影响。
# ============================================================

# 精简 NAT / LXC / KVM 的 PATH 有时没有 /usr/bin，命令明明装上了也报 not found。
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
export PATH

# ---------- 0. 打印小工具 ----------
# info 绿色 [OK]、warn 黄色 [注意]、err 红色 [出错]；die 打印错误后直接结束脚本。
# step 用来打印每一大步的标题，让你知道脚本做到哪儿了。
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[注意]${NC} %s\n" "$1"; }
err()  { printf "${RED}[出错]${NC} %s\n" "$1"; }
step() { printf "\n${CYAN}${BOLD}%s${NC}\n" "$1"; }
die()  { _dns64_off 2>/dev/null; err "$1"; exit 1; }

# ask：问你一个问题并把回答存进变量。直接回车就用方括号里的默认值。
ask() { # ask "提示文字" "默认值" 变量名
  _p="$1"; _d="$2"; _v="$3"
  if [ -n "$_d" ]; then
    printf "%s [默认 %s]: " "$_p" "$_d"
  else
    printf "%s: " "$_p"
  fi
  # 读失败不能当成回车。输入已经结束时，空答案会被当成默认值，端口和伪装域名就不再问。
  if ! read -r _a; then
    printf "\n" >&2
    die "没有读到你的选择，已停止，没有继续安装。请重新粘贴 README 里的那一行安装命令。"
  fi
  # 只去掉两头的空格。不能去掉数字里的 0，否则公网地址 0.0.0.0 会变成 .0.0.0。
  _a=$(printf '%s' "$_a" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ -z "$_a" ]; then _a="$_d"; fi
  # 不能直接 eval "$_v=$_a"：输入里的 $(...) 或反引号会被执行。
  # 用单引号包裹并转义输入里的单引号，保证原样赋值、什么都不执行。
  _a_esc=$(printf "%s" "$_a" | sed "s/'/'\\\\''/g")
  eval "$_v='$_a_esc'"
}

# 从系统随机数源 /dev/urandom 取随机字节，转成 0-9a-f 的字符串。
# 密码、REALITY 的 shortId、WebSocket 路径都用它生成，别人猜不到。
rand_hex() { # rand_hex 字节数 -> 十六进制串
  od -An -tx1 -N"$1" /dev/urandom 2>/dev/null | tr -d ' \n'
}

# 查某个端口是不是已经有程序在用。两个程序不能同时占同一个端口，
# 所以装节点前要先查，查到被占用就换一个。TCP 和 UDP 的端口是分开算的。
port_in_use() { # port_in_use <端口> <tcp|udp>
  _pi_port="$1"; _pi_proto="$2"
  if command -v ss >/dev/null 2>&1; then
    if [ "$_pi_proto" = "udp" ]; then _pi_list=$(ss -uln 2>/dev/null); else _pi_list=$(ss -ltn 2>/dev/null); fi
  elif command -v netstat >/dev/null 2>&1; then
    if [ "$_pi_proto" = "udp" ]; then _pi_list=$(netstat -uln 2>/dev/null); else _pi_list=$(netstat -ltn 2>/dev/null); fi
  else
    # 与 wait_for_port 一致：极简系统没有 ss/netstat 时从 /proc 查。
    # 以前这里直接 return 2，调用方把“查不了”当成“空闲”，可能选中已被占用的端口；
    # 随后 wait_for_port 的 /proc 回退又会看到别人的监听，误报安装成功。
    _pi_hex=$(printf '%04X' "$_pi_port" 2>/dev/null) || return 2
    if [ "$_pi_proto" = "udp" ]; then
      _pi_files="/proc/net/udp /proc/net/udp6"; _pi_state=07
    else
      _pi_files="/proc/net/tcp /proc/net/tcp6"; _pi_state=0A
    fi
    _pi_checked=0
    for _pi_file in $_pi_files; do
      [ -r "$_pi_file" ] || continue
      _pi_checked=1
      awk -v port="$_pi_hex" -v state="$_pi_state" '
        NR > 1 { split($2, addr, ":"); if (toupper(addr[2]) == port && toupper($4) == state) found = 1 }
        END { exit !found }
      ' "$_pi_file" && return 0
    done
    # /proc 可读且未命中：确认空闲。都读不到才返回 2（未知）。
    [ "$_pi_checked" = "1" ] && return 1
    return 2
  fi
  printf '%s\n' "$_pi_list" | grep -Eq ":${_pi_port}[[:space:]]"
}

# 随机挑一个没人用的端口当默认值。用 20000 以上的高端口，
# 避开 22（SSH）、80/443（网站）这些常用端口，减少冲突。
rand_port() { # rand_port <tcp|udp|both> -> 随机一个空闲端口 20000-59999
  _rp_proto="$1"
  _try=0
  while [ "$_try" -lt 50 ]; do
    _try=$((_try + 1))
    # 用 /dev/urandom 取随机数：awk 的 srand() 在 gawk 等实现里按秒播种，
    # 一秒内连调 50 次会拿到 50 个相同的"随机"端口，重试就形同虚设了
    _p=$(od -An -tu2 -N2 /dev/urandom 2>/dev/null | tr -d ' ')
    if [ -n "$_p" ]; then
      _p=$((20000 + _p % 40000))
    else
      _p=$(awk 'BEGIN{srand(); print int(20000+rand()*40000)}')
    fi
    _used=0
    case "$_rp_proto" in
      tcp|both) port_in_use "$_p" tcp && _used=1 ;;
    esac
    case "$_rp_proto" in
      udp|both) port_in_use "$_p" udp && _used=1 ;;
    esac
    if [ "$_used" -eq 0 ]; then printf "%s" "$_p"; return 0; fi
  done
  return 1
}

# UUID 是一串形如 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx 的随机编号，
# VLESS / VMess / TUIC 用它当“用户身份”，相当于账号密码合在一起。
gen_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    tr 'A-Z' 'a-z' < /proc/sys/kernel/random/uuid | tr -d '\n'
  else
    rand_hex 16 | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/'
  fi
}

# base64 是把任意内容变成只含字母数字的一串字符的编码方式（不是加密）。
# VMess 和 Shadowsocks 的分享链接规定要这样编码，客户端导入时会自动解开。
b64url() { # 标准输入 -> base64url（去换行、去 =）
  base64 2>/dev/null | tr -d '\n' | tr '+/' '-_' | tr -d '='
}

# 找出这台服务器的公网 IP，写进分享链接里。
# 公网 IP 是全世界都能访问到的地址；10.x、192.168.x 这类是“内网地址”，外面连不进来。
# NAT VPS（很多便宜小鸡）网卡上只有内网地址，这时才去问外部网站“我的出口 IP 是多少”。
get_ip() { # get_ip 4|6 -> 打印客户端要连接的地址，失败返回非零
  _v="$1"
  # 链接里的地址是别人连进来用的，取主路由网卡上的公网地址。
  # curl 看到的是出口。L2TP 接通后出口是隧道地址，不能写进节点链接。
  _nic=""
  _ip=""
  if [ "$_v" = "4" ]; then
    _nic=$(ip -4 route show default table main 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')
    # 网卡上可能有好几个地址（内网 + 公网）。逐个看，用第一个公网地址。
    for _ip in $(ip -4 -o addr show dev "$_nic" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}'); do
      _valid_ip 4 "$_ip" || continue
      case "$_ip" in
        10.*|127.*|192.168.*|169.254.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*) ;;
        *) printf "%s" "$_ip"; return 0 ;;
      esac
    done
  else
    _nic=$(ip -6 route show default table main 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')
    # 临时地址（隐私扩展）过一阵就换，写进链接会失效；deprecated 的也跳过。
    for _ip in $(ip -6 -o addr show dev "$_nic" scope global 2>/dev/null | awk '/ temporary/ || / deprecated/ { next } {split($4,a,"/"); print a[1]}'); do
      _valid_ip 6 "$_ip" || continue
      case "$_ip" in
        fe80:*|fc*|fd*|FC*|FD*) ;;
        *) printf "%s" "$_ip"; return 0 ;;
      esac
    done
  fi
  # 网卡是内网地址时，没有 L2TP 就用出口检测得到 NAT 公网地址。
  # L2TP 已接通时出口是隧道地址，交给使用者手填这台机器真实的公网地址。
  if ip -4 addr show dev l2tp-aa 2>/dev/null | grep -q 'inet '; then
    return 1
  fi
  if [ "$_v" = "6" ]; then _f="-6"; else _f="-4"; fi
  for _u in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com"; do
    if command -v curl >/dev/null 2>&1; then
      _ip=$(curl -fsSL --max-time 10 $_f "$_u" 2>/dev/null | tr -d ' \r\n')
    elif command -v wget >/dev/null 2>&1; then
      _ip=$(wget -qO- -T 10 $_f "$_u" 2>/dev/null | tr -d ' \r\n')
    elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx wget; then
      _ip=$(busybox wget -qO- -T 10 $_f "$_u" 2>/dev/null | tr -d ' \r\n')
    else
      _ip=""
    fi
    # 检测网站偶尔返回非 IP 的垃圾（比如限流提示页）：长得不像 IP 就换下一个
    if [ -n "$_ip" ] && _valid_ip "$_v" "$_ip"; then
      printf "%s" "$_ip"; return 0
    fi
  done
  return 1
}

# 检查一串文字长得像不像 IP 地址。手动输错或检测网站返回乱码时，
# 不能把垃圾写进链接，否则“装成功了”却怎么也连不上。
_valid_ip() { # _valid_ip 4|6 <串>：长得像对应版本的 IP 才返回 0
  if [ "$1" = "6" ]; then
    _v6="$2"
    case "$_v6" in
      \[*\]) _v6=${_v6#\[}; _v6=${_v6%\]} ;;
    esac
    # 检测网站失败时可能返回带冒号的网页文字。只要有冒号就当成 IPv6 的话，
    # 节点链接是一串垃圾，安装却显示成功。
    case "$_v6" in
      *[!0-9A-Fa-f:]*) return 1 ;;
      *[0-9A-Fa-f]*) ;;
      *) return 1 ;;
    esac
    case "$_v6" in
      *:*) ;;
      *) return 1 ;;
    esac
    case "$_v6" in *:::*) return 1 ;; esac
    _v6_once=${_v6#*::}
    case "$_v6" in
      *::*) case "$_v6_once" in *::*) return 1 ;; esac ;;
    esac
    # 每一段 1-4 位十六进制。有 :: 时显式段最多 7 段；没有 :: 时必须正好 8 段。
    _v6_ok_side() {
      _vs="$1"
      _vs_n=0
      [ -n "$_vs" ] || return 0
      _vs_rest=$_vs
      while [ -n "$_vs_rest" ]; do
        _vs_g=${_vs_rest%%:*}
        case "$_vs_g" in ''|*[!0-9A-Fa-f]*) return 1 ;; esac
        [ "${#_vs_g}" -le 4 ] || return 1
        _vs_n=$((_vs_n + 1))
        case "$_vs_rest" in
          *:*) _vs_rest=${_vs_rest#*:} ;;
          *) _vs_rest="" ;;
        esac
      done
      return 0
    }
    case "$_v6" in
      *::*)
        _v6_ok_side "${_v6%%::*}" || return 1
        _v6_left_n=$_vs_n
        _v6_ok_side "${_v6#*::}" || return 1
        _v6_total=$((_v6_left_n + _vs_n))
        [ "$_v6_total" -ge 1 ] && [ "$_v6_total" -le 7 ]
        ;;
      *)
        _v6_ok_side "$_v6" || return 1
        [ "$_vs_n" -eq 8 ]
        ;;
    esac
  else
    case "$2" in *:*|''|*[!0-9.]*|.*|*.) return 1 ;; esac
    [ "$(printf "%s" "$2" | tr -cd '.' | wc -c)" -eq 3 ] || return 1
    # 每段必须是 0-255 的数字：之前 999.1.1.1、1.2.3.256 这种也能通过，
    # 手动输错 IP 会直接写进节点链接，节点就废了
    _v4_rest="$2."
    _v4_n=0
    while [ -n "$_v4_rest" ]; do
      _v4_o=${_v4_rest%%.*}; _v4_rest=${_v4_rest#*.}
      _v4_n=$((_v4_n + 1))
      [ "$_v4_n" -gt 4 ] && return 1
      case "$_v4_o" in ''|*[!0-9]*) return 1 ;; esac
      [ "${#_v4_o}" -gt 3 ] && return 1
      # 去掉前导 0 再比大小（"08" 在 sh 算术里会被当成非法八进制）
      _v4_on=$(printf "%s" "$_v4_o" | sed 's/^0*//')
      [ -z "$_v4_on" ] && _v4_on=0
      if [ "$_v4_on" -gt 255 ] 2>/dev/null; then return 1; fi
    done
    [ "$_v4_n" -eq 4 ]
  fi
}

# ---------- 下载工具 ----------
# 各个内核都发布在 GitHub 的 Releases 页面。下面几个函数负责从 GitHub 下载，
# 有 curl 用 curl，没有就用 wget，一条路不通就换另一条。
# gh_api_dl <仓库> <文件名> <输出路径>
# 走 GitHub API 下载 release 文件：api.github.com 比 github.com 稳得多，
# API 返回 302 跳到 release-assets，下得快。成功返回 0，失败返回非零。
gh_api_dl() {
  _gh_repo="$1"; _gh_asset="$2"; _gh_out="$3"
  _gh_rel=$(_http_body "https://api.github.com/repos/${_gh_repo}/releases/latest" 2>/dev/null) || return 1
  [ -n "$_gh_rel" ] || return 1
  _gh_aid=$(printf "%s\n" "$_gh_rel" | grep -B10 -F "\"name\": \"${_gh_asset}\"" | grep '"id"' | tail -1 | grep -o '[0-9][0-9]*' | head -1)
  [ -n "$_gh_aid" ] || return 1
  _http_save "https://api.github.com/repos/${_gh_repo}/releases/assets/${_gh_aid}" "$_gh_out" "Accept: application/octet-stream"
}

# 有 curl 就用 curl；只有 wget（含 busybox wget）就用 wget。两边都没有则失败。
_http_body() { # _http_body [-4|-6] URL -> 正文
  _hb_flag=""
  if [ "$1" = "-4" ] || [ "$1" = "-6" ]; then
    _hb_flag="$1"
    shift
  fi
  _hb_url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 20 --connect-timeout 15 $_hb_flag "$_hb_url"
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- -T 20 $_hb_flag "$_hb_url"
    return $?
  fi
  if command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx wget; then
    busybox wget -qO- -T 20 $_hb_flag "$_hb_url"
    return $?
  fi
  return 127
}

# 小内存机器（64MB 容器）上，刚下载、刚解压的内容会先堆在内存里等着写盘。
# 写盘一慢就把内存上限顶满，系统会随手杀进程，常常杀到你的 SSH / 网页终端，表现为装到一半突然掉线。
# _pace_start 在后台每秒催一次写盘，_pace_stop 停掉它。主脚本退出后它自己也会停。
_PACE_PID=""
_pace_start() {
  [ "$LOW_MEM" = "1" ] || return 0
  [ -z "$_PACE_PID" ] || return 0
  ( while kill -0 "$$" 2>/dev/null; do sync; sleep 1; done ) >/dev/null 2>&1 &
  _PACE_PID=$!
}
_pace_stop() {
  [ -n "$_PACE_PID" ] || return 0
  kill "$_PACE_PID" 2>/dev/null
  wait "$_PACE_PID" 2>/dev/null
  _PACE_PID=""
  sync
}

# _drip_to <文件>：把标准输入写进文件，每写 4MB 就等它真正落盘再写下一段。
# 这样等着写盘的内容最多 4MB，64MB 的机器解压几十 MB 的内核也不会被杀。
# 这台机器的 dd 不认这种写法时返回 1，调用的地方再换老办法。
_drip_to() {
  : > "$1" 2>/dev/null || return 1
  while :; do
    _dt=$(LC_ALL=C dd bs=1048576 count=4 iflag=fullblock conv=fsync 2>&1 >>"$1") || return 1
    case "$_dt" in
      "0+0 records in"*) return 0 ;;
      *"records in"*) ;;
      *) return 1 ;;
    esac
  done
}

# _unpack_drip <zip|tgz> <安装包> <包里的文件> <输出文件>：小内存机器专用，边解压边落盘，直接写到目标位置。
# 成功返回 0；做不了（不是小内存、dd 不支持、大小对不上）返回 1 并删掉半截文件。
_unpack_drip() {
  [ "$LOW_MEM" = "1" ] || return 1
  _ud_want=""
  rm -f "$4"
  case "$1" in
    zip)
      _ud_want=$(unzip -l "$2" "$3" 2>/dev/null | awk -v n="$3" '$NF == n { print $1; exit }')
      unzip -p "$2" "$3" 2>/dev/null | _drip_to "$4"
      ;;
    tgz)
      tar xzOf "$2" "$3" 2>/dev/null | _drip_to "$4"
      ;;
    *) return 1 ;;
  esac
  _ud_rc=$?
  _ud_have=$(wc -c < "$4" 2>/dev/null | tr -d ' ')
  case "$_ud_want" in ''|*[!0-9]*) _ud_want="" ;; esac
  if [ "$_ud_rc" -eq 0 ] && [ -n "$_ud_have" ] && [ "$_ud_have" -ge 1000000 ] \
     && { [ -z "$_ud_want" ] || [ "$_ud_have" = "$_ud_want" ]; }; then
    return 0
  fi
  rm -f "$4"
  return 1
}

# _cp_bin <源> <目标>：拷贝内核文件（几十 MB）。小内存机器上分段落盘，别的机器照常 cp。
_cp_bin() {
  if [ "$LOW_MEM" = "1" ] && _drip_to "$2" < "$1" && chmod 0755 "$2"; then
    return 0
  fi
  _pace_start
  cp -a "$1" "$2"
  _cb_rc=$?
  _pace_stop
  return "$_cb_rc"
}

_http_save() { # _http_save URL 输出文件 [请求头]
  _pace_start
  _http_save_raw "$@"
  _hs_rc=$?
  _pace_stop
  return "$_hs_rc"
}

_http_save_raw() {
  _hs_url="$1"; _hs_out="$2"; _hs_hdr="${3:-}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$_hs_hdr" ]; then
      curl -fSL --progress-bar --connect-timeout 20 --speed-time 30 --speed-limit 1000 --retry 2 --retry-delay 3 \
        -H "$_hs_hdr" -o "$_hs_out" "$_hs_url"
    else
      curl -fSL --progress-bar --connect-timeout 20 --speed-time 30 --speed-limit 1000 --retry 2 --retry-delay 3 \
        -o "$_hs_out" "$_hs_url"
    fi
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    if [ -n "$_hs_hdr" ]; then
      wget -O "$_hs_out" -T 30 --header="$_hs_hdr" "$_hs_url"
    else
      wget -O "$_hs_out" -T 30 "$_hs_url"
    fi
    return $?
  fi
  if command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx wget; then
    busybox wget -O "$_hs_out" -T 30 "$_hs_url"
    return $?
  fi
  return 127
}

# ---------- 下载工具：GitHub 连不上时换镜像、换 NAT64 ----------
# 纯 IPv6 小鸡连不上 github.com（GitHub 没有 IPv6 地址）。按下面的顺序一条条试：
#   1. 直接连 GitHub（API 和 github.com 两条路）
#   2. 有 IPv6 地址的 GitHub 下载镜像（在原地址前面加一段镜像网址）
#   3. 临时把 DNS 换成公共 NAT64/DNS64，让 IPv6 机器也能连上 IPv4 的 GitHub，下载完马上换回去
# 镜像是别人搭的中转站，所以下载完一定对一遍官方公布的 SHA256 校验值，对不上就不装。
GH_MIRRORS="https://v6.gh-proxy.org/ https://gh.llkk.cc/ https://ghproxy.net/"
# 公共 NAT64/DNS64：nat64.net（Kasper Dupont）和 Trex。只在下载时临时用。
DNS64_SERVERS="2a00:1098:2b::1 2a01:4f8:c2c:123f::1 2a00:1098:2c::1 2001:67c:2b0::4"
_DNS64_ON=0
_GH_VIA=""

_no_ipv4_route() {
  command -v ip >/dev/null 2>&1 || return 1
  [ -z "$(ip -4 route show default 2>/dev/null)" ]
}

# 临时换 DNS。/etc/resolv.conf 可能是指向 systemd-resolved 的链接，整个挪开再写新的，换回时原样挪回。
_dns64_on() {
  [ "$_DNS64_ON" = "1" ] && return 0
  _no_ipv4_route || return 1
  [ -e /etc/resolv.conf.xray-node-bak ] && return 1
  if [ -e /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
    mv -f /etc/resolv.conf /etc/resolv.conf.xray-node-bak 2>/dev/null || return 1
  else
    : > /etc/resolv.conf.xray-node-bak.none 2>/dev/null || return 1
  fi
  {
    for _ds in $DNS64_SERVERS; do printf 'nameserver %s\n' "$_ds"; done
  } > /etc/resolv.conf 2>/dev/null || { _DNS64_ON=1; _dns64_off; return 1; }
  _DNS64_ON=1
  trap '_dns64_off; exit 130' INT TERM HUP
  warn "直连和镜像都不通，临时换成公共 NAT64/DNS64 再试（下载完马上换回原来的 DNS）"
  return 0
}

_dns64_off() {
  [ "$_DNS64_ON" = "1" ] || return 0
  if [ -e /etc/resolv.conf.xray-node-bak ] || [ -L /etc/resolv.conf.xray-node-bak ]; then
    rm -f /etc/resolv.conf
    mv -f /etc/resolv.conf.xray-node-bak /etc/resolv.conf 2>/dev/null
  elif [ -e /etc/resolv.conf.xray-node-bak.none ]; then
    rm -f /etc/resolv.conf /etc/resolv.conf.xray-node-bak.none
  fi
  _DNS64_ON=0
  # 换回 DNS 后，Ctrl+C 恢复成“直接退出”。正在装节点时，退出会顺带清理装了一半的节点。
  trap 'exit 130' INT TERM HUP
}

# 上次脚本被强行关掉、DNS 没来得及换回时，这次开头先换回去。
_dns64_recover() {
  if [ -e /etc/resolv.conf.xray-node-bak ] || [ -L /etc/resolv.conf.xray-node-bak ]; then
    _DNS64_ON=1
    _dns64_off
  fi
}

_sha256_of() { # _sha256_of <文件> -> 64 位小写十六进制
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print tolower($1)}'
  elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx sha256sum; then
    busybox sha256sum "$1" 2>/dev/null | awk '{print tolower($1)}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" 2>/dev/null | awk '{print tolower($NF)}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print tolower($1)}'
  fi
}

# _gh_get <github 地址> <输出文件> [先不用的镜像]：直连 -> 镜像。成功时 _GH_VIA 记下走的哪条路。
_gh_get() {
  _gg_url="$1"; _gg_out="$2"; _gg_skip="${3:-}"
  rm -f "$_gg_out"
  if _http_save "$_gg_url" "$_gg_out" && [ -s "$_gg_out" ]; then _GH_VIA=direct; return 0; fi
  rm -f "$_gg_out"
  for _gg_m in $GH_MIRRORS; do
    [ "$_gg_m" = "$_gg_skip" ] && continue
    info "换镜像下载：${_gg_m}"
    if _http_save "${_gg_m}${_gg_url}" "$_gg_out" && [ -s "$_gg_out" ]; then _GH_VIA="$_gg_m"; return 0; fi
    rm -f "$_gg_out"
  done
  if [ -n "$_gg_skip" ]; then
    if _http_save "${_gg_skip}${_gg_url}" "$_gg_out" && [ -s "$_gg_out" ]; then _GH_VIA="$_gg_skip"; return 0; fi
    rm -f "$_gg_out"
  fi
  return 1
}

# _gh_prepare：纯 IPv6 机器先试 GitHub 和镜像通不通，全都不通才临时换 NAT64。
# 必须在主流程里调用（不能放在 $(...) 里）：换 DNS 是改文件，换回也要在同一个进程里做。
_gh_prepare() {
  [ "$_DNS64_ON" = "1" ] && return 0
  _no_ipv4_route || return 0
  _gp_probe="https://github.com/apernet/hysteria/releases/latest/download/hashes.txt"
  _http_body "$_gp_probe" >/dev/null 2>&1 && return 0
  for _gp_m in $GH_MIRRORS; do
    _http_body "${_gp_m}${_gp_probe}" >/dev/null 2>&1 && return 0
  done
  _dns64_on || return 0
  if [ "$_DNS64_ON" = "1" ]; then
    _http_body "$_gp_probe" >/dev/null 2>&1 || warn "换了 NAT64 也连不上 GitHub，还是会继续试"
  fi
  return 0
}

# _gh_text <github 地址>：小文件（校验值、API）直接打印出来。
_gh_text() {
  _gt_tmp="${DL_TMP:-/tmp}/xray-node-gh.$$"
  if _gh_get "$1" "$_gt_tmp" "${2:-}" >/dev/null 2>&1; then
    cat "$_gt_tmp"
    rm -f "$_gt_tmp"
    return 0
  fi
  rm -f "$_gt_tmp"
  return 1
}

# _gh_expect_sum <owner/repo> <tag> <文件名>：从官方发布页取这个文件的 SHA256。
# 下载走了镜像时，校验值优先从别的路取，不全信同一个中转站。
_gh_expect_sum() {
  _ges_repo="$1"; _ges_tag="$2"; _ges_asset="$3"; _ges_avoid="${_GH_VIA:-}"
  case "$_ges_avoid" in direct) _ges_avoid="" ;; esac
  _ges=""
  case "$_ges_repo" in
    apernet/hysteria)
      _ges=$(_gh_text "https://github.com/${_ges_repo}/releases/download/${_ges_tag}/hashes.txt" "$_ges_avoid" \
        | awk -v a="build/${_ges_asset}" '$2 == a || $2 == "./" a || $2 == a ".exe" { print tolower($1); exit }')
      ;;
    XTLS/Xray-core)
      _ges=$(_gh_text "https://github.com/${_ges_repo}/releases/download/${_ges_tag}/${_ges_asset}.dgst" "$_ges_avoid" \
        | sed -n 's/^SHA2-256=[[:space:]]*//p' | head -1 | tr -d ' \r\n' | tr 'A-F' 'a-f')
      ;;
  esac
  if [ -z "$_ges" ]; then
    # GitHub 从 2025 年起在 API 里给每个发布文件附上 sha256（digest 字段）。sing-box 只有这一种来源。
    _ges=$(_gh_text "https://api.github.com/repos/${_ges_repo}/releases/tags/${_ges_tag}" "$_ges_avoid" \
      | tr ',{}' '\n\n\n' | awk -v a="\"${_ges_asset}\"" '
          index($0, "\"name\"") && index($0, a) { hit = 1; next }
          hit && index($0, "\"digest\"") { sub(/.*sha256:/, ""); gsub(/[" \r]/, ""); print tolower($0); exit }
        ')
  fi
  case "$_ges" in
    *[!0-9a-f]*|"") return 1 ;;
  esac
  [ "${#_ges}" -eq 64 ] || return 1
  printf '%s' "$_ges"
}

# _verify_dl <文件> <owner/repo> <tag> <文件名>：校验值对不上就删文件并返回 1。
# 取不到官方校验值时只提醒（后面还会试运行 version，跑不起来一样不装）。
_verify_dl() {
  _vd_want=$(_gh_expect_sum "$2" "$3" "$4") || _vd_want=""
  if [ -z "$_vd_want" ]; then
    warn "没取到官方 SHA256 校验值，改为只检查程序能不能运行（${4}）"
    return 0
  fi
  _vd_have=$(_sha256_of "$1")
  if [ -z "$_vd_have" ]; then
    warn "这台机器没有 sha256sum，跳过校验（${4}）"
    return 0
  fi
  if [ "$_vd_have" != "$_vd_want" ]; then
    rm -f "$1"
    err "下载的 ${4} 和官方校验值对不上（可能是镜像被篡改或下载出错），已删除，不安装。"
    return 1
  fi
  info "SHA256 校验通过：${4}"
  return 0
}

# 全部路都不通时的说明。
_gh_hint() {
  if _no_ipv4_route; then
    printf '%s' "。这台机器没有 IPv4，而 GitHub 只有 IPv4 地址。脚本已经试过 IPv6 镜像和公共 NAT64，都没成功。请先给机器加一个 IPv4 出口（WARP）：运行 wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh ，在菜单里选给 IPv6 only 机器「添加 IPv4 网络接口」的那一项。装好以后重跑这个脚本"
  fi
}

# 下载的安装包先放到硬盘上的临时目录，装完就删。
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

# 卸载时只删脚本自己装的内核。如果你机器上本来就有 xray 等程序（别的服务在用），不能误删。
# mark_our_bin <名字>: 记录这个内核是脚本自己下载安装的，卸载时才删
# （用户机器上本来就有的不删，避免误删）
mark_our_bin() {
  mkdir -p /etc/xray-node 2>/dev/null
  grep -qx "$1" /etc/xray-node/our_bins 2>/dev/null || echo "$1" >> /etc/xray-node/our_bins
}

# 服务启动后要等它真的“开门”（端口进入监听状态）才算成功，最多等几秒。
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
      # 极简系统可能没有 ss/netstat；从内核套接字表检查，不能把“无法检查”当作成功。
      _wp_hex=$(printf '%04X' "$_wp")
      if [ "$_wproto" = "udp" ]; then
        _wp_files="/proc/net/udp /proc/net/udp6"; _wp_state=07
      else
        _wp_files="/proc/net/tcp /proc/net/tcp6"; _wp_state=0A
      fi
      for _wp_file in $_wp_files; do
        [ -r "$_wp_file" ] || continue
        awk -v port="$_wp_hex" -v state="$_wp_state" '
          NR > 1 { split($2, addr, ":"); if (toupper(addr[2]) == port && toupper($4) == state) found = 1 }
          END { exit !found }
        ' "$_wp_file" && return 0
      done
    fi
    sleep 1
    _wtry=$((_wtry + 1))
  done
  return 1
}

# ---------- 防火墙 ----------
# iptables 规则默认只存在内存里，服务器一重启就没了，端口又被挡住。
# 所以要么装 iptables-persistent 把规则存盘，要么用下面这个“开机恢复”小服务，
# 开机时只把本脚本放行过的端口重新放行一遍。
# 小内存机器不装 iptables-persistent。开机只恢复本脚本添加的端口规则，
# 不回放整张 iptables 快照，以免清掉安装后其他程序或用户添加的规则。
_save_fw_light() {
  cat > /usr/local/bin/xray-node-fw-restore <<'FWEOF' || return 1
#!/bin/sh
NODES_DIR=${XRAY_NODE_DIR:-/etc/xray-node/nodes}
_restore_failed=0
for _fw in "$NODES_DIR"/*/fw_info; do
  [ -f "$_fw" ] || continue
  while read -r _port _proto _ufw _fwl _ipt _family; do
    case "$_port" in ''|*[!0-9]*) continue ;; esac
    case "$_proto" in tcp|udp) ;; *) continue ;; esac
    # 旧版两列 fw_info 默认记录脚本添加的规则。
    [ "$_ipt" = "1" ] || [ -z "$_ufw$_fwl$_ipt" ] || continue
    if [ "$_family" = "6" ]; then _bin=ip6tables; else _bin=iptables; fi
    command -v "$_bin" >/dev/null 2>&1 || { _restore_failed=1; continue; }
    "$_bin" -C INPUT -p "$_proto" --dport "$_port" -j ACCEPT >/dev/null 2>&1 ||
      "$_bin" -I INPUT -p "$_proto" --dport "$_port" -j ACCEPT >/dev/null 2>&1 ||
      _restore_failed=1
  done < "$_fw"
done
exit "$_restore_failed"
FWEOF
  chmod 700 /usr/local/bin/xray-node-fw-restore || return 1
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    cat > /etc/systemd/system/xray-node-fw.service <<'FWEOF' || return 1
[Unit]
Description=Restore xray-node firewall rules
After=network-pre.target
Before=network.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/xray-node-fw-restore
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
FWEOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray-node-fw.service >/dev/null 2>&1 || return 1
    rm -f /etc/xray-node/rules.v4 /etc/xray-node/rules.v6
    info "本脚本添加的防火墙规则已设为开机恢复"
    return 0
  fi
  if command -v rc-update >/dev/null 2>&1 && [ -d /etc/init.d ]; then
    cat > /etc/init.d/xray-node-fw <<'FWEOF' || return 1
#!/sbin/openrc-run
description="Restore xray-node firewall rules"
depend() { before net; }
start() {
  /usr/local/bin/xray-node-fw-restore
}
FWEOF
    chmod +x /etc/init.d/xray-node-fw || return 1
    rc-update add xray-node-fw default >/dev/null 2>&1 || return 1
    rm -f /etc/xray-node/rules.v4 /etc/xray-node/rules.v6
    info "本脚本添加的防火墙规则已设为开机恢复"
    return 0
  fi
  warn "防火墙规则这次已加上，但没有开机服务管理器；重启后需手动运行 xray-node-fw-restore"
  return 1
}

# 把刚加的放行规则保存下来，保证重启后还在。
_save_fw() { # _save_fw <4|6>：把刚加的 iptables 规则存盘，重启后还在
  # ufw / firewalld 自己会持久化，不用管；只有纯 iptables 需要手动存。
  # 尽力而为：实在存不了就明确告诉用户，不拦主流程。
  # 小内存机器走轻量存盘，避免 apt 把仅有的几十 MB 内存吃光。
  if [ "$LOW_MEM" = "1" ]; then
    _save_fw_light || warn "防火墙规则没能设为开机恢复，重启后可能需要重新放行端口"
    return 0
  fi
  if [ "$1" = "6" ]; then _fw_svc=ip6tables; _fw_save_bin=ip6tables-save
  else _fw_svc=iptables; _fw_save_bin=iptables-save; fi
  if [ -f /etc/alpine-release ] && [ -f "/etc/init.d/$_fw_svc" ]; then
    # Alpine：IPv4 和 IPv6 分别由对应的 OpenRC 服务恢复
    rc-update add "$_fw_svc" default >/dev/null 2>&1
    if "/etc/init.d/$_fw_svc" save >/dev/null 2>&1; then
      info "iptables 规则已存盘（重启后仍有效）"
    fi
    return 0
  fi
  if command -v netfilter-persistent >/dev/null 2>&1; then
    if netfilter-persistent save >/dev/null 2>&1; then
      info "iptables 规则已存盘（重启后仍有效）"
    fi
    return 0
  fi
  # 装了 ufw 或 firewalld 时不能装 iptables-persistent：ufw 的包声明和它冲突（Breaks），
  # apt -y 会顺手把 ufw 卸掉；firewalld 开机也会和整表回放打架。只恢复本脚本加的端口规则。
  if command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1; then
    _save_fw_light || warn "防火墙规则没能设为开机恢复，重启后可能需要重新放行端口"
    return 0
  fi
  if command -v "$_fw_save_bin" >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    # Debian/Ubuntu：装 iptables-persistent 来存盘（_apt_do 会处理 dpkg 锁占用）
    # DEBIAN_FRONTEND 必须设：iptables-persistent 装时会弹 debconf 提问（是否保存当前规则），
    # 不设的话在小白的终端上会突然蹦出个看不懂的提问，把人卡住
    export DEBIAN_FRONTEND=noninteractive
    if _apt_do "正在安装 iptables-persistent（让防火墙规则重启后还在）" 300 -- install -y -qq iptables-persistent; then
      if command -v netfilter-persistent >/dev/null 2>&1 \
        && netfilter-persistent save >/dev/null 2>&1; then
        info "iptables 规则已存盘（重启后仍有效）"
      fi
    else
      warn "iptables-persistent 没装上：防火墙规则重启后会丢失，重启后重跑一次一键脚本即可恢复"
    fi
    unset DEBIAN_FRONTEND
    return 0
  fi
  warn "这台机器只有纯 iptables 且无法自动存盘：防火墙规则重启后会丢失，重启后重跑一次一键脚本即可恢复"
}

# 放行端口 = 告诉防火墙“这个门牌号允许外面的人进来”。
# 机器上有哪种防火墙工具就用哪种；每条自己加的规则都记到节点的 fw_info 文件里，
# 删节点时只删这些，你自己原来设的规则一条都不动。
# _fw_allow <端口> <tcp|udp> <4|6> <fw_info路径> <1=同时处理 ufw/firewalld>
# ufw 和 firewalld 一条规则同时覆盖 IPv4 和 IPv6，只记一次，删节点时才不会删两次。
# iptables 和 ip6tables 要各记一条。
_fw_allow() {
  _fa_port="$1"; _fa_proto="$2"; _fa_family="$3"; _fa_file="$4"; _fa_front="$5"
  _UFW_ADDED=0; _FWL_ADDED=0; _IPT_ADDED=0
  if [ "$_fa_family" = "6" ]; then _IPT_BIN=ip6tables; else _IPT_BIN=iptables; fi
  if [ "$_fa_front" = "1" ]; then
    if command -v ufw >/dev/null 2>&1; then
      if ufw status 2>/dev/null | grep -qE "^${_fa_port}/${_fa_proto}[[:space:]]"; then
        :
      elif ufw allow "$_fa_port"/"$_fa_proto" >/dev/null 2>&1; then
        _UFW_ADDED=1
        info "ufw 已放行 ${_fa_port}/${_fa_proto}"
      fi
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
      if firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | grep -qx "${_fa_port}/${_fa_proto}"; then
        :
      elif firewall-cmd --permanent --add-port="$_fa_port"/"$_fa_proto" >/dev/null 2>&1 \
        && firewall-cmd --reload >/dev/null 2>&1; then
        _FWL_ADDED=1
        info "firewalld 已放行 ${_fa_port}/${_fa_proto}"
      fi
    fi
  fi
  if command -v "$_IPT_BIN" >/dev/null 2>&1; then
    if "$_IPT_BIN" -C INPUT -p "$_fa_proto" --dport "$_fa_port" -j ACCEPT >/dev/null 2>&1; then
      :
    elif "$_IPT_BIN" -I INPUT -p "$_fa_proto" --dport "$_fa_port" -j ACCEPT >/dev/null 2>&1; then
      _IPT_ADDED=1
    fi
  fi
  if [ -n "$_fa_file" ]; then
    echo "$_fa_port $_fa_proto $_UFW_ADDED $_FWL_ADDED $_IPT_ADDED $_fa_family" >> "$_fa_file"
  fi
}

# ---------- 定时节点：选多久后失效 ----------
# _nft_drop_chains：找出“直接用 nftables 写的、默认拒绝外来连接”的入口链，每行打印“协议族 表 链”。
# iptables（ip/ip6 filter 表）、ufw、firewalld 的规则上面已经处理过，这里不管。
# 这种链会在 iptables 放行之后再拦一次，端口照样不通。
_nft_drop_chains() {
  command -v nft >/dev/null 2>&1 || return 0
  nft list ruleset 2>/dev/null | awk '
    $1 == "table" { fam = $2; tbl = $3 }
    $1 == "chain" { ch = $2 }
    /type filter hook input/ && /policy drop/ {
      if ((fam == "ip" || fam == "ip6") && tbl == "filter") next
      if (tbl == "firewalld") next
      print fam, tbl, ch
    }
  '
}

_set_expire_choice() { # 定时节点菜单编号 -> EXPIRE_AFTER（秒）和 EXPIRE_LABEL
  case "$1" in
    1) EXPIRE_AFTER=3600; EXPIRE_LABEL="1 小时" ;;
    2) EXPIRE_AFTER=7200; EXPIRE_LABEL="2 小时" ;;
    3) EXPIRE_AFTER=21600; EXPIRE_LABEL="6 小时" ;;
    4) EXPIRE_AFTER=86400; EXPIRE_LABEL="24 小时" ;;
    5) EXPIRE_AFTER=172800; EXPIRE_LABEL="48 小时" ;;
    6) EXPIRE_AFTER=259200; EXPIRE_LABEL="72 小时" ;;
    7) EXPIRE_AFTER=604800; EXPIRE_LABEL="1 周" ;;
    *) return 1 ;;
  esac
}

_choose_expire_duration() {
  printf "\n定时节点多久后失效？从安装完成开始算，用的是这台服务器的时间。\n"
  printf "到点后大约一分钟内，这个节点会被彻底删掉：服务停掉，链接作废，配置和防火墙一起清掉。\n"
  printf "服务器中间重启过也一样。其它节点不受影响。\n"
  printf "  1) 1 小时\n"
  printf "  2) 2 小时\n"
  printf "  3) 6 小时\n"
  printf "  4) 24 小时\n"
  printf "  5) 48 小时\n"
  printf "  6) 72 小时\n"
  printf "  7) 1 周（7 天）\n"
  printf "不知道选多久就回车，默认 24 小时。\n"
  ask "请选择" "4" _ed
  if _set_expire_choice "$_ed"; then
    info "种类：定时节点，${EXPIRE_LABEL}后彻底失效"
  else
    warn "没有这个选项，按 24 小时算"
    _set_expire_choice 4
    info "种类：定时节点，${EXPIRE_LABEL}后彻底失效"
  fi
}

# ---------- 节点名：地区 + 协议 ----------
# 分享链接最后 # 后面是节点名，客户端列表里显示的就是它。按“服务器所在地区 + 协议”起名，
# 比如 香港Vless-Reality、美国Hysteria2。地区用公网 IP 查（几个免费查询网站轮流试，每个最多等 6 秒），
# 都查不到就写“未知地区”。同名时在后面加 2、3……
_cc_name() { # _cc_name <两位国家代码> -> 中文地区名，不认识就原样打印代码
  case "$1" in
    HK) echo 香港 ;; TW) echo 台湾 ;; MO) echo 澳门 ;; CN) echo 中国 ;; JP) echo 日本 ;; KR) echo 韩国 ;;
    SG) echo 新加坡 ;; US) echo 美国 ;; CA) echo 加拿大 ;; GB) echo 英国 ;; DE) echo 德国 ;; FR) echo 法国 ;;
    NL) echo 荷兰 ;; RU) echo 俄罗斯 ;; IN) echo 印度 ;; AU) echo 澳大利亚 ;; NZ) echo 新西兰 ;; MY) echo 马来西亚 ;;
    TH) echo 泰国 ;; VN) echo 越南 ;; PH) echo 菲律宾 ;; ID) echo 印度尼西亚 ;; KH) echo 柬埔寨 ;; MN) echo 蒙古 ;;
    TR) echo 土耳其 ;; AE) echo 阿联酋 ;; SA) echo 沙特 ;; IL) echo 以色列 ;; IT) echo 意大利 ;; ES) echo 西班牙 ;;
    PT) echo 葡萄牙 ;; CH) echo 瑞士 ;; AT) echo 奥地利 ;; BE) echo 比利时 ;; SE) echo 瑞典 ;; NO) echo 挪威 ;;
    FI) echo 芬兰 ;; DK) echo 丹麦 ;; PL) echo 波兰 ;; CZ) echo 捷克 ;; UA) echo 乌克兰 ;; IE) echo 爱尔兰 ;;
    LU) echo 卢森堡 ;; RO) echo 罗马尼亚 ;; BG) echo 保加利亚 ;; HU) echo 匈牙利 ;; GR) echo 希腊 ;; LT) echo 立陶宛 ;;
    LV) echo 拉脱维亚 ;; EE) echo 爱沙尼亚 ;; IS) echo 冰岛 ;; MD) echo 摩尔多瓦 ;; RS) echo 塞尔维亚 ;; HR) echo 克罗地亚 ;;
    BR) echo 巴西 ;; AR) echo 阿根廷 ;; CL) echo 智利 ;; MX) echo 墨西哥 ;; CO) echo 哥伦比亚 ;; PE) echo 秘鲁 ;;
    ZA) echo 南非 ;; EG) echo 埃及 ;; NG) echo 尼日利亚 ;; KE) echo 肯尼亚 ;; PK) echo 巴基斯坦 ;; BD) echo 孟加拉 ;;
    KZ) echo 哈萨克斯坦 ;; GE) echo 格鲁吉亚 ;; AM) echo 亚美尼亚 ;; IR) echo 伊朗 ;; QA) echo 卡塔尔 ;; BH) echo 巴林 ;;
    *) echo "$1" ;;
  esac
}

_geo_cc() { # _geo_cc <公网 IP> <4|6> -> 两位国家代码
  _gc_ip="$1"; _gc_f="-$2"
  for _gc_u in "https://ipinfo.io/${_gc_ip}/country" "https://api.ip.sb/geoip/${_gc_ip}" \
               "https://ipwho.is/${_gc_ip}" "http://ip-api.com/line/${_gc_ip}?fields=countryCode" \
               "https://v6.ipinfo.io/${_gc_ip}/country"; do
    _gc_out=""
    if command -v curl >/dev/null 2>&1; then
      _gc_out=$(curl -fsSL --max-time 6 --connect-timeout 4 "$_gc_f" -A "curl/8" "$_gc_u" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
      _gc_out=$(wget -qO- -T 6 "$_gc_u" 2>/dev/null)
    fi
    _gc=$(printf '%s' "$_gc_out" | tr ',{}' '\n\n\n' | awk '
      /"country_code"/ { sub(/.*"country_code"[[:space:]]*:[[:space:]]*"/, ""); sub(/".*/, ""); print; exit }
      /^[A-Za-z][A-Za-z][[:space:]]*$/ { gsub(/[[:space:]]/, ""); print; exit }
    ' | tr 'a-z' 'A-Z')
    case "$_gc" in
      [A-Z][A-Z]) printf '%s' "$_gc"; return 0 ;;
    esac
  done
  return 1
}

_urlenc() { # _urlenc <文字> -> 百分号编码（中文节点名放进链接 # 后面要这样写）
  printf '%s' "$1" | od -An -v -tx1 | tr -s ' \n' '\n\n' | awk '
    $0 == "" { next }
    {
      h = tolower($0)
      d = index("0123456789abcdef", substr(h, 1, 1)) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 17
      if ((d >= 48 && d <= 57) || (d >= 65 && d <= 90) || (d >= 97 && d <= 122) || d == 45 || d == 46 || d == 95 || d == 126)
        printf "%c", d
      else
        printf "%%%s", toupper(h)
    }
  '
}

_node_name() { # _node_name <协议显示名> -> 不和已有节点重名的名字
  _nn_base="${NODE_REGION:-未知地区}$1"
  _nn="$_nn_base"
  _nn_i=1
  while :; do
    _nn_dup=0
    for _nn_f in "${XRAY_NODES_DIR:-/etc/xray-node/nodes}"/*/name; do
      [ -f "$_nn_f" ] || continue
      [ "$(cat "$_nn_f" 2>/dev/null)" = "$_nn" ] && { _nn_dup=1; break; }
    done
    [ "$_nn_dup" = "0" ] && break
    _nn_i=$((_nn_i + 1))
    _nn="${_nn_base}${_nn_i}"
  done
  printf '%s' "$_nn"
}

# ---------- 机器类型：母鸡还是小鸡 ----------
# 母鸡 = 独立服务器/宿主机（上面可能跑着 PVE、KVM 虚拟机）；小鸡 = 从母鸡上分出来的 VPS。
# 小鸡分 KVM（完整虚拟机，什么都能做）、LXC / OpenVZ（容器，内核和宿主共用，常常不给改防火墙 nat 表）。
_virt_kind() { # 打印 none / kvm / lxc / openvz / docker / 其它
  _vk=""
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    _vk=$(systemd-detect-virt -c 2>/dev/null)
    [ "$_vk" = "none" ] && _vk=""
    if [ -z "$_vk" ]; then
      _vk=$(systemd-detect-virt -v 2>/dev/null)
    fi
  fi
  if [ -z "$_vk" ] || [ "$_vk" = "none" ]; then
    if [ -f /proc/user_beancounters ] || { [ -d /proc/vz ] && [ ! -d /proc/bc ]; }; then
      _vk=openvz
    elif grep -qa 'container=lxc' /proc/1/environ 2>/dev/null || [ "$(cat /run/container_type 2>/dev/null)" = "lxc" ]; then
      _vk=lxc
    elif [ -f /.dockerenv ] || grep -qa 'container=docker' /proc/1/environ 2>/dev/null; then
      _vk=docker
    elif grep -q '^flags.* hypervisor' /proc/cpuinfo 2>/dev/null; then
      _vk=kvm
    else
      _vk=none
    fi
  fi
  printf '%s' "$_vk"
}

# 端口跳跃打不开时，用大白话说原因。$1 是系统给的报错原文。
_hop_explain() {
  _he_kind=$(_virt_kind)
  case "$_he_kind" in
    openvz)
      warn "这是 OpenVZ 小鸡。它和宿主机共用内核，服务商一般不给容器做端口转发（nat 表），所以端口跳跃用不了。"
      warn "想用端口跳跃：换 KVM 小鸡，或者问服务商能不能给你的容器打开 iptables nat。"
      ;;
    lxc|lxc-libvirt|systemd-nspawn|docker|podman|container-other|wsl)
      warn "这是 ${_he_kind} 容器。容器用的是宿主机的内核，宿主没把端口转发（nat）权限交给容器，所以端口跳跃用不了。"
      warn "宿主机是你自己的（比如 PVE 母鸡）：在宿主上运行 modprobe nf_nat nft_chain_nat nft_redir，再给这个容器打开 nesting/特权后重试；或者直接在宿主上把这些 UDP 端口转发进来。"
      warn "宿主机是服务商的：问服务商能不能开 nat，或者换 KVM 小鸡。"
      ;;
    *)
      if [ -d /etc/pve ]; then
        warn "这是 PVE 母鸡。PVE 自带防火墙时，请确认内核里有 nf_nat、nft_chain_nat、nft_redir 这几个模块（运行 modprobe 它们）。"
      else
        warn "这台机器的内核没有给端口转发用的 nat 功能，或者防火墙工具（nft / iptables）用不了。"
      fi
      ;;
  esac
  [ -n "$1" ] && warn "系统原话：$(printf '%s' "$1" | cut -c1-300)"
}

# 保证有 nft 或 iptables 其中一个。都没有时先装 nftables（很小），装不上再装 iptables。
_hop_ensure_tool() {
  command -v nft >/dev/null 2>&1 && return 0
  command -v iptables >/dev/null 2>&1 && return 0
  _have_pkgman || return 1
  _pkg_add "正在安装 nftables（端口跳跃要用它做转发）" nftables
  hash -r 2>/dev/null || true
  command -v nft >/dev/null 2>&1 && return 0
  _pkg_add "nftables 没装上，改装 iptables" iptables
  hash -r 2>/dev/null || true
  command -v nft >/dev/null 2>&1 || command -v iptables >/dev/null 2>&1
}

# 正式问端口之前先试一次：建一张临时转发表，马上删掉。做不了就不浪费你的时间去填端口。
_hy_hop_probe() { # _hy_hop_probe <4|6|46>
  install_hop_bin || { warn "端口跳跃小程序没写进去"; return 1; }
  if ! _hop_ensure_tool; then
    _hop_explain "没有 nft，也没有 iptables，而且装不上"
    return 1
  fi
  _hp_err=$(XRAY_HOP_PROBE_FAMILY="$1" /usr/local/bin/xray-node-hop probe 2>&1 >/dev/null)
  _hp_rc=$?
  if [ "$_hp_rc" -ne 0 ]; then
    _hop_explain "$_hp_err"
    return 1
  fi
  return 0
}

# ---------- 端口跳跃小程序 xray-node-hop ----------
# 端口跳跃 = 客户端在好几个 UDP 端口之间换着连，服务器上只有主端口真的在听。
# 其它“跳跃端口”收到的包，要靠 Linux 防火墙的 nat 转发（REDIRECT）转给主端口。
# 以前把跳跃端口写进 Hysteria2 的 listen，让它自己写防火墙。它会把端口从小到大排序，
# 拿最小的那个当主端口去听。主端口不是最小的时，脚本等的主端口永远没人听，
# 于是误报“这台机器做不了转发”。现在 Hysteria2 只听主端口，转发由下面这个小程序管：
#   1. 先用 nftables 的 inet 表（一张表同时管 IPv4 和 IPv6）
#   2. 老内核不支持 inet 的 nat，就分成 ip 表和 ip6 表
#   3. 没有 nft 或 nft 写不进去，再用 iptables / ip6tables
# 只转发“发给本机”的包（fib daddr type local / addrtype LOCAL）。
# 母鸡（宿主机）上跑着虚拟机时，发给虚拟机的同号端口不会被抢走。
# 服务启动前自动打开，服务停止后自动拆掉；重启服务器后跟着服务一起回来。
install_hop_bin() { # 写出 /usr/local/bin/xray-node-hop。重复运行只覆盖脚本。
  _hb_dir=${XRAY_BIN_DIR:-/usr/local/bin}
  mkdir -p "$_hb_dir" 2>/dev/null || return 1
  cat > "$_hb_dir/xray-node-hop" <<'HOPEOF' || return 1
#!/bin/sh
# 端口跳跃转发：把跳跃端口收到的 UDP 包转给节点的主端口。
#   xray-node-hop up <编号>     打开转发（节点服务启动前自动调用）
#   xray-node-hop down <编号>   拆掉转发（节点服务停止后、删节点时自动调用）
#   xray-node-hop check <编号>  规则真的在系统里就返回 0，并打印用的是哪种方式
#   xray-node-hop probe        试一下这台机器能不能做转发，试完马上拆掉，不留规则
# 节点目录里的 hop 文件：main=主端口  ports=跳跃端口(逗号分隔，可写 20000-20010)  family=4/6/46
PATH="${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
NODES_DIR=${XRAY_NODE_DIR:-/etc/xray-node/nodes}
STATE_DIR=${XRAY_HOP_STATE:-/run/xray-node-hop}
act=$1
id=$2
[ "$act" = "probe" ] && id=probe
case "$id" in
  probe) ;;
  ''|*[!0-9]*) echo "节点编号不对：$id" >&2; exit 2 ;;
esac
TABLE="xray_node_hop_$id"
CHAIN="XRAY-NODE-HOP-$id"
ERRF="${TMPDIR:-/tmp}/xray-node-hop.$$.err"
trap 'rm -f "$ERRF"' EXIT

_load() {
  main=""; ports=""; family=46
  if [ "$id" = "probe" ]; then
    main=2; ports=1; family=${XRAY_HOP_PROBE_FAMILY:-46}
    return 0
  fi
  [ -f "$NODES_DIR/$id/hop" ] || return 1
  while IFS='=' read -r _k _v; do
    case "$_k" in
      main) main=$_v ;;
      ports) ports=$_v ;;
      family) family=$_v ;;
    esac
  done < "$NODES_DIR/$id/hop"
  case "$main" in ''|*[!0-9]*) return 1 ;; esac
  case "$ports" in ''|*[!0-9,-]*) return 1 ;; esac
  case "$family" in 4|6|46) ;; *) family=46 ;; esac
  return 0
}

# 有的内核不会自动加载 nat 模块。能加载就先加载，加载不了（容器里常见）也继续试。
_mods() {
  _mp=${XRAY_HOP_MODPROBE:-modprobe}
  command -v "$_mp" >/dev/null 2>&1 || return 0
  for _m in "$@"; do "$_mp" -q "$_m" >/dev/null 2>&1 || true; done
}

# 这台机器在帮别人转发（母鸡、软路由）时，必须只转“发给本机”的包。
_forwarding() {
  [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ] && return 0
  [ "$(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null)" = "1" ] && return 0
  return 1
}

_nft_rules() { # _nft_rules <inet|ip|ip6> <1=只转发给本机的包>
  printf 'table %s %s {\n  chain prerouting {\n    type nat hook prerouting priority -100; policy accept;\n' "$1" "$TABLE"
  _nr_pre=""
  if [ "$1" = "inet" ]; then
    case "$family" in
      4) _nr_pre="meta nfproto ipv4 " ;;
      6) _nr_pre="meta nfproto ipv6 " ;;
    esac
  fi
  [ "$2" = "1" ] && _nr_pre="${_nr_pre}fib daddr type local "
  for _p in $(printf '%s' "$ports" | tr ',' ' '); do
    printf '    %sudp dport %s counter redirect to :%s\n' "$_nr_pre" "$_p" "$main"
  done
  printf '  }\n}\n'
}

_nft_apply() { # _nft_apply <inet|ip|ip6> <1|0>：先删同名旧表再整张写入，重复运行不会叠规则
  { printf 'table %s %s {}\ndelete table %s %s\n' "$1" "$TABLE" "$1" "$TABLE"; _nft_rules "$1" "$2"; } \
    | nft -f - 2>>"$ERRF"
}

_nft_del() {
  command -v nft >/dev/null 2>&1 || return 0
  for _f in inet ip ip6; do
    nft delete table "$_f" "$TABLE" >/dev/null 2>&1 || true
  done
}

_ipt_del() { # _ipt_del <iptables|ip6tables>：拆掉本节点的跳转规则和自建链
  _ib=$1
  command -v "$_ib" >/dev/null 2>&1 || return 0
  "$_ib" -w -t nat -S PREROUTING 2>/dev/null | grep -- "-j ${CHAIN}\$" | sed 's/^-A //' | while read -r _line; do
    set -f
    # shellcheck disable=SC2086
    set -- $_line
    set +f
    "$_ib" -w -t nat -D "$@" >/dev/null 2>&1 || true
  done
  "$_ib" -w -t nat -F "$CHAIN" >/dev/null 2>&1 || true
  "$_ib" -w -t nat -X "$CHAIN" >/dev/null 2>&1 || true
}

_ipt_apply() { # _ipt_apply <iptables|ip6tables> <1|0>
  command -v "$1" >/dev/null 2>&1 || { echo "没有 $1" >>"$ERRF"; return 1; }
  _ipt_del "$1"
  "$1" -w -t nat -N "$CHAIN" 2>>"$ERRF" || return 1
  "$1" -w -t nat -A "$CHAIN" -p udp -j REDIRECT --to-ports "$main" 2>>"$ERRF" || { _ipt_del "$1"; return 1; }
  for _p in $(printf '%s' "$ports" | tr ',' ' '); do
    _pp=$(printf '%s' "$_p" | tr '-' ':')
    if [ "$2" = "1" ]; then
      "$1" -w -t nat -A PREROUTING -p udp -m addrtype --dst-type LOCAL --dport "$_pp" -j "$CHAIN" 2>>"$ERRF" \
        || { _ipt_del "$1"; return 1; }
    else
      "$1" -w -t nat -A PREROUTING -p udp --dport "$_pp" -j "$CHAIN" 2>>"$ERRF" \
        || { _ipt_del "$1"; return 1; }
    fi
  done
  return 0
}

# 服务启动时的 up 和巡检时的 up 可能同时发生，排队一个一个来，免得 iptables 规则加重
_lock() {
  command -v flock >/dev/null 2>&1 || return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  exec 9>"$STATE_DIR/.lock" || return 0
  # busybox 的 flock 没有 -w（限时等待），所以自己数：最多等 20 秒，等不到也照常干活
  _lk=0
  while ! flock -n 9 2>/dev/null; do
    _lk=$((_lk + 1))
    [ "$_lk" -ge 20 ] && break
    sleep 1
  done
}

_down_all() {
  _nft_del
  _ipt_del iptables
  _ipt_del ip6tables
  rm -f "$STATE_DIR/$id"
}

# 依次尝试。成功时 got 记下方式和真正打开的地址族。
_up() {
  got=""
  : > "$ERRF"
  _mods nf_tables nf_nat nft_chain_nat nft_redir nft_fib nft_fib_inet nft_fib_ipv4 nft_fib_ipv6 \
    nft_chain_nat_ipv4 nft_chain_nat_ipv6 nft_redir_ipv4 nft_redir_ipv6 \
    iptable_nat ip6table_nat xt_REDIRECT xt_addrtype
  _locs=1
  _forwarding || _locs="1 0"
  for _loc in $_locs; do
    if command -v nft >/dev/null 2>&1; then
      if _nft_apply inet "$_loc"; then got="nft-inet $family"; return 0; fi
      _nft_del
      _g4=0; _g6=0
      case "$family" in *4*) _nft_apply ip "$_loc" && _g4=1 ;; esac
      case "$family" in *6*) _nft_apply ip6 "$_loc" && _g6=1 ;; esac
      if [ "$family" = "46" ] && [ "$_g4$_g6" = "11" ]; then got="nft 46"; return 0; fi
      if [ "$family" = "4" ] && [ "$_g4" = "1" ]; then got="nft 4"; return 0; fi
      if [ "$family" = "6" ] && [ "$_g6" = "1" ]; then got="nft 6"; return 0; fi
      if [ "$family" = "46" ] && [ "$_g4" = "1" ]; then got="nft 4"; return 0; fi
      if [ "$family" = "46" ] && [ "$_g6" = "1" ]; then got="nft 6"; return 0; fi
      _nft_del
    fi
    _g4=0; _g6=0
    case "$family" in *4*) _ipt_apply iptables "$_loc" && _g4=1 ;; esac
    case "$family" in *6*) _ipt_apply ip6tables "$_loc" && _g6=1 ;; esac
    if [ "$_g4$_g6" = "11" ]; then got="iptables 46"; return 0; fi
    if [ "$_g4" = "1" ]; then got="iptables 4"; return 0; fi
    if [ "$_g6" = "1" ]; then got="iptables 6"; return 0; fi
    _ipt_del iptables
    _ipt_del ip6tables
  done
  return 1
}

_check() {
  if command -v nft >/dev/null 2>&1; then
    for _f in inet ip ip6; do
      nft list table "$_f" "$TABLE" 2>/dev/null | grep -q "redirect to :$main" && return 0
    done
  fi
  for _b in iptables ip6tables; do
    command -v "$_b" >/dev/null 2>&1 || continue
    "$_b" -w -t nat -S PREROUTING 2>/dev/null | grep -q -- "-j ${CHAIN}\$" \
      && "$_b" -w -t nat -S "$CHAIN" 2>/dev/null | grep -q -- "--to-ports $main" && return 0
  done
  return 1
}

case "$act" in
  up)
    _lock
    _load || { _down_all; exit 0; }
    _down_all
    if _up; then
      mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$got" > "$STATE_DIR/$id"
      echo "端口跳跃已打开：$got"
      exit 0
    fi
    echo "端口跳跃没打开。系统说：$(tr '\n' ' ' < "$ERRF" | cut -c1-400)" >&2
    exit 1
    ;;
  down)
    _lock
    _down_all
    exit 0
    ;;
  check)
    _load || exit 1
    _check || exit 1
    cat "$STATE_DIR/$id" 2>/dev/null || echo "规则在"
    exit 0
    ;;
  probe)
    _lock
    _load
    _down_all
    if _up; then
      _down_all
      echo "$got"
      exit 0
    fi
    _down_all
    tr '\n' ' ' < "$ERRF" | cut -c1-400 >&2
    exit 1
    ;;
esac
echo "用法：xray-node-hop up|down|check <节点编号>，或 xray-node-hop probe" >&2
exit 2
HOPEOF
  chmod 700 "$_hb_dir/xray-node-hop" || return 1
}

# ---------- 回程路由小程序 xray-node-route ----------
# 有的机器上装了“策略路由”（比如 L2TP、WireGuard 等 VPN 一键脚本），会把本机发出去、
# 又没打标记的流量默认送进 VPN 网卡。TCP 节点不受影响：连接建好以后，回包的源地址是固定的。
# UDP 节点（Hysteria2、TUIC，还有 Shadowsocks 的 UDP）就不一样了：每个回包都要系统现查一次路由，
# 结果回包从 VPN 网卡、用 VPN 的地址发了出去，客户端根本认不出来，节点就连不上。
# 这个小程序发现这种情况时，给节点加一条只管自己的规则：
#   本机从节点端口发出的 UDP 包，走公网网卡所在的路由表（通常是 main）。
# 端口跳跃的包进来时已经被改成发往主端口，所以这一条规则把跳跃端口的回包也一起管上了。
# 规则在节点启动时加、停掉时拆，巡检每分钟看一次（VPN 晚于节点启动时也能补上）。
# 需要 Linux 4.17 以上的内核（按端口分流是从这一版开始有的）。
install_route_bin() { # 写出 /usr/local/bin/xray-node-route。重复运行只覆盖脚本。
  _rb_dir=${XRAY_BIN_DIR:-/usr/local/bin}
  mkdir -p "$_rb_dir" 2>/dev/null || return 1
  # 先写到临时文件再换上去：正在跑的旧脚本不会读到写了一半的内容
  cat > "$_rb_dir/xray-node-route.tmp" <<'ROUTEEOF' || return 1
#!/bin/sh
# UDP 节点的回程路由。用法：
#   xray-node-route up <编号>     需要就加上回程规则，不需要就拆掉（节点启动前、巡检时自动调用）
#   xray-node-route down <编号>   拆掉（节点停止后、删节点时自动调用）
#   xray-node-route check <编号>  系统里的规则和现在需要的一样就返回 0（巡检用）
#   xray-node-route show <编号>   用大白话说一下这个节点加了哪些规则
#   xray-node-route need          有 UDP 节点、机器上又有策略路由时返回 0（决定要不要挂巡检）
PATH="${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
NODES_DIR=${XRAY_NODE_DIR:-/etc/xray-node/nodes}
STATE_DIR=${XRAY_ROUTE_STATE:-/run/xray-node-route}
# 用这两个公网地址问系统“包会从哪张网卡出去”。只是查路由表，不会真的发包。
PROBE4=${XRAY_ROUTE_PROBE4:-1.1.1.1}
PROBE6=${XRAY_ROUTE_PROBE6:-2606:4700:4700::1111}
# 规则优先级从 8890 往下找空位，而且一定排在机器上别的策略路由规则前面（数字越小越先看）
PREF_TOP=${XRAY_ROUTE_PREF:-8890}
act=$1
id=$2
case "$act" in
  need) ;;
  *) case "$id" in ''|*[!0-9]*) echo "节点编号不对：$id" >&2; exit 2 ;; esac ;;
esac
ERRF="${TMPDIR:-/tmp}/xray-node-route.$$.err"
trap 'rm -f "$ERRF"' EXIT

_kw() { # _kw <关键字> <一行 ip 输出>：打印关键字后面的那个词，比如 dev 后面的网卡名
  printf '%s\n' "$2" | awk -v k="$1" '{ for (i = 1; i < NF; i++) if ($i == k) { print $(i + 1); exit } }'
}

_is_udp_node() { # 只有 UDP 节点才需要：Hysteria2、TUIC、Shadowsocks
  _d="$NODES_DIR/$id"
  core=$(tr -d ' \r\n' < "$_d/core" 2>/dev/null)
  case "$core" in
    hysteria) [ -f "$_d/config.yaml" ] ;;
    sing-box) grep -q '"type": *"tuic"' "$_d/config.json" 2>/dev/null ;;
    xray) grep -q '"protocol": *"shadowsocks"' "$_d/config.json" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

_listen() { # 打印配置里的监听地址（去掉引号）
  if [ "$core" = "hysteria" ]; then
    sed -n 's/^listen:[[:space:]]*//p' "$NODES_DIR/$id/config.yaml" 2>/dev/null | head -1 | tr -d "\"' \r"
  else
    sed -n 's/.*"listen":[[:space:]]*"\([^"]*\)".*/\1/p' "$NODES_DIR/$id/config.json" 2>/dev/null | head -1
  fi
}

_load() { # 读出 UDP 主端口 port 和要管的地址族 fams
  port=$(awk '$2 == "udp" && $1 ~ /^[0-9]+$/ { print $1; exit }' "$NODES_DIR/$id/fw_info" 2>/dev/null)
  _ll=$(_listen)
  if [ -z "$port" ]; then
    if [ "$core" = "hysteria" ]; then
      _lp=${_ll%%,*}; port=${_lp##*:}
    else
      port=$(sed -n 's/.*"\(listen_\)\{0,1\}port":[[:space:]]*\([0-9][0-9]*\).*/\2/p' "$NODES_DIR/$id/config.json" 2>/dev/null | head -1)
    fi
  fi
  case "$port" in ''|*[!0-9]*) return 1 ;; esac
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
  # 只听 IPv4 的节点只管 IPv4；听 IPv6 或全部地址的两种都管
  case "$_ll" in
    0.0.0.0*|[0-9]*.*) fams=4 ;;
    *) fams="4 6" ;;
  esac
  return 0
}

_node_addrs() { # _node_addrs <4|6>：node.txt 里写给客户端的地址
  sed -n 's/^[^:：]*地址[^:：]*:[[:space:]]*//p' "$NODES_DIR/$id/node.txt" 2>/dev/null | tr -d '[] \r' |
    while read -r _a; do
      case "$1:$_a" in
        4:*.*.*.*) case "$_a" in *[!0-9.]*) ;; *) printf '%s\n' "$_a" ;; esac ;;
        6:*:*) case "$_a" in *[!0-9a-fA-F:]*) ;; *) printf '%s\n' "$_a" ;; esac ;;
      esac
    done
}

_dev_of_addr() { # _dev_of_addr <4|6> <地址>：这个地址在哪张网卡上（不在本机就什么都不打印）
  ip -o "-$1" addr show 2>/dev/null | awk -v a="$2" '{ split($4, p, "/"); if (tolower(p[1]) == tolower(a)) { print $2; exit } }'
}

_dev_has() { # _dev_has <4|6> <网卡> <地址>：网卡上有这个地址就返回 0
  ip -o "-$1" addr show dev "$2" 2>/dev/null | awk -v a="$3" '{ split($4, p, "/"); if (tolower(p[1]) == tolower(a)) f = 1 } END { exit !f }'
}

_main_dev() { # main 路由表里默认路由的网卡
  _kw dev "$(ip "-$1" route show table main default 2>/dev/null | head -1)"
}

_table_for() { # _table_for <4|6> <网卡>：哪张路由表的默认路由走这张网卡（优先 main）
  if [ "$(_main_dev "$1")" = "$2" ]; then echo main; return 0; fi
  ip "-$1" route show table all default 2>/dev/null | awk -v d="$2" '
    { dv = ""; t = ""
      for (i = 1; i < NF; i++) { if ($i == "dev") dv = $(i + 1); if ($i == "table") t = $(i + 1) }
      if (dv == d && t != "" && t != "local") { print t; exit } }'
}

# _want <4|6>：要不要加规则。要加返回 0，并给出 want_dev（该走的网卡）和 want_table（查哪张表）。
# 不用加返回 1；看出来回包走错了、却找不到能走公网网卡的路由表，返回 2。
_want() {
  want_dev=""; want_table=""; nat_dev=""; nat_src=""
  if [ "$1" = "6" ]; then _probe=$PROBE6; else _probe=$PROBE4; fi
  # 公网网卡：写给客户端的地址在哪张网卡上；地址不在本机（云服务器的 NAT）就看 main 表的默认路由
  for _a in $(_node_addrs "$1"); do
    want_dev=$(_dev_of_addr "$1" "$_a")
    [ -n "$want_dev" ] && break
  done
  [ -n "$want_dev" ] || want_dev=$(_main_dev "$1")
  [ -n "$want_dev" ] || return 1
  # 不带端口问一次：这是没有我们这条规则时，回包本来会走的路
  _nat=$(ip "-$1" route get "$_probe" 2>/dev/null | head -1)
  [ -n "$_nat" ] || return 1
  nat_dev=$(_kw dev "$_nat")
  nat_src=$(_kw src "$_nat")
  if [ "$nat_dev" = "$want_dev" ]; then
    [ -z "$nat_src" ] && return 1
    _dev_has "$1" "$want_dev" "$nat_src" && return 1
  fi
  want_table=$(_table_for "$1" "$want_dev")
  [ -n "$want_table" ] || return 2
  return 0
}

_ours() { # _ours <4|6>：打印我们给这个端口加的规则，每行“优先级 路由表”
  ip "-$1" rule show 2>/dev/null | awk -v p="$port" '
    $0 ~ ("iif lo ipproto (udp|17) sport " p " lookup ") {
      pr = $1; sub(":", "", pr); t = ""
      for (i = 1; i < NF; i++) if ($i == "lookup") t = $(i + 1)
      print pr, t }'
}

_del_ours() { # 只删“iif lo ipproto udp sport 本端口”这种我们自己的规则，你手动加的不碰
  _do_n=0
  for _pr in $(_ours "$1" | awk '{ print $1 }'); do
    ip "-$1" rule del pref "$_pr" iif lo ipproto udp sport "$port" >/dev/null 2>&1 || true
    _do_n=$((_do_n + 1))
    [ "$_do_n" -ge 20 ] && break
  done
}

_pick_pref() { # 找一个空着的优先级：不超过 8890，并且比机器上别的策略路由规则都小
  ip "-$1" rule show 2>/dev/null | awk -v top="$PREF_TOP" '
    { pr = $1; sub(":", "", pr); pr += 0; used[pr] = 1
      if (pr == 0 || pr >= 32766) next
      if ($0 ~ /iif lo ipproto (udp|17) sport [0-9]+ lookup /) next
      if (min == "" || pr < min) min = pr }
    END { c = top; if (min != "" && min - 1 < c) c = min - 1
          while (c > 0 && (c in used)) c--
          print c }'
}

_state_get() { # _state_get <4|6>：状态文件里这个地址族的那一行
  awk -v f="$1" '$1 == f { print; exit }' "$STATE_DIR/$id" 2>/dev/null
}

_state_put() { # _state_put <4|6> <其余字段…>
  _sf=$1; shift
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  { awk -v f="$_sf" '$1 != f' "$STATE_DIR/$id" 2>/dev/null; printf '%s %s\n' "$_sf" "$*"; } > "$STATE_DIR/$id.tmp" &&
    mv -f "$STATE_DIR/$id.tmp" "$STATE_DIR/$id"
}

# _sync <4|6> <check|up>：check 只比较，up 把系统改成需要的样子
_sync() {
  _f=$1
  _cur=$(_ours "$_f")
  _cnt=$(printf '%s' "$_cur" | grep -c .)
  _want "$_f"; _w=$?
  if [ "$_w" = "0" ]; then
    if [ "$_cnt" = "1" ] && [ "${_cur#* }" = "$want_table" ]; then
      [ "$2" = "up" ] && _state_put "$_f" ok "${_cur%% *}" "$want_table" "$want_dev" "$port" "$nat_dev"
      return 0
    fi
    # 内核太老加不上：记下来，巡检不再每分钟重试
    if [ "$_cnt" = "0" ] && [ "$(_state_get "$_f" | awk '{ print $2 }')" = "old" ]; then return 0; fi
    [ "$2" = "check" ] && return 1
    _del_ours "$_f"
    _pref=$(_pick_pref "$_f")
    case "$_pref" in ''|*[!0-9]*|0) _state_put "$_f" fail - - "$want_dev" "$port" "$nat_dev"; return 1 ;; esac
    if ! ip "-$_f" rule add pref "$_pref" iif lo ipproto udp sport "$port" lookup "$want_table" 2>"$ERRF"; then
      # Linux 4.17 以前的内核（或很老的 ip 命令）不认 ipproto / sport
      _state_put "$_f" old - - "$want_dev" "$port" "$nat_dev"
      return 3
    fi
    # 加完再问一次系统，确认从这个端口发的 UDP 真的改走公网网卡了；没改过来就拆掉，不留没用的规则
    if [ "$_f" = "6" ]; then _probe=$PROBE6; else _probe=$PROBE4; fi
    _got=$(_kw dev "$(ip "-$_f" route get "$_probe" ipproto udp sport "$port" 2>/dev/null | head -1)")
    if [ "$_got" != "$want_dev" ]; then
      _del_ours "$_f"
      _state_put "$_f" fail - "$want_table" "$want_dev" "$port" "$nat_dev"
      return 1
    fi
    _state_put "$_f" ok "$_pref" "$want_table" "$want_dev" "$port" "$nat_dev"
    return 0
  fi
  if [ "$_w" = "2" ]; then
    [ "$2" = "up" ] && _state_put "$_f" notable - - "$want_dev" "$port" "$nat_dev"
  fi
  # 不需要规则：有就拆掉
  if [ "$_cnt" != "0" ]; then
    [ "$2" = "check" ] && return 1
    _del_ours "$_f"
  fi
  [ "$2" = "up" ] && [ "$_w" = "1" ] && _state_put "$_f" none
  return 0
}

_lock() { # 节点启动和巡检可能同时来，排队一个一个改
  command -v flock >/dev/null 2>&1 || return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  exec 9>"$STATE_DIR/.lock" || return 0
  _lk=0
  while ! flock -n 9 2>/dev/null; do
    _lk=$((_lk + 1))
    [ "$_lk" -ge 20 ] && break
    sleep 1
  done
}

_down() { # 端口优先用状态文件里记的（节点目录可能已经删了）
  port=$(awk 'NF >= 6 && $6 ~ /^[0-9]+$/ { print $6; exit }' "$STATE_DIR/$id" 2>/dev/null)
  if [ -z "$port" ]; then
    _is_udp_node || true
    _load || port=""
  fi
  if [ -n "$port" ]; then
    _del_ours 4
    _del_ours 6
  fi
  rm -f "$STATE_DIR/$id"
}

_has_policy() { # 机器上除了系统默认的三条规则，还有别的策略路由规则吗
  for _hf in 4 6; do
    ip "-$_hf" rule show 2>/dev/null | awk '{ pr = $1; sub(":", "", pr); if (pr != "0" && pr != "32766" && pr != "32767") f = 1 } END { exit !f }' && return 0
  done
  return 1
}

command -v ip >/dev/null 2>&1 || { [ "$act" = "need" ] && exit 1; exit 0; }
case "$act" in
  up)
    _lock
    if ! _is_udp_node || ! _load; then _down; exit 0; fi
    _rc=0
    for _f in 4 6; do
      case " $fams " in
        *" $_f "*) _sync "$_f" up || _rc=$? ;;
        *) _del_ours "$_f"; _state_put "$_f" none ;;
      esac
    done
    exit "$_rc"
    ;;
  down)
    _lock
    _down
    exit 0
    ;;
  check)
    if ! _is_udp_node || ! _load; then
      [ -f "$STATE_DIR/$id" ] && exit 1
      exit 0
    fi
    for _f in $fams; do _sync "$_f" check || exit 1; done
    exit 0
    ;;
  show)
    [ -f "$STATE_DIR/$id" ] || exit 0
    while read -r _f _st _pr _tb _dv _pt _nd; do
      if [ "$_f" = "6" ]; then _fn=IPv6; else _fn=IPv4; fi
      case "$_st" in
        ok) echo "${_fn}：回包本来会从 ${_nd} 发出去，已加规则让 UDP ${_pt} 的回包走 ${_dv}（规则优先级 ${_pr}，查路由表 ${_tb}）" ;;
        old) echo "${_fn}：回包会从 ${_nd} 发出去（应该走 ${_dv}），但内核太老（4.17 以前），加不了按端口分的规则" ;;
        notable) echo "${_fn}：回包会从 ${_nd} 发出去（应该走 ${_dv}），但找不到走 ${_dv} 的路由表，没法自动修" ;;
        fail) echo "${_fn}：回包会从 ${_nd} 发出去（应该走 ${_dv}），加了规则也没改过来，已经拆掉" ;;
      esac
    done < "$STATE_DIR/$id"
    exit 0
    ;;
  need)
    _has_policy || exit 1
    for _nd in "$NODES_DIR"/*/; do
      id=$(basename "$_nd")
      case "$id" in ''|*[!0-9]*) continue ;; esac
      _is_udp_node && exit 0
    done
    exit 1
    ;;
esac
echo "用法：xray-node-route up|down|check|show <节点编号>，或 xray-node-route need" >&2
exit 2
ROUTEEOF
  chmod 700 "$_rb_dir/xray-node-route.tmp" || return 1
  mv -f "$_rb_dir/xray-node-route.tmp" "$_rb_dir/xray-node-route" || return 1
}

# ---------- 巡检小程序 xray-node-watch ----------
# 每分钟跑一次，平时几乎什么都不做，只做两件事：
#   1. 端口跳跃规则自愈：防火墙服务（nftables、firewalld、ufw、iptables、netfilter-persistent）
#      重启或重载时，经常把所有规则清空，跳跃端口就不通了。发现规则没了就补回去。
#   2. 证书续期端口：用自己的域名申请正规证书时，TCP 80（或 443）只在申请和快到期续期时打开，平时关着。
# 有 systemd 用定时器（timer），还会挂在防火墙服务后面：防火墙一重启/重载，马上补一次。
# Alpine 用 OpenRC 后台服务，都没有就用 cron，再没有就在后台循环。
# 没有节点需要它时（没开跳跃、也没有要管的证书端口），自动卸掉。
install_watch_bin() { # 写出 /usr/local/bin/xray-node-watch。重复运行只覆盖脚本。
  _wb_dir=${XRAY_BIN_DIR:-/usr/local/bin}
  mkdir -p "$_wb_dir" 2>/dev/null || return 1
  # 先写到临时文件再换上去：后台正在跑的巡检不会读到写了一半的脚本
  cat > "$_wb_dir/xray-node-watch.tmp" <<'WATCHEOF' || return 1
#!/bin/sh
# xray-node 巡检小程序。用法：
#   xray-node-watch tick [--now]  巡检一次（--now：证书端口那部分也马上查，不等一小时）
#   xray-node-watch arm           有节点需要就挂上每分钟的巡检，没有就卸掉
#   xray-node-watch disarm        卸掉巡检（全部卸载时用）
#   xray-node-watch loop          没有 systemd / OpenRC / cron 时，在后台一直循环巡检
#   xray-node-watch acme-open|acme-close|acme-drop <节点编号>   打开 / 关上 / 删掉证书用的端口
#   xray-node-watch undo <防火墙记录文件>   撤销记录里本脚本加过的放行（装到一半失败时用）
PATH="${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
NODES_DIR=${XRAY_NODE_DIR:-/etc/xray-node/nodes}
BIN_DIR=${XRAY_BIN_DIR:-/usr/local/bin}
STATE_DIR=${XRAY_WATCH_STATE:-/run/xray-node-watch}
SD_DIR=${XRAY_SYSTEMD_DIR:-/etc/systemd/system}
SD_RUN=${XRAY_SYSTEMD_RUN:-/run/systemd/system}
INITD=${XRAY_INITD:-/etc/init.d}
CRON_DIR=${XRAY_CRON_DIR:-/etc/cron.d}
PIDF=${XRAY_WATCH_PID:-/run/xray-node-watch.pid}
LOG=${XRAY_WATCH_LOG:-/var/log/xray-node-watch.log}
SELF="$BIN_DIR/xray-node-watch"
HOP="$BIN_DIR/xray-node-hop"
ROUTE="$BIN_DIR/xray-node-route"
# 各系统里防火墙服务的名字。机器上有哪个，就把巡检挂在哪个后面。
FW_UNITS="nftables.service firewalld.service ufw.service netfilter-persistent.service iptables.service ip6tables.service"
FW_UNIT_DIRS=${XRAY_FW_UNIT_DIRS:-"$SD_DIR /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system"}
# 证书剩不到 32 天就打开续期端口（Let's Encrypt 证书 90 天，剩 30 天左右开始续期）
ACME_WINDOW=${XRAY_ACME_WINDOW:-2764800}

_log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  # 日志超过 64KB 只留最后 200 行，不会越写越大
  if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 65536 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
  fi
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$1" >> "$LOG" 2>/dev/null
}

_has_systemd() { command -v systemctl >/dev/null 2>&1 && [ -d "$SD_RUN" ]; }

# 节点服务正在跑吗？没在跑的节点不补规则、不开端口。
_active() {
  if _has_systemd; then
    case "$(tr -d ' \r\n' < "$NODES_DIR/$1/core" 2>/dev/null)" in
      sing-box) systemctl is-active --quiet "singbox-node@$1" ;;
      xray) systemctl is-active --quiet "xray-node@$1" ;;
      *) systemctl is-active --quiet "hysteria-node@$1" ;;
    esac
    return
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "xray-node-$1" status >/dev/null 2>&1
    return
  fi
  for _ap in /proc/[0-9]*/cmdline; do
    case "$_ap" in "/proc/$$/"*) continue ;; esac
    tr '\000' ' ' < "$_ap" 2>/dev/null | grep -qF "$NODES_DIR/$1/config.yaml" && return 0
    tr '\000' ' ' < "$_ap" 2>/dev/null | grep -qF "$NODES_DIR/$1/config.json" && return 0
  done
  return 1
}

# ---- 端口跳跃规则自愈 ----
_heal_hop() {
  [ -x "$HOP" ] || return 0
  for _hd in "$NODES_DIR"/*/; do
    [ -f "${_hd}hop" ] || continue
    # 还在安装中的节点（没有 node.txt）由安装脚本自己管
    [ -f "${_hd}node.txt" ] || continue
    _hid=$(basename "$_hd")
    case "$_hid" in ''|*[!0-9]*) continue ;; esac
    _active "$_hid" || continue
    _hfail="$STATE_DIR/hop-$_hid.fail"
    # 规则还在：什么都不做（绝大多数时候都是这样，只花一次 nft list 的工夫）
    if "$HOP" check "$_hid" >/dev/null 2>&1; then
      rm -f "$_hfail"
      continue
    fi
    # 刚补失败过：5 分钟内不再重试，免得一直折腾
    if [ -f "$_hfail" ] && [ -n "$(find "$_hfail" -mmin -5 2>/dev/null)" ]; then
      continue
    fi
    if _herr=$("$HOP" up "$_hid" 2>&1 >/dev/null); then
      rm -f "$_hfail"
      _log "节点 $_hid 的端口跳跃规则不见了（多半是防火墙服务重启或重载过），已经补回"
    else
      : > "$_hfail"
      _log "节点 $_hid 的端口跳跃规则补不回来：$(printf '%s' "$_herr" | tr '\n' ' ' | cut -c1-300)"
    fi
  done
}

# ---- 回程路由自愈 ----
# VPN 常常比节点晚启动，或者半路重连换了网卡：每分钟看一次 UDP 节点的回包该不该加规则、规则还在不在。
_heal_route() {
  [ -x "$ROUTE" ] || return 0
  for _rd in "$NODES_DIR"/*/; do
    [ -f "${_rd}node.txt" ] || continue
    _rid=$(basename "$_rd")
    case "$_rid" in ''|*[!0-9]*) continue ;; esac
    _active "$_rid" || continue
    "$ROUTE" check "$_rid" >/dev/null 2>&1 && continue
    _rfail="$STATE_DIR/route-$_rid.fail"
    if [ -f "$_rfail" ] && [ -n "$(find "$_rfail" -mmin -5 2>/dev/null)" ]; then
      continue
    fi
    if "$ROUTE" up "$_rid" >/dev/null 2>&1; then
      rm -f "$_rfail"
      _log "节点 $_rid 的回程路由已按现在的网络改好：$("$ROUTE" show "$_rid" 2>/dev/null | tr '\n' ' ' | cut -c1-300)"
    else
      : > "$_rfail"
      _log "节点 $_rid 的回程路由没改好：$("$ROUTE" show "$_rid" 2>/dev/null | tr '\n' ' ' | cut -c1-300)"
    fi
  done
}

# ---- 防火墙放行：按记录文件打开 / 撤销 ----
# 记录文件每行：端口 协议 ufw加过 firewalld加过 iptables加过 地址族（和 fw_info 一样）。
# 只动当初本脚本亲手加的那几种，你自己设的规则不碰。
_fw_save() { # iptables 改了要存盘，重启后才一致
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  elif [ -f /etc/alpine-release ]; then
    if [ "$1" = "6" ]; then _fs_svc=ip6tables; else _fs_svc=iptables; fi
    if [ -f "/etc/init.d/$_fs_svc" ]; then "/etc/init.d/$_fs_svc" save >/dev/null 2>&1 || true; fi
  fi
}

_fw_undo() {
  [ -f "$1" ] || return 0
  _u4=0; _u6=0
  while read -r _fp _fpr _fu _ff _fi _ffam; do
    case "$_fp" in ''|*[!0-9]*) continue ;; esac
    case "$_fpr" in tcp|udp) ;; *) continue ;; esac
    if [ "$_fu" = "1" ] && command -v ufw >/dev/null 2>&1; then
      ufw delete allow "$_fp/$_fpr" >/dev/null 2>&1 || true
    fi
    if [ "$_ff" = "1" ] && command -v firewall-cmd >/dev/null 2>&1; then
      firewall-cmd --permanent --remove-port="$_fp/$_fpr" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    if [ "$_fi" = "1" ]; then
      if [ "$_ffam" = "6" ]; then _fb=ip6tables; _u6=1; else _fb=iptables; _u4=1; fi
      command -v "$_fb" >/dev/null 2>&1 && "$_fb" -D INPUT -p "$_fpr" --dport "$_fp" -j ACCEPT >/dev/null 2>&1
    fi
  done < "$1"
  [ "$_u4" = "1" ] && _fw_save 4
  [ "$_u6" = "1" ] && _fw_save 6
  return 0
}

_fw_redo() { # 已经放行的不重复加
  [ -f "$1" ] || return 0
  _r4=0; _r6=0
  while read -r _fp _fpr _fu _ff _fi _ffam; do
    case "$_fp" in ''|*[!0-9]*) continue ;; esac
    case "$_fpr" in tcp|udp) ;; *) continue ;; esac
    if [ "$_fu" = "1" ] && command -v ufw >/dev/null 2>&1; then
      ufw status 2>/dev/null | grep -qE "^${_fp}/${_fpr}[[:space:]]" || ufw allow "$_fp/$_fpr" >/dev/null 2>&1
    fi
    if [ "$_ff" = "1" ] && command -v firewall-cmd >/dev/null 2>&1; then
      if ! firewall-cmd --query-port="$_fp/$_fpr" >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="$_fp/$_fpr" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1
      fi
    fi
    if [ "$_fi" = "1" ]; then
      if [ "$_ffam" = "6" ]; then _fb=ip6tables; else _fb=iptables; fi
      if command -v "$_fb" >/dev/null 2>&1 && ! "$_fb" -C INPUT -p "$_fpr" --dport "$_fp" -j ACCEPT >/dev/null 2>&1; then
        "$_fb" -I INPUT -p "$_fpr" --dport "$_fp" -j ACCEPT >/dev/null 2>&1
        if [ "$_ffam" = "6" ]; then _r6=1; else _r4=1; fi
      fi
    fi
  done < "$1"
  [ "$_r4" = "1" ] && _fw_save 4
  [ "$_r6" = "1" ] && _fw_save 6
  return 0
}

# ---- 证书续期端口 ----
# 节点目录里的 fw_acme 记着为申请证书打开的端口，fw_acme.state 写着现在是 open 还是 closed。
_acme_open() {
  _ao="$NODES_DIR/$1"
  [ -f "$_ao/fw_acme" ] || return 0
  _fw_redo "$_ao/fw_acme"
  echo open > "$_ao/fw_acme.state"
}

_acme_close() {
  _ac="$NODES_DIR/$1"
  [ -f "$_ac/fw_acme" ] || return 0
  # 已经关着就不再删：免得把你后来自己加的同样规则删掉
  [ "$(cat "$_ac/fw_acme.state" 2>/dev/null)" = "closed" ] && return 0
  _fw_undo "$_ac/fw_acme"
  echo closed > "$_ac/fw_acme.state"
}

_acme_need() { # 返回 0 = 现在需要打开（还没拿到证书，或者快到期要续期）
  _an_d="$NODES_DIR/$1"
  _active "$1" || return 1
  _an_crt=$(find "$_an_d/acme" -type f -name '*.crt' 2>/dev/null | head -1)
  [ -n "$_an_crt" ] || return 0
  # 没有 openssl 看不了到期时间，只好一直开着，保证能续期
  command -v openssl >/dev/null 2>&1 || return 0
  openssl x509 -checkend "$ACME_WINDOW" -noout -in "$_an_crt" >/dev/null 2>&1 && return 1
  return 0
}

_acme_tick() {
  _at_stamp="$STATE_DIR/acme.stamp"
  # 证书一天才变一次，一小时查一次就够
  if [ "$1" != "--now" ] && [ -f "$_at_stamp" ] && [ -n "$(find "$_at_stamp" -mmin -60 2>/dev/null)" ]; then
    return 0
  fi
  : > "$_at_stamp"
  for _ad in "$NODES_DIR"/*/; do
    [ -f "${_ad}fw_acme" ] || continue
    # 还在安装中的节点（没有 node.txt）正在申请证书，别去关它的端口
    [ -f "${_ad}node.txt" ] || continue
    _aid=$(basename "$_ad")
    case "$_aid" in ''|*[!0-9]*) continue ;; esac
    _ast=$(cat "${_ad}fw_acme.state" 2>/dev/null)
    if _acme_need "$_aid"; then
      [ "$_ast" = "open" ] || _log "节点 $_aid 的证书要申请或续期了，临时打开证书用的端口"
      _acme_open "$_aid"
    elif [ "$_ast" != "closed" ]; then
      _acme_close "$_aid"
      _log "节点 $_aid 的证书已经是新的，证书用的端口关上了"
    fi
  done
}

_tick() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  # 定时器和防火墙钩子同时触发时，只让一个在干活
  if command -v flock >/dev/null 2>&1; then
    exec 8>"$STATE_DIR/tick.lock"
    flock -n 8 || return 0
  fi
  # 先开关证书端口，再补跳跃规则：firewalld 重载时可能把跳跃规则一起清掉，放在后面补更稳
  _acme_tick "$1"
  _heal_hop
  _heal_route
}

# ---- 挂上 / 卸掉巡检 ----
_needed() {
  for _nd in "$NODES_DIR"/*/; do
    [ -f "${_nd}hop" ] && return 0
    [ -f "${_nd}fw_acme" ] && return 0
  done
  # 有 UDP 节点、机器上又有策略路由：要每分钟看一下回程路由
  [ -x "$ROUTE" ] && "$ROUTE" need >/dev/null 2>&1 && return 0
  return 1
}

_fw_units_present() { # 打印机器上真的有的防火墙服务
  for _fu in $FW_UNITS; do
    for _fdir in $FW_UNIT_DIRS; do
      if [ -f "$_fdir/$_fu" ]; then printf '%s ' "$_fu"; break; fi
    done
  done
}

_arm_systemd() {
  cat > "$SD_DIR/xray-node-watch.service" <<EOF
[Unit]
Description=xray-node watch: restore port-hopping rules, open certificate port when renewing
After=network.target
[Service]
Type=oneshot
ExecStart=$SELF tick
EOF
  cat > "$SD_DIR/xray-node-watch.timer" <<EOF
[Unit]
Description=Run xray-node watch every minute
[Timer]
OnBootSec=30
OnUnitActiveSec=60
AccuracySec=5s
[Install]
WantedBy=timers.target
EOF
  _units=$(_fw_units_present)
  _units=${_units% }
  if [ -n "$_units" ]; then
    # PartOf：防火墙服务重启时，这个小服务也跟着重启（也就是马上巡检一次）。
    # ReloadPropagatedFrom：防火墙服务 reload 时，这里也跟着跑一次。
    # After：等防火墙把它自己的规则写完再补，免得刚补上又被清掉。
    cat > "$SD_DIR/xray-node-watch-fw.service" <<EOF
[Unit]
Description=Restore xray-node port-hopping rules after the firewall restarts or reloads
After=${_units}
PartOf=${_units}
ReloadPropagatedFrom=${_units}
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SELF tick --now
ExecReload=$SELF tick --now
[Install]
WantedBy=multi-user.target ${_units}
EOF
  elif [ -f "$SD_DIR/xray-node-watch-fw.service" ]; then
    # 防火墙服务被卸掉了：钩子也撤掉，连同开机自启的链接
    systemctl disable --now xray-node-watch-fw.service >/dev/null 2>&1 || true
    rm -f "$SD_DIR/xray-node-watch-fw.service"
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now xray-node-watch.timer >/dev/null 2>&1 || return 1
  if [ -n "$_units" ]; then
    systemctl reenable xray-node-watch-fw.service >/dev/null 2>&1 || systemctl enable xray-node-watch-fw.service >/dev/null 2>&1 || true
    systemctl restart xray-node-watch-fw.service >/dev/null 2>&1 || true
  fi
  return 0
}

_disarm_systemd() {
  _has_systemd || return 0
  [ -f "$SD_DIR/xray-node-watch.timer" ] || [ -f "$SD_DIR/xray-node-watch-fw.service" ] || return 0
  systemctl disable --now xray-node-watch.timer >/dev/null 2>&1 || true
  systemctl disable --now xray-node-watch-fw.service >/dev/null 2>&1 || true
  rm -f "$SD_DIR/xray-node-watch.timer" "$SD_DIR/xray-node-watch.service" "$SD_DIR/xray-node-watch-fw.service"
  systemctl daemon-reload >/dev/null 2>&1 || true
}

_arm_openrc() {
  cat > "$INITD/xray-node-watch" <<EOF
#!/sbin/openrc-run
name="xray-node-watch"
description="xray-node watch: restore port-hopping rules, open certificate port when renewing"
command="$SELF"
command_args="loop"
command_background="yes"
pidfile="/run/xray-node-watch-openrc.pid"
depend() { after net firewall; }
EOF
  chmod 755 "$INITD/xray-node-watch" || return 1
  rc-update add xray-node-watch default >/dev/null 2>&1 || true
  rc-service xray-node-watch status >/dev/null 2>&1 || rc-service xray-node-watch start >/dev/null 2>&1 || true
  return 0
}

_disarm_openrc() {
  [ -f "$INITD/xray-node-watch" ] || return 0
  rc-service xray-node-watch stop >/dev/null 2>&1 || true
  rc-update del xray-node-watch default >/dev/null 2>&1 || true
  rm -f "$INITD/xray-node-watch"
}

_kill_loop() {
  [ -f "$PIDF" ] || return 0
  _kp=$(tr -d ' \r\n' < "$PIDF" 2>/dev/null)
  case "$_kp" in ''|*[!0-9]*) ;; *) kill "$_kp" >/dev/null 2>&1 || true ;; esac
  rm -f "$PIDF"
}

_disarm() {
  _disarm_systemd
  _disarm_openrc
  rm -f "$CRON_DIR/xray-node-watch"
  _kill_loop
}

_arm() {
  if ! _needed; then
    _disarm
    return 0
  fi
  if _has_systemd && [ -d "$SD_DIR" ] && [ -w "$SD_DIR" ]; then
    _arm_systemd && return 0
  fi
  if command -v rc-update >/dev/null 2>&1 && [ -d "$INITD" ] && [ -w "$INITD" ]; then
    _arm_openrc && return 0
  fi
  if [ -d "$CRON_DIR" ] && [ -w "$CRON_DIR" ]; then
    cat > "$CRON_DIR/xray-node-watch" <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root $SELF tick
EOF
    return 0
  fi
  # 什么服务管理器都没有：后台循环。已经在跑就不再开第二个。
  if [ -f "$PIDF" ]; then
    _op=$(tr -d ' \r\n' < "$PIDF" 2>/dev/null)
    case "$_op" in ''|*[!0-9]*) ;; *) kill -0 "$_op" 2>/dev/null && return 0 ;; esac
  fi
  nohup "$SELF" loop >/dev/null 2>&1 &
  echo $! > "$PIDF" 2>/dev/null || true
  return 2
}

_id_ok() { case "$1" in ''|*[!0-9]*) echo "节点编号不对：$1" >&2; exit 2 ;; esac; }

case "$1" in
  tick) _tick "$2" ;;
  arm) _arm; exit $? ;;
  disarm) _disarm ;;
  loop)
    while :; do
      "$SELF" tick
      sleep 60
    done
    ;;
  acme-open) _id_ok "$2"; _acme_open "$2" ;;
  acme-close) _id_ok "$2"; _acme_close "$2" ;;
  acme-drop)
    _id_ok "$2"
    _acme_close "$2"
    rm -f "$NODES_DIR/$2/fw_acme" "$NODES_DIR/$2/fw_acme.state"
    ;;
  undo) _fw_undo "$2" ;;
  *) echo "用法：xray-node-watch tick|arm|disarm|loop|acme-open|acme-close|acme-drop <编号>|undo <文件>" >&2; exit 2 ;;
esac
exit 0
WATCHEOF
  chmod 700 "$_wb_dir/xray-node-watch.tmp" || return 1
  mv -f "$_wb_dir/xray-node-watch.tmp" "$_wb_dir/xray-node-watch" || return 1
}

# 挂上 / 卸掉巡检。返回前说明一下，不让小白以为多了个来路不明的服务。
arm_node_watch() {
  install_watch_bin || { warn "巡检小程序没写进去：防火墙重启后端口跳跃可能要等节点重启才回来"; return 0; }
  _anw_bin="${XRAY_BIN_DIR:-/usr/local/bin}/xray-node-watch"
  "$_anw_bin" arm
  if [ $? -eq 2 ]; then
    warn "这台机器没有 systemd、OpenRC 或 cron，巡检先在后台跑着。服务器重启后，请再运行一次安装脚本。"
  fi
  return 0
}

# ---------- IPv6 开关 ----------
# IPv6 是新一代的 IP 地址（长这样：2001:db8::1）。有的服务器 IPv6 线路很差，
# 访问网站时优先走 IPv6 反而又慢又不稳。菜单里的“关闭 IPv6”就是让这台服务器
# 只用 IPv4 上网，并写进系统配置，重启后仍然关闭。“开启 IPv6”是反过来。
# 下面这些函数分别负责：立刻生效、写开机配置、调整地址优先级、改节点监听地址。
_ipv6_conf_path() {
  printf '%s' "${XRAY_IPV6_CONF:-/etc/sysctl.d/99-xray-node-ipv6.conf}"
}

_ipv6_has_v4() {
  if [ -n "${XRAY_IPV6_HAS_V4+x}" ]; then
    [ "$XRAY_IPV6_HAS_V4" = "1" ]
    return $?
  fi
  command -v ip >/dev/null 2>&1 || return 1
  ip -4 -o addr show scope global 2>/dev/null | grep -q '[0-9]'
}

_ipv6_ssh_is_v6() {
  _sc="${SSH_CONNECTION:-}"
  [ -n "$_sc" ] || return 1
  _sip=$(printf '%s\n' "$_sc" | awk '{print $3}')
  case "$_sip" in
    *:*) return 0 ;;
  esac
  return 1
}

_ipv6_is_off() {
  _iv_root=${XRAY_IPV6_PROC:-/proc/sys/net/ipv6/conf}
  _iv_all="${_iv_root}/all/disable_ipv6"
  if [ -f "$_iv_all" ]; then
    [ "$(tr -d ' \r\n' < "$_iv_all" 2>/dev/null)" = "1" ]
    return $?
  fi
  [ -f "$(_ipv6_conf_path)" ]
}

_ipv6_apply() { # _ipv6_apply 0|1：立刻生效。以 all/disable_ipv6 的结果为准。
  _iv="$1"
  _root=${XRAY_IPV6_PROC:-/proc/sys/net/ipv6/conf}
  [ -d "$_root" ] || return 1
  for _f in "$_root"/*/disable_ipv6; do
    [ -f "$_f" ] || continue
    printf '%s\n' "$_iv" > "$_f" 2>/dev/null || true
  done
  _all="${_root}/all/disable_ipv6"
  if [ ! -f "$_all" ] || [ "$(tr -d ' \r\n' < "$_all" 2>/dev/null)" != "$_iv" ]; then
    if command -v sysctl >/dev/null 2>&1; then
      sysctl -w "net.ipv6.conf.all.disable_ipv6=${_iv}" >/dev/null 2>&1 || true
      sysctl -w "net.ipv6.conf.default.disable_ipv6=${_iv}" >/dev/null 2>&1 || true
      sysctl -w "net.ipv6.conf.lo.disable_ipv6=${_iv}" >/dev/null 2>&1 || true
    fi
  fi
  [ -f "$_all" ] || return 1
  [ "$(tr -d ' \r\n' < "$_all" 2>/dev/null)" = "$_iv" ]
}

_ipv6_sysctl_block() { # off|on：改 sysctl.conf 里的标记段，开机时还会再关一次。
  _mode="$1"
  _sc="${XRAY_SYSCTL_CONF:-/etc/sysctl.conf}"
  _dir=$(dirname "$_sc")
  [ -d "$_dir" ] && [ -w "$_dir" ] || return 1
  _tmp=$(mktemp 2>/dev/null) || return 1
  if [ -f "$_sc" ]; then
    awk '
      /^# xray-node-ipv6 begin/ { skip=1; next }
      /^# xray-node-ipv6 end/ { skip=0; next }
      skip { next }
      { print }
    ' "$_sc" > "$_tmp" || { rm -f "$_tmp"; return 1; }
  else
    : > "$_tmp" || { rm -f "$_tmp"; return 1; }
  fi
  if [ "$_mode" = "off" ]; then
    if [ -s "$_tmp" ]; then
      _last=$(tail -c 1 "$_tmp" 2>/dev/null || true)
      [ -z "$_last" ] || printf '\n' >> "$_tmp"
    fi
    printf '%s\n' \
      "# xray-node-ipv6 begin" \
      "net.ipv6.conf.all.disable_ipv6 = 1" \
      "net.ipv6.conf.default.disable_ipv6 = 1" \
      "net.ipv6.conf.lo.disable_ipv6 = 1" \
      "# xray-node-ipv6 end" >> "$_tmp" || { rm -f "$_tmp"; return 1; }
  fi
  cat "$_tmp" > "$_sc" || { rm -f "$_tmp"; return 1; }
  rm -f "$_tmp"
}

_ipv6_gai() { # off|on：让程序查地址时先用 IPv4。关掉 IPv6 时写上，打开时删掉。
  _mode="$1"
  _gai="${XRAY_GAI_CONF:-/etc/gai.conf}"
  _dir=$(dirname "$_gai")
  [ -d "$_dir" ] && [ -w "$_dir" ] || return 1
  _tmp=$(mktemp 2>/dev/null) || return 1
  if [ -f "$_gai" ]; then
    # grep 把标记行全部滤掉时退出码是 1，这不是读文件失败。
    _gstat=0
    grep -v 'xray-node-ipv6' "$_gai" > "$_tmp" || _gstat=$?
    if [ "$_gstat" -gt 1 ]; then
      rm -f "$_tmp"
      return 1
    fi
  else
    : > "$_tmp" || { rm -f "$_tmp"; return 1; }
  fi
  if [ "$_mode" = "off" ]; then
    printf '%s\n' "precedence ::ffff:0:0/96  100  # xray-node-ipv6" >> "$_tmp" || { rm -f "$_tmp"; return 1; }
  fi
  cat "$_tmp" > "$_gai" || { rm -f "$_tmp"; return 1; }
  rm -f "$_tmp"
}

_ipv6_boot_unit() { # off|on：有 systemd 就开机再关一次。没有就靠 sysctl 配置。
  _mode="$1"
  _sd="${XRAY_SYSTEMD_DIR:-/etc/systemd/system}"
  _run="${XRAY_SYSTEMD_RUN:-/run/systemd/system}"
  _unit="${_sd}/xray-node-ipv6.service"
  if command -v systemctl >/dev/null 2>&1 && [ -d "$_run" ] && [ -d "$_sd" ] && [ -w "$_sd" ]; then
    if [ "$_mode" = "off" ]; then
      cat > "$_unit" <<'EOF'
[Unit]
Description=Keep IPv6 disabled
DefaultDependencies=no
Before=network-pre.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do [ -f "$f" ] && echo 1 > "$f"; done'
[Install]
WantedBy=sysinit.target
EOF
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl enable xray-node-ipv6.service >/dev/null 2>&1 || true
    else
      systemctl disable xray-node-ipv6.service >/dev/null 2>&1 || true
      rm -f "$_unit"
      systemctl daemon-reload >/dev/null 2>&1 || true
    fi
  fi
  if [ "$_mode" = "off" ] && [ -x /etc/init.d/sysctl ] && command -v rc-update >/dev/null 2>&1; then
    rc-update add sysctl boot >/dev/null 2>&1 || true
  fi
}

# 关掉 IPv6 前，把还在听 IPv6 的节点改成只听 IPv4。
# 双栈套接字在 IPv6 被关掉时会一起失效，不改的话 IPv4 客户端也会断。
_ipv6_rebind_nodes() {
  _root=${XRAY_NODES_DIR:-/etc/xray-node/nodes}
  [ -d "$_root" ] || return 0
  for _d in "$_root"/*/; do
    [ -d "$_d" ] || continue
    _id=$(basename "$_d")
    if [ -f "${_d}config.yaml" ]; then
      _listen=$(awk '
        /^listen:/ {
          line = $0
          sub(/\r$/, "", line)
          sub(/^listen:[[:space:]]*/, "", line)
          gsub(/^"|"$/, "", line)
          print line
          exit
        }
      ' "${_d}config.yaml")
      # :443 和 [::]:443 要改成只听 IPv4。端口跳跃是 :443,20000，逗号后面的端口要留下。
      # 留着双栈地址的话，关掉 IPv6 时这个套接字会一起失效，IPv4 也连不上。
      _body=""
      case "$_listen" in
        \[::\]:*) _body=${_listen#\[::\]:} ;;
        :*) _body=${_listen#:} ;;
      esac
      _port=${_body%%,*}
      _hop=""
      case "$_body" in
        *,*) _hop=${_body#*,} ;;
      esac
      case "$_port" in
        ''|*[!0-9]*) ;;
        *)
          case "$_hop" in
            *[!0-9,]*) ;;
            *)
              _cfg="${_d}config.yaml"
              _newlisten="0.0.0.0:${_port}"
              [ -n "$_hop" ] && _newlisten="${_newlisten},${_hop}"
              cp -a "$_cfg" "${_cfg}.bak-ipv6off" || continue
              if _hy_set_listen "$_cfg" "$_newlisten"; then
                # 端口跳跃也改成只转发 IPv4
                [ -f "${_d}hop" ] && sed -i 's/^family=.*/family=4/' "${_d}hop" 2>/dev/null
                _svc_restart "$_id"
                if wait_for_port "$_port" udp 15; then
                  rm -f "${_cfg}.bak-ipv6off"
                  info "节点 ${_id} 已改为只听 IPv4，避免关掉 IPv6 后这个节点一起停"
                else
                  mv -f "${_cfg}.bak-ipv6off" "$_cfg"
                  _svc_restart "$_id"
                  warn "节点 ${_id} 改成只听 IPv4 后没起来，已改回原来的配置"
                fi
              else
                mv -f "${_cfg}.bak-ipv6off" "$_cfg"
                warn "节点 ${_id} 的监听地址没改成"
              fi
              ;;
          esac
          ;;
      esac
    fi
    if [ -f "${_d}config.json" ] && grep -q '"listen"[[:space:]]*:[[:space:]]*"::"' "${_d}config.json" 2>/dev/null; then
      _cfg="${_d}config.json"
      cp -a "$_cfg" "${_cfg}.bak-ipv6off" || continue
      sed 's/"listen"[[:space:]]*:[[:space:]]*"::"/"listen": "0.0.0.0"/' "${_cfg}.bak-ipv6off" > "$_cfg" || {
        mv -f "${_cfg}.bak-ipv6off" "$_cfg"
        warn "节点 ${_id} 的监听地址没改成"
        continue
      }
      _proto=tcp
      _port=""
      if [ -f "${_d}fw_info" ]; then
        read -r _port _fproto _frest < "${_d}fw_info"
        case "$_fproto" in udp) _proto=udp ;; esac
      fi
      _svc_restart "$_id"
      case "$_port" in
        ''|*[!0-9]*)
          rm -f "${_cfg}.bak-ipv6off"
          info "节点 ${_id} 已改为只听 IPv4"
          ;;
        *)
          if wait_for_port "$_port" "$_proto" 15; then
            rm -f "${_cfg}.bak-ipv6off"
            info "节点 ${_id} 已改为只听 IPv4，避免关掉 IPv6 后这个节点一起停"
          else
            mv -f "${_cfg}.bak-ipv6off" "$_cfg"
            _svc_restart "$_id"
            warn "节点 ${_id} 改成只听 IPv4 后没起来，已改回原来的配置"
          fi
          ;;
      esac
    fi
  done
}

_ipv6_persist() { # off|on
  _mode="$1"
  _conf=$(_ipv6_conf_path)
  _cdir=$(dirname "$_conf")
  if [ "$_mode" = "off" ]; then
    mkdir -p "$_cdir" 2>/dev/null || return 1
    cat > "$_conf" <<'EOF' || return 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
  else
    rm -f "$_conf"
  fi
  _ipv6_sysctl_block "$_mode" || true
  _ipv6_gai "$_mode" || true
  _ipv6_boot_unit "$_mode" || true
}

# 关掉 IPv6 后，节点说明里的 IPv6 链接不能再用，从 jiedian 里拿掉。
_ipv6_strip_links() {
  _root=${XRAY_NODES_DIR:-/etc/xray-node/nodes}
  [ -d "$_root" ] || return 0
  for _d in "$_root"/*/; do
    [ -f "${_d}node.txt" ] || continue
    _tmp="${_d}node.txt.tmp-ipv6off"
    awk '
      /^ 你的节点（两行是同一个节点/ { print " 你的节点（复制下面整行，粘贴到客户端导入）"; next }
      /^IPv6 链接/ { next }
      /^IPv6 地址:/ { next }
      /^IPv6 端口:/ { next }
      /^hysteria2:\/\/.*@\[/ { next }
      /^Hysteria2 = Hysteria2,/ {
        n = split($0, a, ",")
        if (n >= 2 && a[2] ~ /:/) next
      }
      { print }
    ' "${_d}node.txt" > "$_tmp" && mv -f "$_tmp" "${_d}node.txt"
    chmod 600 "${_d}node.txt" 2>/dev/null || true
    rm -f "$_tmp"
  done
}

_ipv6_turn_off() {
  if ! _ipv6_has_v4; then
    printf "这台服务器没有 IPv4。关掉 IPv6 之后，它访问不了网站，你也可能连不上。\n"
    ask "仍然关闭吗？输入 y 才关闭" "n" _iv_yes
    case "$_iv_yes" in
      y|Y|yes|YES) ;;
      *) info "保持 IPv6 可用。"; return 0 ;;
    esac
  elif _ipv6_ssh_is_v6; then
    printf "你现在是用 IPv6 连上这台服务器的。关掉之后这次连接会断，之后要用 IPv4 才能再连。\n"
    ask "确定关闭 IPv6 吗？输入 y 才关闭" "n" _iv_yes
    case "$_iv_yes" in
      y|Y|yes|YES) ;;
      *) info "保持 IPv6 可用。"; return 0 ;;
    esac
  fi
  # 有些容器把 /proc/sys 设成只读，根本关不掉 IPv6。先看能不能改，
  # 改不了就什么都不动：否则节点已被改成只听 IPv4，IPv6 却还开着，IPv6 链接就连不上了。
  _root=${XRAY_IPV6_PROC:-/proc/sys/net/ipv6/conf}
  if [ -f "$_root/all/disable_ipv6" ] && [ ! -w "$_root/all/disable_ipv6" ]; then
    warn "系统不允许修改 IPv6 设置（有些容器被服务商锁住）。IPv6 保持开着，节点也没有改动。"
    return 0
  fi
  # 文件能写，不代表写进去的值会留下来。先试一次；读不回来就不要改节点。
  # 试写会立刻关掉 IPv6。忽略挂断，把原值写回后再改节点，避免连上的会话一断脚本就停。
  if [ -f "$_root/all/disable_ipv6" ]; then
    _iv_old=$(tr -d ' \r\n' < "$_root/all/disable_ipv6" 2>/dev/null || true)
    if [ "$_iv_old" != "1" ]; then
      trap '' HUP
      if ! _ipv6_apply 1; then
        trap - HUP
        warn "系统不允许修改 IPv6 设置（有些容器被服务商锁住）。IPv6 保持开着，节点也没有改动。"
        return 0
      fi
      if [ "$_iv_old" = "0" ]; then
        _ipv6_apply 0 || true
      fi
      trap - HUP
    fi
  fi
  _ipv6_rebind_nodes
  if ! _ipv6_persist off; then
    warn "关闭设置没写上，重启后 IPv6 可能又会打开。"
  fi
  _root=${XRAY_IPV6_PROC:-/proc/sys/net/ipv6/conf}
  if [ ! -d "$_root" ]; then
    _ipv6_strip_links
    info "这台服务器现在没有 IPv6。已经记下：以后也不使用 IPv6。"
    return 0
  fi
  if _ipv6_apply 1; then
    _ipv6_strip_links
    info "IPv6 已关闭。这台服务器以后只通过 IPv4 访问网站和 App，效果和没有 IPv6 一样。重启后也保持关闭。"
    info "用 IPv4 连接不受影响。想重新打开，再运行脚本，选「开启 IPv6」。"
  else
    warn "系统没有允许马上关闭 IPv6。有些容器会被服务商锁住，脚本改不了。"
  fi
}

_ipv6_turn_on() {
  _ipv6_persist on || warn "有的关闭设置没删掉。如果重启后又没有 IPv6，再选一次开启。"
  _root=${XRAY_IPV6_PROC:-/proc/sys/net/ipv6/conf}
  if [ ! -d "$_root" ]; then
    info "已经去掉关闭设置。这台系统现在没有 IPv6 可以打开。"
    return 0
  fi
  if _ipv6_apply 0; then
    info "IPv6 已打开。地址可能要过一会儿，或重启一次服务器，才会回来。"
    info "已经装好的节点如果要同时听 IPv6，再运行脚本，选「更新内核」。"
  else
    warn "关闭设置已去掉，但系统现在没允许打开 IPv6。重启后再看；服务商没分配的话，打开后仍然没有地址。"
  fi
}

_ipv6_switch_menu() {
  while true; do
    printf "\n要怎么处理这台服务器的 IPv6？\n"
    printf "  1) 关闭（以后只通过 IPv4 访问网站和 App，效果和没有 IPv6 一样。重启后也保持关闭）\n"
    printf "  2) 开启（恢复使用 IPv6）\n"
    printf "  3) 返回\n"
    if _ipv6_is_off; then
      printf "当前：IPv6 已关闭。\n"
    else
      printf "当前：IPv6 开着。\n"
    fi
    ask "请选择" "3" _ip6m
    case "$_ip6m" in
      1) _ipv6_turn_off ;;
      2) _ipv6_turn_on ;;
      3) break ;;
      *) warn "没有这个选项，请重新选择" ;;
    esac
  done
}

_choose_node_kind() {
  while true; do
    printf "\n请选择：\n"
    printf "  1) 永久节点（一直有效）\n"
    printf "  2) 定时节点（到时间后彻底失效）\n"
    printf "  3) 关闭 IPv6（这台服务器以后只通过 IPv4 访问网站和 App，效果和没有 IPv6 一样。重启后也保持关闭）\n"
    printf "  4) 开启 IPv6（恢复使用。服务商没分配地址的话，打开后仍然没有 IPv6）\n"
    printf "  5) 先不装节点，退出\n"
    if _ipv6_is_off; then
      printf "当前：IPv6 已关闭。\n"
    else
      printf "当前：IPv6 开着。\n"
    fi
    printf "看不懂就回车，默认是永久节点。\n"
    ask "请选择" "1" _nk
    case "$_nk" in
      2)
        NODE_KIND=timed
        break
        ;;
      3) _ipv6_turn_off ;;
      4) _ipv6_turn_on ;;
      5)
        echo "已退出，没有安装节点"
        _drop_expire_bins_if_unused
        exit 0
        ;;
      *)
        if [ "$_nk" != "1" ]; then
          warn "没有这个选项，按永久节点安装"
        fi
        NODE_KIND=permanent
        EXPIRE_AFTER=0
        EXPIRE_LABEL=""
        break
        ;;
    esac
  done
  if [ "$NODE_KIND" = "timed" ]; then
    _choose_expire_duration
  else
    info "种类：永久节点，一直有效"
  fi
}

# ---------- 定时节点的“到点删除”程序 ----------
# 写出三个小脚本到 /usr/local/bin：
#   xray-node-expire      检查所有定时节点，到时间的就彻底删掉（服务、配置、防火墙规则）
#   xray-node-run         启动节点前先看是否已过期，过期就不再启动（防止重启后“复活”）
#   xray-node-expire-loop 没有 systemd/cron 的机器上，每分钟检查一次
install_expire_bins() { # 写出到点删除脚本和启动包装。重复运行只覆盖脚本，不动节点。
  _eb_bin=${XRAY_BIN_DIR:-/usr/local/bin}
  mkdir -p "$_eb_bin" 2>/dev/null || return 1
  cat > "$_eb_bin/xray-node-expire" <<'EXPEOF' || return 1
#!/bin/sh
# 到点后彻底删除定时节点。没有 expire 文件的永久节点不会被碰。
NODES_DIR=${XRAY_NODE_DIR:-/etc/xray-node/nodes}
LOG=${XRAY_EXPIRE_LOG:-/var/log/xray-node-expire.log}
LOCK=${XRAY_EXPIRE_LOCK:-/run/xray-node-expire.lock}
WANTS=${XRAY_SYSTEMD_WANTS:-/etc/systemd/system/multi-user.target.wants}
SD_DIR=${XRAY_SYSTEMD_DIR:-/etc/systemd/system}
INITD=${XRAY_INITD:-/etc/init.d}
RUNLEVEL=${XRAY_RUNLEVEL:-/etc/runlevels/default}

case "$LOCK" in
  */xray-node-expire.lock) ;;
  *) exit 0 ;;
esac
case "$NODES_DIR" in
  ''|'/'|*..*) exit 0 ;;
esac

_log() {
  _log_dir=${LOG%/*}
  if [ -n "$_log_dir" ] && [ -d "$_log_dir" ] && [ -w "$_log_dir" ]; then
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$1" >> "$LOG" 2>/dev/null || true
  fi
}

_due() {
  [ -f "$1" ] || return 1
  _ts=$(tr -d ' \r\n' < "$1" 2>/dev/null) || return 1
  case "$_ts" in ''|*[!0-9]*) return 1 ;; esac
  _now=$(date +%s 2>/dev/null) || return 1
  [ "$_now" -ge "$_ts" ]
}

_fw_save() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  elif [ -f /etc/alpine-release ]; then
    if [ "$1" = "6" ]; then _fs_svc=ip6tables; else _fs_svc=iptables; fi
    [ -f "/etc/init.d/$_fs_svc" ] && "/etc/init.d/$_fs_svc" save >/dev/null 2>&1 || true
  fi
}

_del_fw() {
  [ -f "$1" ] || return 0
  _fipt_v4=0
  _fipt_v6=0
  while read -r _fport _fproto _fufw _ffwl _fipt _ffamily; do
    [ -n "$_fport" ] && [ -n "$_fproto" ] || continue
    _oldfmt=0
    if [ -z "$_fufw$_ffwl$_fipt" ]; then _fufw=1; _ffwl=1; _fipt=1; _oldfmt=1; fi
    if [ "$_fufw" = "1" ] && command -v ufw >/dev/null 2>&1; then
      ufw delete allow "$_fport"/"$_fproto" >/dev/null 2>&1 || true
    fi
    if [ "$_ffwl" = "1" ] && command -v firewall-cmd >/dev/null 2>&1; then
      firewall-cmd --permanent --remove-port="$_fport"/"$_fproto" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    if [ "$_ffamily" = "6" ]; then _fipbin=ip6tables; else _fipbin=iptables; fi
    if [ "$_fipt" = "1" ] && command -v "$_fipbin" >/dev/null 2>&1; then
      if [ "$_ffamily" = "6" ]; then _fipt_v6=1; else _fipt_v4=1; fi
      if [ "$_oldfmt" = "1" ]; then
        while "$_fipbin" -C INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1; do
          "$_fipbin" -D INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1 || break
        done
      else
        "$_fipbin" -D INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1 || true
      fi
    fi
  done < "$1"
  [ "$_fipt_v4" = "1" ] && _fw_save 4
  [ "$_fipt_v6" = "1" ] && _fw_save 6
}

_stop_outside() {
  _x_id=$1
  _x_core=$(tr -d ' \r\n' < "$NODES_DIR/$_x_id/core" 2>/dev/null || true)
  if command -v systemctl >/dev/null 2>&1 && [ -d "${XRAY_SYSTEMD_RUN:-/run/systemd/system}" ]; then
    case "$_x_core" in
      sing-box) _x_unit="singbox-node@${_x_id}" ;;
      hysteria) _x_unit="hysteria-node@${_x_id}" ;;
      *) _x_unit="xray-node@${_x_id}" ;;
    esac
    systemctl stop "$_x_unit" >/dev/null 2>&1 || true
    systemctl disable "$_x_unit" >/dev/null 2>&1 || true
    systemctl reset-failed "$_x_unit" >/dev/null 2>&1 || true
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "xray-node-${_x_id}" stop >/dev/null 2>&1 || true
    rc-update del "xray-node-${_x_id}" default >/dev/null 2>&1 || true
    rm -f "$INITD/xray-node-${_x_id}"
  fi
  pkill -f "$NODES_DIR/${_x_id}/config.json" >/dev/null 2>&1 || true
  pkill -f "$NODES_DIR/${_x_id}/config.yaml" >/dev/null 2>&1 || true
  sleep 1
}

# 包装脚本发现自己到期时，不能 systemctl stop 自己，否则会和正在进行的启动互相卡住。
# 只拆掉开机链接。这次启动会马上退出，端口不会打开。
_stop_inside() {
  _x_id=$1
  rm -f "$WANTS/xray-node@${_x_id}.service" \
    "$WANTS/hysteria-node@${_x_id}.service" \
    "$WANTS/singbox-node@${_x_id}.service" \
    "$RUNLEVEL/xray-node-${_x_id}" \
    "$INITD/xray-node-${_x_id}"
}

_delete_node() {
  _d_id=$1
  case "$_d_id" in ''|*[!0-9]*) return 1 ;; esac
  [ -d "$NODES_DIR/$_d_id" ] || return 0
  _due "$NODES_DIR/$_d_id/expire" || return 0
  if [ "${XRAY_EXPIRE_FROM_SERVICE:-}" = "$_d_id" ]; then
    _del_fw "$NODES_DIR/$_d_id/fw_info"
    _stop_inside "$_d_id"
  else
    _stop_outside "$_d_id"
    _del_fw "$NODES_DIR/$_d_id/fw_info"
  fi
  # 拆掉端口跳跃的转发规则（没开跳跃时什么都不做）
  _x_hop="${XRAY_BIN_DIR:-/usr/local/bin}/xray-node-hop"
  [ -x "$_x_hop" ] && "$_x_hop" down "$_d_id" >/dev/null 2>&1
  # 拆掉回程路由规则（没加过时什么都不做）
  _x_rt="${XRAY_BIN_DIR:-/usr/local/bin}/xray-node-route"
  [ -x "$_x_rt" ] && "$_x_rt" down "$_d_id" >/dev/null 2>&1
  # 证书用的端口如果还开着，也关上
  _x_watch="${XRAY_BIN_DIR:-/usr/local/bin}/xray-node-watch"
  [ -x "$_x_watch" ] && "$_x_watch" acme-drop "$_d_id" >/dev/null 2>&1
  rm -rf "$NODES_DIR/$_d_id"
  # 没有节点再需要巡检了，就把巡检一起卸掉
  [ -x "$_x_watch" ] && "$_x_watch" arm >/dev/null 2>&1
  echo "节点 ${_d_id} 已到时间，已经彻底删除。"
  _log "节点 ${_d_id} 已到时间，已彻底删除（服务已停、链接作废、配置和防火墙规则已清除）"
}

_expire_lock() {
  if mkdir "$1" 2>/dev/null; then
    return 0
  fi
  _now=$(date +%s 2>/dev/null) || return 1
  _born=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || true)
  case "$_born" in ''|*[!0-9]*) return 1 ;; esac
  if [ $((_now - _born)) -gt 120 ]; then
    rm -rf "$1"
    mkdir "$1" 2>/dev/null && return 0
  fi
  return 1
}

_lock_parent=${LOCK%/*}
if [ -n "$_lock_parent" ] && [ ! -d "$_lock_parent" ]; then
  mkdir -p "$_lock_parent" 2>/dev/null || exit 0
fi
_got=0
if _expire_lock "$LOCK"; then _got=1; fi
if [ "$_got" != "1" ] && [ "$1" = "--delete" ]; then
  _w=0
  while [ "$_got" != "1" ] && [ "$_w" -lt 5 ]; do
    sleep 1
    _w=$((_w + 1))
    if _expire_lock "$LOCK"; then _got=1; fi
  done
fi
[ "$_got" = "1" ] || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

case "$1" in
  --delete) _delete_node "$2" ;;
  *)
    for _d in "$NODES_DIR"/*/; do
      [ -d "$_d" ] || continue
      _id=$(basename "$_d")
      case "$_id" in ''|*[!0-9]*) continue ;; esac
      _due "$_d/expire" || continue
      _delete_node "$_id"
    done
    ;;
esac

if [ -d "$NODES_DIR" ]; then
  _left=0
  for _d in "$NODES_DIR"/*/; do
    [ -f "${_d}expire" ] || continue
    _left=1
    break
  done
  if [ "$_left" = "0" ]; then
    if [ -f "$SD_DIR/xray-node-expire.timer" ] && command -v systemctl >/dev/null 2>&1; then
      systemctl disable --now xray-node-expire.timer >/dev/null 2>&1 || true
      rm -f "$SD_DIR/xray-node-expire.timer" "$SD_DIR/xray-node-expire.service"
      systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if [ -f "$INITD/xray-node-expire" ] && command -v rc-update >/dev/null 2>&1; then
      rc-service xray-node-expire stop >/dev/null 2>&1 || true
      rc-update del xray-node-expire default >/dev/null 2>&1 || true
      rm -f "$INITD/xray-node-expire"
    fi
    rm -f "${XRAY_CRON_DIR:-/etc/cron.d}/xray-node-expire"
  fi
fi
exit 0
EXPEOF
  cat > "$_eb_bin/xray-node-run" <<'RUNEOF' || return 1
#!/bin/sh
# 启动一个节点。定时节点如果已经到期，先彻底删掉，不再打开端口。
_id=$1
case "$_id" in
  ''|*[!0-9]*) exit 0 ;;
esac
_nodes=${XRAY_NODE_DIR:-/etc/xray-node/nodes}
_dir="${_nodes}/${_id}"
_bin_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd) || exit 1

_is_due() {
  [ -f "$1" ] || return 1
  _ts=$(tr -d ' \r\n' < "$1" 2>/dev/null) || return 1
  case "$_ts" in ''|*[!0-9]*) return 1 ;; esac
  _now=$(date +%s 2>/dev/null) || return 1
  [ "$_now" -ge "$_ts" ]
}

if _is_due "$_dir/expire"; then
  # Hysteria2 用普通用户跑时删不了文件，直接不启动；root 身份的到期巡检一分钟内会删掉它。
  [ -w "$_nodes" ] || exit 0
  if [ -x "$_bin_dir/xray-node-expire" ]; then
    XRAY_EXPIRE_FROM_SERVICE="$_id" "$_bin_dir/xray-node-expire" --delete "$_id" || true
  fi
  exit 0
fi
[ -d "$_dir" ] || exit 0
[ -f "$_dir/core" ] || exit 1
_core=$(tr -d ' \r\n' < "$_dir/core")
_xray=${XRAY_BIN_PATH:-/usr/local/bin/xray}
_sb=${SB_BIN_PATH:-/usr/local/bin/sing-box}
_hy=${HY_BIN_PATH:-/usr/local/bin/hysteria}
case "$_core" in
  hysteria) exec "$_hy" server -c "$_dir/config.yaml" ;;
  sing-box) exec "$_sb" run -c "$_dir/config.json" ;;
  *) exec "$_xray" -config "$_dir/config.json" ;;
esac
exit 1
RUNEOF
  cat > "$_eb_bin/xray-node-expire-loop" <<'LOOPEOF' || return 1
#!/bin/sh
_here=$(CDPATH= cd -- "$(dirname "$0")" && pwd) || exit 1
while true; do
  "$_here/xray-node-expire"
  sleep 60
done
LOOPEOF
  chmod 700 "$_eb_bin/xray-node-expire" "$_eb_bin/xray-node-expire-loop" || return 1
  # xray-node-run 要让普通用户 xray-node 也能执行（Hysteria2 用它启动），里面没有任何秘密。
  chmod 755 "$_eb_bin/xray-node-run" || return 1
}

# 让系统每分钟自动跑一次到点检查。有 systemd 用它的“定时器”（timer），
# Alpine 用 OpenRC 服务，都没有就用 cron（Linux 自带的定时任务）。
# 一个节点都没有时（比如只进来开关 IPv6 就退出、或者第一次安装中途失败），
# 把开头写出的三个定时小脚本删掉，不在系统里留垃圾。
_drop_expire_bins_if_unused() {
  _de_nodes=${XRAY_NODE_DIR:-/etc/xray-node/nodes}
  for _de_d in "$_de_nodes"/*/; do
    [ -d "$_de_d" ] && return 0
  done
  _de_bin=${XRAY_BIN_DIR:-/usr/local/bin}
  rm -f "$_de_bin/xray-node-expire" "$_de_bin/xray-node-run" "$_de_bin/xray-node-expire-loop"
}

arm_expire_watch() { # 有定时节点才挂上巡检；没有就卸掉以前留下的巡检。
  _aw_nodes=${XRAY_NODE_DIR:-/etc/xray-node/nodes}
  _aw_need=0
  for _aw_d in "$_aw_nodes"/*/; do
    [ -f "${_aw_d}expire" ] || continue
    _aw_need=1
    break
  done
  _aw_bin_dir=${XRAY_BIN_DIR:-/usr/local/bin}
  _aw_expire="$_aw_bin_dir/xray-node-expire"
  _aw_loop="$_aw_bin_dir/xray-node-expire-loop"
  _aw_sd=${XRAY_SYSTEMD_DIR:-/etc/systemd/system}
  _aw_run=${XRAY_SYSTEMD_RUN:-/run/systemd/system}
  if [ "$_aw_need" = "1" ] && [ ! -x "$_aw_expire" ]; then
    warn "找不到定时失效程序，到点后不会自动删除。下次运行安装脚本或 jiedian 时还会再试。"
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1 && [ -d "$_aw_run" ] && [ -d "$_aw_sd" ] && [ -w "$_aw_sd" ]; then
    if [ "$_aw_need" = "1" ]; then
      _aw_was=$(systemctl is-enabled xray-node-expire.timer 2>/dev/null || true)
      cat > "$_aw_sd/xray-node-expire.service" <<EOF
[Unit]
Description=Delete expired proxy nodes
[Service]
Type=oneshot
ExecStart=${_aw_expire}
EOF
      cat > "$_aw_sd/xray-node-expire.timer" <<EOF
[Unit]
Description=Watch proxy nodes and delete them when their time is up
[Timer]
OnBootSec=15
OnUnitActiveSec=60
AccuracySec=1s
Persistent=true
[Install]
WantedBy=timers.target
EOF
      systemctl daemon-reload >/dev/null 2>&1 || true
      if systemctl enable --now xray-node-expire.timer >/dev/null 2>&1; then
        if [ "$_aw_was" != "enabled" ]; then
          info "定时节点到点后大约一分钟内会自动彻底失效"
        fi
      else
        warn "定时检查没能设成开机自启。到点后，运行 jiedian 或重跑安装脚本也会把到期节点删掉。"
      fi
    elif [ -f "$_aw_sd/xray-node-expire.timer" ] || [ -f "$_aw_sd/xray-node-expire.service" ]; then
      systemctl disable --now xray-node-expire.timer >/dev/null 2>&1 || true
      rm -f "$_aw_sd/xray-node-expire.timer" "$_aw_sd/xray-node-expire.service"
      systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    return 0
  fi
  if command -v rc-update >/dev/null 2>&1 && [ -d /etc/init.d ] && [ -w /etc/init.d ]; then
    if [ "$_aw_need" = "1" ]; then
      _aw_new=0
      [ -f /etc/init.d/xray-node-expire ] || _aw_new=1
      cat > /etc/init.d/xray-node-expire <<EOF
#!/sbin/openrc-run
name="xray-node-expire"
description="Delete proxy nodes when their time is up"
command="${_aw_loop}"
command_background="yes"
pidfile="/run/xray-node-expire.pid"
depend() { after localmount; }
EOF
      chmod 700 /etc/init.d/xray-node-expire || return 0
      rc-update add xray-node-expire default >/dev/null 2>&1 || true
      rc-service xray-node-expire restart >/dev/null 2>&1 || rc-service xray-node-expire start >/dev/null 2>&1 || true
      if [ "$_aw_new" = "1" ]; then
        info "定时节点到点后大约一分钟内会自动彻底失效"
      fi
    elif [ -f /etc/init.d/xray-node-expire ]; then
      rc-service xray-node-expire stop >/dev/null 2>&1 || true
      rc-update del xray-node-expire default >/dev/null 2>&1 || true
      rm -f /etc/init.d/xray-node-expire
    fi
    return 0
  fi
  _aw_cron=${XRAY_CRON_DIR:-/etc/cron.d}
  if [ -d "$_aw_cron" ] && [ -w "$_aw_cron" ]; then
    if [ "$_aw_need" = "1" ]; then
      cat > "$_aw_cron/xray-node-expire" <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root ${_aw_expire}
EOF
      return 0
    fi
    rm -f "$_aw_cron/xray-node-expire"
    return 0
  fi
  if [ "$_aw_need" != "1" ]; then
    return 0
  fi
  _aw_pid=${XRAY_EXPIRE_PID:-/run/xray-node-expire.pid}
  if [ -f "$_aw_pid" ]; then
    _aw_old=$(tr -d ' \r\n' < "$_aw_pid" 2>/dev/null || true)
    case "$_aw_old" in
      ''|*[!0-9]*) ;;
      *)
        if kill -0 "$_aw_old" 2>/dev/null; then
          return 0
        fi
        ;;
    esac
  fi
  if [ -x "$_aw_loop" ]; then
    nohup "$_aw_loop" >/dev/null 2>&1 &
    echo $! > "$_aw_pid" 2>/dev/null || true
  fi
  warn "这台机器没有 systemd、OpenRC 或 cron。已在后台看着到期时间。服务器重启后，请再跑一次安装脚本，定时才会继续生效。"
  return 0
}

# ---------- 写入 jiedian / shanjiedian 两个快捷命令 ----------
# jiedian：显示所有节点的分享链接；shanjiedian：删除某个节点或全部卸载。
# 它们是普通的 shell 脚本，放在 /usr/local/bin，以后直接输入名字就能用。
write_helper_cmds() { # 写入/刷新 jiedian、shanjiedian，以及定时失效脚本
cat > /usr/local/bin/jiedian <<'JDEOF'
#!/bin/sh
# 输入 jiedian，显示所有已安装节点的信息和链接
if [ -x /usr/local/bin/xray-node-expire ]; then
  /usr/local/bin/xray-node-expire || true
fi
_n=0
for _d in /etc/xray-node/nodes/*/; do
  [ -f "${_d}node.txt" ] || continue
  _n=1
  printf "\n==================== 节点 %s ====================\n" "$(basename "$_d")"
  cat "${_d}node.txt"
done
if [ "$_n" = "0" ]; then
  echo "还没安装节点，请先运行一键安装脚本"
fi
exit 0
JDEOF
chmod 700 /usr/local/bin/jiedian
cat > /usr/local/bin/shanjiedian <<'XZEOF'
#!/bin/sh
# 输入 shanjiedian，进入节点管理：查看节点、删除单个节点，或全部卸载
if [ -x /usr/local/bin/xray-node-expire ]; then
  /usr/local/bin/xray-node-expire || true
fi
NODES_DIR=/etc/xray-node/nodes

# _node_info <节点id>：从 node.txt 里读出"协议，端口，种类"
_node_info() {
  _ni_proto=$(grep -m1 '^协议: ' "$NODES_DIR/$1/node.txt" 2>/dev/null | sed 's/^协议: //')
  _ni_port=$(grep -m1 '^端口: ' "$NODES_DIR/$1/node.txt" 2>/dev/null | sed 's/^端口: //')
  _ni_kind="永久节点"
  _ni_exp=$(tr -d ' \r\n' < "$NODES_DIR/$1/expire" 2>/dev/null || true)
  case "$_ni_exp" in
    ''|*[!0-9]*) ;;
    *)
      _ni_when=$(date -d "@$_ni_exp" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$_ni_exp" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '%s' "$_ni_exp")
      _ni_kind="定时节点，${_ni_when} 失效"
      ;;
  esac
  printf "%s，端口 %s，%s" "$_ni_proto" "$_ni_port" "$_ni_kind"
}

# _fw_save：iptables 规则改动后存盘（删规则后也要存，否则重启后删掉的规则又回来了）
# 安装时如果装过 iptables-persistent，这里 netfilter-persistent 肯定在；Alpine 走自带服务
_fw_save() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1
  elif [ -f /etc/alpine-release ]; then
    if [ "$1" = "6" ]; then _fs_svc=ip6tables; else _fs_svc=iptables; fi
    [ -f "/etc/init.d/$_fs_svc" ] && "/etc/init.d/$_fs_svc" save >/dev/null 2>&1
  fi
  # 小内存模式的恢复器按现存节点的 fw_info 工作，无需保存整张规则表。
}

# _del_fw_rules <fw_info路径>：撤销该节点我们亲手加的防火墙规则（用户手写的不碰）
_del_fw_rules() {
  [ -f "$1" ] || return 0
  _fipt_v4=0
  _fipt_v6=0
  while read -r _fport _fproto _fufw _ffwl _fipt _ffamily; do
    [ -n "$_fport" ] && [ -n "$_fproto" ] || continue
    # 老版本 fw_info 只有"端口 协议"两列：按老行为尽量清干净
    _oldfmt=0
    if [ -z "$_fufw$_ffwl$_fipt" ]; then _fufw=1; _ffwl=1; _fipt=1; _oldfmt=1; fi
    if [ "$_fufw" = "1" ] && command -v ufw >/dev/null 2>&1; then
      ufw delete allow "$_fport"/"$_fproto" >/dev/null 2>&1
    fi
    if [ "$_ffwl" = "1" ] && command -v firewall-cmd >/dev/null 2>&1; then
      firewall-cmd --permanent --remove-port="$_fport"/"$_fproto" >/dev/null 2>&1
      firewall-cmd --reload >/dev/null 2>&1
    fi
    if [ "$_ffamily" = "6" ]; then _fipbin=ip6tables; else _fipbin=iptables; fi
    if [ "$_fipt" = "1" ] && command -v "$_fipbin" >/dev/null 2>&1; then
      if [ "$_ffamily" = "6" ]; then _fipt_v6=1; else _fipt_v4=1; fi
      if [ "$_oldfmt" = "1" ]; then
        while "$_fipbin" -C INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1; do
          "$_fipbin" -D INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1 || break
        done
      else
        # 新格式：这条规则是我们加的，只删一条；用户后来手加的相同规则不动
        "$_fipbin" -D INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1
      fi
    fi
    echo "已撤销端口 $_fport/$_fproto 的防火墙放行"
  done < "$1"
  # iptables 删了规则也要存盘，不然重启后删掉的规则又回来了。两种地址分开存。
  [ "$_fipt_v4" = "1" ] && _fw_save 4
  [ "$_fipt_v6" = "1" ] && _fw_save 6
}

# _stop_remove_svc <节点id>：停掉并删除该节点的服务，不碰其它节点
_stop_remove_svc() {
  _x_id="$1"
  _x_core=$(tr -d ' \r\n' < "$NODES_DIR/$_x_id/core" 2>/dev/null)
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    case "$_x_core" in
      sing-box) _x_unit="singbox-node@${_x_id}" ;;
      hysteria) _x_unit="hysteria-node@${_x_id}" ;;
      *) _x_unit="xray-node@${_x_id}" ;;
    esac
    systemctl stop "$_x_unit" >/dev/null 2>&1
    systemctl disable "$_x_unit" >/dev/null 2>&1
    systemctl reset-failed "$_x_unit" >/dev/null 2>&1
    rm -f "/etc/systemd/system/${_x_unit}.service"
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "xray-node-${_x_id}" stop >/dev/null 2>&1
    rc-update del "xray-node-${_x_id}" default >/dev/null 2>&1
    rm -f "/etc/init.d/xray-node-${_x_id}"
  fi
  # 兜底：按该节点的配置文件路径精确杀进程，不碰其它节点的进程
  pkill -f "/etc/xray-node/nodes/${_x_id}/config.json" >/dev/null 2>&1
  pkill -f "/etc/xray-node/nodes/${_x_id}/config.yaml" >/dev/null 2>&1
  # 拆掉端口跳跃的转发规则（没开跳跃时什么都不做）
  [ -x /usr/local/bin/xray-node-hop ] && /usr/local/bin/xray-node-hop down "$_x_id" >/dev/null 2>&1
  # 拆掉回程路由规则（没加过时什么都不做）
  [ -x /usr/local/bin/xray-node-route ] && /usr/local/bin/xray-node-route down "$_x_id" >/dev/null 2>&1
  sleep 1
}

# _del_node <节点id> [skip_confirm]：删除单个节点（服务+防火墙+配置），其它节点不受影响
_del_node() {
  _d_id="$1"
  [ -d "$NODES_DIR/$_d_id" ] || { echo "节点 $_d_id 不存在"; return 1; }
  if [ "$2" != "skip_confirm" ]; then
    printf "确定删除节点 %s（%s）吗？删掉后这个节点就不能用了。[y/N]: " "$_d_id" "$(_node_info "$_d_id")"
    read -r _ans || { echo "已取消"; return 0; }
    _ans=$(_clean_choice "$_ans")
    case "$_ans" in y|Y|yes|YES) ;; *) echo "已取消"; return 0 ;; esac
  fi
  echo "正在删除节点 ${_d_id}…"
  _stop_remove_svc "$_d_id"
  [ -d /run/systemd/system ] && systemctl daemon-reload >/dev/null 2>&1
  _del_fw_rules "$NODES_DIR/$_d_id/fw_info"
  # 证书用的端口如果还开着，也关上
  [ -x /usr/local/bin/xray-node-watch ] && /usr/local/bin/xray-node-watch acme-drop "$_d_id" >/dev/null 2>&1
  rm -rf "$NODES_DIR/$_d_id"
  # 没有节点再需要巡检了，就把巡检一起卸掉（全部卸载时最后统一处理）
  [ "$2" != "skip_confirm" ] && [ -x /usr/local/bin/xray-node-watch ] && /usr/local/bin/xray-node-watch arm >/dev/null 2>&1
  echo "节点 $_d_id 已删除，其它节点不受影响。"
}

# _uninstall_all：删除全部节点并卸载干净（含内核、命令、配置）
_uninstall_all() {
  echo "正在删除全部节点并卸载…"
  for _d in "$NODES_DIR"/*/; do
    [ -d "$_d" ] || continue
    _del_node "$(basename "$_d")" skip_confirm
  done
  # 巡检（每分钟检查端口跳跃规则、证书端口的小程序）也卸掉
  [ -x /usr/local/bin/xray-node-watch ] && /usr/local/bin/xray-node-watch disarm >/dev/null 2>&1
  # _svc_install 建的 systemd 模板（xray-node@.service / singbox-node@.service）
  # 不是按节点实例建的，上面的循环删不掉，不清会残留在系统里
  if [ -d /run/systemd/system ]; then
    systemctl disable xray-node-fw.service >/dev/null 2>&1
    systemctl stop xray-node-fw.service >/dev/null 2>&1
    systemctl disable --now xray-node-expire.timer >/dev/null 2>&1
  fi
  if command -v rc-update >/dev/null 2>&1; then
    rc-service xray-node-fw stop >/dev/null 2>&1
    rc-update del xray-node-fw default >/dev/null 2>&1
    rc-service xray-node-expire stop >/dev/null 2>&1
    rc-update del xray-node-expire default >/dev/null 2>&1
  fi
  if [ -f /run/xray-node-expire.pid ]; then
    kill "$(tr -d ' \r\n' < /run/xray-node-expire.pid)" >/dev/null 2>&1
    rm -f /run/xray-node-expire.pid
  fi
  rm -f /etc/systemd/system/xray-node@.service /etc/systemd/system/singbox-node@.service \
    /etc/systemd/system/hysteria-node@.service /etc/systemd/system/xray-node-fw.service \
    /etc/systemd/system/xray-node-expire.service /etc/systemd/system/xray-node-expire.timer
  rm -f /etc/init.d/xray-node-fw /etc/init.d/xray-node-expire /etc/sysctl.d/99-xray-node-overcommit.conf
  rm -f /etc/cron.d/xray-node-expire
  if [ -f /xray-node.swap ]; then
    swapoff /xray-node.swap >/dev/null 2>&1
    rm -f /xray-node.swap
    # 粘在别的行末尾时只拆掉 swap 这一段，不能整行删掉（那一行可能是根分区）
    _fs_file=${XRAY_FSTAB:-/etc/fstab}
    if [ -f "$_fs_file" ] && [ -w "$_fs_file" ]; then
      _fs_tmp=$(mktemp 2>/dev/null) || _fs_tmp=""
      if [ -n "$_fs_tmp" ] && awk '
        BEGIN { key = "/xray-node.swap none swap sw 0 0" }
        {
          i = index($0, key)
          if (i == 0) { print; next }
          if (i == 1) next
          pre = substr($0, 1, i - 1)
          if (pre != "") print pre
        }
      ' "$_fs_file" > "$_fs_tmp"; then
        cat "$_fs_tmp" > "$_fs_file"
      fi
      rm -f "$_fs_tmp"
    fi
  fi
  [ -d /run/systemd/system ] && systemctl daemon-reload >/dev/null 2>&1
  # 只删脚本自己下载安装的内核（our_bins 里记着），用户机器上本来就有的不碰
  # 注意：必须在删 /etc/xray-node 之前读
  if [ -f /etc/xray-node/our_bins ]; then
    while read -r _b; do
      case "$_b" in
        xray|sing-box|hysteria) rm -f "/usr/local/bin/$_b" && echo "已删除脚本安装的 $_b" ;;
      esac
    done < /etc/xray-node/our_bins
  fi
  # 脚本自己建的运行用户 xray-node 也删掉
  if [ -f /etc/xray-node/svc_user_created ] && id xray-node >/dev/null 2>&1; then
    userdel xray-node >/dev/null 2>&1 || true
  fi
  # 删掉配置、节点、日志
  rm -rf /etc/xray-node
  rm -f /var/log/xray-node-*.log
  rm -f /etc/sysctl.d/99-xray-node-bbr.conf
  rm -f /usr/local/bin/jiedian
  rm -f /usr/local/bin/shanjiedian /usr/local/bin/xiezai
  rm -f /usr/local/bin/xray-node-fw-restore
  rm -f /usr/local/bin/xray-node-expire /usr/local/bin/xray-node-run /usr/local/bin/xray-node-expire-loop
  rm -f /usr/local/bin/xray-node-hop /usr/local/bin/xray-node-watch /usr/local/bin/xray-node-watch.tmp
  rm -f /usr/local/bin/xray-node-route /usr/local/bin/xray-node-route.tmp
  rm -rf /run/xray-node-hop /run/xray-node-watch /run/xray-node-route
  echo "卸载完成：所有节点、配置、开机自启、防火墙规则都已清除干净。"
  # IPv6 开关是整台服务器的设置，不跟着节点删。关过的话提醒一下怎么打开。
  if [ -f /etc/sysctl.d/99-xray-node-ipv6.conf ]; then
    echo "注意：你之前在菜单里关掉的 IPv6 仍然是关闭的。想打开：重新运行一键安装命令，选「开启 IPv6」，再选退出。"
  fi
}

# 去掉空格和回车符。复制进去时经常带上这些。
_clean_choice() {
  printf '%s' "$1" | tr -d '[:space:]'
}

_n_count=0
_n_ids=""
_n_max=0
for _d in "$NODES_DIR"/*/; do
  [ -f "${_d}node.txt" ] || continue
  _n_id=$(basename "$_d")
  # 编号会跳号（删过的不重用）。输入几就删节点几，不能按第几行来删。
  # 否则列表里第 2 行可能是节点 5，输入 2 会把还在用的节点删掉。
  case "$_n_id" in ''|*[!0-9]*) continue ;; esac
  _n_count=$((_n_count + 1))
  _n_ids="$_n_ids $_n_id"
  [ "$_n_id" -gt "$_n_max" ] && _n_max="$_n_id"
done
if [ "$_n_count" = "0" ]; then
  echo "没有已安装的节点。"
  exit 0
fi
# 有节点 1、2、3 时，4 就是删除全部。有节点 1、2、5 时，6 才是删除全部。
_n_all=$((_n_max + 1))
echo "==================== 节点管理 ===================="
_n_sorted=$(printf '%s\n' $_n_ids | sort -n)
for _n_id in $_n_sorted; do
  printf "  %s) 删除节点 %s（%s）\n" "$_n_id" "$_n_id" "$(_node_info "$_n_id")"
done
printf "  %s) 删除全部节点并卸载干净\n" "$_n_all"
printf "  0) 取消，什么都不删\n"
printf "请选择: "
read -r _sel || { echo "已取消"; exit 0; }
_sel=$(_clean_choice "$_sel")
case "$_sel" in
  0|"") echo "已取消" ;;
  *[!0-9]*) echo "输入不对，已取消" ;;
  *)
    # 08 和 8 是同一个节点。先去掉数字前面的 0。
    _sel=$(printf '%s' "$_sel" | sed 's/^0*//')
    if [ -z "$_sel" ] || [ "$_sel" = "0" ]; then
      echo "已取消"
    elif [ "$_sel" = "$_n_all" ]; then
      printf "这会删除全部 %s 个节点，并卸掉内核、命令和配置。删了就不能用了。\n" "$_n_count"
      printf "确定删除全部节点并卸载干净吗？[y/N]: "
      read -r _ans2 || { echo "已取消"; exit 0; }
      _ans2=$(_clean_choice "$_ans2")
      case "$_ans2" in
        y|Y|yes|YES) _uninstall_all ;;
        *) echo "已取消" ;;
      esac
    else
      _found=0
      for _cand in $_n_ids; do
        if [ "$_cand" = "$_sel" ]; then
          _found=1
          _del_node "$_sel"
          break
        fi
      done
      [ "$_found" = "1" ] || echo "没有这个编号，已取消"
    fi
    ;;
esac
XZEOF
chmod 700 /usr/local/bin/shanjiedian
# 旧版的 xiezai 是"一键全删"，改名后把它删掉，免得留着误导人
rm -f /usr/local/bin/xiezai
for _hy_node in /etc/xray-node/nodes/*/; do
  [ -f "${_hy_node}core" ] && [ -f "${_hy_node}node.txt" ] || continue
  [ "$(tr -d ' \r\n' < "${_hy_node}core")" = "hysteria" ] || continue
  # 旧节点只修分享链接和文字提示；证书、密码、端口和服务不变。
  if grep -q '^hysteria2://.*pinSHA256=' "${_hy_node}node.txt" &&
     ! grep -q '^hysteria2://.*[?&]insecure=' "${_hy_node}node.txt"; then
    sed -e '/^hysteria2:\/\//s/?sni=/?insecure=1\&sni=/' \
      -e 's/客户端不要打开“跳过证书验证”。如果导入后证书锁定是空的，把上面的指纹填进去。/官方 Hysteria2 客户端：自签证书须同时启用 insecure 和证书指纹锁定；如果指纹为空，填入上面的值。/' \
      "${_hy_node}node.txt" > "${_hy_node}node.txt.tmp" &&
      mv -f "${_hy_node}node.txt.tmp" "${_hy_node}node.txt"
    chmod 600 "${_hy_node}node.txt" 2>/dev/null
  fi
done
install_expire_bins || true
arm_expire_watch || true
# 端口跳跃 / 证书端口的巡检：有节点要用就挂上，没有就卸掉
arm_node_watch || true
}

# ---------- 服务（让节点在后台一直跑、开机自启） ----------
_hy_export_env() { # 给没有 systemd 的启动方式用。和 unit 文件里的 Environment 保持一致。
  export HYSTERIA_DISABLE_UPDATE_CHECK=1
  export HYSTERIA_LOG_LEVEL=warn
  if [ "$LOW_MEM" = "1" ]; then
    export GOGC=30
    if [ "$SWAP_OK" != "1" ] && [ -n "$MEM_MB" ]; then
      _hy_gomem=$((MEM_MB / 3))
      [ "$_hy_gomem" -lt 16 ] && _hy_gomem=16
      [ "$_hy_gomem" -gt 32 ] && _hy_gomem=32
      export GOMEMLIMIT="${_hy_gomem}MiB"
    fi
  fi
}

# systemd 够新（>= 231）、内核够新（>= 4.3）才改用普通用户跑 Hysteria2。
_svc_can_drop_root() {
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] || return 1
  _scd_v=$(systemctl --version 2>/dev/null | awk 'NR==1 {print $2}' | sed 's/[^0-9].*//')
  case "$_scd_v" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_scd_v" -ge 231 ] || return 1
  _scd_k=$(uname -r 2>/dev/null)
  _scd_maj=${_scd_k%%.*}; _scd_rest=${_scd_k#*.}; _scd_min=${_scd_rest%%[!0-9]*}
  case "$_scd_maj$_scd_min" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_scd_maj" -gt 4 ] || { [ "$_scd_maj" -eq 4 ] && [ "$_scd_min" -ge 3 ]; }
}

# 建一个不能登录的系统用户 xray-node，专门用来跑 Hysteria2。
_ensure_svc_user() {
  id xray-node >/dev/null 2>&1 && return 0
  command -v useradd >/dev/null 2>&1 || return 1
  _esu_sh=/usr/sbin/nologin
  [ -x "$_esu_sh" ] || _esu_sh=/sbin/nologin
  [ -x "$_esu_sh" ] || _esu_sh=/bin/false
  useradd --system --no-create-home --home-dir /nonexistent --shell "$_esu_sh" xray-node >/dev/null 2>&1 || return 1
  mkdir -p /etc/xray-node 2>/dev/null
  : > /etc/xray-node/svc_user_created
  return 0
}

# _hy_perms <节点id> <运行用户>：用普通用户跑时，让它只能读自己的配置、证书（节点链接 node.txt 仍然只有 root 能看）。
_hy_perms() {
  _hp_d=/etc/xray-node/nodes/$1
  [ -d "$_hp_d" ] || return 0
  if [ "$2" != "xray-node" ] || ! id xray-node >/dev/null 2>&1; then
    chmod 700 "$_hp_d" 2>/dev/null
    return 0
  fi
  chmod 711 /etc/xray-node /etc/xray-node/nodes 2>/dev/null
  chgrp xray-node "$_hp_d" 2>/dev/null && chmod 750 "$_hp_d"
  for _hp_f in config.yaml cert.pem key.pem core expire; do
    [ -f "$_hp_d/$_hp_f" ] || continue
    chgrp xray-node "$_hp_d/$_hp_f" 2>/dev/null && chmod 640 "$_hp_d/$_hp_f"
  done
  if grep -q '^acme:' "$_hp_d/config.yaml" 2>/dev/null; then
    mkdir -p "$_hp_d/acme" && chown -R xray-node:xray-node "$_hp_d/acme" 2>/dev/null && chmod 700 "$_hp_d/acme"
  fi
}

# 把节点注册成系统服务。
# systemd 用“模板服务”：一个 xray-node@.service 文件，节点 1 就是 xray-node@1，节点 2 是 xray-node@2，
# 各管各的。程序意外退出会在 5 秒后自动重启（Restart=on-failure）。
# 没有 systemd 的机器（Alpine 等）用 OpenRC；两者都没有就用 nohup 放到后台跑（重启后要重跑脚本）。
_svc_install() { # _svc_install <节点id>：按该节点的 core 装好开机自启服务并启动（systemd 模板实例 / OpenRC 独立脚本 / 兜底后台）
  _si_id="$1"
  _si_core=$(tr -d ' \r\n' < /etc/xray-node/nodes/"$_si_id"/core 2>/dev/null)
  _si_cfg=/etc/xray-node/nodes/"$_si_id"/config.json
  _si_unit_env=""
  _si_openrc_env=""
  case "$_si_core" in
    hysteria)
      _si_cfg=/etc/xray-node/nodes/"$_si_id"/config.yaml
      _si_bin="$HY_BIN"; _si_args="server -c $_si_cfg"
      _si_tpl=/etc/systemd/system/hysteria-node@.service; _si_unit="hysteria-node@${_si_id}"
      # 关掉官方程序的更新检查，小内存机器上这一下会多占内存、还可能卡住启动
      _si_unit_env="Environment=HYSTERIA_DISABLE_UPDATE_CHECK=1
Environment=HYSTERIA_LOG_LEVEL=warn"
      _si_openrc_env="export HYSTERIA_DISABLE_UPDATE_CHECK=1
export HYSTERIA_LOG_LEVEL=warn"
      if [ "$LOW_MEM" = "1" ]; then
        _si_unit_env="${_si_unit_env}
Environment=GOGC=30"
        _si_openrc_env="${_si_openrc_env}
export GOGC=30"
        if [ "$SWAP_OK" != "1" ] && [ -n "$MEM_MB" ]; then
          _hy_gomem=$((MEM_MB / 3))
          [ "$_hy_gomem" -lt 16 ] && _hy_gomem=16
          [ "$_hy_gomem" -gt 32 ] && _hy_gomem=32
          _si_unit_env="${_si_unit_env}
Environment=GOMEMLIMIT=${_hy_gomem}MiB"
          _si_openrc_env="${_si_openrc_env}
export GOMEMLIMIT=${_hy_gomem}MiB"
        fi
      fi
      ;;
    sing-box) _si_bin="$SB_BIN"; _si_args="run -c $_si_cfg"; _si_tpl=/etc/systemd/system/singbox-node@.service; _si_unit="singbox-node@${_si_id}" ;;
    *)        _si_bin="$XRAY_BIN"; _si_args="-config $_si_cfg"; _si_tpl=/etc/systemd/system/xray-node@.service; _si_unit="xray-node@${_si_id}" ;;
  esac
  # 小内存机器上 Xray / sing-box 也让 Go 勤快点回收内存，少占一些，不容易被系统杀掉
  if [ "$LOW_MEM" = "1" ] && [ "$_si_core" != "hysteria" ]; then
    _si_unit_env="Environment=GOGC=30"
    _si_openrc_env="export GOGC=30"
  fi
  SVC_UNIT="$_si_unit"
  _si_svc="xray-node-${_si_id}"
  install_expire_bins || true
  install_hop_bin || true
  install_route_bin || true
  # Hysteria2 用普通用户 xray-node 运行（只给“绑 1024 以下端口”这一项权限），
  # 万一程序有漏洞，别人也拿不到 root。端口跳跃的转发规则要 root 才能写，
  # 所以用 systemd 的 “+” 前缀单独以 root 身份跑 xray-node-hop。
  # 老 systemd（< 231，比如 CentOS 7）不认 “+” 前缀；老内核（< 4.3）不支持只给一项权限。这两种情况照旧用 root。
  _si_user=root
  _si_plus=""
  _si_harden=""
  if [ "$_si_core" = "hysteria" ] && [ ! -f /etc/xray-node/hy_root ] && _svc_can_drop_root && _ensure_svc_user; then
    _si_user=xray-node
    _si_plus="+"
    _si_harden="AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true"
  fi
  [ "$_si_core" = "hysteria" ] && _hy_perms "$_si_id" "$_si_user"
  # 包装脚本在到期时直接退出，避免重启后过期节点又把端口打开。
  if [ -x /usr/local/bin/xray-node-run ]; then
    _si_bin=/usr/local/bin/xray-node-run
    _si_args="$_si_id"
  fi
  [ "$LOW_MEM" = "1" ] && drop_page_cache
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    # 每次都重写模板。只在文件不存在时写一次的话，旧模板没有小内存环境变量，
    # 64MB 机器更新内核后新进程照旧被打爆，端口起不来。
    case "$_si_core" in
      hysteria) _si_tpl_bin="$HY_BIN"; _si_tpl_args="server -c /etc/xray-node/nodes/%i/config.yaml"; _si_tpl_desc="Hysteria2 node %i" ;;
      sing-box) _si_tpl_bin="$SB_BIN"; _si_tpl_args="run -c /etc/xray-node/nodes/%i/config.json"; _si_tpl_desc="sing-box node %i" ;;
      *)        _si_tpl_bin="$XRAY_BIN"; _si_tpl_args="-config /etc/xray-node/nodes/%i/config.json"; _si_tpl_desc="Xray node %i" ;;
    esac
    if [ -x /usr/local/bin/xray-node-run ]; then
      _si_tpl_exec="/usr/local/bin/xray-node-run %i"
    else
      _si_tpl_exec="${_si_tpl_bin} ${_si_tpl_args}"
    fi
    _si_hop_pre=""
    _si_hop_post=""
    if [ "$_si_core" = "hysteria" ]; then
      # 端口跳跃：启动前打开转发，停止后拆掉（没开跳跃的节点什么都不做）。前面的 “-” 表示失败也照样启动主端口。
      _si_hop_pre="ExecStartPre=-${_si_plus}/usr/local/bin/xray-node-hop up %i"
      _si_hop_post="ExecStopPost=-${_si_plus}/usr/local/bin/xray-node-hop down %i"
    fi
    # 回程路由：UDP 节点在有策略路由的机器上，回包要走公网网卡（不是 UDP 节点时这一步什么都不做）
    _si_rt_pre="ExecStartPre=-${_si_plus}/usr/local/bin/xray-node-route up %i"
    _si_rt_post="ExecStopPost=-${_si_plus}/usr/local/bin/xray-node-route down %i"
    cat > "$_si_tpl" <<EOF
[Unit]
Description=${_si_tpl_desc}
After=network.target
[Service]
Type=simple
User=${_si_user}
${_si_unit_env}
${_si_harden}
${_si_hop_pre}
${_si_rt_pre}
ExecStart=${_si_tpl_exec}
${_si_hop_post}
${_si_rt_post}
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$_si_unit" >/dev/null 2>&1
    systemctl restart "$_si_unit" >/dev/null 2>&1
    sleep 1
    if systemctl is-active --quiet "$_si_unit"; then
      info "节点 $_si_id 服务已启动，并设为开机自启"
    else
      warn "节点 $_si_id 服务好像没起来，运行 systemctl status $_si_unit 看看原因"
    fi
  elif command -v rc-service >/dev/null 2>&1; then
    _si_rc_hop_up=":"
    _si_rc_hop_down=":"
    if [ "$_si_core" = "hysteria" ]; then
      _si_rc_hop_up="/usr/local/bin/xray-node-hop up ${_si_id} >/dev/null 2>&1 || true"
      _si_rc_hop_down="/usr/local/bin/xray-node-hop down ${_si_id} >/dev/null 2>&1 || true"
    fi
    cat > /etc/init.d/${_si_svc} <<RCEOF
#!/sbin/openrc-run
${_si_openrc_env}
name="${_si_svc}"
description="${_si_svc} proxy service"
command="${_si_bin}"
command_args="${_si_args}"
command_background="yes"
pidfile="/run/${_si_svc}.pid"
output_log="/var/log/${_si_svc}.log"
error_log="/var/log/${_si_svc}.log"
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
    # 端口跳跃：启动前打开转发（没开跳跃的节点什么都不做）
    ${_si_rc_hop_up}
    # WireGuard 落地：装了 wg-luodi 时，让它看看这个节点的端口要不要走 WireGuard（没装就跳过）
    [ -x /usr/local/bin/wg-luodi ] && /usr/local/bin/wg-luodi hook ${_si_id} >/dev/null 2>&1 || true
    # 回程路由：有策略路由的机器上，UDP 回包走公网网卡（不需要时什么都不做）
    /usr/local/bin/xray-node-route up ${_si_id} >/dev/null 2>&1 || true
}
stop_post() {
    ${_si_rc_hop_down}
    /usr/local/bin/xray-node-route down ${_si_id} >/dev/null 2>&1 || true
}
RCEOF
    chmod +x /etc/init.d/${_si_svc}
    rc-update add "$_si_svc" default >/dev/null 2>&1
    # 先清掉可能残留的旧状态，再启动（比 restart 更稳）
    rc-service "$_si_svc" zap >/dev/null 2>&1
    rc-service "$_si_svc" start >/dev/null 2>&1
    sleep 1
    if rc-service "$_si_svc" status >/dev/null 2>&1; then
      info "节点 $_si_svc 已启动，并设为开机自启"
    else
      warn "节点 $_si_svc 好像没起来，运行 rc-service $_si_svc status 看看原因"
    fi
  else
    warn "没找到 systemd/OpenRC，改用后台方式启动（重启后需手动再跑一次脚本）"
    if [ "$_si_core" = "hysteria" ]; then
      _hy_export_env
      /usr/local/bin/xray-node-hop up "$_si_id" >/dev/null 2>&1 || true
    elif [ "$LOW_MEM" = "1" ]; then
      export GOGC=30
    fi
    # WireGuard 落地：装了 wg-luodi 时先让它改好配置（没装就跳过）
    [ -x /usr/local/bin/wg-luodi ] && /usr/local/bin/wg-luodi hook "$_si_id" >/dev/null 2>&1 || true
    /usr/local/bin/xray-node-route up "$_si_id" >/dev/null 2>&1 || true
    pkill -f "$_si_cfg" >/dev/null 2>&1
    # _si_args 故意不加引号，拆成多个参数
    # shellcheck disable=SC2086
    nohup $_si_bin $_si_args >/var/log/xray-node-${_si_id}.log 2>&1 &
    sleep 1
    info "节点 $_si_id 已在后台启动"
  fi
}

_svc_restart() { # _svc_restart <节点id>：重写服务模板后再重启（更新模式用）
  # 走 _svc_install：它会重写 systemd/OpenRC 模板。只 systemctl restart 的话，
  # 64MB 机器上的旧单元没有 GOMEMLIMIT，新内核一起就可能被打爆。
  _svc_install "$1"
}

# ---------- Hysteria2 的 IPv4 / IPv6 双栈 ----------
# 双栈 = 同时有 IPv4 和 IPv6 地址。Hysteria2 走 UDP，这里判断要不要两种地址都听，
# 这样不管你家网络是 IPv4 还是 IPv6 都能连。
_hy_local_ipv4() { # 打印本机第一个全局 IPv4；没有就失败。内网地址也算，用来判断要不要双栈监听。
  command -v ip >/dev/null 2>&1 || return 1
  _hip=$(ip -4 -o addr show scope global 2>/dev/null | awk '
    { split($4, a, "/"); if (a[1] != "") { print a[1]; exit } }
  ')
  [ -n "$_hip" ] || return 1
  printf '%s' "$_hip"
}

_hy_local_ipv6() { # 打印本机第一个公网 IPv6。临时地址和内网地址（fc/fd）不要，客户端连不上。
  command -v ip >/dev/null 2>&1 || return 1
  _hip6=$(ip -6 -o addr show scope global 2>/dev/null | awk '
    / temporary/ || / deprecated/ { next }
    {
      split($4, a, "/")
      ip = a[1]
      if (ip == "" || ip ~ /^[fF][cCdD]/) next
      print ip
      exit
    }
  ')
  [ -n "$_hip6" ] || return 1
  _valid_ip 6 "$_hip6" || return 1
  printf '%s' "$_hip6"
}

# 端口跳跃：除了主端口，再多给几个 UDP 端口，客户端会在这些端口之间换着连。
# 每个端口一个一个填，直接回车就结束。也可以填 20000-20010 这种一段连续的端口。
# 填过的端口用逗号串起来，例如 20000,20001,30000-30010。空字符串表示不开。
_hy_hop_family() { # 这个节点会听哪几种地址：46 = IPv4 和 IPv6 都听
  if _hy_local_ipv6 >/dev/null 2>&1 && _hy_local_ipv4 >/dev/null 2>&1; then
    printf '46'
  else
    printf '%s' "$IPVER"
  fi
}

_hy_hop_overlap() { # _hy_hop_overlap <起> <止> -> 0 表示和主端口或已经填过的端口重叠
  for _ho_p in $PORT $LINK_PORT $(printf '%s' "$HY_HOP_PORTS" | tr ',' ' '); do
    _ho_a=${_ho_p%-*}; _ho_b=${_ho_p#*-}
    [ "$1" -le "$_ho_b" ] && [ "$2" -ge "$_ho_a" ] && return 0
  done
  return 1
}

_hy_hop_busy() { # _hy_hop_busy <起> <止> -> 打印第一个已被占用的 UDP 端口
  if [ "$1" = "$2" ]; then
    port_in_use "$1" udp && { printf '%s' "$1"; return 0; }
    return 1
  fi
  command -v ss >/dev/null 2>&1 || return 1
  ss -uln 2>/dev/null | awk -v a="$1" -v b="$2" '
    NR > 1 { n = split($4, x, ":"); p = x[n] + 0; if (p >= a && p <= b) { print p; found = 1; exit } }
    END { exit !found }
  '
}

_hy_collect_hop_ports() {
  HY_HOP_PORTS=""
  printf "下面一个一个填跳跃端口，每填一个就回车。填完以后，下一个直接回车就结束。\n"
  printf "可以填一个端口（比如 20001），也可以填一段（比如 20000-20010）。不要和主端口 %s 重复。最多 16 项。\n" "$PORT"
  if [ "$LINK_PORT" != "$PORT" ]; then
    printf "你这台是 NAT 小鸡（公网端口 %s 和本机端口 %s 不一样）。跳跃端口必须在服务商分给你的端口范围里，\n" "$LINK_PORT" "$PORT"
    printf "而且服务商要按相同号码转发进来（公网 20001 进来就到本机 20001）。不在范围里的端口填了也连不上。\n"
  fi
  _hh_n=1
  _hh_blank=0
  while [ "$_hh_n" -le 16 ]; do
    printf "请设置你的端口跳跃%s（输入端口后回车）: " "$_hh_n"
    if ! read -r _hh_a; then
      printf "\n" >&2
      die "没有读到你的选择，已停止，没有继续安装。请重新粘贴 README 里的那一行安装命令。"
    fi
    _hh_a=$(printf '%s' "$_hh_a" | tr -d ' \t\r')
    if [ -z "$_hh_a" ]; then
      [ -n "$HY_HOP_PORTS" ] && break
      _hh_blank=$((_hh_blank + 1))
      if [ "$_hh_blank" -ge 2 ]; then
        warn "没有填端口，改为不开启端口跳跃"
        HY_HOP_PORTS=""
        break
      fi
      warn "还没填端口。再直接回车就改为不开启。"
      continue
    fi
    _hh_blank=0
    case "$_hh_a" in
      *[!0-9-]*|-*|*-|*-*-*)
        warn "这个不是端口。请输入 1 到 65535 的数字，或者 20000-20010 这种一段。"
        continue
        ;;
    esac
    _hh_lo=${_hh_a%-*}; _hh_hi=${_hh_a#*-}
    _hh_lo=$(printf '%s' "$_hh_lo" | sed 's/^0*//'); [ -z "$_hh_lo" ] && _hh_lo=0
    _hh_hi=$(printf '%s' "$_hh_hi" | sed 's/^0*//'); [ -z "$_hh_hi" ] && _hh_hi=0
    if [ "${#_hh_lo}" -gt 5 ] || [ "${#_hh_hi}" -gt 5 ] || [ "$_hh_lo" -lt 1 ] || [ "$_hh_hi" -gt 65535 ] || [ "$_hh_hi" -lt 1 ] || [ "$_hh_lo" -gt 65535 ]; then
      warn "端口超出 1 到 65535，请重新输入。"
      continue
    fi
    if [ "$_hh_lo" -gt "$_hh_hi" ]; then
      warn "一段端口要小的在前、大的在后，比如 20000-20010。请重新输入。"
      continue
    fi
    if _hy_hop_overlap "$_hh_lo" "$_hh_hi"; then
      warn "和主端口或前面填过的端口重复了，请换一个。"
      continue
    fi
    if _hh_busy=$(_hy_hop_busy "$_hh_lo" "$_hh_hi"); then
      warn "端口 ${_hh_busy}/UDP 已经有程序在用。转发过来会抢走它的流量，请换一个。"
      continue
    fi
    if [ "$_hh_lo" = "$_hh_hi" ]; then _hh_item="$_hh_lo"; else _hh_item="${_hh_lo}-${_hh_hi}"; fi
    HY_HOP_PORTS="${HY_HOP_PORTS:+${HY_HOP_PORTS},}${_hh_item}"
    _hh_n=$((_hh_n + 1))
  done
  if [ "$_hh_n" -gt 16 ] && [ -n "$HY_HOP_PORTS" ]; then
    info "已经填了 16 项，够用了，不再继续问。"
  fi
}

_hy_ask_hop() {
  HY_HOP_PORTS=""
  printf "\n是否开启端口跳跃？\n"
  printf "开了以后，除了主端口，再多开几个 UDP 端口，客户端隔一会儿换一个端口连。\n"
  printf "有的地方运营商会把长时间用的单个 UDP 端口限速或掐断，换着端口就不容易被盯上。\n"
  printf "  1) 开启\n"
  printf "  2) 不开启\n"
  printf "看不懂就回车，默认不开启。\n"
  while true; do
    ask "请选择" "2" _hy_hop_choice
    case "$_hy_hop_choice" in
      1) break ;;
      2) info "不开启端口跳跃"; return 0 ;;
      *) warn "没有这个选项，请重新选择" ;;
    esac
  done
  printf "先试一下这台机器能不能做端口转发…\n"
  if ! _hy_hop_probe "$(_hy_hop_family)"; then
    warn "这台机器做不了端口跳跃，改为不开启。节点照样能用，只用主端口 ${PORT}。"
    return 0
  fi
  info "这台机器可以做端口跳跃"
  while true; do
    _hy_collect_hop_ports
    [ -n "$HY_HOP_PORTS" ] || return 0
    printf "\n你设置的端口跳跃：主端口 %s，跳跃端口 %s\n" "$PORT" "$(printf '%s' "$HY_HOP_PORTS" | sed 's/,/、/g')"
    printf "  1) 确认，就用这些\n"
    printf "  2) 重新填\n"
    printf "  3) 不开启端口跳跃了\n"
    ask "请选择" "1" _hy_hop_ok
    case "$_hy_hop_ok" in
      2) continue ;;
      3) HY_HOP_PORTS=""; info "不开启端口跳跃"; return 0 ;;
      *) info "端口跳跃已设置：$(printf '%s' "$HY_HOP_PORTS" | sed 's/,/、/g')"; return 0 ;;
    esac
  done
}

# 混淆（salamander）：把每个 UDP 包再用混淆密码打乱一遍。外面看不出这是 QUIC，
# 不知道混淆密码的人来探测，服务器一声不吭，像没开这个端口。
# 代价：没有“伪装网站”效果了，而且客户端必须支持 salamander（主流客户端都支持）。
_hy_ask_obfs() {
  printf "\n要不要打开 Hysteria2 混淆（salamander）？\n"
  printf "  1) 打开（推荐在中国大陆用：包看起来是一串乱码，认不出是 QUIC；别人来探测，服务器不回应）\n"
  printf "  2) 不打开（看起来就是普通的 HTTP/3 网站，别人来探测会看到一个真实网页；很老的客户端也能连）\n"
  printf "看不懂就回车，默认打开。\n"
  while true; do
    ask "请选择" "1" _hy_obfs_choice
    case "$_hy_obfs_choice" in
      1) HY2_USE_OBFS=1; info "混淆：打开"; return 0 ;;
      2) HY2_USE_OBFS=0; info "混淆：不打开，用伪装网站"; return 0 ;;
      *) warn "没有这个选项，请重新选择" ;;
    esac
  done
}

# 自己有域名（已经解析到这台服务器）时，可以申请正规证书（Let's Encrypt），客户端不用“跳过证书验证”。
# 没有域名就用自签证书 + 证书指纹（pinSHA256）：客户端只认这一张证书，别人冒充不了，同样安全。
# 申请证书要外面能连到这台机器的 TCP 80（或 443）端口，NAT 小鸡一般做不到，所以 NAT 小鸡直接用自签。
_hy_ask_domain() {
  HY2_DOMAIN=""; HY2_ACME_TYPE=""
  printf "\n有没有已经解析到这台服务器的域名？\n"
  printf "有的话用它申请正规证书；没有就直接回车，用自签证书加证书指纹，一样安全。\n"
  ask "你的域名（没有就回车）" "" _hy_dom
  _hy_dom=$(printf '%s' "$_hy_dom" | tr 'A-Z' 'a-z')
  if [ -z "$_hy_dom" ]; then
    info "证书：自签证书（链接里带证书指纹）"
    return 0
  fi
  case "$_hy_dom" in
    *[!a-z0-9.-]*|.*|*.|*..*|*.*.*.*.*.*.*) _hy_dom_bad=1 ;;
    *.*) _hy_dom_bad=0 ;;
    *) _hy_dom_bad=1 ;;
  esac
  if [ "$_hy_dom_bad" = "1" ]; then
    warn "「${_hy_dom}」不像域名，改用自签证书"
    return 0
  fi
  if [ "$LINK_PORT" != "$PORT" ]; then
    warn "NAT 小鸡一般收不到申请证书用的 80/443 端口请求，改用自签证书"
    return 0
  fi
  if command -v getent >/dev/null 2>&1; then
    _hy_dom_ips=$(getent ahosts "$_hy_dom" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')
    if [ -z "$_hy_dom_ips" ]; then
      warn "查不到 ${_hy_dom} 的解析，改用自签证书。先去域名后台加一条 A/AAAA 记录指向 ${SERVER_IP}"
      return 0
    fi
    case " $_hy_dom_ips " in
      *" $SERVER_IP "*) ;;
      *)
        warn "${_hy_dom} 解析到 ${_hy_dom_ips}，不是这台服务器 ${SERVER_IP}（开了 CDN 小云朵也会这样）。改用自签证书"
        return 0
        ;;
    esac
  fi
  if ! port_in_use 80 tcp; then
    HY2_ACME_TYPE=http
  elif ! port_in_use 443 tcp; then
    HY2_ACME_TYPE=tls
  else
    warn "这台机器的 TCP 80 和 443 都被别的程序占着，申请不了证书，改用自签证书"
    return 0
  fi
  HY2_DOMAIN="$_hy_dom"
  info "证书：给 ${HY2_DOMAIN} 申请正规证书（启动时自动申请，申请不下来会自动改回自签证书）"
}

# 写 Hysteria2 的配置文件。证书申请失败时会用自签证书再写一次，所以单独做成函数。
_hy_write_config() {
  if [ -n "$HY2_DOMAIN" ]; then
    _hy_tls="acme:
  domains:
    - $HY2_DOMAIN
  dir: $NODE_DIR/acme
  type: $HY2_ACME_TYPE"
  else
    _hy_tls="tls:
  cert: $NODE_DIR/cert.pem
  key: $NODE_DIR/key.pem
  sniGuard: dns-san"
  fi
  _hy_obfs_blk=""
  if [ "$HY2_USE_OBFS" = "1" ]; then
    _hy_obfs_blk="
obfs:
  type: salamander
  salamander:
    password: \"$HY2_OBFS\"
"
  fi
  if [ "$HY2_USE_OBFS" = "1" ]; then
    # 开了混淆，不知道混淆密码的人根本走不到伪装页这一步，放一段普通网页就够了，不额外连外网。
    _hy_masq="masquerade:
  type: string
  string:
    content: \"<!DOCTYPE html><html><head><title>Welcome</title></head><body><p>Welcome</p></body></html>\"
    headers:
      content-type: text/html
    statusCode: 200"
  else
    # 没开混淆时，别人用浏览器（HTTP/3）来探测，看到的是一个真实网站的内容。
    _hy_masq="masquerade:
  type: proxy
  proxy:
    url: https://www.samsung.com/
    rewriteHost: true"
    # 有正规证书时，同一个端口的 TCP 也开一个 HTTPS 网站：真网站都是 TCP 和 UDP 一起开的。
    if [ -n "$HY2_DOMAIN" ] && [ "$HY_TCP_MASQ" = "1" ]; then
      _hy_masq="${_hy_masq}
  listenHTTPS: \":$PORT\""
    fi
  fi
  cat > "$HY_CONF" <<EOF
listen: "$HY_LISTEN"

$_hy_tls
$_hy_obfs_blk
auth:
  type: password
  password: "$HY2_PASS"

# 不听客户端报的带宽，统一用 BBR 拥塞控制，不会因为客户端乱填带宽把线路挤爆。
ignoreClientBandwidth: true
# 测速接口关掉，别人不能拿它来识别这是 Hysteria2。
speedTest: false

$_hy_masq
$_hy_quic
EOF
  chmod 600 "$HY_CONF" 2>/dev/null
}

_hy_listen_for() { # _hy_listen_for <端口> <4|6> <非空=两种都听>
  # 官方 Hysteria2 把 0.0.0.0 收成只听 IPv4，把 [::] 收成只听 IPv6。
  # 写成 :端口 才是同一个口同时收两种地址。只有一种地址时维持单栈，
  # 避免纯 IPv4 机器去绑一个用不了的 IPv6。
  if [ -n "$3" ]; then
    printf ':%s' "$1"
    return 0
  fi
  if [ "$2" = "6" ]; then
    printf '[::]:%s' "$1"
  else
    printf '0.0.0.0:%s' "$1"
  fi
}

_hy_set_listen() { # _hy_set_listen <config.yaml> <listen值>
  _hs_tmp="$1.tmp"
  awk -v listen="$2" '
    /^listen:/ { print "listen: \"" listen "\""; found = 1; next }
    { print }
    END { if (!found) exit 1 }
  ' "$1" > "$_hs_tmp" && mv -f "$_hs_tmp" "$1" || return 1
  chmod 600 "$1" 2>/dev/null
  return 0
}

_hy_read_listen() { # _hy_read_listen <config.yaml>：打印 listen 的值（去掉引号）
  awk '
    /^listen:/ {
      line = $0
      sub(/\r$/, "", line)
      sub(/^listen:[[:space:]]*/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }
  ' "$1" 2>/dev/null
}

_hop_set_family() { # _hop_set_family <节点目录> <4|6|46>：改端口跳跃要管哪种地址
  [ -f "$1/hop" ] || return 0
  sed -i "s/^family=.*/family=$2/" "$1/hop" 2>/dev/null
}

# 以前的端口跳跃把所有端口都写在 listen 里（:主端口,跳跃端口…），Hysteria2 会去听最小的那个。
# 更新时改成新写法：listen 只写主端口，跳跃端口写进 hop 文件，由 xray-node-hop 转发。
# 改完端口没起来就恢复原来的配置。
_hy_migrate_hop_all() {
  for _mh_d in /etc/xray-node/nodes/*/; do
    [ -f "${_mh_d}core" ] && [ -f "${_mh_d}config.yaml" ] || continue
    [ "$(tr -d ' \r\n' < "${_mh_d}core")" = "hysteria" ] || continue
    _mh_cfg="${_mh_d}config.yaml"
    _mh_l=$(_hy_read_listen "$_mh_cfg")
    case "$_mh_l" in *,*) ;; *) continue ;; esac
    case "$_mh_l" in
      0.0.0.0:*) _mh_pre="0.0.0.0:"; _mh_fam=4 ;;
      \[::\]:*) _mh_pre="[::]:"; _mh_fam=6 ;;
      :*) _mh_pre=":"; _mh_fam=46 ;;
      *) continue ;;
    esac
    _mh_body=${_mh_l#"$_mh_pre"}
    _mh_main=${_mh_body%%,*}
    _mh_hops=${_mh_body#*,}
    case "$_mh_main" in ''|*[!0-9]*) continue ;; esac
    case "$_mh_hops" in ''|*[!0-9,-]*) continue ;; esac
    _mh_id=$(basename "$_mh_d")
    cp -a "$_mh_cfg" "${_mh_cfg}.bak-hop" || continue
    printf 'main=%s\nports=%s\nfamily=%s\n' "$_mh_main" "$_mh_hops" "$_mh_fam" > "${_mh_d}hop"
    chmod 600 "${_mh_d}hop" 2>/dev/null
    if _hy_set_listen "$_mh_cfg" "${_mh_pre}${_mh_main}"; then
      _svc_restart "$_mh_id"
      if wait_for_port "$_mh_main" udp 15; then
        rm -f "${_mh_cfg}.bak-hop"
        info "节点 $_mh_id 的端口跳跃改成了新写法：主端口 $_mh_main，跳跃端口 $_mh_hops"
        continue
      fi
    fi
    mv -f "${_mh_cfg}.bak-hop" "$_mh_cfg"
    [ -x /usr/local/bin/xray-node-hop ] && /usr/local/bin/xray-node-hop down "$_mh_id" >/dev/null 2>&1
    rm -f "${_mh_d}hop"
    _svc_restart "$_mh_id"
    warn "节点 $_mh_id 换成新的端口跳跃写法后没起来，已恢复原来的配置"
  done
}

# ---------- 阻止 QUIC：在客户端里打开，不在服务器上拦 ----------
# QUIC 是走 UDP 443 的新版网页协议（HTTP/3）。经过代理时常常更慢、更容易断，
# 所以很多 App 有一个「阻止 QUIC」开关（Loon 写 block-quic=true，Surge 写 block-quic=on）：
# 打开后浏览器和 App 发现 QUIC 走不通，会自动改走普通的 TCP。
# 这个开关是客户端自己的设置。分享链接（vless:// 这种）里没有通用的写法，
# 所以脚本另外给 Loon、Surge 各生成一行“节点配置”，里面已经写好这个开关，粘贴导入后自动打开。
# 下面这些函数用 CQ_ 开头的变量拼出这些行：
#   CQ_PROTO 协议（vless/trojan/vmess/ss/anytls/hy2/tuic）  CQ_NAME 节点名
#   CQ_HOST 服务器地址（IPv6 不带方括号）  CQ_PORT 端口  CQ_UUID  CQ_PASS 密码
#   CQ_SNI 伪装域名  CQ_PBK / CQ_SID REALITY 公钥和 short-id  CQ_PATH WebSocket 路径

_cq_ok() { # 值不能空，也不能带逗号、引号、空白：这些字符会把一整行配置切坏
  for _cq_v in "$@"; do
    case "$_cq_v" in
      ''|*[,\"\ \	]*) return 1 ;;
    esac
  done
  return 0
}

_cq_loon_line() { # 打印 Loon 节点行（官方格式：节点名 = 协议,地址,端口,…）。Loon 不支持的协议什么都不打印
  _cq_ok "$CQ_HOST" "$CQ_PORT" || return 0
  case "$CQ_NAME" in ''|*[,=]*) return 0 ;; esac
  case "$CQ_PROTO" in
    vless)
      _cq_ok "$CQ_UUID" "$CQ_PBK" "$CQ_SID" "$CQ_SNI" || return 0
      printf '%s = VLESS,%s,%s,"%s",transport=tcp,flow=xtls-rprx-vision,public-key="%s",short-id=%s,over-tls=true,sni=%s,udp=true,block-quic=true\n' \
        "$CQ_NAME" "$CQ_HOST" "$CQ_PORT" "$CQ_UUID" "$CQ_PBK" "$CQ_SID" "$CQ_SNI"
      ;;
    trojan)
      _cq_ok "$CQ_PASS" "$CQ_PBK" "$CQ_SID" "$CQ_SNI" || return 0
      printf '%s = Trojan,%s,%s,"%s",transport=tcp,public-key="%s",short-id=%s,sni=%s,udp=true,block-quic=true\n' \
        "$CQ_NAME" "$CQ_HOST" "$CQ_PORT" "$CQ_PASS" "$CQ_PBK" "$CQ_SID" "$CQ_SNI"
      ;;
    vmess)
      _cq_ok "$CQ_UUID" "$CQ_PATH" || return 0
      printf '%s = VMess,%s,%s,auto,"%s",transport=ws,alterId=0,path=%s,over-tls=false,udp=true,block-quic=true\n' \
        "$CQ_NAME" "$CQ_HOST" "$CQ_PORT" "$CQ_UUID" "$CQ_PATH"
      ;;
    ss)
      _cq_ok "$CQ_PASS" || return 0
      printf '%s = Shadowsocks,%s,%s,2022-blake3-aes-128-gcm,"%s",udp=true,block-quic=true\n' \
        "$CQ_NAME" "$CQ_HOST" "$CQ_PORT" "$CQ_PASS"
      ;;
    anytls)
      _cq_ok "$CQ_PASS" "$CQ_PBK" "$CQ_SID" "$CQ_SNI" || return 0
      printf '%s = AnyTLS,%s,%s,"%s",sni=%s,public-key="%s",short-id=%s,udp=true,block-quic=true\n' \
        "$CQ_NAME" "$CQ_HOST" "$CQ_PORT" "$CQ_PASS" "$CQ_SNI" "$CQ_PBK" "$CQ_SID"
      ;;
  esac
  return 0
}

_cq_surge_line() { # 打印 Surge 节点行。Surge 不支持 VLESS 和 REALITY，这几种什么都不打印
  _cq_ok "$CQ_HOST" "$CQ_PORT" || return 0
  case "$CQ_NAME" in ''|*[,=]*) return 0 ;; esac
  case "$CQ_PROTO" in
    vmess)
      _cq_ok "$CQ_UUID" "$CQ_PATH" || return 0
      printf '%s = vmess, %s, %s, username=%s, ws=true, ws-path=%s, vmess-aead=true, block-quic=on\n' \
        "$CQ_NAME" "$CQ_HOST" "$CQ_PORT" "$CQ_UUID" "$CQ_PATH"
      ;;
    ss)
      _cq_ok "$CQ_PASS" || return 0
      printf '%s = ss, %s, %s, encrypt-method=2022-blake3-aes-128-gcm, password=%s, udp-relay=true, block-quic=on\n' \
        "$CQ_NAME" "$CQ_HOST" "$CQ_PORT" "$CQ_PASS"
      ;;
    tuic)
      _cq_ok "$CQ_UUID" "$CQ_PASS" || return 0
      printf '%s = tuic-v5, %s, %s, uuid=%s, password=%s, alpn=h3, sni=www.samsung.com, skip-cert-verify=true, block-quic=on\n' \
        "$CQ_NAME" "$CQ_HOST" "$CQ_PORT" "$CQ_UUID" "$CQ_PASS"
      ;;
  esac
  return 0
}

_cq_section() { # 打印 node.txt 里“拦截 QUIC”这一段
  printf "拦截 QUIC（阻止 QUIC / block-quic）：这是客户端 App 里的开关，服务器上不拦。\n"
  printf "  QUIC 是走 UDP 443 的新版网页协议，经过代理时常常更慢、更容易断。打开后 App 会自动改走 TCP，更稳。\n"
  if [ "$CQ_PROTO" = "hy2" ]; then
    printf "  上面给 Loon / Surge 粘贴的那几行已经写好这个开关，导入后自动打开。\n"
  else
    _cq_l=$(_cq_loon_line)
    _cq_s=$(_cq_surge_line)
    if [ -n "$_cq_l" ]; then
      printf "Loon 可粘贴这一行（已写好 block-quic=true，导入后自动打开阻止 QUIC）:\n%s\n" "$_cq_l"
    fi
    if [ -n "$_cq_s" ]; then
      printf "Surge 可粘贴这一行（已写好 block-quic=on）:\n%s\n" "$_cq_s"
    fi
  fi
  printf "  用上面的分享链接导入时，链接里带不了这个开关，请自己打开:\n"
  printf "  Loon / Surge：在这个节点的设置里打开「阻止 QUIC」（Block QUIC）\n"
  printf "  小火箭 Shadowrocket：配置文件的 [General] 里写 block-quic = all-proxy\n"
  printf "  Clash / mihomo / Stash：rules 最前面加一行 - AND,((NETWORK,UDP),(DST-PORT,443)),REJECT\n"
  printf '  sing-box：route 的 rules 最前面加 { "network": "udp", "port": 443, "action": "reject" }\n'
}

_cq_from_nodetxt() { # _cq_from_nodetxt <节点目录>：从老节点的 node.txt 读出 CQ_ 变量
  _cq_nt="$1/node.txt"
  [ -f "$_cq_nt" ] || return 1
  _cq_link=$(grep -m1 -E '^(vless|trojan|vmess|ss|anytls|hysteria2|tuic)://' "$_cq_nt" 2>/dev/null | tr -d '\r')
  case "$_cq_link" in
    vless://*) CQ_PROTO=vless ;;
    trojan://*) CQ_PROTO=trojan ;;
    vmess://*) CQ_PROTO=vmess ;;
    ss://*) CQ_PROTO=ss ;;
    anytls://*) CQ_PROTO=anytls ;;
    hysteria2://*) CQ_PROTO=hy2 ;;
    tuic://*) CQ_PROTO=tuic ;;
    *) return 1 ;;
  esac
  CQ_NAME=$(_cq_kv "节点名")
  [ -n "$CQ_NAME" ] || CQ_NAME=$(head -1 "$1/name" 2>/dev/null | tr -d '\r')
  [ -n "$CQ_NAME" ] || CQ_NAME="节点$(basename "$1")"
  CQ_HOST=$(_cq_kv "地址")
  CQ_PORT=$(_cq_kv "端口")
  CQ_UUID=$(_cq_kv "UUID")
  CQ_PASS=$(_cq_kv "密码")
  CQ_SNI=$(_cq_kv "伪装域名")
  CQ_PATH=$(_cq_kv "WS 路径")
  CQ_PBK=$(printf '%s' "$_cq_link" | sed -n 's/.*[?&]pbk=\([^&#]*\).*/\1/p')
  CQ_SID=$(printf '%s' "$_cq_link" | sed -n 's/.*[?&]sid=\([^&#]*\).*/\1/p')
  return 0
}

_cq_kv() { # 读 node.txt 里“名字: 值”那一行的值
  sed -n "s/^$1: //p" "$_cq_nt" 2>/dev/null | head -1 | tr -d '\r'
}

# 老节点的 node.txt 里写着“已在服务器上打开”，换成新说明，并补上 Loon / Surge 行。
_cq_fix_nodetxt() { # _cq_fix_nodetxt <节点目录>
  _cf_nt="$1/node.txt"
  grep -q '^拦截 QUIC: \|^想在客户端也拦：' "$_cf_nt" 2>/dev/null || return 0
  (
    CQ_PROTO=""; CQ_NAME=""; CQ_HOST=""; CQ_PORT=""; CQ_UUID=""; CQ_PASS=""
    CQ_SNI=""; CQ_PBK=""; CQ_SID=""; CQ_PATH=""
    _cq_from_nodetxt "$1" || CQ_PROTO=""
    _cq_section
  ) > "$_cf_nt.quic" 2>/dev/null || { rm -f "$_cf_nt.quic"; return 1; }
  awk -v sec="$_cf_nt.quic" '
    /^拦截 QUIC: / {
      if (!done) { while ((getline l < sec) > 0) print l; done = 1 }
      next
    }
    /^想在客户端也拦：/ {
      if (!done) { while ((getline l < sec) > 0) print l; done = 1 }
      next
    }
    { print }
  ' "$_cf_nt" > "$_cf_nt.tmp" && mv -f "$_cf_nt.tmp" "$_cf_nt"
  rm -f "$_cf_nt.quic" "$_cf_nt.tmp"
  chmod 600 "$_cf_nt" 2>/dev/null
  return 0
}

# 去掉旧版写进服务器配置的“拦 UDP 443”。只认本脚本当初写的那几行原样，
# 你自己改过的配置不动。改好打印到标准输出；没有要改的返回 1。
_cq_strip_xray() { # _cq_strip_xray <config.json>
  awk '
    BEGIN {
      r = "  \"routing\": { \"rules\": [ { \"type\": \"field\", \"network\": \"udp\", \"port\": \"443\", \"outboundTag\": \"block\" } ] },"
      o = "  \"outbounds\": [ { \"protocol\": \"freedom\", \"tag\": \"direct\" }, { \"protocol\": \"blackhole\", \"tag\": \"block\" } ]"
    }
    { sub(/\r$/, "") }
    $0 == r { hr = 1; next }
    $0 == o { print "  \"outbounds\": [ { \"protocol\": \"freedom\" } ]"; ho = 1; next }
    { print }
    END { exit (hr && ho) ? 0 : 1 }
  ' "$1"
}

_cq_strip_singbox() { # _cq_strip_singbox <config.json>
  awk '
    BEGIN {
      o = "  \"outbounds\": [ { \"type\": \"direct\" } ],"
      r = "  \"route\": { \"rules\": [ { \"network\": \"udp\", \"port\": 443, \"action\": \"reject\" } ] }"
    }
    { sub(/\r$/, ""); line[NR] = $0 }
    END {
      for (i = 1; i < NR; i++) if (line[i] == o && line[i + 1] == r) { hit = i; break }
      if (!hit) exit 1
      for (i = 1; i <= NR; i++) {
        if (i == hit) { print "  \"outbounds\": [ { \"type\": \"direct\" } ]"; continue }
        if (i == hit + 1) continue
        print line[i]
      }
    }
  ' "$1"
}

_cq_strip_hysteria() { # _cq_strip_hysteria <config.yaml>：只删 acl 里只有这一条 reject(all, udp/443) 的情况
  awk '
    { sub(/\r$/, ""); line[NR] = $0 }
    END {
      for (i = 1; i + 2 <= NR; i++) {
        if (line[i] == "acl:" && line[i + 1] == "  inline:" && line[i + 2] == "    - reject(all, udp/443)" && line[i + 3] !~ /^[[:space:]]/) { hit = i; break }
      }
      if (!hit) exit 1
      from = hit; to = hit + 2
      # 连同上面两行说明一起删；下面紧跟的空行也删掉
      if (from > 2 && line[from - 1] ~ /^# 只管“经过节点出去”的流量/ && line[from - 2] ~ /^# 拦截 QUIC：/) from -= 2
      if (to < NR && line[to + 1] == "") to++
      for (i = 1; i <= NR; i++) if (i < from || i > to) print line[i]
    }
  ' "$1"
}

# 更新模式：把所有老节点服务器上的“拦 QUIC”去掉。改完先校验配置，再重启；
# 端口没起来就换回原来的配置再启动，保证节点不会被弄断。
_quic_unblock_all() {
  for _qu_d in "${XRAY_NODES_DIR:-/etc/xray-node/nodes}"/*/; do
    if [ ! -f "${_qu_d}core" ] || [ ! -f "${_qu_d}node.txt" ]; then continue; fi
    _qu_id=$(basename "$_qu_d")
    case "$_qu_id" in ''|*[!0-9]*) continue ;; esac
    _qu_core=$(tr -d ' \r\n' < "${_qu_d}core" 2>/dev/null)
    case "$_qu_core" in
      xray) _qu_cfg="${_qu_d}config.json" ;;
      sing-box) _qu_cfg="${_qu_d}config.json" ;;
      hysteria) _qu_cfg="${_qu_d}config.yaml" ;;
      *) continue ;;
    esac
    # 临时文件要保留 .json / .yaml 结尾：Xray 是看文件结尾来认配置格式的
    _qu_new="${_qu_cfg%.*}.noquic.${_qu_cfg##*.}"
    _qu_hit=1
    case "$_qu_core" in
      xray) _cq_strip_xray "$_qu_cfg" > "$_qu_new" 2>/dev/null || _qu_hit=0 ;;
      sing-box) _cq_strip_singbox "$_qu_cfg" > "$_qu_new" 2>/dev/null || _qu_hit=0 ;;
      hysteria) _cq_strip_hysteria "$_qu_cfg" > "$_qu_new" 2>/dev/null || _qu_hit=0 ;;
    esac
    if [ "$_qu_hit" = "1" ] && [ -s "$_qu_new" ]; then
      # 先用内核自带的检查命令看新配置对不对，不对就不换
      _qu_bad=""
      if [ "$_qu_core" = "xray" ] && [ -x "$XRAY_BIN" ]; then
        "$XRAY_BIN" -test -config "$_qu_new" >/dev/null 2>&1 || _qu_bad=1
      elif [ "$_qu_core" = "sing-box" ] && [ -x "$SB_BIN" ]; then
        "$SB_BIN" check -c "$_qu_new" >/dev/null 2>&1 || _qu_bad=1
      fi
      if [ -n "$_qu_bad" ]; then
        rm -f "$_qu_new"
        warn "节点 $_qu_id 去掉服务器端拦 QUIC 后配置校验没通过，保持原样"
        continue
      elif cp -a "$_qu_cfg" "${_qu_cfg}.bak-quic"; then
        cat "$_qu_new" > "$_qu_cfg" && rm -f "$_qu_new"
        _svc_restart "$_qu_id"
        _qu_port=""; _qu_proto="tcp"
        if _qu_pp=$(_node_port "$_qu_id"); then _qu_port=${_qu_pp%% *}; _qu_proto=${_qu_pp#* }; fi
        if [ -n "$_qu_port" ] && wait_for_port "$_qu_port" "$_qu_proto" 15; then
          rm -f "${_qu_cfg}.bak-quic"
          info "节点 $_qu_id：已去掉服务器端拦 QUIC（以后在客户端里打开「阻止 QUIC」）"
        else
          mv -f "${_qu_cfg}.bak-quic" "$_qu_cfg"
          _svc_restart "$_qu_id"
          warn "节点 $_qu_id 改完后端口没起来，已换回原来的配置"
          continue
        fi
      else
        rm -f "$_qu_new"
        warn "节点 $_qu_id 的配置备份失败（磁盘满了？），这次先不改"
        continue
      fi
    else
      rm -f "$_qu_new"
    fi
    _cq_fix_nodetxt "${_qu_d%/}" || true
  done
}

# 回程路由的提示：有规则加上（或者该加却加不上）时，用大白话说明一下。
_route_note() { # _route_note <节点id> <UDP 端口>
  _rn_show=$("${XRAY_BIN_DIR:-/usr/local/bin}/xray-node-route" show "$1" 2>/dev/null)
  [ -n "$_rn_show" ] || return 0
  warn "节点 $1：这台机器有策略路由（常见于装了 L2TP、WireGuard 等 VPN），没打标记的流量默认走 VPN 网卡。UDP 节点的回包要是也走那边，客户端收不到，节点就连不上。"
  printf '%s\n' "$_rn_show" | sed 's/^/  /'
  case "$_rn_show" in
    *内核太老*)
      warn "解决办法：把内核升级到 4.17 以上；或者把节点配置里的监听地址从全部地址（0.0.0.0 或 ::）改成公网网卡上的那个地址，再重启节点。" ;;
    *没法自动修*|*已经拆掉*)
      warn "这种情况脚本修不了：请在 VPN 的设置里，让这台服务器自己从 UDP ${2:-节点端口} 发出的包走公网网卡。" ;;
    *)
      info "这条规则只管本机从 UDP ${2:-节点端口} 发出的包（端口跳跃的回包也算），别的程序不受影响。节点启动时自动加、停掉时自动拆，每分钟检查一次。" ;;
  esac
}

# 更新模式：给老节点装上回程路由。服务模板里还没有这一步的，重启一次换上新模板；
# 然后马上按现在的网络核对一次（不用等重启）。
_route_refresh_all() {
  install_route_bin || return 0
  _rr_bin=${XRAY_BIN_DIR:-/usr/local/bin}/xray-node-route
  for _rr_d in "${XRAY_NODES_DIR:-/etc/xray-node/nodes}"/*/; do
    if [ ! -f "${_rr_d}core" ] || [ ! -f "${_rr_d}node.txt" ]; then continue; fi
    _rr_id=$(basename "$_rr_d")
    case "$_rr_id" in ''|*[!0-9]*) continue ;; esac
    if [ -d /run/systemd/system ]; then
      case "$(tr -d ' \r\n' < "${_rr_d}core" 2>/dev/null)" in
        sing-box) _rr_unit=/etc/systemd/system/singbox-node@.service ;;
        hysteria) _rr_unit=/etc/systemd/system/hysteria-node@.service ;;
        *) _rr_unit=/etc/systemd/system/xray-node@.service ;;
      esac
    else
      _rr_unit=/etc/init.d/xray-node-${_rr_id}
    fi
    if [ -f "$_rr_unit" ] && ! grep -q 'xray-node-route' "$_rr_unit" 2>/dev/null; then
      _svc_restart "$_rr_id"
      _rr_port=""; _rr_proto="tcp"
      if _rr_pp=$(_node_port "$_rr_id"); then _rr_port=${_rr_pp%% *}; _rr_proto=${_rr_pp#* }; fi
      if [ -n "$_rr_port" ] && ! wait_for_port "$_rr_port" "$_rr_proto" 15; then
        warn "节点 $_rr_id 重启后端口 $_rr_port 没监听，请运行 jiedian 看一下，或者重启服务器再试"
      fi
    fi
    "$_rr_bin" up "$_rr_id" >/dev/null 2>&1
    _route_note "$_rr_id" "$(awk '$2 == "udp" { print $1; exit }' "${_rr_d}fw_info" 2>/dev/null)"
  done
}

_hy_fix_existing_ipv6() {
  # 以前装的 Hysteria2 选了 IPv4 就只听 0.0.0.0。重跑脚本选更新时改成同时听 IPv6。
  # 改完端口没起来就把配置改回去，避免把正在用的节点弄断。
  _hy6=$(_hy_local_ipv6) || return 0
  [ -n "$_hy6" ] || return 0
  for _hd in /etc/xray-node/nodes/*/; do
    [ -f "${_hd}core" ] && [ -f "${_hd}config.yaml" ] || continue
    [ "$(tr -d ' \r\n' < "${_hd}core")" = "hysteria" ] || continue
    _hcfg="${_hd}config.yaml"
    _hlisten=$(awk '
      /^listen:/ {
        line = $0
        sub(/\r$/, "", line)
        sub(/^listen:[[:space:]]*/, "", line)
        gsub(/^"|"$/, "", line)
        print line
        exit
      }
    ' "$_hcfg")
    case "$_hlisten" in
      0.0.0.0:*) ;;
      *) continue ;;
    esac
    # 端口跳跃的监听是 0.0.0.0:主端口,跳跃端口。改双栈时把后面的端口原样留下。
    _hbody=${_hlisten#0.0.0.0:}
    _hport=${_hbody%%,*}
    _hhop=""
    case "$_hbody" in
      *,*) _hhop=${_hbody#*,} ;;
    esac
    case "$_hport" in
      ''|*[!0-9]*) continue ;;
    esac
    case "$_hhop" in
      *[!0-9,]*) continue ;;
    esac
    _hnew=":${_hport}"
    [ -n "$_hhop" ] && _hnew="${_hnew},${_hhop}"
    _hid=$(basename "$_hd")
    cp -a "$_hcfg" "${_hcfg}.bak-ipv6" || {
      warn "节点 $_hid 无法备份配置，跳过 IPv6"
      continue
    }
    if ! _hy_set_listen "$_hcfg" "$_hnew"; then
      mv -f "${_hcfg}.bak-ipv6" "$_hcfg"
      warn "节点 $_hid 没能改成同时听 IPv6"
      continue
    fi
    _svc_restart "$_hid"
    _hy_up=0
    if wait_for_port "$_hport" udp 15; then
      _hy_up=1
      if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl is-active --quiet "hysteria-node@${_hid}" || _hy_up=0
      elif command -v rc-service >/dev/null 2>&1; then
        rc-service "xray-node-${_hid}" status >/dev/null 2>&1 || _hy_up=0
      fi
    fi
    if [ "$_hy_up" = "1" ]; then
      rm -f "${_hcfg}.bak-ipv6"
      HY_IPV6_FIXED=1
      if [ -f "${_hd}hop" ]; then
        _hop_set_family "$_hd" 46
        /usr/local/bin/xray-node-hop up "$_hid" >/dev/null 2>&1 || true
      fi
      if [ -f "${_hd}node.txt" ] && ! grep -F "[${_hy6}]" "${_hd}node.txt" >/dev/null 2>&1; then
        _hline=$(grep -m1 '^hysteria2://' "${_hd}node.txt" 2>/dev/null)
        _hrest=${_hline#hysteria2://}
        _hpass=${_hrest%%@*}
        _hafter=${_hrest#*@}
        _hquery=""
        case "$_hafter" in
          *\?*) _hquery=${_hafter#*\?}; _hquery=${_hquery%%#*} ;;
        esac
        if [ -n "$_hpass" ] && [ -n "$_hquery" ]; then
          # 原来的 mport 开头是 IPv4 公网端口。IPv6 直接连本机端口，开头不一样就要换成这个端口。
          _hmport=""
          case "$_hquery" in
            *'&mport='*) _hmport=${_hquery#*&mport=} ;;
            mport=*) _hmport=${_hquery#mport=} ;;
          esac
          _hmport=${_hmport%%&*}
          case "$_hmport" in
            *,*)
              if [ "${_hmport%%,*}" != "$_hport" ]; then
                _hnewm="${_hport},${_hmport#*,}"
                _hquery=$(printf '%s' "$_hquery" | sed "s/mport=${_hmport}/mport=${_hnewm}/")
              fi
              ;;
          esac
          # 节点名沿用原来那行链接 # 后面的名字
          _hfrag="xray-node"
          case "$_hafter" in *'#'*) _hfrag=${_hafter#*#} ;; esac
          _hlink="hysteria2://${_hpass}@[${_hy6}]:${_hport}/?${_hquery}#${_hfrag}"
          _htmp="${_hd}node.txt.tmp"
          awk -v link="$_hlink" '
            { print }
            !done && /^hysteria2:\/\// {
              print "IPv6 链接（同一个节点）:"
              print link
              done = 1
            }
          ' "${_hd}node.txt" > "$_htmp" && mv -f "$_htmp" "${_hd}node.txt"
          chmod 600 "${_hd}node.txt" 2>/dev/null
        fi
      fi
      if command -v ip6tables >/dev/null 2>&1; then
        # 跳跃端口经过 nat 转发后就是主端口，本机防火墙只放主端口。
        _hfw_ports=$_hport
        for _hfw in $_hfw_ports; do
          if ! ip6tables -C INPUT -p udp --dport "$_hfw" -j ACCEPT >/dev/null 2>&1; then
            _fw_allow "$_hfw" udp 6 "${_hd}fw_info" 0
            [ "$_IPT_ADDED" = "1" ] && _save_fw 6
          fi
        done
      fi
      info "节点 $_hid 的 Hysteria2 已同时听 IPv6：${_hy6}"
    else
      mv -f "${_hcfg}.bak-ipv6" "$_hcfg"
      _svc_restart "$_hid"
      warn "节点 $_hid 改成同时听 IPv6 后端口没起来，已改回只听 IPv4"
    fi
  done
}

# ---------- 更新内核时用的小工具：读端口、比版本号 ----------
_node_port() { # _node_port <节点id> -> "端口 协议"（从该节点的 fw_info 第一行读）
  read -r _np_port _np_proto _np_rest < /etc/xray-node/nodes/"$1"/fw_info 2>/dev/null
  [ -n "$_np_port" ] || return 1
  [ -n "$_np_proto" ] || _np_proto="tcp"
  printf "%s %s" "$_np_port" "$_np_proto"
}

_ver_num() { # _ver_num <字符串> -> 提取其中的第一个版本号，如 "Xray 26.3.27 (…)" -> "26.3.27"
  printf "%s" "$1" | sed 's/^[^0-9]*//; s/[^0-9.].*//; s/\.*$//'
}

# _latest_tag_web <owner/repo>：不走 API，看 github.com/<repo>/releases/latest 跳转到哪个 tag。
# api.github.com 对每个 IP 每小时只给 60 次，同一出口的机器多了就会被限流。
_latest_tag_web() { # _latest_tag_web <owner/repo> [镜像前缀]
  _ltw_page="${2:-}https://github.com/$1/releases/latest"
  _ltw_url=""
  if command -v curl >/dev/null 2>&1; then
    _ltw_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' --max-time 20 --connect-timeout 15 "$_ltw_page" 2>/dev/null)
  elif command -v wget >/dev/null 2>&1; then
    _ltw_url=$(wget -S --spider -T 20 "$_ltw_page" 2>&1 | awk 'tolower($1) == "location:" { u = $2 } END { print u }')
  fi
  case "$_ltw_url" in
    */releases/tag/*) printf '%s' "${_ltw_url##*/releases/tag/}" | tr -d '\r' ;;
    *) return 1 ;;
  esac
}

# _latest_tag_raw <owner/repo>：打印最新 release 的原始 tag（比如 v26.3.27、app/v2.12.3）。
# 顺序：GitHub API -> github.com 跳转 -> IPv6 镜像的 API 和跳转（NAT64 由 _gh_prepare 提前打开）。
_latest_tag_raw() {
  _ltr_api="https://api.github.com/repos/$1/releases/latest"
  _ltr_pick() { grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//; s/".*//'; }
  _ltr=$(_http_body "$_ltr_api" 2>/dev/null | _ltr_pick)
  # API 被限流或连不上时，改看 github.com 的跳转地址
  [ -n "$_ltr" ] || _ltr=$(_latest_tag_web "$1") || _ltr=""
  if [ -z "$_ltr" ]; then
    for _ltr_m in $GH_MIRRORS; do
      _ltr=$(_http_body "${_ltr_m}${_ltr_api}" 2>/dev/null | _ltr_pick)
      [ -n "$_ltr" ] || _ltr=$(_latest_tag_web "$1" "$_ltr_m") || _ltr=""
      [ -n "$_ltr" ] && break
    done
  fi
  [ -n "$_ltr" ] || return 1
  printf '%s' "$_ltr" | tr -d '\r'
}

_latest_tag() { # _latest_tag <owner/repo> -> 打印最新 release 版本号（去 v 前缀），失败返回非零
  _lt_tag=$(_latest_tag_raw "$1" | sed 's|.*%2[Ff]||; s|.*/||; s/^v//')
  # 必须是版本号的样子：tag 格式万一变了（比如 "nightly"），
  # 不能把整行垃圾当版本号吐出去，否则版本比较永远对不上、每次更新都重复下载
  case "$_lt_tag" in ''|*[!0-9a-zA-Z.-]*) return 1 ;; esac
  printf "%s" "$_lt_tag"
}

# _cached_ver_ok <二进制路径> <owner/repo> [已知最新版本]：
# 缓存安装包里的内核已是最新版返回 0；连不上 API 拿不到"最新"时返回 0
# （不断网折腾，照旧用缓存）；包里版本读不出来返回 1（重新下载）
_cached_ver_ok() {
  _cvo_ver=$(_ver_num "$("$1" version 2>/dev/null | head -1)")
  [ -n "$_cvo_ver" ] || return 1
  if [ -n "$3" ]; then
    _cvo_latest="$3"
  else
    _cvo_latest=$(_latest_tag "$2") || return 0
  fi
  [ "$_cvo_ver" = "$_cvo_latest" ]
}

# ---------- 小内存机器（64MB / 128MB）的特殊处理 ----------
# 内存很小时，下载和启动内核容易被系统“杀掉”。下面会检测内存大小，
# 必要时做一块硬盘上的虚拟内存（swap），并放宽内存申请限制。
_read_meminfo_kb() { # _read_meminfo_kb MemTotal: -> 数字（kB）
  awk -v k="$1" '$1==k {print $2; exit}' /proc/meminfo 2>/dev/null
}

# 容器里的 MemTotal 经常是宿主机的内存，真正的上限在 cgroup。
# 不限制时这个文件是一个超大整数或 max，不能拿去运算（shell 算术会溢出）。
_cgroup_mem_mb() {
  for _cgf in /sys/fs/cgroup/memory.max \
              /sys/fs/cgroup/memory/memory.limit_in_bytes \
              /sys/fs/cgroup/memory.limit_in_bytes; do
    [ -r "$_cgf" ] || continue
    _cgv=$(tr -d ' \r\n' < "$_cgf" 2>/dev/null)
    case "$_cgv" in ''|max|*[!0-9]*) continue ;; esac
    [ "${#_cgv}" -le 12 ] || continue
    [ "$_cgv" -ge 1048576 ] || continue
    printf '%s' $((_cgv / 1024 / 1024))
    return 0
  done
  return 1
}

# 容器里 /proc/meminfo 的 SwapTotal 常常是宿主机的，容器自己能用多少虚拟内存要看 cgroup。
# 打印 kB。没限制（max）或读不到时返回 1。
_cgroup_swap_kb() {
  _csf=/sys/fs/cgroup/memory.swap.max
  [ -r "$_csf" ] || return 1
  _csv=$(tr -d ' \r\n' < "$_csf" 2>/dev/null)
  case "$_csv" in ''|max|*[!0-9]*) return 1 ;; esac
  [ "${#_csv}" -le 12 ] || return 1
  printf '%s' $((_csv / 1024))
}

_disk_free_mb() { # _disk_free_mb <路径> -> 该路径所在磁盘剩余 MB
  df -Pk "$1" 2>/dev/null | awk 'NR==2 {print int($4/1024)}'
}

_fstype() { # _fstype <挂载点>
  awk -v m="$1" '$2==m {print $3; exit}' /proc/mounts 2>/dev/null
}

drop_page_cache() {
  sync
  # 有的容器这个文件看着能写，写的时候仍被拒绝。报错是外壳自己打的，要包住整个重定向。
  if [ -w /proc/sys/vm/drop_caches ]; then
    { printf '3\n' > /proc/sys/vm/drop_caches; } 2>/dev/null || true
  fi
}

# 上次安装失败会把几十 MB 的安装包留在临时目录。1GB 硬盘上这些残留会让下一次装直接写满。
recover_disk_space() {
  rm -rf /var/tmp/xray-node-dl "$HOME/xray-node-dl" /tmp/xray-node-dl 2>/dev/null
  rm -f /usr/local/bin/sing-box.new /usr/local/bin/xray.new /usr/local/bin/hysteria.new 2>/dev/null
  _rdf=$(_disk_free_mb /)
  if [ "$LOW_MEM" = "1" ] || { [ -n "$_rdf" ] && [ "$_rdf" -lt 200 ]; }; then
    rm -f /var/cache/apt/archives/*.deb 2>/dev/null
  fi
}

# 往 fstab 追加 swap 行。文件最后如果没有换行，直接 >> 会把上一行粘死
# （常见是根分区那一行），重启时根分区挂不上。
_fstab_append_swap() {
  _fs_file=${XRAY_FSTAB:-/etc/fstab}
  if [ ! -f "$_fs_file" ]; then
    _fs_dir=$(dirname "$_fs_file")
    [ -w "$_fs_dir" ] || return 0
    touch "$_fs_file" 2>/dev/null || return 0
  fi
  [ -w "$_fs_file" ] || return 0
  _fs_key='/xray-node.swap none swap sw 0 0'
  if grep -q '/xray-node\.swap' "$_fs_file" 2>/dev/null; then
    grep -q '^/xray-node\.swap[[:space:]]' "$_fs_file" 2>/dev/null && return 0
    _fs_tmp=$(mktemp 2>/dev/null) || return 0
    if awk -v key="$_fs_key" '
      {
        i = index($0, key)
        if (i == 0) { print; next }
        if (i == 1) { print; next }
        pre = substr($0, 1, i - 1)
        if (pre != "") print pre
        print key
      }
    ' "$_fs_file" > "$_fs_tmp"; then
      cat "$_fs_tmp" > "$_fs_file"
    fi
    rm -f "$_fs_tmp"
    return 0
  fi
  if [ -s "$_fs_file" ] && [ -n "$(tail -c 1 "$_fs_file" 2>/dev/null)" ]; then
    printf '\n' >> "$_fs_file"
  fi
  printf '%s\n' "$_fs_key" >> "$_fs_file"
}

# 64MB / 128MB 的 NAT：Go 程序启动时会多申请一段内存，默认策略直接拒绝；
# 再加一块放在硬盘上的虚拟内存，Hysteria2 才起得来。tmpfs 上的 swap 等于拿内存当内存，不用。
prepare_low_memory() {
  LOW_MEM=0
  SWAP_OK=0
  MEM_MB=""
  _tot_kb=$(_read_meminfo_kb "MemTotal:")
  _cg_mb=$(_cgroup_mem_mb) || _cg_mb=""
  if [ -n "$_tot_kb" ]; then
    MEM_MB=$((_tot_kb / 1024))
  fi
  if [ -n "$_cg_mb" ]; then
    if [ -z "$MEM_MB" ] || [ "$_cg_mb" -lt "$MEM_MB" ]; then
      MEM_MB="$_cg_mb"
    fi
  fi
  # 只看机器的内存上限。临时剩下的可用内存很少时，不去改大机器的系统设置。
  if [ -n "$MEM_MB" ] && [ "$MEM_MB" -le 192 ]; then LOW_MEM=1; fi
  # 先清残留安装包，再决定要不要做 swap（磁盘数字才准）
  recover_disk_space
  [ "$LOW_MEM" = "1" ] || return 0
  info "这台机器大约 ${MEM_MB:-很少}MB 内存。先准备虚拟内存，否则 Hysteria2 起不来。"
  if [ -w /proc/sys/vm/overcommit_memory ]; then
    _oc=$(tr -d ' \r\n' < /proc/sys/vm/overcommit_memory 2>/dev/null)
    if [ "$_oc" != "1" ]; then
      if sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1 \
        || printf '1\n' > /proc/sys/vm/overcommit_memory 2>/dev/null; then
        mkdir -p /etc/sysctl.d 2>/dev/null
        printf 'vm.overcommit_memory=1\n' > /etc/sysctl.d/99-xray-node-overcommit.conf 2>/dev/null
        info "已放开内存申请限制（小内存机器需要这一步）"
      fi
    fi
  fi
  _swap_kb=$(_read_meminfo_kb "SwapTotal:")
  _swap_kb=${_swap_kb:-0}
  # 容器被限制了虚拟内存（常见是 0）时，按限制算，别把宿主机的当成自己的
  if _cg_swap_kb=$(_cgroup_swap_kb) && [ "$_cg_swap_kb" -lt "$_swap_kb" ]; then
    _swap_kb="$_cg_swap_kb"
  fi
  if [ "$_swap_kb" -ge 65536 ]; then
    SWAP_OK=1
    info "虚拟内存已经有了，直接用"
    return 0
  fi
  _root_type=$(_fstype /)
  case "$_root_type" in
    tmpfs|devtmpfs)
      warn "系统盘在内存里，没法再加虚拟内存"
      return 0
      ;;
  esac
  _free=$(_disk_free_mb /)
  [ -n "$_free" ] || _free=0
  _sw=0
  if [ "$_free" -ge 220 ]; then _sw=128
  elif [ "$_free" -ge 120 ]; then _sw=64
  fi
  if [ "$_sw" -eq 0 ]; then
    warn "磁盘只剩大约 ${_free}MB，腾不出虚拟内存。安装会继续，内存实在不够时会失败。"
    return 0
  fi
  _swapf=/xray-node.swap
  if [ -f "$_swapf" ]; then
    if swapon "$_swapf" >/dev/null 2>&1; then
      SWAP_OK=1
      info "已启用原来的虚拟内存文件"
      return 0
    fi
    swapoff "$_swapf" >/dev/null 2>&1
    rm -f "$_swapf"
  fi
  info "正在做 ${_sw}MB 虚拟内存（做完就能装 Hysteria2）…"
  _made=0
  if command -v fallocate >/dev/null 2>&1 && fallocate -l "${_sw}M" "$_swapf" 2>/dev/null; then
    _made=1
  else
    rm -f "$_swapf"
    _i=0
    _made=1
    while [ "$_i" -lt "$_sw" ]; do
      if ! dd if=/dev/zero of="$_swapf" bs=1048576 count=1 seek="$_i" conv=notrunc >/dev/null 2>&1; then
        _made=0
        break
      fi
      _i=$((_i + 1))
      if [ $((_i % 8)) -eq 0 ]; then sync; fi
    done
  fi
  if [ "$_made" != "1" ]; then
    rm -f "$_swapf"
    warn "虚拟内存文件没做成，继续安装"
    return 0
  fi
  chmod 600 "$_swapf" 2>/dev/null
  if mkswap "$_swapf" >/dev/null 2>&1 && swapon "$_swapf" >/dev/null 2>&1; then
    SWAP_OK=1
    _fstab_append_swap
    info "虚拟内存已开启（${_sw}MB），重启后也会自动挂上"
  else
    rm -f "$_swapf"
    warn "这台机器不允许开启虚拟内存（不少 NAT 容器都这样）。继续安装，程序会尽量省着内存用。"
  fi
}

# ---------- 下载三个内核：Hysteria2 / Xray / sing-box ----------
# 都是先下载到临时文件名、确认能运行，再替换正式文件，避免装到一半把旧的弄坏。
_latest_hysteria_ver() { # 打印 hysteria 最新版本号（不带 v），失败返回非零
  # tag 形如 app/v2.12.3，从跳转地址拿到时斜杠可能被编码成 %2F
  _hv=$(_latest_tag_raw "apernet/hysteria" | sed 's|.*%2[Ff]||; s|.*/||; s/^v//') || _hv=""
  case "$_hv" in ''|*[!0-9A-Za-z.-]*) return 1 ;; esac
  printf '%s' "$_hv"
}

_hysteria_local_ver() { # _hysteria_local_ver <二进制>
  "$1" version 2>/dev/null | sed -n 's/^Version:[[:space:]]*v\{0,1\}//p' | head -1 | tr -d ' \r\n'
}

_hy_asset() {
  case "$MACH" in
    amd64) printf '%s' hysteria-linux-amd64 ;;
    arm64) printf '%s' hysteria-linux-arm64 ;;
    armv7) printf '%s' hysteria-linux-arm ;;
    *) return 1 ;;
  esac
}

_dl_hysteria_inner() { # 下载官方 Hysteria2。它是静态的小程序，64MB 内存装得下；sing-box 1.14 解压后约 80MB，装不上。
  step "[下载] 获取 Hysteria2 内核…"
  _hy_asset=$(_hy_asset) || die "这个 CPU 架构没有对应的 Hysteria2 程序：$(uname -m)"
  _hy_latest=$(_latest_hysteria_ver) || _hy_latest=""
  if [ "$FORCE_DL" != "1" ] && [ -x "$HY_BIN" ]; then
    _hy_have=$(_hysteria_local_ver "$HY_BIN")
    if [ -n "$_hy_have" ] && { [ -z "$_hy_latest" ] || [ "$_hy_have" = "$_hy_latest" ]; }; then
      info "Hysteria2 已存在，直接用现有的：v${_hy_have}"
      return 0
    fi
  fi
  recover_disk_space
  _hy_free=$(_disk_free_mb /usr/local)
  if [ -z "$_hy_free" ]; then _hy_free=$(_disk_free_mb /); fi
  if [ -n "$_hy_free" ] && [ "$_hy_free" -lt 40 ]; then
    die "磁盘剩余大约 ${_hy_free}MB，装不下 Hysteria2（大约还要 40MB）。1GB 硬盘请先删掉不用的文件再重跑。"
  fi
  rm -f "${HY_BIN}.new"
  _dl_ok=0
  _GH_VIA=direct
  info "尝试下载：${_hy_asset}"
  if [ -n "$_hy_latest" ]; then
    _url="https://github.com/apernet/hysteria/releases/download/app/v${_hy_latest}/${_hy_asset}"
  else
    _url="https://github.com/apernet/hysteria/releases/latest/download/${_hy_asset}"
  fi
  if gh_api_dl "apernet/hysteria" "$_hy_asset" "${HY_BIN}.new"; then
    _dl_ok=1
  else
    warn "API 路线失败，换 github.com 直链和镜像试试…"
    rm -f "${HY_BIN}.new"
    info "尝试下载：$_url"
    if _gh_get "$_url" "${HY_BIN}.new"; then
      _dl_ok=1
    fi
  fi
  if [ "$_dl_ok" != "1" ]; then
    rm -f "${HY_BIN}.new"
    die "Hysteria2 下载失败：到 GitHub 的网络不稳定，稍等几分钟后重跑脚本试试$(_gh_hint)"
  fi
  # 官方 hashes.txt 里有每个文件的 SHA256。对不上就不装。
  if [ -n "$_hy_latest" ]; then
    _verify_dl "${HY_BIN}.new" "apernet/hysteria" "app/v${_hy_latest}" "$_hy_asset" \
      || die "Hysteria2 安装包校验没通过，已停止。请稍后重跑脚本"
  else
    warn "不知道最新版本号，取不到官方校验值，改为只检查程序能不能运行"
  fi
  # 小于 1MB 的多半是错误页，不是内核
  _hy_sz=$(wc -c < "${HY_BIN}.new" 2>/dev/null | tr -d ' ')
  if [ -z "$_hy_sz" ] || [ "$_hy_sz" -lt 1000000 ]; then
    rm -f "${HY_BIN}.new"
    die "下载到的 Hysteria2 文件不完整，请重跑脚本"
  fi
  chmod 0755 "${HY_BIN}.new" || { rm -f "${HY_BIN}.new"; die "安装 Hysteria2 失败"; }
  drop_page_cache
  _hy_run=$("${HY_BIN}.new" version 2>&1)
  _hy_rc=$?
  if [ "$_hy_rc" -ne 0 ]; then
    rm -f "${HY_BIN}.new"
    die "下载的 Hysteria2 内核跑不起来（退出码 ${_hy_rc}）。内存大约 ${MEM_MB:-未知}MB。系统说：$(printf '%s' "$_hy_run" | tr '\n' ' ' | cut -c1-300)"
  fi
  mv -f "${HY_BIN}.new" "$HY_BIN"
  _dns64_off
  mark_our_bin "hysteria"
  _hy_have=$(_hysteria_local_ver "$HY_BIN")
  info "Hysteria2 安装成功：v${_hy_have:-未知}"
}

# 三个下载函数的外壳：先看看 GitHub 通不通（纯 IPv6 时可能临时换 NAT64），下完一定把 DNS 换回去。
dl_hysteria() { _gh_prepare; _dl_hysteria_inner; _dl_rc=$?; _dns64_off; return "$_dl_rc"; }
dl_xray() { _gh_prepare; _dl_xray_inner; _dl_rc=$?; _dns64_off; return "$_dl_rc"; }
dl_singbox() { _gh_prepare; _dl_singbox_inner; _dl_rc=$?; _dns64_off; return "$_dl_rc"; }

_ensure_unzip() {
  command -v unzip >/dev/null 2>&1 && return 0
  warn "缺少 unzip，正在安装…"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    _apt_do "正在安装 unzip" 300 -- install -y -qq unzip || true
    unset DEBIAN_FRONTEND
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache unzip >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q unzip >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q unzip >/dev/null 2>&1 || true
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm --needed unzip >/dev/null 2>&1 || true
  fi
  command -v unzip >/dev/null 2>&1 || die "装不上 unzip，请手动安装 unzip 后重试"
}

_dl_xray_inner() { # 下载并安装 Xray 内核；FORCE_DL=1 时即使已存在也强制下载最新版
  step "[下载] 获取 Xray 内核…"
  case "$MACH" in
    amd64) XARCH="64" ;;
    arm64) XARCH="arm64-v8a" ;;
    armv7) XARCH="arm32-v7a" ;;
  esac
  if [ "$FORCE_DL" != "1" ] && [ -x "$XRAY_BIN" ] && "$XRAY_BIN" version >/dev/null 2>&1; then
    info "Xray 已存在，直接用现有的：$($XRAY_BIN version 2>/dev/null | head -1)"
  else
    # 机器上已有能用的 Xray 时不需要 unzip，只有真要下载解压才装它
    _ensure_unzip
    DL_DIR=$(pick_dldir) || die "找不到可写的下载目录"
    # 磁盘上已有完整可用的包就直接用（上次下载完但被中断的情况，不用重新下载）；
    # 更新模式（FORCE_DL=1）不走这里，必须拉最新版。
    # 但缓存的包可能是几个月前的旧版本：验一下版本，旧了就重新下，别装个过期内核
    _reuse=0
    if [ "$FORCE_DL" != "1" ] && [ -s "$DL_DIR/xray.zip" ] && unzip -t -q "$DL_DIR/xray.zip" >/dev/null 2>&1; then
      rm -rf "$DL_DIR/xray-ver" && mkdir -p "$DL_DIR/xray-ver"
      if unzip -o -q "$DL_DIR/xray.zip" -d "$DL_DIR/xray-ver" xray 2>/dev/null \
         && [ -x "$DL_DIR/xray-ver/xray" ] \
         && _cached_ver_ok "$DL_DIR/xray-ver/xray" "XTLS/Xray-core"; then
        _reuse=1
        info "安装包已在本地且是最新版，直接使用（跳过下载）"
      else
        info "本地安装包不是最新版，重新下载…"
      fi
      rm -rf "$DL_DIR/xray-ver"
    fi
    if [ "$_reuse" = "0" ]; then
      rm -f "$DL_DIR/xray.zip"
      _xasset="Xray-linux-${XARCH}.zip"
      _dl_ok=0
      _GH_VIA=direct
      _xver=$(_latest_tag "XTLS/Xray-core") || _xver=""
      # 路线 A：GitHub API（api.github.com 稳，302 跳到 release-assets 下得快）
      info "尝试下载：GitHub API"
      if gh_api_dl "XTLS/Xray-core" "$_xasset" "$DL_DIR/xray.zip"; then
        _dl_ok=1
      else
        warn "API 路线失败，换 github.com 直链和镜像试试…"
        rm -f "$DL_DIR/xray.zip"
        # 路线 B：github.com 直链（版本直链优先，/latest/download 兜底），不通再走镜像和 NAT64
        if [ -n "$_xver" ]; then
          _url="https://github.com/XTLS/Xray-core/releases/download/v${_xver}/${_xasset}"
        else
          _url="https://github.com/XTLS/Xray-core/releases/latest/download/${_xasset}"
        fi
        info "尝试下载：$_url"
        if _gh_get "$_url" "$DL_DIR/xray.zip"; then
          _dl_ok=1
        fi
      fi
      [ "$_dl_ok" -eq 1 ] || die "Xray 下载失败：到 GitHub 的网络不稳定，稍等几分钟后重跑脚本试试$(_gh_hint)"
      # 官方每个包都有 .dgst 校验文件，SHA256 对不上就不装
      if [ -n "$_xver" ]; then
        _verify_dl "$DL_DIR/xray.zip" "XTLS/Xray-core" "v${_xver}" "$_xasset" \
          || die "Xray 安装包校验没通过，已停止。请稍后重跑脚本"
      fi
    fi
    # 完整性校验：包坏了直接报错，不往下装半截文件
    unzip -t -q "$DL_DIR/xray.zip" >/dev/null 2>&1 || die "下载的安装包已损坏，请重跑脚本重新下载"
    # 先装到临时名、验明能跑再原子替换：更新模式下旧内核一直可用，直到新内核确认没问题
    rm -f "${XRAY_BIN}.new"
    if _unpack_drip zip "$DL_DIR/xray.zip" xray "${XRAY_BIN}.new"; then
      # 小内存机器：边解压边落盘，直接写到目标位置，不再多拷一份 36MB
      chmod 0755 "${XRAY_BIN}.new" || { rm -f "${XRAY_BIN}.new"; die "安装 Xray 失败"; }
    else
      rm -rf "$DL_DIR/xray-dl" && mkdir -p "$DL_DIR/xray-dl"
      _pace_start
      unzip -o -q "$DL_DIR/xray.zip" -d "$DL_DIR/xray-dl" xray || { _pace_stop; die "解压失败"; }
      [ -s "$DL_DIR/xray-dl/xray" ] || { _pace_stop; die "解压后没找到 xray 文件"; }
      install -m 0755 "$DL_DIR/xray-dl/xray" "${XRAY_BIN}.new" || { _pace_stop; rm -f "${XRAY_BIN}.new"; die "安装 Xray 失败"; }
      _pace_stop
    fi
    # 安装包用完就删：删掉以后它占的缓存马上还给系统，小内存机器试运行内核时才有地方
    rm -rf "$DL_DIR"
    drop_page_cache
    _x_run=$("${XRAY_BIN}.new" version 2>&1)
    _x_rc=$?
    if [ "$_x_rc" -ne 0 ]; then
      rm -f "${XRAY_BIN}.new"
      die "下载的 Xray 内核跑不起来（退出码 ${_x_rc}）。内存大约 ${MEM_MB:-未知}MB。系统说：$(printf '%s' "$_x_run" | tr '\n' ' ' | cut -c1-300)"
    fi
    mv -f "${XRAY_BIN}.new" "$XRAY_BIN"
    _dns64_off
    mark_our_bin "xray"
    rm -rf "$DL_DIR"
    info "Xray 安装成功：$($XRAY_BIN version 2>/dev/null | head -1)"
  fi
}

_dl_singbox_inner() { # 下载并安装 sing-box 内核；FORCE_DL=1 时即使已存在也强制下载最新版
  step "[下载] 获取 sing-box 内核…"
  if [ "$LOW_MEM" = "1" ]; then
    warn "sing-box 解压后大约 80MB，这台机器大约 ${MEM_MB:-很少}MB 内存，有可能装不上。装不上的话，协议请选 6（Hysteria2）。"
  fi
  if [ "$FORCE_DL" != "1" ] && [ -x "$SB_BIN" ] && "$SB_BIN" version >/dev/null 2>&1; then
    info "sing-box 已存在，直接用现有的：$($SB_BIN version 2>/dev/null | head -1)"
  else
    DL_DIR=$(pick_dldir) || die "找不到可写的下载目录"
    _ver=$(_latest_tag "SagerNet/sing-box") \
      || die "获取 sing-box 最新版本失败，检查服务器能否访问 github.com$(_gh_hint)"
    # 磁盘上已有完整可用的包就直接用（上次下载完但被中断的情况，不用重新下载）；
    # 更新模式（FORCE_DL=1）不走这里，必须拉最新版。
    # 但缓存的包可能是几个月前的旧版本：验一下版本，旧了就重新下，别装个过期内核
    _reuse=0
    if [ "$FORCE_DL" != "1" ] && [ -s "$DL_DIR/sb.tar.gz" ] && tar tzf "$DL_DIR/sb.tar.gz" >/dev/null 2>&1; then
      rm -rf "$DL_DIR/sb-ver" && mkdir -p "$DL_DIR/sb-ver"
      _sb_ver_inner=$(tar tzf "$DL_DIR/sb.tar.gz" 2>/dev/null | head -1 | cut -d/ -f1)
      if [ -n "$_sb_ver_inner" ] \
         && tar xzf "$DL_DIR/sb.tar.gz" -C "$DL_DIR/sb-ver" 2>/dev/null \
         && [ -x "$DL_DIR/sb-ver/${_sb_ver_inner}/sing-box" ] \
         && _cached_ver_ok "$DL_DIR/sb-ver/${_sb_ver_inner}/sing-box" "SagerNet/sing-box" "$_ver"; then
        _reuse=1
        info "安装包已在本地且是最新版，直接使用（跳过下载）"
      else
        info "本地安装包不是最新版，重新下载…"
      fi
      rm -rf "$DL_DIR/sb-ver"
    fi
    if [ "$_reuse" = "0" ]; then
      rm -f "$DL_DIR/sb.tar.gz"
      _dl_ok=0
      # 候选包名：Alpine 先 musl 再 generic；其它系统先 generic 再 glibc。
      # generic 是官方长期提供的传统包，兼容性最稳；显式 libc 后缀包作兜底
      # （防官方某天改名或下掉某一版）
      if [ -f /etc/alpine-release ]; then
        _sb_cands="sing-box-${_ver}-linux-${MACH}-musl.tar.gz sing-box-${_ver}-linux-${MACH}.tar.gz"
      else
        _sb_cands="sing-box-${_ver}-linux-${MACH}.tar.gz sing-box-${_ver}-linux-${MACH}-glibc.tar.gz"
      fi
      _GH_VIA=direct
      for _cand in $_sb_cands; do
        info "尝试下载：${_cand}"
        # 路线 A：GitHub API（api.github.com 稳，302 跳到 release-assets 下得快）
        if gh_api_dl "SagerNet/sing-box" "$_cand" "$DL_DIR/sb.tar.gz"; then
          _dl_ok=1
          break
        fi
        warn "API 路线失败，换 github.com 直链和镜像试试…"
        rm -f "$DL_DIR/sb.tar.gz"
        # 路线 B：github.com 版本直链，不通再走镜像和 NAT64
        _url="https://github.com/SagerNet/sing-box/releases/download/v${_ver}/${_cand}"
        if _gh_get "$_url" "$DL_DIR/sb.tar.gz"; then
          _dl_ok=1
          break
        fi
        warn "这个包名下载失败，换下一个包名试试…"
        rm -f "$DL_DIR/sb.tar.gz"
      done
      [ "$_dl_ok" -eq 1 ] || die "sing-box 下载失败：到 GitHub 的网络不稳定，稍等几分钟后重跑脚本试试$(_gh_hint)"
      # sing-box 没有单独的校验文件，用 GitHub API 给的 sha256（digest）对一遍
      _verify_dl "$DL_DIR/sb.tar.gz" "SagerNet/sing-box" "v${_ver}" "$_cand" \
        || die "sing-box 安装包校验没通过，已停止。请稍后重跑脚本"
    fi
    # 完整性校验：包坏了直接报错，不往下装半截文件
    tar tzf "$DL_DIR/sb.tar.gz" >/dev/null 2>&1 || die "下载的安装包已损坏，请重跑脚本重新下载"
    # 包内顶层目录名跟包名走（不同候选包名目录名不同），动态探测，不写死
    _sb_inner=$(tar tzf "$DL_DIR/sb.tar.gz" 2>/dev/null | head -1 | cut -d/ -f1)
    [ -n "$_sb_inner" ] || die "解压后没找到 sing-box 文件"
    # 先装到临时名、验明能跑再原子替换：更新模式下旧内核一直可用，直到新内核确认没问题
    rm -f "${SB_BIN}.new"
    if _unpack_drip tgz "$DL_DIR/sb.tar.gz" "${_sb_inner}/sing-box" "${SB_BIN}.new"; then
      # 小内存机器：边解压边落盘，直接写到目标位置
      chmod 0755 "${SB_BIN}.new" || { rm -f "${SB_BIN}.new"; die "安装 sing-box 失败"; }
    else
      rm -rf "$DL_DIR/sb-dl" && mkdir -p "$DL_DIR/sb-dl"
      _pace_start
      tar xzf "$DL_DIR/sb.tar.gz" -C "$DL_DIR/sb-dl" || { _pace_stop; die "解压失败"; }
      [ -s "$DL_DIR/sb-dl/${_sb_inner}/sing-box" ] || { _pace_stop; die "解压后没找到 sing-box 文件"; }
      install -m 0755 "$DL_DIR/sb-dl/${_sb_inner}/sing-box" "${SB_BIN}.new" || { _pace_stop; rm -f "${SB_BIN}.new"; die "安装 sing-box 失败"; }
      _pace_stop
    fi
    # 安装包用完就删，占的缓存马上还给系统
    rm -rf "$DL_DIR"
    drop_page_cache
    _sb_run=$("${SB_BIN}.new" version 2>&1)
    if [ $? -ne 0 ]; then
      rm -f "${SB_BIN}.new"
      die "下载的 sing-box 内核跑不起来。内存大约 ${MEM_MB:-未知}MB。系统说：$(printf '%s' "$_sb_run" | tr '\n' ' ' | cut -c1-300)"
    fi
    mv -f "${SB_BIN}.new" "$SB_BIN"
    _dns64_off
    mark_our_bin "sing-box"
    rm -rf "$DL_DIR"
    info "sing-box 安装成功：$($SB_BIN version 2>/dev/null | head -1)"
  fi
}

# ---------- 1. 必须是 root ----------
# 装软件、写系统配置、改防火墙都要管理员（root）权限，普通用户做不了。
if [ "$(id -u)" -ne 0 ]; then
  die "请用 root 用户运行（root 下直接运行，或在命令前加 sudo）"
fi
# 用 heredoc 或管道把脚本喂给 sh 时，标准输入已经结束。
# 提问会读到空，回车的默认值会被当成你的选择，端口和伪装域名就不再问。
# 键盘还在就改回键盘。这里不能写进 ask：测试用管道喂答案，在 ask 里读 /dev/tty 会卡住。
# 没有控制终端时（面板、cloud-init、无 tty 的 ssh 命令）/dev/tty 打不开，dash 下 exec 失败会直接退出。先试开一次。
if [ ! -t 0 ] && [ -r /dev/tty ] && (: < /dev/tty) 2>/dev/null; then
  exec < /dev/tty
fi
umask 077
# 上次脚本中途被关掉、临时 DNS 没换回时，先换回来。
_dns64_recover
# 旧版本可能把节点链接和密码写成全机可读；升级时也一并收紧。
for _sec_dir in /etc/xray-node /etc/xray-node/nodes /etc/xray-node/nodes/*/; do
  [ -d "$_sec_dir" ] && chmod 700 "$_sec_dir"
done
for _sec_file in /etc/xray-node/nodes/*/config.json /etc/xray-node/nodes/*/node.txt \
  /etc/xray-node/nodes/*/fw_info /etc/xray-node/nodes/*/core \
  /etc/xray-node/nodes/*/key.pem /etc/xray-node/nodes/*/cert.pem \
  /etc/xray-node/nodes/*/expire \
  /etc/xray-node/our_bins /etc/xray-node/node.txt /etc/xray-node/core /etc/xray-node/fw_info; do
  [ -f "$_sec_file" ] && chmod 600 "$_sec_file"
done
# 上面把目录都收成只有 root 能进。用普通用户 xray-node 跑的 Hysteria2 还要能读自己的配置和证书。
if grep -q '^User=xray-node' /etc/systemd/system/hysteria-node@.service 2>/dev/null; then
  for _sec_dir in /etc/xray-node/nodes/*/; do
    [ "$(tr -d ' \r\n' < "${_sec_dir}core" 2>/dev/null)" = "hysteria" ] || continue
    _hy_perms "$(basename "$_sec_dir")" xray-node
  done
fi

printf "\n${BOLD}==============================================${NC}\n"
printf "${BOLD}   Xray 节点一键安装（小白版）${NC}\n"
printf "${BOLD}==============================================${NC}\n"
printf "全程中文提问，看不懂就一路回车用默认。\n"
printf "节点分两种：永久节点一直有效；定时节点到点后彻底失效。\n"
printf "同一个菜单里可以关闭 IPv6：关掉之后，这台服务器只通过 IPv4 访问网站和 App。\n"

# ---------- 2b. 架构与路径（更新模式也要用，提前确定） ----------
# 架构就是 CPU 类型：常见服务器是 x86_64（amd64），也有 ARM。下载内核要选对应的版本。
mkdir -p /usr/local/bin 2>/dev/null  # 极简系统可能连这个目录都没有
XRAY_BIN="/usr/local/bin/xray"
SB_BIN="/usr/local/bin/sing-box"
HY_BIN="/usr/local/bin/hysteria"
LOW_MEM=0
SWAP_OK=0
MEM_MB=""
SVC_UNIT=""
case "$(uname -m)" in
  x86_64|amd64) MACH="amd64" ;;
  aarch64|arm64) MACH="arm64" ;;
  armv7l|armv7) MACH="armv7" ;;
  *) die "不支持的 CPU 架构：$(uname -m)" ;;
esac

# 64MB NAT 要在装任何大程序之前做完：放开内存申请，并尽量加一块虚拟内存
prepare_low_memory

# ---------- 2a. 清理上次没装完的半截节点 ----------
# 上次安装如果在写出 node.txt 之前失败，目录和服务会留下，但 shanjiedian 看不到。
# 服务开着 Restart=on-failure 就会一直占端口；64MB 机器上还会把后来的更新拖进回滚。
_drop_partial_node() {
  _dp_id="$1"
  _dp_dir="$2"
  [ -n "$_dp_id" ] && [ -n "$_dp_dir" ] && [ -d "$_dp_dir" ] || return 0
  [ -f "$_dp_dir/node.txt" ] && return 0
  case "$_dp_id" in ''|*[!0-9]*) return 0 ;; esac
  _dp_core=$(tr -d ' \r\n' < "$_dp_dir/core" 2>/dev/null)
  _dp_sd=${XRAY_SYSTEMD_RUN:-/run/systemd/system}
  if command -v systemctl >/dev/null 2>&1 && [ -d "$_dp_sd" ]; then
    case "$_dp_core" in
      sing-box) _dp_units="singbox-node@${_dp_id}" ;;
      hysteria) _dp_units="hysteria-node@${_dp_id}" ;;
      xray) _dp_units="xray-node@${_dp_id}" ;;
      *) _dp_units="xray-node@${_dp_id} singbox-node@${_dp_id} hysteria-node@${_dp_id}" ;;
    esac
    for _dp_unit in $_dp_units; do
      systemctl stop "$_dp_unit" >/dev/null 2>&1
      systemctl disable "$_dp_unit" >/dev/null 2>&1
      systemctl reset-failed "$_dp_unit" >/dev/null 2>&1
    done
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "xray-node-${_dp_id}" stop >/dev/null 2>&1
    rc-update del "xray-node-${_dp_id}" default >/dev/null 2>&1
    rm -f "/etc/init.d/xray-node-${_dp_id}"
  fi
  pkill -f "${_dp_dir%/}/config.json" >/dev/null 2>&1
  pkill -f "${_dp_dir%/}/config.yaml" >/dev/null 2>&1
  [ -x /usr/local/bin/xray-node-hop ] && /usr/local/bin/xray-node-hop down "$_dp_id" >/dev/null 2>&1
  [ -x /usr/local/bin/xray-node-route ] && /usr/local/bin/xray-node-route down "$_dp_id" >/dev/null 2>&1
  # 装到一半为这个节点放行的防火墙端口（证书用的 fw_acme、节点自己的 fw_info）也撤掉
  _dp_watch="${XRAY_BIN_DIR:-/usr/local/bin}/xray-node-watch"
  _dp_d="${_dp_dir%/}"
  if [ -x "$_dp_watch" ]; then
    if [ -f "$_dp_d/fw_acme" ] && [ "$(cat "$_dp_d/fw_acme.state" 2>/dev/null)" != "closed" ]; then
      "$_dp_watch" undo "$_dp_d/fw_acme" >/dev/null 2>&1
    fi
    [ -f "$_dp_d/fw_info" ] && "$_dp_watch" undo "$_dp_d/fw_info" >/dev/null 2>&1
  fi
  rm -rf "$_dp_dir"
}

_reap_partial_nodes() {
  _nodes_root=${XRAY_NODES_DIR:-/etc/xray-node/nodes}
  for _rp in "$_nodes_root"/*/; do
    [ -d "$_rp" ] || continue
    [ -f "${_rp}node.txt" ] && continue
    _reap_id=$(basename "$_rp")
    _drop_partial_node "$_reap_id" "$_rp"
    [ -d "$_rp" ] || warn "已清掉上次没装完的节点 ${_reap_id}"
  done
  rmdir "$_nodes_root" 2>/dev/null || true
}

_abort_partial_node() {
  [ -n "${NODE_DIR:-}" ] && [ -n "${NODE_ID:-}" ] || return 0
  [ -d "$NODE_DIR" ] && [ ! -f "$NODE_DIR/node.txt" ] || return 0
  _drop_partial_node "$NODE_ID" "$NODE_DIR"
  rmdir "${XRAY_NODES_DIR:-/etc/xray-node/nodes}" 2>/dev/null || true
  _drop_expire_bins_if_unused
}

_reap_partial_nodes

# ---------- 2c. 老版本迁移：单节点布局 -> 多节点布局 ----------
# 老版本只有一个节点（/etc/xray-node/node.txt + xray/sing-box 单服务）。
# 转为"每个节点独立目录 + 独立服务"，旧节点配置原样保留；
# 先停旧服务、再起新服务，中间只断几秒。
if [ -f /etc/xray-node/node.txt ] && [ ! -d /etc/xray-node/nodes ]; then
  step "[迁移] 检测到老版本单节点，正在转为多节点管理（旧节点保留）…"
  _m_core=$(tr -d ' \r\n' < /etc/xray-node/core 2>/dev/null)
  case "$_m_core" in xray|sing-box) ;; *) _m_core="xray" ;; esac
  if [ "$_m_core" = "xray" ]; then
    _m_cfg=/usr/local/etc/xray/config.json
  else
    _m_cfg=/usr/local/etc/sing-box/config.json
  fi
  if [ ! -f "$_m_cfg" ]; then
    die "找不到老节点的配置文件（${_m_cfg}），旧节点资料已保留；请先检查旧安装再重试"
  else
    _m_port=$(sed -n 's/^端口: //p' /etc/xray-node/node.txt | head -1)
    _m_proto=tcp
    case "$(sed -n 's/^协议: //p' /etc/xray-node/node.txt | head -1)" in
      hy2|hysteria2|tuic|TUIC) _m_proto=udp ;;
    esac
    if [ -f /etc/xray-node/fw_info ]; then
      read -r _m_fw_port _m_fw_proto _m_rest < /etc/xray-node/fw_info
      case "$_m_fw_port" in *[!0-9]*|'') ;; *)
        _m_port=$_m_fw_port
        case "$_m_fw_proto" in tcp|udp) _m_proto=$_m_fw_proto ;; esac
        ;;
      esac
    fi
    _m_manager=""
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      _m_manager=systemd
    elif command -v rc-service >/dev/null 2>&1; then
      _m_manager=openrc
    fi
    case "$_m_port" in *[!0-9]*|'') _m_port="" ;; esac
    if [ -z "$_m_port" ] || [ "$_m_port" -lt 1 ] || [ "$_m_port" -gt 65535 ] ||
       [ -z "$_m_manager" ] ||
       { ! command -v ss >/dev/null 2>&1 && ! command -v netstat >/dev/null 2>&1 &&
         [ ! -r /proc/net/tcp ] && [ ! -r /proc/net/udp ]; }; then
      die "无法可靠核验老节点的端口或服务管理方式，旧节点保持原状；请检查后再重试"
    else
      # 先复制；只有新服务确认可用后才删除旧配置和旧服务。
      mkdir -p /etc/xray-node/nodes/1 || die "无法创建新节点目录，旧节点未受影响"
      cp -p "$_m_cfg" /etc/xray-node/nodes/1/config.json &&
        cp -p /etc/xray-node/node.txt /etc/xray-node/nodes/1/node.txt ||
        { rm -rf /etc/xray-node/nodes/1; rmdir /etc/xray-node/nodes 2>/dev/null; die "复制旧节点资料失败，旧节点未受影响"; }
      [ ! -f /etc/xray-node/fw_info ] || cp -p /etc/xray-node/fw_info /etc/xray-node/nodes/1/fw_info ||
        { rm -rf /etc/xray-node/nodes/1; rmdir /etc/xray-node/nodes 2>/dev/null; die "复制旧防火墙记录失败，旧节点未受影响"; }
      printf '%s\n' "$_m_core" > /etc/xray-node/nodes/1/core ||
        { rm -rf /etc/xray-node/nodes/1; rmdir /etc/xray-node/nodes 2>/dev/null; die "写入内核标记失败，旧节点未受影响"; }
      if [ "$_m_manager" = systemd ]; then
        systemctl stop "$_m_core" >/dev/null 2>&1
      else
        rc-service "$_m_core" stop >/dev/null 2>&1
      fi
      pkill -f "$_m_cfg" >/dev/null 2>&1
      sleep 1
      _svc_install 1
      _m_new_ok=1
      if [ "$_m_manager" = systemd ]; then
        case "$_m_core" in sing-box) _m_new_unit=singbox-node@1 ;; *) _m_new_unit=xray-node@1 ;; esac
        systemctl is-active --quiet "$_m_new_unit" || _m_new_ok=0
      else
        rc-service xray-node-1 status >/dev/null 2>&1 || _m_new_ok=0
      fi
      wait_for_port "$_m_port" "$_m_proto" 15 || _m_new_ok=0
      if [ "$_m_new_ok" = 1 ]; then
        if [ "$_m_manager" = systemd ]; then
          systemctl disable "$_m_core" >/dev/null 2>&1
          rm -f "/etc/systemd/system/${_m_core}.service"
          systemctl daemon-reload >/dev/null 2>&1
        else
          rc-update del "$_m_core" default >/dev/null 2>&1
          rm -f "/etc/init.d/${_m_core}"
        fi
        rm -f "$_m_cfg" /etc/xray-node/node.txt /etc/xray-node/fw_info /etc/xray-node/core
        rmdir /usr/local/etc/xray /usr/local/etc/sing-box 2>/dev/null
        info "迁移完成：老节点已转为节点 1，端口 $_m_port/$_m_proto 监听正常"
        # 马上换成新版的 jiedian / shanjiedian。老版 xiezai 按旧布局一键全删，
        # 迁移后再用它会删掉共用内核、弄坏节点 1；用户在下面菜单直接取消也不能留着它。
        write_helper_cmds
      else
        if [ "$_m_manager" = systemd ]; then
          systemctl stop "$_m_new_unit" >/dev/null 2>&1
          systemctl disable "$_m_new_unit" >/dev/null 2>&1
          systemctl start "$_m_core" >/dev/null 2>&1
        else
          rc-service xray-node-1 stop >/dev/null 2>&1
          rc-update del xray-node-1 default >/dev/null 2>&1
          rm -f /etc/init.d/xray-node-1
          rc-service "$_m_core" start >/dev/null 2>&1
        fi
        rm -rf /etc/xray-node/nodes/1
        rmdir /etc/xray-node/nodes 2>/dev/null
        die "新服务未能正常监听，已尝试恢复旧节点；请检查旧服务状态后再重试"
      fi
    fi
  fi
fi

# ---------- 2d. 已有节点时的主菜单 ----------
# 已经装过节点：更新（默认）/ 添加节点 / 节点管理 / 取消
# 选 2 之后先进入种类菜单：永久节点、定时节点，或关闭/开启 IPv6。旧节点继续用。
# 想删节点选 3，或直接输 shanjiedian
UPDATE_MODE=0
FORCE_DL=0
NODE_KIND=permanent
EXPIRE_AFTER=0
EXPIRE_LABEL=""
_KIND_CHOSEN=0
# 先清掉已经到点的定时节点，再数还剩几个。永久节点没有失效时间，不会被碰。
install_expire_bins || warn "定时失效程序没能写上。永久节点不受影响；定时节点可能要等下次运行脚本才会被删掉。"
if [ -x /usr/local/bin/xray-node-expire ]; then
  /usr/local/bin/xray-node-expire || true
fi
arm_expire_watch || true
arm_node_watch || true
_NODE_COUNT=0
if [ -d /etc/xray-node/nodes ]; then
  for _nd in /etc/xray-node/nodes/*/; do
    [ -f "${_nd}node.txt" ] && _NODE_COUNT=$((_NODE_COUNT + 1))
  done
fi
if [ "$_NODE_COUNT" -gt 0 ]; then
  while true; do
  printf "\n检测到这台机器已经装了 %s 个节点。\n" "$_NODE_COUNT"
  printf "  1) 更新内核（推荐。顺便把旧版端口跳跃改成新写法、去掉旧版在服务器上拦 QUIC 的设置；Hysteria2 在有 IPv6 的机器上会同时听 IPv6，其它配置不动）\n"
  printf "  2) 添加节点（下一步再选永久节点或定时节点，旧节点不受影响）\n"
  printf "  3) 节点管理（查看所有节点、删除某个节点）\n"
  printf "  4) 取消，什么都不做\n"
  printf "  5) 关闭或开启 IPv6（不添加节点。关掉后，这台服务器只通过 IPv4 访问网站和 App）\n"
  ask "请选择" "1" _um
  case "$_um" in
    1) UPDATE_MODE=1; HY_IPV6_FIXED=0; _hy_migrate_hop_all; _hy_fix_existing_ipv6; _quic_unblock_all; break ;;
    2) _choose_node_kind; _KIND_CHOSEN=1; break ;;
    3) write_helper_cmds; sh /usr/local/bin/shanjiedian; exit 0 ;;
    4|n|N|no|NO) echo "已取消"; exit 0 ;;
    5) _ipv6_switch_menu ;;
    *) warn "没有这个选项，请重新选择" ;;
  esac
  done
fi

# 旧版小内存模式保存了整张 iptables 快照。更新或加节点时改为只恢复本脚本的规则。
if [ -f /etc/xray-node/rules.v4 ] || [ -f /etc/xray-node/rules.v6 ]; then
  _save_fw_light || warn "旧版防火墙恢复服务迁移失败，重启前请检查防火墙规则"
fi

# 新节点编号：已有最大编号 + 1（删掉的编号不重用，避免和以前的节点搞混）
NODE_ID=1
for _nd in /etc/xray-node/nodes/*/; do
  [ -d "$_nd" ] || continue
  _nn=$(basename "$_nd")
  case "$_nn" in ''|*[!0-9]*) continue ;; esac
  [ "$_nn" -ge "$NODE_ID" ] && NODE_ID=$((_nn + 1))
done
NODE_DIR=/etc/xray-node/nodes/$NODE_ID
# 注意：目录在这里先不建，留到更新模式之后——更新模式不需要新目录，
# 提前建会在每次更新时留下一个空编号目录，节点编号越跳越大

# ---------- 2. 装依赖（缺啥装啥，都有就直接跳过） ----------
# 依赖 = 脚本要用到的系统工具，这里主要是下载用的 curl（或 wget）。用系统自带的软件管理器安装。
step "[准备] 检查系统工具…"
_dep_log="/tmp/xray-dep-apt.log"
# _apt_do <描述> <单次超时秒> -- <apt-get 参数…>
# 刚开机的机器常被系统自动更新占着 dpkg 锁：不等锁就硬装会白白超时失败。
# 这里检测到锁就等 20 秒重试并报进度，而不是静默卡死。
# 注意：这个函数定义在 if 外面——后面存 iptables 规则时也要用它装 iptables-persistent，
# 放里面会导致"依赖本来就齐"时函数根本没定义、调用直接报错。
# 有的精简系统没有 timeout。没有就自己计时，避免装 curl 时先报 timeout: not found。
_timeout_cmd() {
  _tsec="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_tsec" "$@"
    return $?
  fi
  "$@" &
  _tpid=$!
  _tw=0
  while kill -0 "$_tpid" 2>/dev/null; do
    if [ "$_tw" -ge "$_tsec" ]; then
      kill "$_tpid" 2>/dev/null || true
      sleep 1
      kill -9 "$_tpid" 2>/dev/null || true
      wait "$_tpid" 2>/dev/null || true
      return 124
    fi
    sleep 2
    _tw=$((_tw + 2))
  done
  wait "$_tpid"
  return $?
}

_apt_do() {
  _ad="$1"; _ato="$2"; shift 2
  [ "$1" = "--" ] && shift
  _an=0
  while [ "$_an" -lt 10 ]; do
    printf "%s…\n" "$_ad"
    # DPkg::Lock::Timeout=120：锁被系统自动更新占着时，120 秒拿不到就快速失败，
    # 走下面的排队重试。不设的话老版本 apt 会静默等锁（-qq 还把等待提示吞了），
    # 单次尝试卡满整个超时、重试逻辑还检测不到——看着就像"卡住不动"。
    # 心跳：apt 的输出被吞掉了，单次尝试最长 $_ato 秒；每 30 秒报一次"还在装"，
    # 免得小白以为卡死。
    ( _timeout_cmd "$_ato" apt-get -o DPkg::Lock::Timeout=120 "$@" >"$_dep_log" 2>&1
      echo "$?" >"$_dep_log.rc" ) &
    _apt_pid=$!
    _apt_waited=0
    while kill -0 "$_apt_pid" 2>/dev/null; do
      sleep 2
      _apt_waited=$((_apt_waited + 2))
      if kill -0 "$_apt_pid" 2>/dev/null && [ "$((_apt_waited % 30))" = "0" ]; then
        printf "还在安装中，已等待 %s 秒（机器慢时会久一点，正常）…\n" "$_apt_waited"
      fi
    done
    wait "$_apt_pid" 2>/dev/null
    _apt_rc=$(cat "$_dep_log.rc" 2>/dev/null); rm -f "$_dep_log.rc"
    if [ "$_apt_rc" = "0" ]; then return 0; fi
    # 超时杀在 dpkg 中间，或下一次 apt 已报 interrupted：先修复再重试。
    # 这条路径也必须计入 _an，否则会在反复 interrupted 时死循环。
    if [ "$_apt_rc" = "124" ] || grep -qi "dpkg was interrupted" "$_dep_log" 2>/dev/null; then
      _an=$((_an + 1))
      printf "检测到安装被打断或超时，正在修复（%s/10）…\n" "$_an"
      _timeout_cmd 120 dpkg --configure -a >"$_dep_log" 2>&1 || true
      continue
    fi
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
# unzip 只有 Xray 的 zip 包才要。小内存机器上为了 Hysteria2 先 apt 装 unzip，
# 很容易在选协议之前就把内存吃光。缺 unzip 时留到下载 Xray 再装。
_have_curl() { command -v curl >/dev/null 2>&1; }
_have_wget() {
  command -v wget >/dev/null 2>&1 && return 0
  command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx wget
}
_have_pkgman() {
  command -v apt-get >/dev/null 2>&1 && return 0
  command -v apk >/dev/null 2>&1 && return 0
  command -v dnf >/dev/null 2>&1 && return 0
  command -v yum >/dev/null 2>&1 && return 0
  command -v pacman >/dev/null 2>&1 && return 0
  command -v zypper >/dev/null 2>&1 && return 0
  return 1
}
_pkg_updated=0
_pkg_add() { # _pkg_add 描述 包名…
  _pa_desc="$1"; shift
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    if [ "$_pkg_updated" != 1 ]; then
      _apt_do "正在更新软件源" 90 -- update -qq \
        || _apt_do "正在更新软件源（改走 IPv4）" 90 -- -o Acquire::ForceIPv4=true update -qq \
        || warn "软件源更新失败，用已有索引继续装（多数情况不影响）"
      _pkg_updated=1
    fi
    _apt_do "$_pa_desc" 300 -- install -y -qq "$@" \
      || _apt_do "${_pa_desc}（改走 IPv4）" 300 -- -o Acquire::ForceIPv4=true install -y "$@" \
      || _dep_fail
    unset DEBIAN_FRONTEND
    return 0
  fi
  printf "%s…\n" "$_pa_desc"
  if command -v apk >/dev/null 2>&1; then
    _timeout_cmd 300 apk add --no-cache "$@" >"$_dep_log" 2>&1 || _dep_fail
  elif command -v dnf >/dev/null 2>&1; then
    _timeout_cmd 300 dnf install -y -q "$@" >"$_dep_log" 2>&1 \
      || _timeout_cmd 300 dnf install -y -q --setopt=ip_resolve=4 "$@" >"$_dep_log" 2>&1 \
      || _dep_fail
  elif command -v yum >/dev/null 2>&1; then
    _timeout_cmd 300 yum install -y -q "$@" >"$_dep_log" 2>&1 || _dep_fail
  elif command -v pacman >/dev/null 2>&1; then
    _timeout_cmd 300 pacman -Sy --noconfirm --needed "$@" >"$_dep_log" 2>&1 || _dep_fail
  elif command -v zypper >/dev/null 2>&1; then
    _timeout_cmd 300 zypper --non-interactive install "$@" >"$_dep_log" 2>&1 || _dep_fail
  else
    return 1
  fi
}
if _have_curl; then
  info "curl 已有，直接跳过安装"
elif _have_wget; then
  info "没有 curl，用已有的 wget 继续"
else
  printf "没有 curl，也没有 wget。正在识别系统并自动安装，装完继续…\n"
  _have_pkgman || die "识别不到软件安装方式。请先手动安装 curl 或 wget，然后再运行。"
  _pkg_add "正在安装 curl" curl ca-certificates
  hash -r 2>/dev/null || true
  if ! _have_curl && ! _have_wget; then
    _pkg_add "正在安装 curl" curl
    hash -r 2>/dev/null || true
  fi
  if ! _have_curl && ! _have_wget; then
    _pkg_add "curl 没装上，改装 wget" wget
    hash -r 2>/dev/null || true
  fi
  rm -f "$_dep_log"
  if _have_curl; then
    info "curl 已装好，继续"
  elif _have_wget; then
    info "wget 已装好，继续"
  else
    die "curl 和 wget 都没装上。请把上面的报错发出来，或手动安装 curl 后再运行。"
  fi
fi
info "系统工具就绪"

# ---------- U. 更新模式：只升级内核，节点配置原样保留 ----------
# 重跑一键命令选"1"进到这里：不问问题、不改配置，只把各节点用的内核升到最新版。
if [ "$UPDATE_MODE" = "1" ]; then
  step "[更新] 检查已安装的内核版本…"
  # 收集所有节点用到的内核（去重）
  _u_cores=""
  for _ud in /etc/xray-node/nodes/*/; do
    [ -f "${_ud}core" ] || continue
    _uc=$(tr -d ' \r\n' < "${_ud}core" 2>/dev/null)
    case "$_uc" in
      xray|sing-box|hysteria)
        case " $_u_cores " in *" $_uc "*) ;; *) _u_cores="$_u_cores $_uc" ;; esac
        ;;
    esac
  done
  if [ -z "$_u_cores" ]; then
    warn "找不到已安装节点用的内核信息，改走添加新节点流程。"
    UPDATE_MODE=0
  else
    _u_any_fail=0
    for _ucore in $_u_cores; do
      # 每个内核独立处理：一个失败不影响另一个（子 shell 里 die 只退出子 shell）
      (
      if [ "$_ucore" = "xray" ]; then
        _u_repo="XTLS/Xray-core"; _u_bin="$XRAY_BIN"
      elif [ "$_ucore" = "hysteria" ]; then
        _u_repo="apernet/hysteria"; _u_bin="$HY_BIN"
      else
        _u_repo="SagerNet/sing-box"; _u_bin="$SB_BIN"
      fi
      # 首次安装时会复用机器上已有的内核；那可能属于其他服务，不能覆盖升级。
      if ! grep -qx "$_ucore" /etc/xray-node/our_bins 2>/dev/null; then
        warn "$_ucore 是机器上原有的内核，跳过升级，避免影响其他服务"
        exit 0
      fi
      _u_inst=""
      if [ -x "$_u_bin" ]; then
        if [ "$_ucore" = "hysteria" ]; then
          _u_inst=$(_hysteria_local_ver "$_u_bin")
        else
          _u_inst=$(_ver_num "$("$_u_bin" version 2>/dev/null | head -1)")
        fi
      fi
      _gh_prepare
      if [ "$_ucore" = "hysteria" ]; then
        _u_latest=$(_latest_hysteria_ver) || _u_latest=""
      else
        _u_latest=$(_latest_tag "$_u_repo") || _u_latest=""
      fi
      _dns64_off
      if [ -z "$_u_latest" ]; then
        warn "连不上 api.github.com，$_ucore 检查更新失败，跳过（节点不受影响，继续正常使用）。"
        exit 0
      fi
      if [ -n "$_u_inst" ] && [ "$_u_inst" = "$_u_latest" ]; then
        info "$_ucore 已经是最新版（v${_u_inst}），无需更新。"
        exit 0
      fi
      if [ -n "$_u_inst" ]; then
        info "$_ucore 当前版本 v${_u_inst}，最新版本 v${_u_latest}，开始升级…"
      else
        warn "$_ucore 内核文件丢失或已损坏，直接下载最新版 v${_u_latest}（节点配置保留）。"
      fi
      # 每次升级用独立备份路径；上次失败留下的备份不会被覆盖。
      _u_backup=""
      if [ -x "$_u_bin" ]; then
        _u_backup=$(mktemp "${_u_bin}.bak.XXXXXX") ||
          die "$_ucore 无法创建备份文件，升级已取消"
        _cp_bin "$_u_bin" "$_u_backup" ||
          { rm -f "$_u_backup"; die "$_ucore 旧内核备份失败，升级已取消"; }
        info "旧内核备份：$_u_backup"
      fi
      FORCE_DL=1
      if [ "$_ucore" = "xray" ]; then dl_xray
      elif [ "$_ucore" = "hysteria" ]; then dl_hysteria
      else dl_singbox
      fi
      FORCE_DL=0
      # 重启所有用这个内核的节点（子 shell 里改 FORCE_DL 不影响外面）
      step "[更新] 重启 $_ucore 的节点服务…"
      _u_failed=""
      for _ud2 in /etc/xray-node/nodes/*/; do
        [ -f "${_ud2}core" ] || continue
        _uc2=$(tr -d ' \r\n' < "${_ud2}core" 2>/dev/null)
        [ "$_uc2" = "$_ucore" ] || continue
        _u_id=$(basename "$_ud2")
        _svc_restart "$_u_id"
        # 读出该节点端口，硬检查真的在监听
        _u_port=""; _u_proto="tcp"
        if _u_pp=$(_node_port "$_u_id"); then set -- $_u_pp; _u_port="$1"; _u_proto="$2"; fi
        if [ -n "$_u_port" ] && wait_for_port "$_u_port" "$_u_proto" 15; then
          info "节点 $_u_id 升级成功：端口 $_u_port/$_u_proto 监听正常，配置未变"
        else
          warn "节点 $_u_id 更新后端口没监听（端口：${_u_port:-未知}）"
          _u_failed="$_u_failed $_u_id"
        fi
      done
      if [ -n "$_u_failed" ]; then
        _u_rb_bad=""
        if [ -n "$_u_backup" ] && [ -f "$_u_backup" ]; then
          warn "新内核启动后有节点端口没监听，正在回滚到旧版本…"
          # 不能 cp 到正在运行的可执行文件：其他节点可能正运行新版，会触发 ETXTBSY。
          # 在同一目录先写临时文件，再原子替换路径，并保留备份直到全部恢复成功。
          rm -f "${_u_bin}.rollback"
          _cp_bin "$_u_backup" "${_u_bin}.rollback" ||
            die "回滚文件写入失败，备份仍在 ${_u_backup}，请手动恢复"
          mv -f "${_u_bin}.rollback" "$_u_bin" ||
            die "回滚替换失败，备份仍在 ${_u_backup}，请手动恢复"
          # 所有共享此内核的节点都要切回旧版本，不能只重启刚才失败的节点。
          for _rd in /etc/xray-node/nodes/*/; do
            [ -f "${_rd}core" ] || continue
            [ "$(tr -d ' \r\n' < "${_rd}core" 2>/dev/null)" = "$_ucore" ] || continue
            _rid=$(basename "$_rd")
            _svc_restart "$_rid"
            sleep 1
            _r_port=""; _r_proto="tcp"
            if _r_pp=$(_node_port "$_rid"); then set -- $_r_pp; _r_port="$1"; _r_proto="$2"; fi
            if [ -n "$_r_port" ] && wait_for_port "$_r_port" "$_r_proto" 15; then
              info "节点 $_rid 已回滚到旧版本，恢复正常"
            else
              _u_rb_bad="$_u_rb_bad $_rid"
              warn "节点 $_rid 回滚后端口仍未监听，请手动检查该节点的服务状态"
            fi
          done
        else
          _u_rb_bad="$_u_failed"
          warn "没有旧内核备份，无法回滚，请手动检查节点${_u_failed}的服务状态"
        fi
        if [ -z "$_u_rb_bad" ]; then
          rm -f "$_u_backup"
          die "$_ucore 新版本在这台机器上跑不起来，已回滚到旧版本，节点不受影响"
        else
          die "$_ucore 新版本跑不起来，且节点${_u_rb_bad}仍未恢复监听；备份路径：${_u_backup:-无}，请手动检查"
        fi
      fi
      [ -z "$_u_backup" ] || rm -f "$_u_backup"
      info "$_ucore 升级完成"
      ) || _u_any_fail=1
    done
    # UDP 节点的回程路由（有策略路由的机器上，回包要走公网网卡）
    _route_refresh_all
    # 刷新 jiedian / shanjiedian（脚本可能修过它们）
    write_helper_cmds
    info "jiedian / shanjiedian 命令已同步为最新版"
    printf "\n"
    sh /usr/local/bin/jiedian
    if [ "$_u_any_fail" = "1" ]; then
      printf "\n${YELLOW}${BOLD}更新结束：部分内核更新失败（上面有说明），其它节点不受影响。${NC}\n"
      exit 1
    elif [ "$HY_IPV6_FIXED" = "1" ]; then
      printf "\n${GREEN}${BOLD}更新完成。${NC}Hysteria2 已同时听 IPv6。上面多出来的是 IPv6 链接，密码没变。云服务器还要在安全组放行这个 UDP 端口的 IPv6。\n"
    else
      printf "\n${GREEN}${BOLD}更新完成！${NC}节点链接、端口、密码都没变，直接继续用。\n"
    fi
    exit 0
  fi
fi
# 更新模式上面已经退出；新节点目录在完成输入和下载后再建，避免失败时留下空编号。

# 第一次安装，或更新失败后改走添加：先选种类。已经在上面选过就不再问。
if [ "${_KIND_CHOSEN:-0}" != "1" ]; then
  _choose_node_kind
fi

# ---------- 3. 问：IPv4 还是 IPv6 ----------
# 分享链接里要写一个服务器地址。绝大多数服务器用 IPv4；只有没有 IPv4 的机器才选 IPv6。
step "[1/4] 节点里填你服务器的哪个公网地址？"
printf "  1) IPv4 地址（服务器有公网 IPv4 就选这个，大多数情况都是）\n"
printf "  2) IPv6 地址（只有纯 IPv6、没有 IPv4 的服务器才选这个）\n"
# 机器上根本没有 IPv4 出口（纯 IPv6 小鸡）时，把默认值改成 2，免得小白回车后选错
_ipdef=1
if command -v ip >/dev/null 2>&1 && [ -z "$(ip -4 route show default 2>/dev/null)" ] \
   && [ -n "$(ip -6 route show default 2>/dev/null)" ]; then
  _ipdef=2
  printf "检测到这台机器没有 IPv4 出口、只有 IPv6，所以默认选 2。\n"
fi
printf "不知道选哪个就回车用默认 %s。\n" "$_ipdef"
while true; do
  ask "请选择" "$_ipdef" _ipver
  case "$_ipver" in
    1) IPVER=4; break ;;
    2) IPVER=6; break ;;
    *) warn "没有这个选项，请重新选择" ;;
  esac
done
printf "正在检测公网 IP…\n"
if ! SERVER_IP=$(get_ip "$IPVER"); then
  warn "自动检测 IP 失败，请手动输入。"
  _iptry=0
  SERVER_IP=""
  while [ "$_iptry" -lt 3 ]; do
    _iptry=$((_iptry + 1))
    ask "请输入你的服务器公网 IPv$IPVER 地址" "" SERVER_IP
    if [ -z "$SERVER_IP" ]; then
      warn "IP 不能为空"
    elif _valid_ip "$IPVER" "$SERVER_IP"; then
      break
    else
      warn "「${SERVER_IP}」不像个 IPv$IPVER 地址，检查一下再输"
    fi
    SERVER_IP=""
  done
  [ -z "$SERVER_IP" ] && die "没有 IP 装不了，先去查一下你的服务器 IP 再来"
fi
info "服务器 IP：$SERVER_IP"
# 节点名 = 地区 + 协议，比如 香港Vless-Reality。查不到地区就写“未知地区”。
printf "正在查这台服务器在哪个国家/地区（用来给节点起名）…\n"
NODE_REGION=""
if _cc=$(_geo_cc "$SERVER_IP" "$IPVER"); then
  NODE_REGION=$(_cc_name "$_cc")
fi
[ -n "$NODE_REGION" ] || NODE_REGION="未知地区"
info "服务器地区：$NODE_REGION"
# 用户经常把 IPv6 连方括号一起粘贴。这里先剥掉，下面再加一层，避免链成 [[地址]]。
case "$SERVER_IP" in
  \[*\]) SERVER_IP=${SERVER_IP#\[}; SERVER_IP=${SERVER_IP%\]} ;;
esac
# 按实际地址格式决定链接里是否加方括号（IPv6 必须加 []）
case "$SERVER_IP" in
  *:*) LINK_IP="[$SERVER_IP]" ;;
  *)   LINK_IP="$SERVER_IP" ;;
esac

# ---------- 4. 问：协议 ----------
# 7 种协议任选一种。看不懂就用默认 1（VLESS + REALITY + Vision），目前最不容易被识别。
step "[2/4] 选一个协议"
printf "  1) VLESS + REALITY + Vision（推荐，最难被识别）\n"
printf "  2) VMess + WebSocket（兼容性好，老客户端也支持）\n"
printf "  3) Trojan + REALITY（和 1 类似，换种协议）\n"
printf "  4) Shadowsocks（最简单，速度不错）\n"
printf "  5) AnyTLS + REALITY（新协议，表现不错）\n"
printf "  6) Hysteria2（UDP，速度快，弱网表现好。可以选混淆和端口跳跃）\n"
printf "  7) TUIC（UDP，低延迟）\n"
while true; do
  ask "请选择" "1" _proto
  case "$_proto" in
    1) PROTO="vless"; break ;;
    2) PROTO="vmess"; break ;;
    3) PROTO="trojan"; break ;;
    4) PROTO="ss"; break ;;
    5) PROTO="anytls"; break ;;
    6) PROTO="hy2"; break ;;
    7) PROTO="tuic"; break ;;
    *) warn "没有这个选项，请重新选择" ;;
  esac
done
# 1-4 用 Xray。AnyTLS / TUIC 用 sing-box。
# Hysteria2 用官方 hysteria：sing-box 1.14 解压后约 80MB，64MB 内存的 NAT 会在下载或启动时被撑死。
case "$PROTO" in
  hy2) CORE="hysteria" ;;
  anytls|tuic) CORE="sing-box" ;;
  *) CORE="xray" ;;
esac

# ---------- 5. 问：端口 ----------
# 默认给一个随机的空闲端口。NAT VPS 的“公网映射端口”是服务商分配给你的外部端口，要写进链接。
step "[3/4] 节点用哪个端口？"
case "$PROTO" in
  hy2|tuic) _PORT_PROTO=udp ;;
  ss) _PORT_PROTO=both ;;
  *) _PORT_PROTO=tcp ;;
esac
_DEF_PORT=$(rand_port "$_PORT_PROTO") || die "找不到空闲端口，请检查这台机器的端口占用情况"
# 端口被别的程序占着时，直接再问一次（最多 3 次），不用整个脚本重跑。
_port_try=0
while true; do
ask "请输入端口（1-65535）" "$_DEF_PORT" PORT
case "$PORT" in
  ''|*[!0-9]*) warn "端口不是数字，用默认 $_DEF_PORT"; PORT="$_DEF_PORT" ;;
esac
# 去掉前导 0（比如 08080）：JSON 数字不允许前导 0，留着后面配置文件校验过不了
PORT=$(printf "%s" "$PORT" | sed 's/^0*//')
[ -z "$PORT" ] && PORT=0
if [ "${#PORT}" -gt 5 ] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  warn "端口超出范围，用默认 $_DEF_PORT"; PORT="$_DEF_PORT"
fi
_port_busy=""
case "$_PORT_PROTO" in
  tcp|both) port_in_use "$PORT" tcp && _port_busy="TCP" ;;
esac
case "$_PORT_PROTO" in
  udp|both) [ -z "$_port_busy" ] && port_in_use "$PORT" udp && _port_busy="UDP" ;;
esac
[ -z "$_port_busy" ] && break
_port_try=$((_port_try + 1))
if [ "$_port_try" -ge 3 ]; then
  die "端口 $PORT/$_port_busy 已被其他程序占用，请重跑脚本换一个端口"
fi
warn "端口 $PORT/$_port_busy 已被其他程序占用，请换一个。直接回车就用 ${_DEF_PORT}（这个是空闲的）。"
done
info "端口：$PORT"
printf "如果是 NAT VPS，且服务商分配的公网端口与上面的端口不同，请填公网端口；普通 VPS 直接回车。\n"
ask "公网映射端口" "$PORT" LINK_PORT
case "$LINK_PORT" in
  ''|*[!0-9]*) die "公网映射端口必须是 1-65535 的数字" ;;
esac
LINK_PORT=$(printf '%s' "$LINK_PORT" | sed 's/^0*//')
[ -n "$LINK_PORT" ] && [ "${#LINK_PORT}" -le 5 ] \
  && [ "$LINK_PORT" -ge 1 ] && [ "$LINK_PORT" -le 65535 ] \
  || die "公网映射端口必须是 1-65535 的数字"
if [ "$LINK_PORT" != "$PORT" ]; then
  info "节点链接会使用公网端口 ${LINK_PORT}；请确认服务商已把它映射到本机 $PORT"
fi
# WireGuard 落地：这个端口在 wg-luodi 的名单里，就提醒一句（真正的修改由 wg-luodi 在节点启动前完成）
if [ -r /etc/wg-luodi/state ]; then
  for _wgl_p in $(sed -n 's/^PORTS=//p' /etc/wg-luodi/state 2>/dev/null | head -n 1); do
    if [ "$_wgl_p" = "$PORT" ] || [ "$_wgl_p" = "$LINK_PORT" ]; then
      info "端口 $_wgl_p 在 WireGuard 落地名单里：这个节点上网会自动走 WireGuard 落地机的 IP"
      break
    fi
  done
fi
# 只有 Hysteria2 才问。其它协议没有端口跳跃。看不懂就回车，不开启。
HY_HOP_PORTS=""
HY2_USE_OBFS=1
HY2_DOMAIN=""
HY2_ACME_TYPE=""
if [ "$PROTO" = "hy2" ]; then
  _hy_ask_hop
  _hy_ask_obfs
  _hy_ask_domain
fi

# ---------- 6. REALITY 伪装域名 ----------
# REALITY 需要“借用”一个真实的大网站来伪装。这个网站要能从你的服务器顺利访问、支持 TLS 1.3。
NEED_REALITY=0
case "$PROTO" in vless|trojan|anytls) NEED_REALITY=1 ;; esac
if [ "$NEED_REALITY" -eq 1 ]; then
  step "[4/4] REALITY 伪装成哪个网站？"
  printf "  1) www.samsung.com（三星官网，零干扰，最稳）\n"
  printf "  2) www.cisco.com（思科官网，TLS 极稳）\n"
  printf "  3) www.apple.com（苹果官网，社区验证最多，推荐）\n"
  printf "  4) itunes.apple.com（苹果音乐服务）\n"
  printf "  5) www.python.org（Python 官网，技术站小众）\n"
  printf "  6) m.media-amazon.com（亚马逊图片站）\n"
  printf "  7) images-na.ssl-images-amazon.com（亚马逊图片 CDN）\n"
  printf "  8) download-installer.cdn.mozilla.net（火狐下载站）\n"
  printf "  9) www.lovelive-anime.jp（日本动画官网，小众）\n"
  printf " 10) academy.nvidia.com（英伟达学院，备选用）\n"
  printf " 11) lol.secure.dyn.riotcdn.net（游戏补丁 CDN，备选用）\n"
  printf "不知道选哪个就回车用默认 1。\n"
  while true; do
    ask "请选择" "1" _dm
    case "$_dm" in
      1)  REALITY_DOMAIN="www.samsung.com"; break ;;
      2)  REALITY_DOMAIN="www.cisco.com"; break ;;
      3)  REALITY_DOMAIN="www.apple.com"; break ;;
      4)  REALITY_DOMAIN="itunes.apple.com"; break ;;
      5)  REALITY_DOMAIN="www.python.org"; break ;;
      6)  REALITY_DOMAIN="m.media-amazon.com"; break ;;
      7)  REALITY_DOMAIN="images-na.ssl-images-amazon.com"; break ;;
      8)  REALITY_DOMAIN="download-installer.cdn.mozilla.net"; break ;;
      9)  REALITY_DOMAIN="www.lovelive-anime.jp"; break ;;
      10) REALITY_DOMAIN="academy.nvidia.com"; break ;;
      11) REALITY_DOMAIN="lol.secure.dyn.riotcdn.net"; break ;;
      *) warn "没有这个选项，请重新选择" ;;
    esac
  done
  info "伪装域名：$REALITY_DOMAIN"
else
  step "[4/4] 这一步跳过（只有 REALITY 协议才需要选伪装域名）"
fi

# ---------- 7. 随机生成 UUID / 密码 ----------
# 每个节点都随机生成新的钥匙，不用你自己想密码，也不会和别人撞。
step "[生成] 随机生成账号和密码…"
UUID=$(gen_uuid)
TROJAN_PASS=$(rand_hex 16)
ANYTLS_PASS=$(rand_hex 16)
HY2_PASS=$(rand_hex 16)
HY2_OBFS=$(rand_hex 16)
TUIC_PASS=$(rand_hex 16)
if command -v openssl >/dev/null 2>&1; then
  SS_PASS=$(openssl rand -base64 16 2>/dev/null | tr -d '\n')
else
  # 直接对 16 个随机字节做 base64。以前经 awk printf "%c" 转一道，
  # gawk 在 UTF-8 环境会把 >127 的字节写成两个字节，密钥长度不对，Xray 校验失败。
  SS_PASS=$(head -c 16 /dev/urandom 2>/dev/null | base64 | tr -d '\n')
fi
WS_PATH="/$(rand_hex 4)"
info "账号密码已随机生成（装完会显示，平时输入 jiedian 也能看）"

# ---------- 8. 下载内核 ----------
# 1-4 用 Xray，5 和 7 用 sing-box，6 用官方 hysteria。已经有能用的就不重复下载。
if [ "$CORE" = "xray" ]; then
  dl_xray
elif [ "$CORE" = "hysteria" ]; then
  dl_hysteria
else
  dl_singbox
fi

# ---------- 9. REALITY 密钥对 ----------
# REALITY 用一对密钥：私钥只留在服务器上，公钥（pbk）写进分享链接给客户端。shortId（sid）是额外的随机短编号。
if [ "$NEED_REALITY" -eq 1 ]; then
  step "[密钥] 生成 REALITY 密钥…"
  if [ "$CORE" = "xray" ]; then
    _out=$("$XRAY_BIN" x25519 2>/dev/null)
    REALITY_PRIV=$(printf "%s" "$_out" | grep -i "private" | head -1 | awk '{print $NF}' | tr -d '\r\n')
    # 公钥行：老版叫 "Public key"，v26.3.27 起叫 "Password (PublicKey)"——两个关键字都认
    REALITY_PUB=$(printf "%s" "$_out" | grep -iE "public|password" | head -1 | awk '{print $NF}' | tr -d '\r\n')
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

# ---------- 9c. REALITY 伪装域名可用性检查 ----------
# 伪装站合不合适，取决于从这台 VPS 连过去的 TLS 握手情况，和在哪看视频没关系。
# 装机时直接测一次：xray 内核就用 xray tls ping，sing-box 内核用 openssl 兜底。
# 握手不顺就自动换社区验证最多的 www.apple.com 再试；实在不行也只警告、不拦安装。
if [ "$NEED_REALITY" -eq 1 ]; then
  step "[检查] 验证伪装域名从这台 VPS 是否可用…"
  _rp_ok=0
  _rp_try=0
  while [ "$_rp_try" -lt 2 ]; do
    _rp_try=$((_rp_try + 1))
    _rp_out=""
    if [ "$CORE" = "xray" ] && [ -x "$XRAY_BIN" ]; then
      _rp_out=$(_timeout_cmd 25 "$XRAY_BIN" tls ping "$REALITY_DOMAIN" 2>&1)
      if printf "%s" "$_rp_out" | grep -q "Handshake succeeded" \
        && printf "%s" "$_rp_out" | grep -q "TLS 1.3"; then
        _rp_ok=1
      fi
    elif command -v openssl >/dev/null 2>&1; then
      _rp_out=$(_timeout_cmd 20 openssl s_client -connect "${REALITY_DOMAIN}:443" \
        -servername "$REALITY_DOMAIN" -tls1_3 </dev/null 2>&1)
      if printf "%s" "$_rp_out" | grep -q "Protocol *: *TLSv1.3" \
        && printf "%s" "$_rp_out" | grep -q "Verify return code: 0"; then
        _rp_ok=1
      fi
    else
      info "没有可用的检测工具，跳过验证"
      _rp_ok=1
    fi
    if [ "$_rp_ok" -eq 1 ]; then break; fi
    if [ "$_rp_try" -eq 1 ] && [ "$REALITY_DOMAIN" != "www.apple.com" ]; then
      warn "你选的 $REALITY_DOMAIN 从这台 VPS 握手不太顺，伪装效果可能打折。"
      _rp_swap=1
      if [ -t 0 ]; then
        _rp_ans=""
        printf "是否自动换成社区验证最多的 www.apple.com 再试一次？[默认 Y]: "
        read -r _rp_ans
        case "$_rp_ans" in n|N|no|NO) _rp_swap=0 ;; esac
      else
        info "无交互环境，自动换成 www.apple.com 重试"
      fi
      if [ "$_rp_swap" -eq 1 ]; then
        REALITY_DOMAIN="www.apple.com"
        info "已换成 www.apple.com，重新验证…"
        continue
      fi
    fi
    break
  done
  if [ "$_rp_ok" -eq 1 ]; then
    info "伪装域名验证通过：${REALITY_DOMAIN}（TLS 1.3 握手正常）"
  else
    warn "伪装域名 $REALITY_DOMAIN 验证没通过，继续安装（节点照常用，伪装效果可能打折）。"
  fi
fi

# 前面的输入和下载都成功后才创建新节点目录。
# node.txt 写成功后才算装完。中途失败要停掉刚拉起的服务并删掉这个目录，
# 否则重启循环占着端口，而且管理命令看不到它。
trap _abort_partial_node EXIT
# 按 Ctrl+C 或连接断开时，也要走上面的清理（不然装了一半的服务和放行的端口会留下）
trap 'exit 130' INT TERM HUP
mkdir -p "$NODE_DIR" || die "无法创建节点目录 $NODE_DIR"

# ---------- 9b. 自签证书（Hysteria2 / TUIC 需要） ----------
# Hysteria2 和 TUIC 基于 QUIC（UDP 上的加密连接），必须有 TLS 证书。没有域名就自己签一张，客户端靠证书指纹或“跳过验证”来连接。
if [ "$PROTO" = "hy2" ]; then
  step "[证书] 生成自签证书…"
  umask 077
  drop_page_cache
  # 官方 hysteria 自己会写证书和私钥，不用再拆 PEM，也不用装 openssl
  _hy_cert_err=$("$HY_BIN" cert --host www.samsung.com \
    --cert "$NODE_DIR/cert.pem" --key "$NODE_DIR/key.pem" \
    --valid-for 87600h --overwrite 2>&1)
  if [ $? -ne 0 ] || [ ! -s "$NODE_DIR/cert.pem" ] || [ ! -s "$NODE_DIR/key.pem" ]; then
    die "自签证书生成失败。$(printf '%s' "$_hy_cert_err" | tr '\n' ' ' | cut -c1-300)"
  fi
  chmod 600 "$NODE_DIR/key.pem" "$NODE_DIR/cert.pem" 2>/dev/null
  # 新版 Xray 已经取消“跳过证书验证”，客户端必须带这张证书的指纹才能连。
  HY2_PIN=$(printf '%s\n' "$_hy_cert_err" | sed -n 's/.*pinSHA256:[[:space:]]*//p' | head -1 | tr -d ' \r\n' | tr 'a-f' 'A-F')
  case "$HY2_PIN" in
    *[!0-9A-F]*|"") HY2_PIN="" ;;
  esac
  if [ -z "$HY2_PIN" ] && command -v openssl >/dev/null 2>&1; then
    if command -v sha256sum >/dev/null 2>&1; then
      HY2_PIN=$(openssl x509 -in "$NODE_DIR/cert.pem" -outform der 2>/dev/null | sha256sum 2>/dev/null | awk '{print toupper($1)}')
    elif command -v shasum >/dev/null 2>&1; then
      HY2_PIN=$(openssl x509 -in "$NODE_DIR/cert.pem" -outform der 2>/dev/null | shasum -a 256 2>/dev/null | awk '{print toupper($1)}')
    fi
  fi
  case "$HY2_PIN" in
    *[!0-9A-F]*|"") HY2_PIN="" ;;
  esac
  [ "${#HY2_PIN}" -eq 64 ] || HY2_PIN=""
  [ -n "$HY2_PIN" ] || die "自签证书做好了，但没有算出证书指纹。没有指纹的话，新版客户端会拒绝连接。"
  info "自签证书已生成"
elif [ "$PROTO" = "tuic" ]; then
  step "[证书] 生成自签证书…"
  umask 077
  # sing-box 自带 tls-keypair 生成自签证书，不需要 openssl；有效期 120 个月
  # 私钥可能是 "PRIVATE KEY" 或 "EC PRIVATE KEY"，两种都要认
  "$SB_BIN" generate tls-keypair www.samsung.com --months 120 > "$NODE_DIR/tls.pem" 2>/dev/null \
    || die "自签证书生成失败"
  awk '/-----BEGIN / && /PRIVATE KEY-----/{p=1} p{print} /-----END / && /PRIVATE KEY-----/{p=0}' "$NODE_DIR/tls.pem" > "$NODE_DIR/key.pem"
  awk '/BEGIN CERTIFICATE/{p=1} p{print} /END CERTIFICATE/{p=0}' "$NODE_DIR/tls.pem" > "$NODE_DIR/cert.pem"
  rm -f "$NODE_DIR/tls.pem"
  [ -s "$NODE_DIR/key.pem" ] && [ -s "$NODE_DIR/cert.pem" ] \
    || die "自签证书生成失败"
  info "自签证书已生成"
fi

# ---------- 10. 写配置文件 ----------
# 把上面问到和生成的东西（端口、钥匙、伪装域名）写进内核的配置文件，再让内核自己检查一遍格式对不对。
step "[配置] 写入配置…"
mkdir -p /etc/xray-node

if [ "$CORE" = "xray" ]; then
# 与 Hysteria2 / sing-box 一致：纯 IPv6 机器必须听 [::]，默认 0.0.0.0 只收 IPv4，
# 选了 IPv6 却听不到时会出现“安装成功但客户端连不上”。
if [ "$IPVER" = "6" ]; then XRAY_LISTEN="::"; else XRAY_LISTEN="0.0.0.0"; fi
case "$PROTO" in
  vless)
    cat > "$NODE_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "$XRAY_LISTEN",
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
    cat > "$NODE_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "$XRAY_LISTEN",
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
    cat > "$NODE_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "$XRAY_LISTEN",
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
    cat > "$NODE_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "$XRAY_LISTEN",
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
_xray_test=$("$XRAY_BIN" -test -config "$NODE_DIR/config.json" 2>&1) \
  || die "配置文件校验没通过。$(printf '%s' "$_xray_test" | tr '\n' ' ' | cut -c1-300)"
info "配置文件校验通过"

elif [ "$CORE" = "hysteria" ]; then
# ---------- 官方 Hysteria2 配置 ----------
# 混淆用 salamander（可以在提问时关掉）。gecko 混淆更花，但 Loon 和不少旧客户端还不认，所以不用。
# 开了混淆时伪装页用一段普通网页；没开混淆时反向代理一个真实网站，探测的人看到的是真网页。
# 跳跃端口不写进 listen：Hysteria2 会把 listen 里的端口从小到大排，拿最小的当主端口，
# 和我们的主端口对不上。跳跃端口由 xray-node-hop 写转发规则，转到主端口。
HY_CONF="$NODE_DIR/config.yaml"
HY_EXTRA_IP=""
_hy_v6=$(_hy_local_ipv6) || _hy_v6=""
_hy_v4=$(_hy_local_ipv4) || _hy_v4=""
if [ -n "$_hy_v6" ] && [ -n "$_hy_v4" ]; then
  _hy_both=1
else
  _hy_both=""
fi
HY_LISTEN=$(_hy_listen_for "$PORT" "$IPVER" "$_hy_both")
case "$HY2_PASS" in
  *[!0-9a-f]*|"") die "随机密码生成失败，没有装上节点" ;;
esac
case "$HY2_OBFS" in
  *[!0-9a-f]*|"") die "随机密码生成失败，没有装上节点" ;;
esac
[ "${#HY2_PASS}" -eq 32 ] && [ "${#HY2_OBFS}" -eq 32 ] || die "随机密码生成失败，没有装上节点"
if [ -n "$_hy_both" ]; then
  if [ "$IPVER" = "6" ]; then
    HY_EXTRA_IP=$(get_ip 4) || HY_EXTRA_IP=""
  else
    HY_EXTRA_IP="$_hy_v6"
  fi
  case "$HY_EXTRA_IP" in
    \[*\]) HY_EXTRA_IP=${HY_EXTRA_IP#\[}; HY_EXTRA_IP=${HY_EXTRA_IP%\]} ;;
  esac
  [ "$HY_EXTRA_IP" = "$SERVER_IP" ] && HY_EXTRA_IP=""
  info "这台机器同时有 IPv4 和 IPv6，Hysteria2 两个都听"
fi
_hy_quic=""
if [ "$LOW_MEM" = "1" ]; then
  # 官方默认接收窗口是 8MB/20MB，64MB 机器上容易把进程打爆。内存小就收紧。
  if [ "$SWAP_OK" = "1" ]; then
    _hy_qs=2097152; _hy_qc=4194304
  else
    _hy_qs=1048576; _hy_qc=2097152
  fi
  _hy_quic="
quic:
  initStreamReceiveWindow: $_hy_qs
  maxStreamReceiveWindow: $_hy_qs
  initConnReceiveWindow: $_hy_qc
  maxConnReceiveWindow: $_hy_qc
  maxIncomingStreams: 16"
fi
HY_TCP_MASQ=0
if [ -n "$HY2_DOMAIN" ] && [ "$HY2_USE_OBFS" != "1" ] && ! port_in_use "$PORT" tcp; then
  HY_TCP_MASQ=1
fi
_hy_write_config
# 端口跳跃的设置交给 xray-node-hop：服务启动前打开转发，停掉后拆掉。
rm -f "$NODE_DIR/hop"
if [ -n "$HY_HOP_PORTS" ]; then
  if [ -n "$_hy_both" ]; then HY_HOP_FAMILY=46; else HY_HOP_FAMILY="$IPVER"; fi
  printf 'main=%s\nports=%s\nfamily=%s\n' "$PORT" "$HY_HOP_PORTS" "$HY_HOP_FAMILY" > "$NODE_DIR/hop"
  chmod 600 "$NODE_DIR/hop" 2>/dev/null
  info "端口跳跃会把这些 UDP 端口转到主端口 ${PORT}：$(printf '%s' "$HY_HOP_PORTS" | sed 's/,/、/g')"
fi
info "配置文件已写入"

else
# ---------- sing-box 配置（AnyTLS / TUIC） ----------
SB_CONF="$NODE_DIR/config.json"
if [ "$IPVER" = "6" ]; then SB_LISTEN="::"; else SB_LISTEN="0.0.0.0"; fi
case "$PROTO" in
  anytls)
    cat > "$SB_CONF" <<EOF
{
  "log": { "level": "warning" },
  "inbounds": [
    {
      "type": "anytls",
      "listen": "$SB_LISTEN",
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
  tuic)
    cat > "$SB_CONF" <<EOF
{
  "log": { "level": "warning" },
  "inbounds": [
    {
      "type": "tuic",
      "listen": "$SB_LISTEN",
      "listen_port": $PORT,
      "users": [ { "name": "xray-node", "uuid": "$UUID", "password": "$TUIC_PASS" } ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "server_name": "www.samsung.com",
        "alpn": [ "h3" ],
        "certificate_path": "$NODE_DIR/cert.pem",
        "key_path": "$NODE_DIR/key.pem"
      }
    }
  ],
  "outbounds": [ { "type": "direct" } ]
}
EOF
    ;;
esac
_sb_test=$("$SB_BIN" check -c "$SB_CONF" 2>&1) \
  || die "配置文件校验没通过。$(printf '%s' "$_sb_test" | tr '\n' ' ' | cut -c1-300)"
info "配置文件校验通过"
fi

# ---------- 11. 开机自启（每个节点独立服务，互不干扰） ----------
# 注册成系统服务并立刻启动，以后服务器重启也会自动启动。
# 先记下这个节点用的内核，_svc_install 要读它
echo "$CORE" > "$NODE_DIR/core" 2>/dev/null
# 公网映射端口也记一下（NAT 小鸡上和本机端口不同）。wg-luodi 靠它认出“你说的端口”是哪个节点。
echo "$LINK_PORT" > "$NODE_DIR/link_port" 2>/dev/null
step "[服务] 设置开机自启…"
# 申请证书时 Let's Encrypt 要从外面连 TCP 80（或 443），所以启动前先放行。
# 放行了哪些记在节点目录的 fw_acme 里：装到一半失败时撤销；申请成功后先关上，
# 快到期要续期时，巡检程序 xray-node-watch 会自动再打开，续好了再关上。
# 端口本来就是开着的（你自己放行过），就什么都不记，也不去关它。
if [ "$PROTO" = "hy2" ] && [ -n "$HY2_DOMAIN" ]; then
  if [ "$HY2_ACME_TYPE" = "tls" ]; then _acme_port=443; else _acme_port=80; fi
  install_watch_bin || true
  # 看证书哪天到期要用 openssl，没有就装上（很小）。装不上的话证书端口只好一直开着。
  command -v openssl >/dev/null 2>&1 || _pkg_add "正在安装 openssl（用来看证书什么时候到期）" openssl
  : > "$NODE_DIR/fw_acme"
  chmod 600 "$NODE_DIR/fw_acme" 2>/dev/null
  if [ -n "$_hy_both" ]; then _acme_fams="4 6"; else _acme_fams="$IPVER"; fi
  _acme_front=1
  for _acme_fam in $_acme_fams; do
    _fw_allow "$_acme_port" tcp "$_acme_fam" "$NODE_DIR/fw_acme" "$_acme_front"
    [ "$_IPT_ADDED" = "1" ] && _save_fw "$_acme_fam"
    _acme_front=0
  done
  if awk '$3 == 1 || $4 == 1 || $5 == 1 { found = 1 } END { exit !found }' "$NODE_DIR/fw_acme"; then
    echo open > "$NODE_DIR/fw_acme.state"
  else
    rm -f "$NODE_DIR/fw_acme"
  fi
fi
_svc_install "$NODE_ID"

# ---------- 11b. 硬检查：端口必须真的在监听 ----------
# 服务显示"已启动"不代表真在工作，端口没监听节点就是坏的，直接报错不忽悠
_SVC_PROTOS="tcp"
case "$PROTO" in
  hy2|tuic) _SVC_PROTOS="udp" ;;
  ss)       _SVC_PROTOS="tcp udp" ;;  # ss 配了 tcp,udp：只查 TCP 的话，UDP 没起来也发现不了
esac
_svc_listen_ok=1
for _sp in $_SVC_PROTOS; do
  if ! wait_for_port "$PORT" "$_sp" 15; then
    warn "端口 $PORT/$_sp 没在监听"
    _svc_listen_ok=0
  fi
done
# 端口在听不等于是我们的服务：极简机上 port_in_use 曾查不到占用时，
# 别人占用的端口会让 wait_for_port 误报成功。再确认本节点服务/进程还在。
if [ "$_svc_listen_ok" = "1" ]; then
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] && [ -n "$SVC_UNIT" ]; then
    systemctl is-active --quiet "$SVC_UNIT" || _svc_listen_ok=0
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "xray-node-${NODE_ID}" status >/dev/null 2>&1 || _svc_listen_ok=0
  else
    if [ "$CORE" = "hysteria" ]; then
      _svc_cfg_pat="/etc/xray-node/nodes/${NODE_ID}/config.yaml"
    else
      _svc_cfg_pat="/etc/xray-node/nodes/${NODE_ID}/config.json"
    fi
    if command -v pgrep >/dev/null 2>&1; then
      pgrep -f "$_svc_cfg_pat" >/dev/null 2>&1 || _svc_listen_ok=0
    fi
  fi
fi
# 端口在听，并且这个节点自己的服务还在，才算起来了。
_svc_recheck() { # _svc_recheck [等几秒]
  _svc_listen_ok=1
  if ! wait_for_port "$PORT" udp "${1:-15}"; then
    _svc_listen_ok=0
    return
  fi
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] && [ -n "$SVC_UNIT" ]; then
    systemctl is-active --quiet "$SVC_UNIT" || _svc_listen_ok=0
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "xray-node-${NODE_ID}" status >/dev/null 2>&1 || _svc_listen_ok=0
  elif command -v pgrep >/dev/null 2>&1; then
    pgrep -f "/etc/xray-node/nodes/${NODE_ID}/config.yaml" >/dev/null 2>&1 || _svc_listen_ok=0
  fi
}
# 申请正规证书要先连上 Let's Encrypt，最多多等一会儿；申请不下来就改回自签证书。
if [ "$_svc_listen_ok" != "1" ] && [ "$PROTO" = "hy2" ] && [ -n "$HY2_DOMAIN" ]; then
  info "正在给 ${HY2_DOMAIN} 申请证书，最多再等 60 秒…"
  _svc_recheck 60
  if [ "$_svc_listen_ok" != "1" ]; then
    warn "证书没申请下来（常见原因：域名没解析到这台机器、80/443 端口被云安全组挡住）。改用自签证书，节点照样能用。"
    HY2_DOMAIN=""
    HY_TCP_MASQ=0
    _hy_write_config
    _svc_restart "$NODE_ID"
    _svc_recheck
  fi
fi
# 证书端口：申请成功了就先关上（快到期时巡检程序会自动再打开）；改用自签证书了就整个撤掉。
_hy_acme_ports_done() {
  [ "$PROTO" = "hy2" ] && [ -f "$NODE_DIR/fw_acme" ] || return 0
  _hap_watch="${XRAY_BIN_DIR:-/usr/local/bin}/xray-node-watch"
  [ -x "$_hap_watch" ] || return 0
  if [ -z "$HY2_DOMAIN" ]; then
    "$_hap_watch" acme-drop "$NODE_ID"
    info "已撤销为申请证书临时放行的 TCP ${_acme_port}"
    return 0
  fi
  [ "$_svc_listen_ok" = "1" ] || return 0
  [ -n "$(find "$NODE_DIR/acme" -type f -name '*.crt' 2>/dev/null | head -1)" ] || return 0
  if command -v openssl >/dev/null 2>&1; then
    "$_hap_watch" acme-close "$NODE_ID"
    info "证书已申请好。为申请证书临时放行的 TCP ${_acme_port} 已关上；快到期时会自动打开续期，续好再关。"
  else
    warn "没有 openssl，看不了证书哪天到期，TCP ${_acme_port} 只好一直开着，保证能续期。"
  fi
}
# 以非 root 身份跑不起来时（个别精简系统、老内核），改回 root 再试一次。
if [ "$_svc_listen_ok" != "1" ] && [ "$PROTO" = "hy2" ] && [ ! -f /etc/xray-node/hy_root ] \
  && grep -q '^User=xray-node' /etc/systemd/system/hysteria-node@.service 2>/dev/null; then
  warn "用普通用户身份跑不起来，改用 root 再试一次"
  : > /etc/xray-node/hy_root
  _svc_restart "$NODE_ID"
  _svc_recheck
fi
if [ "$_svc_listen_ok" != "1" ] && [ "$PROTO" = "hy2" ] && [ "$HY_LISTEN" = ":$PORT" ]; then
  warn "同时听 IPv4 和 IPv6 没成功，改回只听你刚才选的那一种"
  if [ "$IPVER" = "6" ]; then HY_LISTEN="[::]:$PORT"; else HY_LISTEN="0.0.0.0:$PORT"; fi
  HY_EXTRA_IP=""
  if _hy_set_listen "$NODE_DIR/config.yaml" "$HY_LISTEN"; then
    [ -f "$NODE_DIR/hop" ] && sed -i "s/^family=.*/family=${IPVER}/" "$NODE_DIR/hop" 2>/dev/null
    _svc_restart "$NODE_ID"
    _svc_recheck
  fi
fi
_hy_acme_ports_done
# 端口跳跃：不靠“从本机连跳跃端口”来验（本机发给自己的包根本不经过 PREROUTING，永远测不通），
# 而是看转发规则是不是真的写进了系统。服务启动时已经自动打开过一次。
HY_HOP_V4=1
HY_HOP_V6=1
if [ "$_svc_listen_ok" = "1" ] && [ "$PROTO" = "hy2" ] && [ -n "$HY_HOP_PORTS" ]; then
  _hop_state=$(/usr/local/bin/xray-node-hop check "$NODE_ID" 2>/dev/null)
  if [ $? -ne 0 ]; then
    _hop_err=$(/usr/local/bin/xray-node-hop up "$NODE_ID" 2>&1)
    _hop_state=$(/usr/local/bin/xray-node-hop check "$NODE_ID" 2>/dev/null) || _hop_state=""
  fi
  if [ -z "$_hop_state" ]; then
    warn "端口跳跃没能打开，节点改为只用主端口 ${PORT}（节点照样能用）。原因："
    _hop_explain "$_hop_err"
    /usr/local/bin/xray-node-hop down "$NODE_ID" >/dev/null 2>&1
    rm -f "$NODE_DIR/hop"
    HY_HOP_PORTS=""
  else
    _hop_fam=${_hop_state##* }
    _hop_want=$(sed -n 's/^family=//p' "$NODE_DIR/hop" 2>/dev/null)
    case "$_hop_fam" in
      4|6|46) ;;
      *) _hop_fam="$_hop_want" ;;
    esac
    if [ "$_hop_want" = "46" ] && [ "$_hop_fam" = "4" ]; then
      HY_HOP_V6=0
      warn "IPv6 上做不了端口转发，端口跳跃只在 IPv4 上生效（IPv6 那行链接只用主端口）"
    elif [ "$_hop_want" = "46" ] && [ "$_hop_fam" = "6" ]; then
      HY_HOP_V4=0
      warn "IPv4 上做不了端口转发，端口跳跃只在 IPv6 上生效（IPv4 那行链接只用主端口）"
    fi
    [ "$_hop_fam" != "$_hop_want" ] && sed -i "s/^family=.*/family=${_hop_fam}/" "$NODE_DIR/hop" 2>/dev/null
    info "端口跳跃已打开（${_hop_state}）。服务每次启动都会自动打开，停掉时自动拆掉，重启服务器后也在。"
  fi
fi
if [ "$_svc_listen_ok" = "1" ]; then
  info "端口 $PORT 已在监听，服务真正跑起来了"
else
  echo "-------- 服务最后的日志 --------"
  if [ -n "$SVC_UNIT" ] && command -v journalctl >/dev/null 2>&1; then
    journalctl -u "$SVC_UNIT" -n 20 --no-pager 2>/dev/null
  fi
  if [ -f "/var/log/xray-node-${NODE_ID}.log" ]; then
    tail -n 20 "/var/log/xray-node-${NODE_ID}.log" 2>/dev/null
  fi
  die "服务没能监听端口 ${PORT}：节点装坏了。请把上面的日志截图发我。也可以运行 systemctl status '${SVC_UNIT:-xray-node@${NODE_ID}}'（或 rc-service 'xray-node-${NODE_ID}' status）看原因，修好再重跑脚本"
fi

# ---------- 12. 放行端口 ----------
# 在这台服务器的防火墙上放行节点端口；云服务器的“安全组”要你自己在控制台放行。
step "[网络] 放行端口…"
# 各协议要放行的端口类型：ss 的 network 配的是 tcp,udp，两个都得放；
# hy2/tuic 走 UDP；其余走 TCP
_FW_PROTOS="tcp"
case "$PROTO" in
  hy2|tuic) _FW_PROTOS="udp" ;;
  ss) _FW_PROTOS="tcp udp" ;;
esac
# 逐个协议放行，并记到该节点的 fw_info 里给 shanjiedian 用：
# 只删我们亲手加的规则，用户机器上本来就有的不碰。
# 新节点编号不会重用，不可能有旧规则残留，无需清理。
: > "$NODE_DIR/fw_info"
# Hysteria2 两种地址都听时，IPv4 和 IPv6 的防火墙要分别放行。
# 端口跳跃的跳跃端口不用在本机防火墙放行：nat 转发发生在防火墙检查之前，
# 防火墙看到的已经是主端口。云服务器的安全组在机器外面，那里还是要放行跳跃端口。
_FW_FAMILIES="$IPVER"
if [ "$PROTO" = "hy2" ]; then
  case "$HY_LISTEN" in
    ":$PORT"|":$PORT,$HY_HOP_PORTS")
      if [ "$IPVER" = "6" ]; then _FW_FAMILIES="6 4"; else _FW_FAMILIES="4 6"; fi
      ;;
  esac
fi
_FW_PORT_LIST=$PORT
_FW_SAVE4=0
_FW_SAVE6=0
_fw_front=1
for _fw_family in $_FW_FAMILIES; do
  for _fw_port in $_FW_PORT_LIST; do
    for _np in $_FW_PROTOS; do
      _fw_allow "$_fw_port" "$_np" "$_fw_family" "$NODE_DIR/fw_info" "$_fw_front"
      if [ "$_IPT_ADDED" = "1" ]; then
        if [ "$_fw_family" = "6" ]; then _FW_SAVE6=1; else _FW_SAVE4=1; fi
      fi
    done
  done
  _fw_front=0
done
# 纯 iptables 的规则默认重启就丢：刚才亲手加了规则就存盘，
# 否则机器一重启端口又被墙、节点连不上（ufw/firewalld 自己会持久化，不用管）
# Hysteria2 有正规证书时：同端口的 TCP 伪装网站、申请证书用的 80/443 也要放行。
if [ "$PROTO" = "hy2" ]; then
  _hy_tcp_ports=""
  [ "$HY_TCP_MASQ" = "1" ] && _hy_tcp_ports="$PORT"
  # 申请证书用的端口单独记在 fw_acme，由巡检程序按需开关，这里不管。
  _fw_front=1
  for _fw_family in $_FW_FAMILIES; do
    for _fw_port in $_hy_tcp_ports; do
      _fw_allow "$_fw_port" tcp "$_fw_family" "$NODE_DIR/fw_info" "$_fw_front"
      if [ "$_IPT_ADDED" = "1" ]; then
        if [ "$_fw_family" = "6" ]; then _FW_SAVE6=1; else _FW_SAVE4=1; fi
      fi
    done
    _fw_front=0
  done
fi
[ "$_FW_SAVE4" = "1" ] && _save_fw 4
[ "$_FW_SAVE6" = "1" ] && _save_fw 6
# 自己写的 nftables 防火墙不自动改（改了还要动 /etc/nftables.conf），只告诉你怎么放行。
_nft_chains=$(_nft_drop_chains)
if [ -n "$_nft_chains" ]; then
  warn "这台机器有 nftables 防火墙默认拦截外来连接，脚本没有改它。不放行的话节点连不上。请运行下面的命令放行，并把同样的规则写进 /etc/nftables.conf（重启后才还在）："
  printf '%s\n' "$_nft_chains" | while read -r _nf_fam _nf_tbl _nf_ch; do
    for _fw_port in $_FW_PORT_LIST; do
      for _np in $_FW_PROTOS; do
        printf '  nft insert rule %s %s %s %s dport %s accept\n' "$_nf_fam" "$_nf_tbl" "$_nf_ch" "$_np" "$_fw_port"
      done
    done
  done
fi
if [ "$PROTO" = "hy2" ]; then
  _hy_cloud="UDP ${LINK_PORT}"
  if [ -n "$HY_HOP_PORTS" ]; then
    _hh_show=$(printf '%s' "$HY_HOP_PORTS" | sed 's/,/、/g')
    _hy_cloud="${_hy_cloud}，以及端口跳跃 ${_hh_show}"
  fi
  case "$HY_LISTEN" in
    ":$PORT"|":$PORT,$HY_HOP_PORTS") _hy_cloud="${_hy_cloud}。IPv4 和 IPv6 都要放" ;;
  esac
  [ -n "$_hy_tcp_ports" ] && _hy_cloud="${_hy_cloud}；还有 TCP $(printf '%s' "$_hy_tcp_ports" | sed 's/^ *//; s/ /、/g')"
  [ -n "$HY2_DOMAIN" ] && _hy_cloud="${_hy_cloud}；申请证书用的 TCP ${_acme_port} 也要放（续期还要用。本机防火墙平时关着它，快到期时脚本自动打开）"
  if [ -n "$HY_HOP_PORTS" ] && [ "$LINK_PORT" != "$PORT" ]; then
    _hy_cloud="${_hy_cloud}。NAT 小鸡要把跳跃端口按相同号码映射进来"
  fi
  warn "如果是云服务器（阿里云/腾讯云/AWS 等），还去控制台安全组放行 ${_hy_cloud}"
else
  warn "如果是云服务器（阿里云/腾讯云/AWS 等），还去控制台安全组放行 $PORT 端口"
fi

# ---------- 13. 生成节点链接 ----------
# 按各协议的通用格式拼出分享链接，客户端（v2rayN、Shadowrocket、NekoBox 等）都能直接导入。
step "[完成] 生成你的节点…"
LINK_EXTRA=""
LINK_HY_OFFICIAL=""
_hy_mport_x=""
case "$PROTO" in
  vless)  PROTO_NAME="VLESS + REALITY + Vision"; _nm_proto="Vless-Reality" ;;
  trojan) PROTO_NAME="Trojan + REALITY"; _nm_proto="Trojan-Reality" ;;
  vmess)  PROTO_NAME="VMess + WebSocket"; _nm_proto="Vmess" ;;
  ss)     PROTO_NAME="Shadowsocks"; _nm_proto="Shadowsocks" ;;
  anytls) PROTO_NAME="AnyTLS + REALITY"; _nm_proto="AnyTLS-Reality" ;;
  hy2)    PROTO_NAME="Hysteria2"; _nm_proto="Hysteria2" ;;
  tuic)   PROTO_NAME="TUIC"; _nm_proto="TUIC" ;;
esac
NODE_NAME=$(_node_name "$_nm_proto")
printf '%s\n' "$NODE_NAME" > "$NODE_DIR/name"
NAME_ENC=$(_urlenc "$NODE_NAME")
[ -n "$NAME_ENC" ] || NAME_ENC="xray-node"
case "$PROTO" in
  vless)
    LINK="vless://${UUID}@${LINK_IP}:${LINK_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SID}&type=tcp#${NAME_ENC}"
    ;;
  trojan)
    LINK="trojan://${TROJAN_PASS}@${LINK_IP}:${LINK_PORT}?security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SID}&type=tcp#${NAME_ENC}"
    ;;
  vmess)
    _json="{\"v\":\"2\",\"ps\":\"${NODE_NAME}\",\"add\":\"${SERVER_IP}\",\"port\":\"${LINK_PORT}\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"${WS_PATH}\",\"tls\":\"\"}"
    LINK="vmess://$(printf "%s" "$_json" | b64url)"
    ;;
  ss)
    LINK="ss://$(printf "%s" "2022-blake3-aes-128-gcm:${SS_PASS}" | b64url)@${LINK_IP}:${LINK_PORT}#${NAME_ENC}"
    ;;
  anytls)
    LINK="anytls://${ANYTLS_PASS}@${LINK_IP}:${LINK_PORT}?security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SID}&type=tcp#${NAME_ENC}"
    ;;
  hy2)
    # 证书：有正规证书时只写 sni；自签证书时写 insecure=1 + pinSHA256（官方客户端要两个一起写，
    #   指纹仍然会校验，别人冒充不了）。pcs 给认 Xray 分享字段的客户端用，意思一样。
    # 端口跳跃：主端口留在地址里，跳跃端口放 mport（v2rayN、Clash Verge 等认这个）。
    #   官方客户端认“地址:主端口,跳跃端口”这种写法，下面单独给一行。
    HY2_SNI=${HY2_DOMAIN:-www.samsung.com}
    if [ -n "$HY2_DOMAIN" ]; then
      _hy_q="sni=${HY2_SNI}&alpn=h3"
    else
      _hy_q="insecure=1&sni=${HY2_SNI}&peer=${HY2_SNI}&alpn=h3&pinSHA256=${HY2_PIN}&pcs=${HY2_PIN}"
    fi
    if [ "$HY2_USE_OBFS" = "1" ]; then
      _hy_q="${_hy_q}&obfs=salamander&obfs-password=${HY2_OBFS}"
    fi
    if [ "$IPVER" = "6" ]; then _hy_hop_main="$HY_HOP_V6"; _hy_hop_x="$HY_HOP_V4"; else _hy_hop_main="$HY_HOP_V4"; _hy_hop_x="$HY_HOP_V6"; fi
    HY_MPORT=""
    if [ -n "$HY_HOP_PORTS" ] && [ "$_hy_hop_main" = "1" ]; then
      HY_MPORT="${LINK_PORT},${HY_HOP_PORTS}"
    fi
    LINK="hysteria2://${HY2_PASS}@${LINK_IP}:${LINK_PORT}/?${_hy_q}${HY_MPORT:+&mport=${HY_MPORT}}#${NAME_ENC}"
    if [ -n "$HY_MPORT" ]; then
      LINK_HY_OFFICIAL="hysteria2://${HY2_PASS}@${LINK_IP}:${HY_MPORT}/?${_hy_q}#${NAME_ENC}"
    fi
    LINK_EXTRA=""
    if [ -n "$HY_EXTRA_IP" ]; then
      case "$HY_EXTRA_IP" in
        *:*) _hy_xip="[$HY_EXTRA_IP]" ;;
        *)   _hy_xip="$HY_EXTRA_IP" ;;
      esac
      # IPv6 没有 IPv4 那种公网端口映射，客户端直接连本机监听端口。
      if [ "$IPVER" = "6" ]; then _hy_xport="$LINK_PORT"; else _hy_xport="$PORT"; fi
      _hy_mport_x=""
      if [ -n "$HY_HOP_PORTS" ] && [ "$_hy_hop_x" = "1" ]; then
        _hy_mport_x="${_hy_xport},${HY_HOP_PORTS}"
      fi
      LINK_EXTRA="hysteria2://${HY2_PASS}@${_hy_xip}:${_hy_xport}/?${_hy_q}${_hy_mport_x:+&mport=${_hy_mport_x}}#${NAME_ENC}"
    fi
    ;;
  tuic)
    LINK="tuic://${UUID}:${TUIC_PASS}@${LINK_IP}:${LINK_PORT}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.samsung.com&allow_insecure=1#${NAME_ENC}"
    ;;
esac

# ---------- 14. 保存 + jiedian 命令 ----------
# 链接和参数保存到节点目录的 node.txt，以后输入 jiedian 就能再看到。
EXPIRE_AT=""
EXPIRE_SHOW=""
if [ "$NODE_KIND" = "timed" ]; then
  case "$EXPIRE_AFTER" in
    ''|*[!0-9]*|0) die "定时节点没有有效的失效时间，安装已停" ;;
  esac
  _exp_now=$(date +%s 2>/dev/null) || die "读不到服务器时间，定时节点没装上"
  case "$_exp_now" in ''|*[!0-9]*) die "读不到服务器时间，定时节点没装上" ;; esac
  EXPIRE_AT=$((_exp_now + EXPIRE_AFTER))
  EXPIRE_SHOW=$(date -d "@$EXPIRE_AT" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$EXPIRE_AT" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '%s' "$EXPIRE_AT")
  printf '%s\n' "$EXPIRE_AT" > "$NODE_DIR/expire" || die "写不了失效时间"
  chmod 600 "$NODE_DIR/expire" 2>/dev/null || true
fi
{
  printf "==============================================\n"
  if [ -n "$LINK_EXTRA" ]; then
    # 两行只差地址。你家网络没有 IPv6 时，IPv6 那行连不上，所以写清楚先用哪行。
    if [ "$IPVER" = "6" ]; then
      printf " 你的节点（两行是同一个节点，复制一行就行：第一行用 IPv6 地址，第二行用 IPv4 地址）\n"
    else
      printf " 你的节点（两行是同一个节点：第一行用 IPv4，第二行用 IPv6。不确定就复制第一行）\n"
    fi
  else
    printf " 你的节点（复制下面整行，粘贴到客户端导入）\n"
  fi
  printf "==============================================\n"
  printf "%s\n" "$LINK"
  if [ -n "$LINK_EXTRA" ]; then printf "%s\n" "$LINK_EXTRA"; fi
  printf -- "----------------------------------------------\n"
  printf "节点名: %s\n" "$NODE_NAME"
  printf "协议: %s\n" "$PROTO_NAME"
  printf "地址: %s\n" "$SERVER_IP"
  printf "端口: %s\n" "$LINK_PORT"
  if [ "$LINK_PORT" != "$PORT" ]; then printf "本机监听端口: %s\n" "$PORT"; fi
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
    hy2)
      printf "SNI: %s\n" "$HY2_SNI"
      if [ -n "$HY2_DOMAIN" ]; then
        printf "证书: 正规证书（Let's Encrypt，%s），客户端不要打开「跳过证书验证」。\n" "$HY2_DOMAIN"
      else
        printf "证书指纹: %s\n" "$HY2_PIN"
      fi
      if [ "$HY2_USE_OBFS" = "1" ]; then
        printf "混淆: 已开启（salamander）。别人不容易直接看出这是代理。\n"
        printf "混淆密码: %s\n" "$HY2_OBFS"
        printf "请用上面的整行链接导入。手填时，节点密码和混淆密码是两个，不要填反。\n"
      else
        printf "混淆: 没开。别人探测时看到的是一个普通网站。\n"
      fi
      if [ -n "$HY_HOP_PORTS" ]; then
        printf "端口跳跃: 主端口 %s，跳跃端口 %s\n" "$LINK_PORT" "$(printf '%s' "$HY_HOP_PORTS" | sed 's/,/、/g')"
        printf "v2rayN、Clash Verge、小火箭等导入上面那行（跳跃端口在 mport 里）。导入后没看到跳跃端口，就在节点设置的「端口跳跃/端口范围」里手填：%s\n" "$HY_HOP_PORTS"
        if [ -n "$LINK_HY_OFFICIAL" ]; then
          printf "官方 Hysteria2 客户端用这一行（端口直接写在地址后面）：\n%s\n" "$LINK_HY_OFFICIAL"
        fi
        printf "云服务器安全组要把主端口和这些跳跃端口的 UDP 都放行。\n"
      fi
      if [ -n "$HY_EXTRA_IP" ]; then
        if [ "$IPVER" = "6" ]; then
          printf "另一地址（IPv4）: %s\n" "$HY_EXTRA_IP"
        else
          printf "IPv6 地址: %s\n" "$HY_EXTRA_IP"
          if [ "$PORT" != "$LINK_PORT" ]; then
            printf "IPv6 端口: %s（IPv6 直接连这个端口，不走上面的 IPv4 映射端口）\n" "$PORT"
          fi
        fi
      fi
      if [ -z "$HY2_DOMAIN" ]; then
        printf "官方 Hysteria2 客户端：自签证书须同时启用 insecure 和证书指纹锁定；如果指纹为空，填入上面的值。\n"
      fi
      # 混淆密码是纯字母数字，不要加引号。Loon 导入时会把引号也收进混淆参数。
      _hy_loon_cert="skip-cert-verify=false,tls-cert-sha256=${HY2_PIN}"
      [ -n "$HY2_DOMAIN" ] && _hy_loon_cert="skip-cert-verify=false"
      _hy_loon_obfs=""
      [ "$HY2_USE_OBFS" = "1" ] && _hy_loon_obfs=",salamander-password=${HY2_OBFS}"
      _hy_loon_tail=""
      if [ -n "$HY_MPORT" ]; then
        _hy_loon_tail=",server-ports=\"${HY_MPORT}\",hop-interval=30"
      fi
      printf "Loon 可粘贴这一行（已写好 block-quic=true，导入后自动打开阻止 QUIC）:\n"
      printf "%s = Hysteria2,%s,%s,\"%s\",sni=%s,%s,alpn=\"h3\",udp=true,block-quic=true%s%s\n" \
        "$NODE_NAME" "$SERVER_IP" "$LINK_PORT" "$HY2_PASS" "$HY2_SNI" "$_hy_loon_cert" "$_hy_loon_obfs" "$_hy_loon_tail"
      if [ -n "$LINK_EXTRA" ]; then
        if [ "$IPVER" = "6" ]; then _loon_port="$LINK_PORT"; else _loon_port="$PORT"; fi
        _hy_loon_tail2=""
        if [ -n "$_hy_mport_x" ]; then
          _hy_loon_tail2=",server-ports=\"${_hy_mport_x}\",hop-interval=30"
        fi
        printf "%s = Hysteria2,%s,%s,\"%s\",sni=%s,%s,alpn=\"h3\",udp=true,block-quic=true%s%s\n" \
          "${NODE_NAME}-v6" "$HY_EXTRA_IP" "$_loon_port" "$HY2_PASS" "$HY2_SNI" "$_hy_loon_cert" "$_hy_loon_obfs" "$_hy_loon_tail2"
      fi
      # Surge：自签证书用证书指纹锁定（server-cert-fingerprint-sha256），跳跃端口用分号隔开。
      _hy_surge_cert="server-cert-fingerprint-sha256=${HY2_PIN}"
      [ -n "$HY2_DOMAIN" ] && _hy_surge_cert="skip-cert-verify=false"
      _hy_surge_obfs=""
      [ "$HY2_USE_OBFS" = "1" ] && _hy_surge_obfs=", salamander-password=${HY2_OBFS}"
      _hy_surge_hop=""
      if [ -n "$HY_MPORT" ]; then
        _hy_surge_hop=", port-hopping=\"$(printf '%s' "$HY_MPORT" | tr ',' ';')\", port-hopping-interval=30"
      fi
      printf "Surge 可粘贴这一行（已写好 block-quic=on）:\n"
      printf "%s = hysteria2, %s, %s, password=%s, sni=%s, %s%s%s, block-quic=on\n" \
        "$NODE_NAME" "$SERVER_IP" "$LINK_PORT" "$HY2_PASS" "$HY2_SNI" "$_hy_surge_cert" "$_hy_surge_obfs" "$_hy_surge_hop"
      # mihomo（Clash Meta、Clash Verge、FlClash 用的内核）原生支持端口跳跃：ports + hop-interval。
      printf "mihomo / Clash Meta 配置（贴到 proxies: 下面）:\n"
      printf "  - name: %s\n    type: hysteria2\n    server: %s\n    port: %s\n" "$NODE_NAME" "$SERVER_IP" "$LINK_PORT"
      if [ -n "$HY_MPORT" ]; then
        printf "    ports: %s\n    hop-interval: 30\n" "$HY_MPORT"
      fi
      printf "    password: %s\n    sni: %s\n    alpn: [h3]\n" "$HY2_PASS" "$HY2_SNI"
      if [ -z "$HY2_DOMAIN" ]; then
        printf "    fingerprint: %s\n" "$(printf '%s' "$HY2_PIN" | tr 'A-F' 'a-f')"
      fi
      if [ "$HY2_USE_OBFS" = "1" ]; then
        printf "    obfs: salamander\n    obfs-password: %s\n" "$HY2_OBFS"
      fi
      ;;
    tuic)        printf "SNI: www.samsung.com（自签证书，客户端已设跳过验证）\n" ;;
  esac
  # 拦截 QUIC 是客户端的开关：给 Loon / Surge 各拼一行已经打开它的节点配置，再说明别的 App 怎么开
  CQ_PROTO="$PROTO"; CQ_NAME="$NODE_NAME"; CQ_HOST="$SERVER_IP"; CQ_PORT="$LINK_PORT"
  CQ_UUID="${UUID:-}"; CQ_SNI="${REALITY_DOMAIN:-}"; CQ_PBK="${REALITY_PUB:-}"; CQ_SID="${REALITY_SID:-}"
  CQ_PATH="${WS_PATH:-}"; CQ_PASS=""
  case "$PROTO" in
    trojan) CQ_PASS="$TROJAN_PASS" ;;
    ss)     CQ_PASS="$SS_PASS" ;;
    anytls) CQ_PASS="$ANYTLS_PASS" ;;
    tuic)   CQ_PASS="$TUIC_PASS" ;;
  esac
  _cq_section
  printf -- "----------------------------------------------\n"
  if [ "$NODE_KIND" = "timed" ]; then
    printf "种类: 定时节点\n"
    printf "失效时间: %s（%s后，按这台服务器的时间）\n" "$EXPIRE_SHOW" "$EXPIRE_LABEL"
    printf "到点后大约一分钟内，这个节点会被彻底删除，链接不能再用。其它节点不受影响。\n"
  else
    printf "种类: 永久节点\n"
  fi
  printf "以后想看节点，直接输入: jiedian\n"
  printf "==============================================\n"
} > "$NODE_DIR/node.txt"
trap - EXIT

write_helper_cmds
info "已安装 jiedian 命令：以后输入 jiedian 就能看所有节点"
info "已安装 shanjiedian 命令：输入 shanjiedian 可管理节点（查看/删除）"

# ---------- 14a. UDP 节点的回程路由 ----------
# 服务启动时已经核对过一次；现在 node.txt 写好了（里面有写给客户端的地址），按它再核对一次。
if [ -x /usr/local/bin/xray-node-route ]; then
  /usr/local/bin/xray-node-route up "$NODE_ID" >/dev/null 2>&1
  _route_note "$NODE_ID" "$PORT"
fi

# ---------- 14b. BBR 加速：检测，没开就自动开 ----------
# BBR 是 Linux 内核自带的一种 TCP 加速算法，网络差时速度更稳，打开不影响别的程序。
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
      mkdir -p /etc/sysctl.d
      printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-xray-node-bbr.conf
      if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
        _BBR_ON=1
        info "BBR 已自动开启（立即生效，已写入开机配置）"
      fi
    fi
    [ "$_BBR_ON" = "0" ] && warn "BBR 开启失败（可能是容器内无权改内核参数），不影响节点使用"
  else
    warn "当前内核不支持 BBR，跳过加速；节点仍可正常使用"
  fi
fi

# ---------- 15. 显示结果 ----------
# 把节点信息打印出来，复制那一行链接到客户端就能用。
printf "\n节点 %s 安装完成！\n" "$NODE_ID"
cat "$NODE_DIR/node.txt"
printf "\n${GREEN}${BOLD}安装完成！${NC}把上面那行链接复制到客户端就能用了。\n"
if [ "$NODE_KIND" = "timed" ]; then
  printf "这是定时节点，%s（%s后）会彻底失效：服务停掉，链接作废，配置删掉。其它节点不受影响。\n" "$EXPIRE_SHOW" "$EXPIRE_LABEL"
  printf "到点后不用你操作。到期记录在 /var/log/xray-node-expire.log。\n"
fi
printf "以后看所有节点输入 jiedian，管理节点（查看/删除）输入 shanjiedian。\n"
