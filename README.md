# 小白一键搭建代理节点

> 想改代码、加功能或排查故障（人或 AI 都一样）：**每次动手前，先读完 [AGENTS.md](AGENTS.md)。**

在你自己的服务器（VPS）上一键安装 Xray 节点，全程中文提问，看不懂就一路回车用默认。

支持 Debian / Ubuntu / Alpine / CentOS / Arch，x86_64 和 ARM64。NAT、LXC、KVM 精简系统没有 curl 也能装。

## 小白三步

1. SSH 连上你的服务器（root 或带 sudo 权限的普通用户如 ubuntu 均可，会自动适配）。
2. 点下面代码框右上角的复制按钮，粘贴到服务器里，回车。权限、系统、curl、DNS、能不能连上 GitHub 都会自动识别，自动处理：

```bash
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH";export PATH DEBIAN_FRONTEND=noninteractive;q(){ "$@">/dev/null 2>&1;};h(){ q command -v $1;};S=;[ "$(id -u)" = 0 ]||{ h sudo&&S=sudo||! h doas||S=doas;};R=/etc/resolv.conf;echo "[1/3] 检查 DNS";g=github.com;r(){ q getent hosts $g||q nslookup $g;};N=/proc/net/route;{ h getent||h nslookup;}&&! r&&{ B=$R.xray-node-orig;K=$R.head;[ -e $B ]||[ -L $B ]||q $S cp -P $R $B;d="1.1.1.1 8.8.8.8";[ -r $N ]&&q awk '$2~/^0+$/{exit 1}' $N&&d="2a00:1098:2b::1 2a01:4f8:c2c:123f::1";[ -L $R ]&&$S rm -f $R;printf "nameserver %s\n" $d|q $S tee $R;$S chmod 644 $R;if r;then { h dhcpcd||[ -f /etc/dhcpcd.conf ];}&&$S cp $R $K;echo "DNS -> $d";else q cmp $R $K&&$S rm -f $K;$S mv -f $B $R;echo "公共 DNS 也不通，DNS 已还原";fi;};T=;h curl||{ wget -V 2>&1|grep -q "GNU Wget"&&T="-t 2";[ "$T" ]||{ echo "[2/3] 装 curl";if h apt-get;then i(){ a="$S apt-get $1";$a update -qq&&$a install -y curl;};i||{ h dpkg&&$S dpkg --configure -a;i "-o Acquire::ForceIPv4=true";};else for p in "apk add --wait 90 --no-cache" "dnf install -y" "yum install -y" "pacman -Sy --noconfirm";do h ${p%% *}&&{ $S $p curl;break;};done;fi;hash -r;};};W=wget;h wget||W="busybox wget";F=/tmp/xray-install.sh;E=$F.err;q rm -f $F $E||$S rm -f $F $E;G=https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh;H=https://;for u in $G ${H}v6.gh-proxy.org/$G ${H}gh.llkk.cc/$G ${H}ghproxy.net/$G ${H}cdn.jsdelivr.net/gh/imthnio/VPS-dajianjiedian@main/install.sh;do echo "[3/3] 下载 $u";rm -f $F;l=;if h curl;then curl -fsSL --connect-timeout 10 -m 120 -o $F $u;else $W -O $F -q -T 15 $T $u;fi 2>$E&&[ -s $F ]&&read -r l<$F;case $l in "#!"*) break;;esac;echo "fail: $u";tail -n3 $E;done;rm -f $E;case $l in "#!"*) $S sh $F;;*) rm -f $F;echo "安装脚本没下载下来，请把上面的输出发出来";;esac
```

3. 按提示回答问题：节点名称、端口、伪装域名等都会停下来等你输入（Hysteria2 还会问上下行带宽，只填数字），看不懂就回车用默认。
