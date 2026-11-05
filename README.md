# 小白一键搭建代理节点

在你自己的服务器（VPS）上一键安装 Xray 节点，全程中文提问，看不懂就一路回车用默认。

支持 Debian / Ubuntu / Alpine / CentOS / Arch，x86_64 和 ARM64。NAT、LXC、KVM 精简系统没有 curl 也能装。

## 小白三步

```bash
# 1. SSH 连上你的服务器（root 用户）
# 2. 粘贴下面这一行，回车。没有 curl 会先装上再继续：
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"; export PATH DEBIAN_FRONTEND=noninteractive; q(){ "$@" >/dev/null 2>&1; }; R=/etc/resolv.conf; if { q command -v getent || q command -v nslookup; } && ! { q getent hosts github.com || q nslookup github.com; }; then [ -e $R.xray-node-orig ] || q cp -P $R $R.xray-node-orig; d="1.1.1.1 8.8.8.8"; [ -r /proc/net/route ] && ! q awk '$2=="00000000"{f=1}END{exit !f}' /proc/net/route && d="2a00:1098:2b::1 2a01:4f8:c2c:123f::1"; [ -L $R ] && rm -f $R; for s in $d; do echo "nameserver $s"; done > $R; echo "DNS -> $d"; fi; if ! q command -v curl && ! q command -v wget && ! busybox --list 2>/dev/null | grep -qx wget; then { apt-get update -qq && apt-get install -y curl; } || { q command -v dpkg && dpkg --configure -a; A="apt-get -o Acquire::ForceIPv4=true"; $A update -qq && $A install -y curl; } || apk add --no-cache curl || yum install -y curl || dnf install -y curl || pacman -Sy --noconfirm curl || zypper --non-interactive install curl; hash -r 2>/dev/null; fi; F=/tmp/xray-install.sh; G=https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh; for u in $G https://v6.gh-proxy.org/$G https://gh.llkk.cc/$G https://ghproxy.net/$G https://cdn.jsdelivr.net/gh/imthnio/VPS-dajianjiedian@main/install.sh; do rm -f $F; { curl -fsSL --connect-timeout 10 -m 120 -o $F $u || wget -O $F -q -T 20 $u || busybox wget -O $F -q -T 20 $u; } 2>/dev/null; l=; [ -s $F ] && read -r l < $F; case "$l" in "#!"*) break;; esac; echo "fail: $u"; done; case "$l" in "#!"*) sh $F;; *) rm -f $F; echo "安装脚本没下载下来，请把上面的输出发出来";; esac
# 3. 按提示回答问题：节点名称、端口、伪装域名等都会停下来等你输入（Hysteria2 还会问上下行带宽，只填数字），看不懂就回车用默认。
```

### 报 `bad address` / `Could not resolve host`？

这是服务器的 DNS 解析不了域名（NAT / LXC 小鸡常见：只有 IPv6，DNS 却写的是 IPv4 的）。上面那一行会自动处理：

- DNS 不通时换成公共 DNS（只有 IPv6 的机器用 NAT64/DNS64），原来的 DNS 备份在 `/etc/resolv.conf.xray-node-orig`；
- GitHub 直连下载不了时，自动换几个镜像再试。

还是不行，多半是服务器本身上不了网，先 `ping -c 3 1.1.1.1`（只有 IPv6 就 `ping6 -c 3 2606:4700:4700::1111`）看看通不通。

## 再次运行

已经装过节点的服务器再跑一次上面的命令，会出现菜单：更新内核、添加节点、节点管理等。选「更新内核」或「添加节点」时，Xray / sing-box 有新的**正式版**会自动升级（beta 测试版不装）。

## 看节点

装完之后，随时想看节点链接，SSH 上输入：

```bash
jiedian
```

每个节点只显示两样：**通用节点链接**（v2rayN、小火箭、Clash Verge、NekoBox 等）和 **Loon 节点行**，复制整行粘贴到客户端导入即可。

想看完整参数（端口、密码、Surge / Clash 配置等），输入：

```bash
jiedian all
```

## 限制设备数量

想让一个节点只能给几台设备用，SSH 上输入：

```bash
shanjiedian
```

选「限制节点能连几台设备」，再选节点、输入数字（0 = 不限制）。比如设成 2：手机、电脑、电视加起来同一时间只能 2 台在用；第 3 台连上时，最早连上的那台被挤掉，10 分钟内连不上，以此循环。

设备按上网的 IP 算：同一个 Wi-Fi 下的几台设备只算 1 台；设备几分钟（3 到 6 分钟）没用，名额自动让出来。

## 赞赏支持
如果这个脚本帮到了你，欢迎请我喝杯咖啡 ☕  
微信扫一扫下方赞赏码即可：

![赞赏码](./appreciate.png)
