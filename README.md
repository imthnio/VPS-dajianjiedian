# 小白一键搭建代理节点

在你自己的服务器（VPS）上一键安装 Xray 节点，全程中文提问，看不懂就一路回车用默认。

支持 Debian / Ubuntu / Alpine / CentOS / Arch，x86_64 和 ARM64。

## 小白三步

```bash
# 1. SSH 连上你的服务器（root 用户）
# 2. 粘贴下面这一行，回车：
curl -fsSL -o /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh && sh /tmp/xray-install.sh
# 3. 按提示回答问题，装完自动显示节点链接
```

安装时会询问：

1. **IPv4 还是 IPv6**（默认 IPv4）
2. **协议**：VLESS+REALITY+Vision（推荐）/ VMess+WS / Trojan+REALITY / Shadowsocks / AnyTLS+REALITY / Hysteria2 / TUIC
3. **端口**（默认随机一个空闲端口）
4. **公网映射端口**（普通 VPS 直接回车；NAT VPS 填服务商分配、映射到上一步端口的公网端口）
5. **REALITY 伪装域名**（只有选 REALITY 协议才问）：11 个备选，默认 www.samsung.com

NAT VPS 要先在服务商面板确认端口映射。脚本只能检查本机端口在监听，无法替服务商创建映射或验证公网入口。Hysteria2 和 TUIC 需要 UDP 映射，其余协议需要 TCP；Shadowsocks 需要 TCP 和 UDP。

64MB 内存、1GB 硬盘的小 NAT 也可以装 Hysteria2。脚本会自动加一块虚拟内存，并改用大约 22MB 的官方 Hysteria 程序。新版 sing-box 解压后大约 80MB，这种小机器会在下载或启动时失败。

Hysteria2 用的是自签证书。分享链接同时带有 `insecure=1` 和证书指纹：官方 Hysteria2 客户端连接自签证书需要这两个值一起使用，指纹仍会校验证书。如果导入后“证书锁定”是空的，把脚本打印的指纹填进去。脚本单独打印的 Loon 配置行使用 Loon 自己的证书锁定字段。

UUID 和密码全部随机生成，不用你操心。

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
