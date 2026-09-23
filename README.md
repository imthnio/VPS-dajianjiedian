# 小白一键搭建代理节点

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
4. **REALITY 伪装域名**（只有选 REALITY 协议才问）：10 个实测备选，默认 www.samsung.com（完整清单见下方"REALITY 伪装域名推荐"）

UUID 和密码全部随机生成，不用你操心。

## 看节点

装完之后，随时想看节点链接，SSH 上输入：

```bash
jiedian
```

立刻显示节点，复制整行粘贴到客户端导入即可。

## 更新（已经装过的人看这里）

节点装好之后，想升级内核或修复脚本 bug，不用重装：**直接重跑上面那条一键命令**，看到菜单选 `1`（默认，直接回车就行）：

- 只把 Xray / sing-box 内核升到最新版
- 节点配置、端口、密码、链接**全部不变**，照常用
- 内核已经是最新时，会顺手把 `jiedian` / `xiezai` 两个命令同步成最新版
- 升级后自动检查端口真的在监听；新内核万一起不来会自动回滚到旧版，节点不受影响

菜单里选 `2` 才是彻底重装（重新回答问题、生成全新节点，旧节点作废）。

## 卸载

不想要节点了，SSH 上输入：

```bash
xiezai
```

一键停掉服务、删掉节点、配置和开机自启，清得干干净净。想再装就重新跑一键命令。

## REALITY 伪装域名推荐

**直接用（中国大陆可达性已验证）：**

1. `www.samsung.com` —— 2018–2026 零干扰，最稳
2. `www.cisco.com` —— 2026 年 0% 干扰，TLS 极稳
3. `www.apple.com` —— 社区验证最多，推荐
4. `itunes.apple.com` —— 2025–2026 全干净
5. `www.python.org` —— 技术站，小众不扎眼
6. `m.media-amazon.com` —— 零干扰记录
7. `images-na.ssl-images-amazon.com` —— 图片 CDN，流量普通
8. `download-installer.cdn.mozilla.net` —— 火狐下载站

**小众备选（先自己测一下再用）：**

9. `www.lovelive-anime.jp` —— 日本动画官网，小厂气质
10. `academy.nvidia.com`
11. `lol.secure.dyn.riotcdn.net` —— 游戏补丁 CDN
12. `s0.awsstatic.com`
13. `www.amd.com` —— 有 3% 干扰率，只当备胎
