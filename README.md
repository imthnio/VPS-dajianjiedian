# 小白一键搭建代理节点

在你自己的服务器（VPS）上一键安装 Xray 节点，全程中文提问，看不懂就一路回车用默认。

支持 Debian / Ubuntu / Alpine / CentOS / Arch，x86_64 和 ARM64。NAT、LXC、KVM 精简系统没有 curl 也能装。

## 小白三步

```bash
# 1. SSH 连上你的服务器（root 用户）
# 2. 粘贴下面这一行，回车。没有 curl 会先装上再继续：
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"; if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! { command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx wget; }; then { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y curl; } || { command -v dpkg >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive dpkg --configure -a; apt-get -o Acquire::ForceIPv4=true update -qq && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y curl; } || apk add --no-cache curl || yum install -y curl || dnf install -y curl || pacman -Sy --noconfirm curl || zypper --non-interactive install curl; hash -r 2>/dev/null || true; fi; rm -f /tmp/xray-install.sh; if { curl -fsSL -o /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh || wget -O /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh || busybox wget -O /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh; } && [ -s /tmp/xray-install.sh ]; then sh /tmp/xray-install.sh; else echo "安装脚本没下载下来。请把上面的报错发出来。"; fi
# 3. 按提示回答问题。端口和伪装域名都会停下来等你输入，看不懂就回车用默认。
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
