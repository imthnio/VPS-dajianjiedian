# 小白一键搭建代理节点

在你自己的服务器（VPS）上一键安装 Xray 节点，全程中文提问，看不懂就一路回车用默认。

支持 Debian / Ubuntu / Alpine / CentOS / Arch，x86_64 和 ARM64。NAT、LXC、KVM 精简系统没有 curl 也能装。

## 小白三步

```bash
# 1. SSH 连上你的服务器（root 用户）
# 2. 粘贴下面这一行，回车。没有 curl 会先装上再继续：
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"; if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! { command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx wget; }; then { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y curl; } || { command -v dpkg >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive dpkg --configure -a; apt-get -o Acquire::ForceIPv4=true update -qq && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y curl; } || apk add --no-cache curl || yum install -y curl || dnf install -y curl || pacman -Sy --noconfirm curl || zypper --non-interactive install curl; hash -r 2>/dev/null || true; fi; rm -f /tmp/xray-install.sh; if { curl -fsSL -o /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh || wget -O /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh || busybox wget -O /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh; } && [ -s /tmp/xray-install.sh ]; then sh /tmp/xray-install.sh; else echo "安装脚本没下载下来。请把上面的报错发出来。"; fi
# 3. 按提示回答问题：节点名称、端口、伪装域名等都会停下来等你输入（Hysteria2 还会问上下行带宽，只填数字），看不懂就回车用默认。
```

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

## 赞赏支持
如果这个脚本帮到了你，欢迎请我喝杯咖啡 ☕  
微信扫一扫下方赞赏码即可：

![赞赏码](./appreciate.png)
