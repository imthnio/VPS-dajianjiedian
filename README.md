# 小白一键搭建代理节点

在你自己的服务器（VPS）上一键安装 Xray 节点，全程中文提问，看不懂就一路回车用默认。

支持 Debian / Ubuntu / Alpine / CentOS / Arch，x86_64 和 ARM64。NAT、LXC、KVM 精简系统没有 curl 也能装。

## 小白三步

```bash
# 1. SSH 连上你的服务器（root 用户）
# 2. 整段粘贴，回车。没有 curl 会自己装上再继续：
sh <<'EOF'
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH
url="https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh"
out="/tmp/xray-install.sh"
has() { command -v "$1" >/dev/null 2>&1; }
can_wget() {
  has wget && return 0
  has busybox && busybox --list 2>/dev/null | grep -qx wget
}
download() {
  rm -f "$out"
  if has curl; then
    curl -fsSL --connect-timeout 15 --max-time 120 -o "$out" "$url" && [ -s "$out" ] && return 0
    curl -4 -fsSL --connect-timeout 15 --max-time 120 -o "$out" "$url" && [ -s "$out" ] && return 0
  fi
  if has wget; then
    wget -O "$out" -T 120 "$url" && [ -s "$out" ] && return 0
    wget -4 -O "$out" -T 120 "$url" && [ -s "$out" ] && return 0
  elif can_wget; then
    busybox wget -O "$out" -T 120 "$url" && [ -s "$out" ] && return 0
  fi
  return 1
}
install_curl() {
  echo "没有 curl，也没有 wget。正在识别系统并自动安装，装完继续…"
  sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1 || true
  if has apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    _n=0
    while [ "$_n" -lt 5 ]; do
      apt-get update -qq && break
      apt-get -o Acquire::ForceIPv4=true update -qq && break
      _n=$((_n + 1))
      echo "软件源正忙，20 秒后重试（${_n}/5）…"
      sleep 20
    done
    apt-get install -y -qq curl ca-certificates \
      || apt-get -o Acquire::ForceIPv4=true install -y curl ca-certificates \
      || apt-get -o Acquire::ForceIPv4=true install -y curl \
      || true
  elif has apk; then
    apk add --no-cache curl ca-certificates || apk add --no-cache curl || true
  elif has dnf; then
    dnf install -y curl ca-certificates || dnf install -y curl || true
  elif has yum; then
    yum install -y curl ca-certificates || yum install -y curl || true
  elif has pacman; then
    pacman -Sy --noconfirm --needed curl ca-certificates || true
  elif has zypper; then
    zypper --non-interactive install curl ca-certificates || true
  else
    echo "识别不到软件安装方式。请先手动安装 curl 或 wget。"
    exit 1
  fi
  hash -r 2>/dev/null || true
}
download || {
  if has curl || has wget; then
    echo "安装脚本没下载下来。请把上面的报错发出来。"
    exit 1
  fi
  install_curl
  download || { echo "安装脚本没下载下来。请把上面的报错发出来。"; exit 1; }
}
sh "$out"
EOF
# 3. 按提示回答问题，装完自动显示节点链接
```

安装时会先进入菜单：

- **永久节点**：一直有效。看不懂就回车，默认是这一种。
- **定时节点**：再选 1 小时、2 小时、6 小时、24 小时、48 小时、72 小时或 1 周。到点后大约一分钟内，这个节点彻底失效（服务停掉、链接作废、配置和防火墙规则删掉）。其它节点不受影响。服务器中间重启过也一样。
- **关闭 IPv6**：这台服务器以后只通过 IPv4 访问网站和 App，效果和没有 IPv6 一样。重启后也保持关闭。
- **开启 IPv6**：恢复使用。服务商没分配地址的话，打开后仍然没有 IPv6。

机器上已经有节点时，选「添加节点」会进入上面这个菜单。也可以直接选「关闭或开启 IPv6」，不添加节点。

然后再问：

1. **IPv4 还是 IPv6**（默认 IPv4）
2. **协议**：VLESS+REALITY+Vision（推荐）/ VMess+WS / Trojan+REALITY / Shadowsocks / AnyTLS+REALITY / Hysteria2 / TUIC
3. **端口**（默认随机一个空闲端口）
4. **公网映射端口**（普通 VPS 直接回车；NAT VPS 填服务商分配、映射到上一步端口的公网端口）
5. **REALITY 伪装域名**（只有选 REALITY 协议才问）：11 个备选，默认 www.samsung.com

## 看节点

装完之后，随时想看节点链接，SSH 上输入：

```bash
jiedian
```

立刻显示**所有**节点的信息和链接，复制整行粘贴到客户端导入即可。

## 赞赏支持
如果这个脚本帮到了你，欢迎请我喝杯咖啡 ☕  
微信扫一扫下方赞赏码即可：

![赞赏码](./appreciate.png)
