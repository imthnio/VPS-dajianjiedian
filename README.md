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
2. **协议**：VLESS+REALITY+Vision（推荐）/ VMess+WS / Trojan+REALITY / Shadowsocks
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
