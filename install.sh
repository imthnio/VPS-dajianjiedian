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
# 装完之后，想看所有节点随时输入：  jiedian
# 输入 shanjiedian 进入节点管理：查看节点、删除单个节点，或全部卸载
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
  # 不能直接 eval "$_v=$_a"：输入里的 $(...) 或反引号会被执行。
  # 用单引号包裹并转义输入里的单引号，保证原样赋值、什么都不执行。
  _a_esc=$(printf "%s" "$_a" | sed "s/'/'\\\\''/g")
  eval "$_v='$_a_esc'"
}

rand_hex() { # rand_hex 字节数 -> 十六进制串
  od -An -tx1 -N"$1" /dev/urandom 2>/dev/null | tr -d ' \n'
}

rand_port() { # 随机一个空闲端口 20000-59999
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
    # 检测网站偶尔返回非 IP 的垃圾（比如限流提示页）：长得不像 IP 就换下一个
    if [ -n "$_ip" ] && _valid_ip "$_v" "$_ip"; then
      printf "%s" "$_ip"; return 0
    fi
  done
  return 1
}

_valid_ip() { # _valid_ip 4|6 <串>：长得像对应版本的 IP 才返回 0
  if [ "$1" = "6" ]; then
    case "$2" in *:*) return 0 ;; *) return 1 ;; esac
  else
    case "$2" in *:*|''|*[!0-9.]*|.*|*.) return 1 ;; esac
    [ "$(printf "%s" "$2" | tr -cd '.' | wc -c)" -eq 3 ]
  fi
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

write_helper_cmds() { # 写入/刷新 jiedian 和 shanjiedian 两个命令（安装和更新都会调）
cat > /usr/local/bin/jiedian <<'JDEOF'
#!/bin/sh
# 输入 jiedian，显示所有已安装节点的信息和链接
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
chmod +x /usr/local/bin/jiedian
cat > /usr/local/bin/shanjiedian <<'XZEOF'
#!/bin/sh
# 输入 shanjiedian，进入节点管理：查看节点、删除单个节点，或全部卸载
NODES_DIR=/etc/xray-node/nodes

# _node_info <节点id>：从 node.txt 里读出"协议，端口"
_node_info() {
  _ni_proto=$(grep -m1 '^协议: ' "$NODES_DIR/$1/node.txt" 2>/dev/null | sed 's/^协议: //')
  _ni_port=$(grep -m1 '^端口: ' "$NODES_DIR/$1/node.txt" 2>/dev/null | sed 's/^端口: //')
  printf "%s，端口 %s" "$_ni_proto" "$_ni_port"
}

# _del_fw_rules <fw_info路径>：撤销该节点我们亲手加的防火墙规则（用户手写的不碰）
_del_fw_rules() {
  [ -f "$1" ] || return 0
  while read -r _fport _fproto _fufw _ffwl _fipt; do
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
    if [ "$_fipt" = "1" ] && command -v iptables >/dev/null 2>&1; then
      if [ "$_oldfmt" = "1" ]; then
        while iptables -C INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1; do
          iptables -D INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1 || break
        done
      else
        # 新格式：这条规则是我们加的，只删一条；用户后来手加的相同规则不动
        iptables -D INPUT -p "$_fproto" --dport "$_fport" -j ACCEPT >/dev/null 2>&1
      fi
    fi
    echo "已撤销端口 $_fport/$_fproto 的防火墙放行"
  done < "$1"
}

# _stop_remove_svc <节点id>：停掉并删除该节点的服务，不碰其它节点
_stop_remove_svc() {
  _x_id="$1"
  _x_core=$(tr -d ' \r\n' < "$NODES_DIR/$_x_id/core" 2>/dev/null)
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    case "$_x_core" in
      sing-box) _x_unit="singbox-node@${_x_id}" ;;
      *) _x_unit="xray-node@${_x_id}" ;;
    esac
    systemctl stop "$_x_unit" >/dev/null 2>&1
    systemctl disable "$_x_unit" >/dev/null 2>&1
    rm -f "/etc/systemd/system/${_x_unit}.service"
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "xray-node-${_x_id}" stop >/dev/null 2>&1
    rc-update del "xray-node-${_x_id}" default >/dev/null 2>&1
    rm -f "/etc/init.d/xray-node-${_x_id}"
  fi
  # 兜底：按该节点的配置文件路径精确杀进程，不碰其它节点的进程
  pkill -f "/etc/xray-node/nodes/${_x_id}/config.json" >/dev/null 2>&1
  sleep 1
}

# _del_node <节点id> [skip_confirm]：删除单个节点（服务+防火墙+配置），其它节点不受影响
_del_node() {
  _d_id="$1"
  [ -d "$NODES_DIR/$_d_id" ] || { echo "节点 $_d_id 不存在"; return 1; }
  if [ "$2" != "skip_confirm" ]; then
    printf "确定删除节点 %s（%s）吗？删掉后这个节点就不能用了。[y/N]: " "$_d_id" "$(_node_info "$_d_id")"
    read -r _ans
    case "$_ans" in y|Y|yes|YES) ;; *) echo "已取消"; return 0 ;; esac
  fi
  echo "正在删除节点 $_d_id…"
  _stop_remove_svc "$_d_id"
  [ -d /run/systemd/system ] && systemctl daemon-reload >/dev/null 2>&1
  _del_fw_rules "$NODES_DIR/$_d_id/fw_info"
  rm -rf "$NODES_DIR/$_d_id"
  echo "节点 $_d_id 已删除，其它节点不受影响。"
}

# _uninstall_all：删除全部节点并卸载干净（含内核、命令、配置）
_uninstall_all() {
  echo "正在删除全部节点并卸载…"
  for _d in "$NODES_DIR"/*/; do
    [ -d "$_d" ] || continue
    _del_node "$(basename "$_d")" skip_confirm
  done
  # 兼容老版本：停掉并删掉旧的单服务名残留（xray / sing-box）
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
  sleep 1
  # 只删脚本自己下载安装的内核（our_bins 里记着），用户机器上本来就有的不碰
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
  rm -f /var/log/xray.log /var/log/sing-box.log /var/log/xray-node-*.log
  rm -f /usr/local/bin/jiedian
  rm -f /usr/local/bin/shanjiedian /usr/local/bin/xiezai
  echo "卸载完成：所有节点、配置、开机自启、防火墙规则都已清除干净。"
}

echo "==================== 节点管理 ===================="
_n_count=0
for _d in "$NODES_DIR"/*/; do
  [ -f "${_d}node.txt" ] || continue
  _n_count=$((_n_count + 1))
  _n_id=$(basename "$_d")
  printf "  %s) 节点 %s：%s\n" "$_n_count" "$_n_id" "$(_node_info "$_n_id")"
  eval "_nid_$_n_count='$_n_id'"
done
if [ "$_n_count" = "0" ]; then
  echo "没有已安装的节点。"
  exit 0
fi
printf "  0) 取消\n"
printf "  all) 删除全部节点并卸载干净\n"
printf "请选择要删除的节点编号: "
read -r _sel
case "$_sel" in
  0|"") echo "已取消" ;;
  all|ALL)
    printf "确定删除全部 %s 个节点并卸载干净吗？[y/N]: " "$_n_count"
    read -r _ans2
    case "$_ans2" in y|Y|yes|YES) _uninstall_all ;; *) echo "已取消" ;; esac
    ;;
  *)
    case "$_sel" in ''|*[!0-9]*) echo "输入不对，已取消" ;;
      *)
        if [ "$_sel" -ge 1 ] && [ "$_sel" -le "$_n_count" ]; then
          eval "_del_node \"\$_nid_$_sel\""
        else
          echo "没有这个编号，已取消"
        fi
        ;;
    esac
    ;;
esac
XZEOF
chmod +x /usr/local/bin/shanjiedian
# 旧版的 xiezai 是"一键全删"，改名后把它删掉，免得留着误导人
rm -f /usr/local/bin/xiezai
}

_svc_install() { # _svc_install <节点id>：按该节点的 core 装好开机自启服务并启动（systemd 模板实例 / OpenRC 独立脚本 / 兜底后台）
  _si_id="$1"
  _si_core=$(tr -d ' \r\n' < /etc/xray-node/nodes/"$_si_id"/core 2>/dev/null)
  _si_cfg=/etc/xray-node/nodes/"$_si_id"/config.json
  case "$_si_core" in
    sing-box) _si_bin="$SB_BIN"; _si_args="run -c $_si_cfg"; _si_tpl=/etc/systemd/system/singbox-node@.service; _si_unit="singbox-node@${_si_id}" ;;
    *)        _si_bin="$XRAY_BIN"; _si_args="-config $_si_cfg"; _si_tpl=/etc/systemd/system/xray-node@.service; _si_unit="xray-node@${_si_id}" ;;
  esac
  _si_svc="xray-node-${_si_id}"
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    # 模板 unit 只写一次，多个节点共用（%i 即节点 id）
    if [ ! -f "$_si_tpl" ]; then
      case "$_si_core" in
        sing-box) _si_tpl_bin="$SB_BIN"; _si_tpl_args="run -c /etc/xray-node/nodes/%i/config.json"; _si_tpl_desc="sing-box node %i" ;;
        *)        _si_tpl_bin="$XRAY_BIN"; _si_tpl_args="-config /etc/xray-node/nodes/%i/config.json"; _si_tpl_desc="Xray node %i" ;;
      esac
      cat > "$_si_tpl" <<EOF
[Unit]
Description=${_si_tpl_desc}
After=network.target
[Service]
Type=simple
User=root
ExecStart=${_si_tpl_bin} ${_si_tpl_args}
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    fi
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
    cat > /etc/init.d/${_si_svc} <<RCEOF
#!/sbin/openrc-run
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
    pkill -f "$_si_cfg" >/dev/null 2>&1
    # shellcheck disable=SC2086 — _si_args 故意拆成多个参数
    nohup $_si_bin $_si_args >/var/log/xray-node-${_si_id}.log 2>&1 &
    sleep 1
    info "节点 $_si_id 已在后台启动"
  fi
}

_svc_restart() { # _svc_restart <节点id>：只重启该节点的服务（更新模式用）
  _sr_id="$1"
  _sr_core=$(tr -d ' \r\n' < /etc/xray-node/nodes/"$_sr_id"/core 2>/dev/null)
  case "$_sr_core" in
    sing-box) _sr_unit="singbox-node@${_sr_id}" ;;
    *)        _sr_unit="xray-node@${_sr_id}" ;;
  esac
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl restart "$_sr_unit" >/dev/null 2>&1
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "xray-node-${_sr_id}" restart >/dev/null 2>&1
  else
    _sr_cfg=/etc/xray-node/nodes/"$_sr_id"/config.json
    pkill -f "$_sr_cfg" >/dev/null 2>&1
    sleep 1
    case "$_sr_core" in
      sing-box) nohup "$SB_BIN" run -c "$_sr_cfg" >/var/log/xray-node-"$_sr_id".log 2>&1 & ;;
      *)        nohup "$XRAY_BIN" -config "$_sr_cfg" >/var/log/xray-node-"$_sr_id".log 2>&1 & ;;
    esac
  fi
  sleep 1
}

_node_port() { # _node_port <节点id> -> "端口 协议"（从该节点的 fw_info 第一行读）
  read -r _np_port _np_proto _np_rest < /etc/xray-node/nodes/"$1"/fw_info 2>/dev/null
  [ -n "$_np_port" ] || return 1
  [ -n "$_np_proto" ] || _np_proto="tcp"
  printf "%s %s" "$_np_port" "$_np_proto"
}

_ver_num() { # _ver_num <字符串> -> 提取其中的第一个版本号，如 "Xray 26.3.27 (…)" -> "26.3.27"
  printf "%s" "$1" | sed 's/^[^0-9]*//; s/[^0-9.].*//; s/\.*$//'
}

_latest_tag() { # _latest_tag <owner/repo> -> 打印最新 release 版本号（去 v 前缀），失败返回非零
  _lt_tag=$(curl -fsSL --max-time 20 "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
  [ -n "$_lt_tag" ] || return 1
  printf "%s" "$_lt_tag"
}

dl_xray() { # 下载并安装 Xray 内核；FORCE_DL=1 时即使已存在也强制下载最新版
  step "[下载] 获取 Xray 内核…"
  case "$MACH" in
    amd64) XARCH="64" ;;
    arm64) XARCH="arm64-v8a" ;;
    armv7) XARCH="arm32-v7a" ;;
  esac
  if [ "$FORCE_DL" != "1" ] && [ -x "$XRAY_BIN" ] && "$XRAY_BIN" version >/dev/null 2>&1; then
    info "Xray 已存在，直接用现有的：$($XRAY_BIN version 2>/dev/null | head -1)"
  else
    DL_DIR=$(pick_dldir) || die "找不到可写的下载目录"
    # 磁盘上已有完整可用的包就直接用（上次下载完但被中断的情况，不用重新下载）；
    # 更新模式（FORCE_DL=1）不走这里，必须拉最新版
    if [ "$FORCE_DL" != "1" ] && [ -s "$DL_DIR/xray.zip" ] && unzip -t -q "$DL_DIR/xray.zip" >/dev/null 2>&1; then
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
    # 先装到临时名、验明能跑再原子替换：更新模式下旧内核一直可用，直到新内核确认没问题
    install -m 0755 "$DL_DIR/xray-dl/xray" "${XRAY_BIN}.new" || die "安装 Xray 失败"
    if ! "${XRAY_BIN}.new" version >/dev/null 2>&1; then
      rm -f "${XRAY_BIN}.new"
      die "下载的 Xray 内核跑不起来，安装包可能有问题"
    fi
    mv -f "${XRAY_BIN}.new" "$XRAY_BIN"
    mark_our_bin "xray"
    rm -rf "$DL_DIR"
    info "Xray 安装成功：$($XRAY_BIN version 2>/dev/null | head -1)"
  fi
}

dl_singbox() { # 下载并安装 sing-box 内核；FORCE_DL=1 时即使已存在也强制下载最新版
  step "[下载] 获取 sing-box 内核…"
  if [ "$FORCE_DL" != "1" ] && [ -x "$SB_BIN" ] && "$SB_BIN" version >/dev/null 2>&1; then
    info "sing-box 已存在，直接用现有的：$($SB_BIN version 2>/dev/null | head -1)"
  else
    DL_DIR=$(pick_dldir) || die "找不到可写的下载目录"
    _ver=$(curl -fsSL --max-time 20 https://api.github.com/repos/SagerNet/sing-box/releases/latest \
      | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
    [ -z "$_ver" ] && die "获取 sing-box 最新版本失败，检查服务器能否访问 api.github.com"
    # 磁盘上已有完整可用的包就直接用（上次下载完但被中断的情况，不用重新下载）；
    # 更新模式（FORCE_DL=1）不走这里，必须拉最新版
    if [ "$FORCE_DL" != "1" ] && [ -s "$DL_DIR/sb.tar.gz" ] && tar tzf "$DL_DIR/sb.tar.gz" >/dev/null 2>&1; then
      info "安装包已在本地，直接使用（跳过下载）"
    else
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
      for _cand in $_sb_cands; do
        info "尝试下载：${_cand}"
        # 路线 A：GitHub API（api.github.com 稳，302 跳到 release-assets 下得快）
        if gh_api_dl "SagerNet/sing-box" "$_cand" "$DL_DIR/sb.tar.gz"; then
          _dl_ok=1
          break
        fi
        warn "API 路线失败，换 github.com 直链试试…"
        rm -f "$DL_DIR/sb.tar.gz"
        # 路线 B：github.com 版本直链兜底
        _url="https://github.com/SagerNet/sing-box/releases/download/v${_ver}/${_cand}"
        if curl -fSL --progress-bar --connect-timeout 20 --speed-time 30 --speed-limit 1000 --retry 2 --retry-delay 3 -o "$DL_DIR/sb.tar.gz" "$_url"; then
          _dl_ok=1
          break
        fi
        warn "这个包名下载失败，换下一个包名试试…"
        rm -f "$DL_DIR/sb.tar.gz"
      done
      [ "$_dl_ok" -eq 1 ] || die "sing-box 下载失败：到 GitHub 的网络不稳定，稍等几分钟后重跑脚本试试"
    fi
    # 完整性校验：包坏了直接报错，不往下装半截文件
    tar tzf "$DL_DIR/sb.tar.gz" >/dev/null 2>&1 || die "下载的安装包已损坏，请重跑脚本重新下载"
    rm -rf "$DL_DIR/sb-dl" && mkdir -p "$DL_DIR/sb-dl"
    tar xzf "$DL_DIR/sb.tar.gz" -C "$DL_DIR/sb-dl" || die "解压失败"
    # 包内顶层目录名跟包名走（不同候选包名目录名不同），动态探测，不写死
    _sb_inner=$(tar tzf "$DL_DIR/sb.tar.gz" 2>/dev/null | head -1 | cut -d/ -f1)
    [ -n "$_sb_inner" ] && [ -s "$DL_DIR/sb-dl/${_sb_inner}/sing-box" ] \
      || die "解压后没找到 sing-box 文件"
    # 先装到临时名、验明能跑再原子替换：更新模式下旧内核一直可用，直到新内核确认没问题
    install -m 0755 "$DL_DIR/sb-dl/${_sb_inner}/sing-box" "${SB_BIN}.new" || die "安装 sing-box 失败"
    if ! "${SB_BIN}.new" version >/dev/null 2>&1; then
      rm -f "${SB_BIN}.new"
      die "下载的 sing-box 内核跑不起来，安装包可能有问题"
    fi
    mv -f "${SB_BIN}.new" "$SB_BIN"
    mark_our_bin "sing-box"
    rm -rf "$DL_DIR"
    info "sing-box 安装成功：$($SB_BIN version 2>/dev/null | head -1)"
  fi
}

# ---------- 1. 必须是 root ----------
if [ "$(id -u)" -ne 0 ]; then
  die "请用 root 用户运行（root 下直接运行，或在命令前加 sudo）"
fi

printf "\n${BOLD}==============================================${NC}\n"
printf "${BOLD}   Xray 节点一键安装（小白版）${NC}\n"
printf "${BOLD}==============================================${NC}\n"
printf "全程中文提问，看不懂就一路回车用默认。\n"

# ---------- 2b. 架构与路径（更新模式也要用，提前确定） ----------
mkdir -p /usr/local/bin 2>/dev/null  # 极简系统可能连这个目录都没有
XRAY_BIN="/usr/local/bin/xray"
SB_BIN="/usr/local/bin/sing-box"
case "$(uname -m)" in
  x86_64|amd64) MACH="amd64" ;;
  aarch64|arm64) MACH="arm64" ;;
  armv7l|armv7) MACH="armv7" ;;
  *) die "不支持的 CPU 架构：$(uname -m)" ;;
esac

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
    warn "找不到老节点的配置文件（$_m_cfg），跳过迁移，按全新安装处理"
    rm -f /etc/xray-node/node.txt
  else
    mkdir -p /etc/xray-node/nodes/1
    # 停掉老服务（systemd / OpenRC / 兜底进程都处理）
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      systemctl stop "$_m_core" >/dev/null 2>&1
      systemctl disable "$_m_core" >/dev/null 2>&1
      rm -f "/etc/systemd/system/${_m_core}.service"
      systemctl daemon-reload >/dev/null 2>&1
    fi
    if command -v rc-service >/dev/null 2>&1; then
      rc-service "$_m_core" stop >/dev/null 2>&1
      rc-update del "$_m_core" default >/dev/null 2>&1
      rm -f "/etc/init.d/${_m_core}"
    fi
    pkill -f "$_m_cfg" >/dev/null 2>&1
    sleep 1
    # 搬家：配置、节点信息、防火墙记录、内核标记
    mv -f "$_m_cfg" /etc/xray-node/nodes/1/config.json
    mv -f /etc/xray-node/node.txt /etc/xray-node/nodes/1/node.txt
    [ -f /etc/xray-node/fw_info ] && mv -f /etc/xray-node/fw_info /etc/xray-node/nodes/1/fw_info
    [ -f /etc/xray-node/core ] && mv -f /etc/xray-node/core /etc/xray-node/nodes/1/core
    rmdir /usr/local/etc/xray /usr/local/etc/sing-box 2>/dev/null
    # 按新布局起服务
    _svc_install 1
    _m_port=""; _m_proto="tcp"
    if _m_pp=$(_node_port 1); then set -- $_m_pp; _m_port="$1"; _m_proto="$2"; fi
    if [ -n "$_m_port" ] && wait_for_port "$_m_port" "$_m_proto" 15; then
      info "迁移完成：老节点已转为节点 1，端口 $_m_port/$_m_proto 监听正常"
    else
      warn "老节点服务可能没起来：输入 jiedian 查看，或输入 shanjiedian 进节点管理检查"
    fi
  fi
fi

# 已经装过节点：更新（默认）/ 添加新节点 / 节点管理 / 取消
# 注意：选 2 添加新节点不会动旧节点，旧节点继续用；想删节点选 3 或直接输 shanjiedian
UPDATE_MODE=0
FORCE_DL=0
_NODE_COUNT=0
if [ -d /etc/xray-node/nodes ]; then
  for _nd in /etc/xray-node/nodes/*/; do
    [ -f "${_nd}node.txt" ] && _NODE_COUNT=$((_NODE_COUNT + 1))
  done
fi
if [ "$_NODE_COUNT" -gt 0 ]; then
  printf "\n检测到这台机器已经装了 %s 个节点。\n" "$_NODE_COUNT"
  printf "  1) 更新内核（推荐：所有节点配置不变，只把 Xray/sing-box 内核升到最新版）\n"
  printf "  2) 添加新节点（再搭一个，旧节点不受影响、继续用）\n"
  printf "  3) 节点管理（查看所有节点、删除某个节点）\n"
  printf "  4) 取消，什么都不做\n"
  ask "请选择" "1" _um
  case "$_um" in
    2) info "进入添加新节点流程（旧节点不受影响）" ;;
    3) write_helper_cmds; sh /usr/local/bin/shanjiedian; exit 0 ;;
    4|n|N|no|NO) echo "已取消"; exit 0 ;;
    *) UPDATE_MODE=1 ;;
  esac
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
mkdir -p "$NODE_DIR"

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
      xray|sing-box)
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
      else
        _u_repo="SagerNet/sing-box"; _u_bin="$SB_BIN"
      fi
      _u_inst=""
      [ -x "$_u_bin" ] && _u_inst=$(_ver_num "$("$_u_bin" version 2>/dev/null | head -1)")
      _u_latest=$(_latest_tag "$_u_repo") || _u_latest=""
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
      # 备份旧内核：新内核万一跑不起来，回滚后节点不受影响
      [ -x "$_u_bin" ] && cp -a "$_u_bin" "${_u_bin}.bak" 2>/dev/null
      FORCE_DL=1
      if [ "$_ucore" = "xray" ]; then dl_xray; else dl_singbox; fi
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
        if [ -f "${_u_bin}.bak" ]; then
          warn "新内核启动后有节点端口没监听，正在回滚到旧版本…"
          cp -a "${_u_bin}.bak" "$_u_bin"
          for _rid in $_u_failed; do
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
        rm -f "${_u_bin}.bak"
        if [ -z "$_u_rb_bad" ]; then
          die "$_ucore 新版本在这台机器上跑不起来，已回滚到旧版本，节点不受影响"
        else
          die "$_ucore 新版本跑不起来，且回滚后节点${_u_rb_bad}仍未恢复监听——节点可能已中断，请按上面的提示手动检查"
        fi
      fi
      rm -f "${_u_bin}.bak"
      info "$_ucore 升级完成"
      ) || _u_any_fail=1
    done
    # 刷新 jiedian / shanjiedian（脚本可能修过它们）
    write_helper_cmds
    info "jiedian / shanjiedian 命令已同步为最新版"
    printf "\n"
    sh /usr/local/bin/jiedian
    if [ "$_u_any_fail" = "1" ]; then
      printf "\n${YELLOW}${BOLD}更新结束：部分内核更新失败（上面有说明），其它节点不受影响。${NC}\n"
    else
      printf "\n${GREEN}${BOLD}更新完成！${NC}节点链接、端口、密码都没变，直接继续用。\n"
    fi
    exit 0
  fi
fi

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
      warn "「$SERVER_IP」不像个 IPv$IPVER 地址，检查一下再输"
    fi
    SERVER_IP=""
  done
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
# 去掉前导 0（比如 08080）：JSON 数字不允许前导 0，留着后面配置文件校验过不了
PORT=$(printf "%s" "$PORT" | sed 's/^0*//')
[ -z "$PORT" ] && PORT=0
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
  ask "请选择" "1" _dm
  case "$_dm" in
    2)  REALITY_DOMAIN="www.cisco.com" ;;
    3)  REALITY_DOMAIN="www.apple.com" ;;
    4)  REALITY_DOMAIN="itunes.apple.com" ;;
    5)  REALITY_DOMAIN="www.python.org" ;;
    6)  REALITY_DOMAIN="m.media-amazon.com" ;;
    7)  REALITY_DOMAIN="images-na.ssl-images-amazon.com" ;;
    8)  REALITY_DOMAIN="download-installer.cdn.mozilla.net" ;;
    9)  REALITY_DOMAIN="www.lovelive-anime.jp" ;;
    10) REALITY_DOMAIN="academy.nvidia.com" ;;
    11) REALITY_DOMAIN="lol.secure.dyn.riotcdn.net" ;;
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
if [ "$CORE" = "xray" ]; then
  dl_xray
else
  dl_singbox
fi

# ---------- 9. REALITY 密钥对 ----------
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
      _rp_out=$(timeout 25 "$XRAY_BIN" tls ping "$REALITY_DOMAIN" 2>&1)
      if printf "%s" "$_rp_out" | grep -q "Handshake succeeded" \
        && printf "%s" "$_rp_out" | grep -q "TLS 1.3"; then
        _rp_ok=1
      fi
    elif command -v openssl >/dev/null 2>&1; then
      _rp_out=$(timeout 20 openssl s_client -connect "${REALITY_DOMAIN}:443" \
        -servername "$REALITY_DOMAIN" -tls1_3 </dev/null 2>&1)
      if printf "%s" "$_rp_out" | grep -q "Protocol  *: *TLSv1.3" \
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
    info "伪装域名验证通过：$REALITY_DOMAIN（TLS 1.3 握手正常）"
  else
    warn "伪装域名 $REALITY_DOMAIN 验证没通过，继续安装（节点照常用，伪装效果可能打折）。"
  fi
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
    cat > "$NODE_DIR/config.json" <<EOF
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
    cat > "$NODE_DIR/config.json" <<EOF
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
    cat > "$NODE_DIR/config.json" <<EOF
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
    cat > "$NODE_DIR/config.json" <<EOF
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
"$XRAY_BIN" -test -config "$NODE_DIR/config.json" >/dev/null 2>&1 \
  || die "配置文件校验没通过，请截图发我看看"
info "配置文件校验通过"

else
# ---------- sing-box 配置（AnyTLS / Hysteria2 / TUIC） ----------
mkdir -p /usr/local/etc/sing-box
SB_CONF="$NODE_DIR/config.json"
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

# ---------- 11. 开机自启（每个节点独立服务，互不干扰） ----------
# 先记下这个节点用的内核，_svc_install 要读它
echo "$CORE" > "$NODE_DIR/core" 2>/dev/null
step "[服务] 设置开机自启…"
_svc_install "$NODE_ID"

# ---------- 11b. 硬检查：端口必须真的在监听 ----------
# 服务显示"已启动"不代表真在工作，端口没监听节点就是坏的，直接报错不忽悠
_SVC_PROTO="tcp"
case "$PROTO" in hy2|tuic) _SVC_PROTO="udp" ;; esac
if wait_for_port "$PORT" "$_SVC_PROTO" 15; then
  info "端口 $PORT/$_SVC_PROTO 已在监听，服务真正跑起来了"
else
  die "服务没能监听端口 $PORT：节点装坏了。请先运行 systemctl status 'xray-node@${NODE_ID}'（或 rc-service 'xray-node-${NODE_ID}' status）看原因，修好再重跑脚本"
fi

# ---------- 12. 放行端口 ----------
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
for _np in $_FW_PROTOS; do
  _UFW_ADDED=0; _FWL_ADDED=0; _IPT_ADDED=0
  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -qE "^${PORT}/${_np}[[:space:]]"; then
      : # 这条规则本来就存在（用户自己加的），我们不动它
    elif ufw allow "$PORT"/"$_np" >/dev/null 2>&1; then
      _UFW_ADDED=1
      info "ufw 已放行 $PORT/$_np"
    fi
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | grep -qx "${PORT}/${_np}"; then
      : # 这条规则本来就存在（用户自己加的），我们不动它
    elif firewall-cmd --permanent --add-port="$PORT"/"$_np" >/dev/null 2>&1 \
      && firewall-cmd --reload >/dev/null 2>&1; then
      _FWL_ADDED=1
      info "firewalld 已放行 $PORT/$_np"
    fi
  fi
  if command -v iptables >/dev/null 2>&1; then
    if iptables -C INPUT -p "$_np" --dport "$PORT" -j ACCEPT >/dev/null 2>&1; then
      : # 这条规则本来就存在（用户自己加的），我们不动它
    elif iptables -I INPUT -p "$_np" --dport "$PORT" -j ACCEPT >/dev/null 2>&1; then
      _IPT_ADDED=1
    fi
  fi
  echo "$PORT $_np $_UFW_ADDED $_FWL_ADDED $_IPT_ADDED" >> "$NODE_DIR/fw_info"
done
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
} > "$NODE_DIR/node.txt"

write_helper_cmds
info "已安装 jiedian 命令：以后输入 jiedian 就能看所有节点"
info "已安装 shanjiedian 命令：输入 shanjiedian 可管理节点（查看/删除）"

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
    # _bbr_dir 可能是 mktemp 建的临时目录，也可能是 mktemp 失败时回退的 /tmp：
    # 只删我们下载的那个文件；回退到 /tmp 时绝不能 rm -rf 整个目录
    rm -f "$_bbr_dir/bbr.sh"
    [ "$_bbr_dir" != "/tmp" ] && rm -rf "$_bbr_dir"
  fi
fi

# ---------- 15. 显示结果 ----------
printf "\n节点 %s 安装完成！\n" "$NODE_ID"
cat "$NODE_DIR/node.txt"
printf "\n${GREEN}${BOLD}安装完成！${NC}把上面那行链接复制到客户端就能用了。\n"
printf "以后看所有节点输入 jiedian，管理节点（查看/删除）输入 shanjiedian。\n"
