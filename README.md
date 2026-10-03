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

## 看节点

装完之后，随时想看节点链接，SSH 上输入：

```bash
jiedian
```

立刻显示**所有**节点的信息和链接，复制整行粘贴到客户端导入即可。

## 说明

- **节点名**：自动写成“地区+协议”，比如 `香港Vless-Reality`、`美国Hysteria2`，同名的加数字。
- **拦截 QUIC**：所有协议在服务器端都拒绝 UDP 443，浏览器和 App 会自动改走 TCP，更稳。Loon 链接自带 `block-quic=true`。
- **端口跳跃（Hysteria2）**：装的时候选“开启”，再一个个填跳跃端口（可以写 `20000-20100`）。
  - 独服、PVE 母鸡、KVM 小鸡：一般都能用。
  - OpenVZ、LXC 小鸡：常常没有 nat 转发权限，脚本会先试，不行就说明原因、只用主端口。
  - NAT 小鸡：跳跃端口必须在商家给你的转发端口范围里。
  - 云服务器记得在安全组里放行这些 UDP 端口。
  - 防火墙服务重启或重载（nftables、iptables、firewalld、ufw）会清掉转发规则，脚本装的巡检小程序大约 1 分钟内自动补回。
- **自己的域名（Hysteria2）**：申请证书时脚本临时放行 TCP 80（或 443），装失败或申请成功后马上关上；快到期要续期时自动打开，续好再关。云服务器的安全组仍要放行这个端口。
- **纯 IPv6 机器**：下载内核时会自动换支持 IPv6 的镜像，还不行就临时借用公共 NAT64，用完还原；下载的文件都会核对校验值。全都失败才会提示装 WARP。
- **老节点**：重新运行上面那一行，选「1) 更新内核」，会把旧版端口跳跃改成新写法，并装上巡检小程序。

## 赞赏支持
如果这个脚本帮到了你，欢迎请我喝杯咖啡 ☕  
微信扫一扫下方赞赏码即可：

![赞赏码](./appreciate.png)
