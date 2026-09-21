# xray-node —— 小白一键搭建代理节点

在你自己的服务器（VPS）上一键安装 Xray 节点，全程中文提问，看不懂就一路回车用默认。

支持 Debian / Ubuntu / Alpine / CentOS / Arch，x86_64 和 ARM64。

## 小白三步

```bash
# 1. SSH 连上你的服务器（root 用户）
# 2. 粘贴下面这一行，回车：
curl -fsSL -o /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/xray-node/main/install.sh && sh /tmp/xray-install.sh
# 3. 按提示回答 4 个问题，装完自动显示节点链接
```

4 个问题分别是：

1. **IPv4 还是 IPv6**（默认 IPv4）
2. **协议**：VLESS+REALITY+Vision（推荐）/ VMess+WS / Trojan+REALITY / Shadowsocks / AnyTLS+REALITY / Hysteria2 / TUIC
3. **端口**（默认随机一个空闲端口）
4. **REALITY 伪装域名**（只有选 REALITY 协议才问）：1. www.samsung.com，2. www.apple.com

UUID 和密码全部随机生成，不用你操心。

## 看节点

装完之后，随时想看节点链接，SSH 上输入：

```bash
jiedian
```

立刻显示节点，复制整行粘贴到客户端导入即可。

## 卸载

不想要节点了，SSH 上输入：

```bash
xiezai
```

一键停掉服务、删掉节点、配置和开机自启，清得干干净净。想再装就重新跑一键命令。

## REALITY 伪装域名推荐

选 REALITY 协议时要填伪装域名（SNI），下面是 2026-09-21 实测过的，按靠谱程度排序：

**直接用（中国大陆可达性已验证）：**

1. `www.samsung.com` —— 2018–2026 零干扰，最稳
2. `www.cisco.com` —— 2026 年 0% 干扰，TLS 极稳
3. `itunes.apple.com` —— 2025–2026 全干净
4. `www.python.org` —— 技术站，小众不扎眼
5. `m.media-amazon.com` —— 零干扰记录
6. `images-na.ssl-images-amazon.com` —— 图片 CDN，流量普通
7. `download-installer.cdn.mozilla.net` —— 火狐下载站

**小众备选（先自己测一下再用）：**

8. `www.lovelive-anime.jp` —— 日本动画官网，小厂气质
9. `academy.nvidia.com`
10. `lol.secure.dyn.riotcdn.net` —— 游戏补丁 CDN
11. `s0.awsstatic.com`
12. `www.amd.com` —— 有 3% 干扰率，只当备胎

**千万别用：**

- `www.microsoft.com` —— 2026 年 7 月 TLS 升级后 REALITY 握手失败
- `dl.google.com`、`www.google-analytics.com` —— 国内不通
- `addons.mozilla.org` —— 老教程的默认选项，2026 年已出现干扰

每个域名启用前，先在服务器上跑 `xray tls ping 域名`，确认 TLS 1.3 和 h2 握手正常——能打开网页不等于 REALITY 能用。
