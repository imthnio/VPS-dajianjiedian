# 小白一键搭建代理节点

> 想改代码或加功能（人或 AI 都一样）：**先读完 [AGENTS.md](AGENTS.md) 再动手。**

在你自己的服务器（VPS）上一键安装 Xray 节点，全程中文提问，看不懂就一路回车用默认。

支持 Debian / Ubuntu / Alpine / CentOS / Arch，x86_64 和 ARM64。NAT、LXC、KVM 精简系统没有 curl 也能装。

## 小白三步

```bash
# 1. SSH 连上你的服务器（root 用户）
# 2. 粘贴下面这一行，回车。系统、curl、DNS、能不能连上 GitHub 都会自动识别，自动处理：
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"; export PATH DEBIAN_FRONTEND=noninteractive; q(){ "$@" >/dev/null 2>&1; }; R=/etc/resolv.conf; echo "[1/3] 检查 DNS"; r(){ q getent hosts github.com || q nslookup github.com; }; if { q command -v getent || q command -v nslookup; } && ! r; then B=$R.xray-node-orig; [ -e $B ] || [ -L $B ] || q cp -P $R $B; d="1.1.1.1 8.8.8.8"; [ -r /proc/net/route ] && ! q awk '$2=="00000000"{f=1}END{exit !f}' /proc/net/route && d="2a00:1098:2b::1 2a01:4f8:c2c:123f::1"; [ -L $R ] && rm -f $R; for s in $d; do echo "nameserver $s"; done > $R; chmod 644 $R; if r; then { q command -v dhcpcd || [ -f /etc/dhcpcd.conf ]; } && cp $R $R.head; echo "DNS -> $d"; else q cmp $R $R.head && rm -f $R.head; rm -f $R; cp -P $B $R; rm -f $B; echo "公共 DNS 也连不上，DNS 已还原。这台机器多半上不了网"; fi; fi; if ! q command -v curl && ! wget -V 2>&1 | grep -q "GNU Wget"; then echo "[2/3] 装 curl"; if q command -v apt-get; then { apt-get update -qq && apt-get install -y curl; } || { q command -v dpkg && dpkg --configure -a; A="apt-get -o Acquire::ForceIPv4=true"; $A update -qq && $A install -y curl; }; else for p in "apk add --wait 90 --no-cache" "dnf install -y" "yum install -y" "pacman -Sy --noconfirm" "zypper --non-interactive install"; do q command -v ${p%% *} && { $p curl; break; }; done; fi; hash -r 2>/dev/null; fi; W=wget; q command -v wget || W="busybox wget"; F=/tmp/xray-install.sh; G=https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh; for u in $G https://v6.gh-proxy.org/$G https://gh.llkk.cc/$G https://ghproxy.net/$G https://cdn.jsdelivr.net/gh/imthnio/VPS-dajianjiedian@main/install.sh; do echo "[3/3] 下载 $u"; rm -f $F; l=; { curl -fsSL --connect-timeout 10 -m 120 -o $F $u || $W -O $F -q -T 15 -t 2 $u; } 2>$F.err && [ -s $F ] && read -r l < $F; case "$l" in "#!"*) break;; esac; echo "fail: $u"; tail -n 3 $F.err | sed "s/^/  /"; done; rm -f $F.err; case "$l" in "#!"*) sh $F;; *) rm -f $F; for a in 1.1.1.1 2606:4700:4700::1111; do q ping -c 2 -W 3 $a && echo "ping $a 通" || echo "ping $a 不通"; done; echo "安装脚本没下载下来，请把上面的输出发出来";; esac
# 3. 按提示回答问题：节点名称、端口、伪装域名等都会停下来等你输入（Hysteria2 还会问上下行带宽，只填数字），看不懂就回车用默认。
```

## 赞赏支持
如果这个脚本帮到了你，欢迎请我喝杯咖啡 ☕  
微信扫一扫下方赞赏码即可：

![赞赏码](./appreciate.png)
