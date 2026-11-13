# 排障手册（给 AI 看的）

> **每次动手前都要读这份文件和 [AGENTS.md](AGENTS.md)，每次都读。修完一个新故障，把它补进第 2 节和第 6 节。**
>
> 用户说“装不上 / 卡住了 / 连不上”时，从这里查：**现象 → 出在哪一段 → 怎么改**。
> 规矩（提交方式、POSIX sh、测试）在 [AGENTS.md](AGENTS.md)，先读那份，再读这份。
> 本文件只写查得到的事实。改了代码让这里某一条不再成立，就同时改这里。
> 行号会变，所以本文件只写**章节标题和函数名**，用 `grep -n '标题或函数名' install.sh` 定位。

---

## 1. 一次安装从头到尾走哪些步骤

用户做的事只有一件：把 README 代码框里那一行命令粘贴到服务器的终端里。之后分两段：

**第一段：README 里的安装命令（在用户的交互 shell 里直接执行）**

| 屏幕上打的字 | 在做什么 | 失败时的表现 |
|---|---|---|
| （什么都没打，停在 `>`） | 命令没被 shell 完整收到 | 见 2.1 |
| `[1/3] 检查 DNS` | `getent hosts github.com` 或 `nslookup github.com`。解析不了就把 `/etc/resolv.conf` 换成公共 DNS（没有 IPv4 默认路由的机器换成 DNS64），换完再验证，还不通就还原 | `公共 DNS 也不通，DNS 已还原` |
| `[2/3] 装 curl` | 只有“没有 curl，wget 也不是 GNU 版”时才出现。依次试 apt-get / apk / dnf / yum / pacman | 包管理器自己的报错原样显示 |
| `[3/3] 下载 <网址>` | 依次试 5 个网址：GitHub 直连、3 个镜像、jsDelivr。先 curl，失败再 wget。下载到 `/tmp/xray-install.sh`，第一行是 `#!` 才算成功 | 每个失败的网址打一行 `fail: <网址>` 和最后 3 行真实报错；全失败打 `安装脚本没下载下来` |
| 之后的字都来自 install.sh | `sh /tmp/xray-install.sh` | |

**第二段：install.sh（按 `# ---------- 编号. 标题 ----------` 顺序往下走）**

| 屏幕上打的字 | install.sh 里的章节 |
|---|---|
| `检查网络（DNS 不通时要等几十秒）…` | `1. 必须是 root`（里面调 `_dns64_recover`、`_dns_fix_broken`） |
| `检测到这台机器已经装了 N 个节点` + 5 个选项 | `2d. 已有节点时的主菜单` |
| `[准备] 检查系统工具…` | `2. 装依赖`（`_pkg_add`、`_apt_do`、`_timeout_cmd`） |
| `请选择：1) 永久节点 2) 定时节点 …` | `_choose_node_kind`（在 `IPv6 开关` 一节里） |
| `[1/4] 节点里填你服务器的哪个公网地址？`、`正在检测公网 IP…` | `3. 问：IPv4 还是 IPv6`（`get_ip`、`_geo_cc`） |
| `[2/4] 选一个协议`、节点名称 | `4. 问：协议`（`_ask_node_name`） |
| `[3/4] 节点用哪个端口？`、公网映射端口 | `5. 问：端口`（`rand_port`、`port_in_use`） |
| `[4/4] REALITY 伪装成哪个网站？`、指纹 | `6. REALITY 伪装域名`（`_reality_ask_fp`） |
| `[生成] 随机生成账号和密码…` | `7. 随机生成 UUID / 密码` |
| `[下载] 获取 Xray 内核…` | `8. 下载内核`（`dl_xray` / `dl_singbox` / `dl_hysteria`，下载走 `_gh_get`、校验走 `_verify_dl`） |
| `[密钥] 生成 REALITY 密钥…` | `9. REALITY 密钥对` |
| `[检查] 验证伪装域名从这台 VPS 是否可用…` | `9c. REALITY 伪装域名可用性检查` |
| `[配置] 写入配置…` | `10. 写配置文件`（Hysteria2、sing-box 各有单独一节） |
| `[服务] 设置开机自启…` | `11. 开机自启`（`_svc_install`）和 `11b. 硬检查：端口必须真的在监听`（`wait_for_port`、`_svc_recheck`） |
| 放行端口的提示 | `12. 放行端口`（`_fw_allow`、`_save_fw`） |
| `[完成] 生成你的节点…` | `13. 生成节点链接`、`14. 保存 + jiedian 命令`（`write_helper_cmds`） |
| `检查 BBR 加速…` | `14b. BBR 加速` |
| `节点 N 安装完成` | `15. 显示结果` |

**判断卡在哪：看屏幕上最后一行字，对上表找到章节。** 这是最快的定位办法，所以每一步动手前都必须先打一行字（AGENTS.md 的规矩）。

---

## 2. 现象 → 原因 → 改哪里

### 2.1 粘贴后什么都不运行，光标停在 `>`（用户说“运行到一半卡住”）

- **原因**：shell 没收到完整的命令，还在等后半句。已经确认过的两种来源：
  1. **命令太长被截断。** Alpine 的登录 shell 是 busybox ash，它的行编辑器一行最多收 **2046 个字符**（实测 Alpine 3.20，busybox 1.36.1；中文算 1 个字符），多出来的直接丢掉。命令尾巴没了，`case … esac`、`for … done` 没收尾，就停在 `>`。2026-11 实际出过：命令 2110 个字符，被截在 `echo "ping $a 通"` 后面。bash（Debian / Ubuntu / CentOS）没有这个上限，所以只有 Alpine 出问题，很容易漏测。
  2. **命令里有 heredoc（`<<`）或没配对的引号。**
- **证据怎么拿**：服务器上 `awk '{print length($0)}' ~/.ash_history` 看最后几行长度。正好 2046 就是被截断了。`sed -n '$p' ~/.ash_history | tail -c 200` 能看到截在哪。
- **怎么改**：缩短 README 里的命令。现在是 1747 个字符，测试限制在 1800 以内（`tests/test_expire.py` 的 `readme_command`）。**往命令里加东西之前先数字符**：`grep '^PATH=' README.md | python3 -c 'import sys; print(len(sys.stdin.read().strip()))'`。超了就砍别的，不要去放宽测试里的上限。
- **已经用掉的省字办法**：`;` 后面不留空格；`h(){ q command -v $1; }` 代替重复的 `q command -v`；apt 的两次尝试合成函数 `i`；去掉了 zypper（不在支持列表里）和下载全失败后的 ping 诊断（curl / wget 自己的报错已经说明是解析不了、连不上还是超时）。
- **还要注意**：命令里不能有 Tab 字符（交互 shell 里会触发补全）；`!` 后面要跟空格或在单引号里（bash 交互模式会把 `!词` 当历史展开）。

### 2.2 粘贴后第一个问题就报“输入不对”，或者多出一行 `# 3. 按提示回答问题…`

- **原因**：GitHub 代码框右上角的复制按钮会复制**整个代码框**。以前代码框里除了命令还有三行 `#` 注释，命令后面那一行注释被一起粘贴进去，留在终端的输入里，被 install.sh 的第一个提问当成了回答。命令被截断时（2.1），这一行会掉进 `>` 提示符里，让情况更乱。
- **怎么改**：README 的 ```` ```bash ```` 代码框里**只放那一行命令**，步骤说明写在代码框外面。测试 `readme_command` 检查代码框只有一行。

### 2.3 `[1/3] 检查 DNS` 之后很久没动静

- `getent` / `nslookup` 在等 DNS 超时。resolv.conf 里每个 nameserver 都不通时，要等“nameserver 个数 × 超时秒数 × 重试次数”。
- 看 `/etc/resolv.conf`、`ip route`、`ip -6 route`。只有 IPv6 的机器应该被换成 `2a00:1098:2b::1`（DNS64）。
- 逻辑有两份，改一份要对照另一份：README 命令里的那段，和 install.sh 的 `_dns_fix_broken`（`DNS 坏了` 一节）。测试在 `tests/test_dns_bootstrap.py`。
- 备份文件是 `/etc/resolv.conf.xray-node-orig`；有 dhcpcd 的机器还会写 `/etc/resolv.conf.head`（不然 dhcpcd 续租时把 resolv.conf 冲回去）。

### 2.4 `[3/3] 下载` 五个网址全是 `fail:`

- 先看每个 `fail:` 下面的 3 行报错，不要猜：

| 报错里的字 | 原因 | 改哪里 |
|---|---|---|
| `bad address` / `Could not resolve host` | DNS 不通 | 2.3 |
| `ssl_client` / `not an http or ftp url` / `TLS` | wget 是 busybox 版，没装 `ssl_client`，下不了 https | 命令里 `[2/3] 装 curl` 的判断条件（看 `wget -V` 是不是 `GNU Wget`，不是只看有没有 wget） |
| `Network unreachable` / `Connection timed out`，只在直连那一行 | 只有 IPv6 的机器连不上 GitHub，或 GitHub 被墙 | 正常，后面的镜像会接上。镜像也全挂了就换镜像列表 |
| `404` / `403` | 镜像站下线或改规则了 | 换掉那个镜像（命令里的 `for u in …`；install.sh 里的镜像列表在 `下载工具：GitHub 连不上时换镜像、换 NAT64` 一节，两边一起改） |
| `transfer closed` / 退出码 18 | 下到一半断了 | 已处理：curl 返回非零就不算成功，换下一个网址 |

- 下载成功的判断是“curl 或 wget 返回 0，文件非空，第一行以 `#!` 开头”。镜像站返回一个 HTML 错误页时，靠第一行不是 `#!` 挡住。

### 2.5 `[准备] 检查系统工具…` 卡住或失败

- 章节 `2. 装依赖`。apt 被别的进程锁住、dpkg 上次没配置完、软件源连不上（只有 IPv6 的机器）都在这里处理：`_apt_do`、`_timeout_cmd`（没有 `timeout` 命令时自己用后台进程加 `kill` 实现）。
- Alpine：`apk add --wait 90`，等别的 apk 进程放锁最多 90 秒。
- 失败时走 `_dep_fail`，必须把包管理器的真实报错显示出来。

### 2.6 `正在检测公网 IP…` 卡住，或地址不对

- `get_ip`（`0. 打印小工具` 一节）。依次问几个查 IP 的网站，每个都有超时。NAT 小鸡只有 busybox wget 时也要能查到。
- 查不到会让用户手动输入，可以填 IP 也可以填域名（`_valid_ip`、`_valid_host`、`_resolve_host`）。测试在 `tests/test_ip_input.py`。
- 地区查不到只影响默认节点名（`_geo_cc`、`_cc_name`），不影响安装。

### 2.7 `[下载] 获取 … 内核…` 卡住或失败

- 章节 `下载三个内核` 和 `下载工具` 两节。顺序：GitHub API 查最新版 → 下载 → SHA256 校验（`_gh_expect_sum`、`_verify_dl`）→ 解压 → 运行一次 `version` 确认能用。
- GitHub 连不上：`_gh_get` 自动换镜像；只有 IPv6 的机器临时开 DNS64（`_dns64_on` / `_dns64_off`，脚本中途被杀掉时下次启动由 `_dns64_recover` 还原）。
- 小内存机器（64MB / 128MB）：`小内存机器的特殊处理` 一节。`prepare_low_memory` 会加 swap、清缓存；解压用 `_unpack_drip` 边解边写盘，不把整个文件读进内存。sing-box 解压后约 80MB，64MB 的机器装不下，会明说。测试在 `tests/test_lowmem.py`。
- 被 OOM 杀掉的表现是进程突然消失、没有报错。用 `dmesg | tail`、容器里看 `/sys/fs/cgroup/memory.events` 的 `oom_kill`。

### 2.8 `[检查] 验证伪装域名…` 不通过

- 章节 `9c`。从这台 VPS 对伪装域名做一次 TLS 1.3 握手。不通过说明这台机器访问不了那个网站，换一个伪装域名即可，不是脚本的 bug。

### 2.9 `[服务] 设置开机自启…` 之后报“端口没有在监听”

- 章节 `11` 和 `11b`。`_svc_install` 按系统选 systemd 模板服务或 OpenRC 服务（Alpine）；`wait_for_port` 等端口起来；`_svc_recheck` 再查一遍。
- 查法：systemd 用 `systemctl status xray-node@<编号>`（Hysteria2 是 `hysteria-node@<编号>`）和 `journalctl -u … -n 50`；OpenRC 用 `rc-service xray-node-<编号> status`，日志在 `/var/log/xray-node-*`。
- 手动跑一次内核最直接：`/usr/local/bin/xray run -c /etc/xray-node/nodes/<编号>/config.json`，报错会直接打出来。
- 没装完的节点目录下次运行时由 `2a. 清理上次没装完的半截节点` 自动清掉（`_reap_partial_nodes`）。

### 2.10 装完了，客户端连不上

按这个顺序查，前一步通过再查后一步：

1. **服务在不在跑、端口在不在听**：`ss -lntup | grep <端口>`（没有 ss 用 `netstat -lntup`）。
2. **服务器自己的防火墙**：`12. 放行端口`（`_fw_allow`）。规则存盘走 `_save_fw`，重启后由 `/usr/local/bin/xray-node-fw-restore` 恢复，存盘文件是 `/etc/xray-node/rules.v4`、`rules.v6`。测试在 `tests/test_firewall_restore.py`。
3. **云厂商的安全组**：脚本改不到，装完的提示里会让用户自己去控制台放行。
4. **NAT 小鸡的端口映射**：服务商给的公网端口和节点端口不一样时，要在“公网映射端口”那一问里填公网端口（存在节点目录的 `link_port`）。
5. **UDP 节点（Hysteria2 / TUIC / Shadowsocks）回程走错网卡**：多网卡、多 IP 的机器。小程序 `xray-node-route` 负责加策略路由，`回程路由小程序` 一节，测试在 `tests/test_route.py`。
6. **端口跳跃失效**：Hysteria2。LXC / OpenVZ 小鸡常常没有 nat 转发权限，`_hy_hop_probe` 会先试，做不了就关掉跳跃并说明。防火墙重启会清掉转发规则，巡检 `xray-node-watch` 每分钟补回来。新节点的端口不能落进别的节点的跳跃范围（`_hop_taken`，测试 `tests/test_hop_conflict.py`）。
7. **客户端填的是 IPv6 地址但节点只听 IPv4**：`Hysteria2 的 IPv4 / IPv6 双栈` 一节（`_hy_listen_for`、`_v6_listen_ok`）。
8. **服务器时间不对**：VMess 对时间敏感。

### 2.11 提问被自动跳过，或者报“没有读到你的选择”

- `ask()` 从标准输入读。脚本是被管道 / heredoc 喂给 sh 的时候，标准输入已经结束，`1. 必须是 root` 一节里会 `exec < /dev/tty` 把键盘接回来。没有终端（面板、cloud-init、`ssh 主机 '命令'`）时接不回来，`ask` 读失败就 `die`，不会把空输入当成回车。
- **不要把 `ask` 改成直接读 `/dev/tty`**：测试是用管道喂答案的，会卡住（有测试检查）。

### 2.12 重新运行时的问题（主菜单、更新内核）

- 主菜单在 `2d`。更新内核在 `内核升级` 和 `U. 更新模式` 两节：只装正式版（`_ver_stable`），先备份旧内核，下载失败就删备份并说明旧内核没动。
- 更新时顺带做的迁移都在 `阻止 QUIC` 一节后半段：`_quic_unblock_all`、`_hy_fix_existing_ipv6`、`_fix_existing_json_ipv6`、`_hy_migrate_hop_all`。老节点升级后出问题先看这几个函数。
- `gl` 命令先取最新的 install.sh，取不到用 `/etc/xray-node/install.sh`（`_write_gl_cmd`，测试 `tests/test_gl.py`）。

### 2.13 定时节点、设备数量限制

- 定时节点到点删除：`定时节点的“到点删除”程序` 一节，日志 `/var/log/xray-node-expire.log`，测试 `tests/test_expire.py`。
- 限制节点能连几台设备：`设备数量限制` 一节，小程序 `xray-node-limit`，日志 `/var/log/xray-node-limit.log`，测试 `tests/test_device_limit.py`。

---

## 3. 装好以后机器上有什么

| 路径 | 内容 |
|---|---|
| `/etc/xray-node/nodes/<编号>/` | 一个节点一个目录 |
| `…/config.json` 或 `config.yaml` | 内核配置（Xray、sing-box 用 json；官方 Hysteria2 用 yaml） |
| `…/core` | 这个节点用哪个内核：`xray` / `sing-box` / `hysteria` |
| `…/node.txt` | 给用户看的全部参数和链接，`jiedian all` 显示的就是它 |
| `…/name`、`…/link_port` | 节点名；NAT 小鸡的公网映射端口 |
| `…/fw_info` | 这个节点放行了哪些端口（第一行是“端口 协议”），删节点时照着撤销 |
| `…/hop` | Hysteria2 端口跳跃的范围 |
| `…/cert.pem`、`key.pem`、`pubpin` | 自签证书和它的指纹（Hysteria2 / TUIC） |
| `…/expire` | 定时节点的到期时间 |
| `/etc/xray-node/install.sh` | 上次运行的脚本副本，`gl` 断网时用 |
| `/etc/xray-node/our_bins` | 哪些内核是本脚本装的（卸载时只删这些） |
| `/etc/xray-node/rules.v4`、`rules.v6` | 存盘的防火墙规则 |
| `/usr/local/bin/xray`、`sing-box`、`hysteria` | 三个内核 |
| `/usr/local/bin/jiedian`、`shanjiedian`、`gl` | 三个快捷命令 |
| `/usr/local/bin/xray-node-watch` | 每分钟巡检：补端口跳跃规则、回程路由、证书续期时开关 80/443 |
| `/usr/local/bin/xray-node-hop`、`-route`、`-limit`、`-expire`、`-fw-restore`、`-run` | 端口跳跃、回程路由、设备限制、到点删除、开机恢复防火墙、启动包装 |
| `/var/log/xray-node-watch.log`、`-limit.log`、`-expire.log` | 后台小程序的日志 |
| `/etc/resolv.conf.xray-node-orig` | 换 DNS 之前的备份（没换过就没有） |

服务名：systemd 是 `xray-node@<编号>`、`hysteria-node@<编号>` 这类模板实例；Alpine（OpenRC）是 `xray-node-<编号>`，用 `rc-status` 看。

**所有后台小程序都是 install.sh 里用 heredoc 写出来的**（`install_hop_bin`、`install_route_bin`、`install_watch_bin`、`install_expire_bins`、`install_limit_bin`、`write_helper_cmds`、`_write_gl_cmd`）。改它们要改 install.sh 里的这些函数，不是改机器上的文件；用户重跑一次脚本就会被覆盖成新的。

---

## 4. 怎么在真机上复现（不要靠猜）

用户给了服务器就上去跑。本地测试用的是假命令，真机才有真的 busybox、真的网络。

**先看现场**（只读，不改东西）：

```sh
head -4 /etc/os-release; uname -m; free -m; df -h /
cat /etc/resolv.conf; ip route; ip -6 route
tail -5 ~/.ash_history ~/.bash_history 2>/dev/null   # 用户实际粘贴进去的是什么
ls -la /tmp/xray-install.sh /etc/xray-node 2>&1       # 脚本下载下来没有、装到哪一步
cat /sys/fs/cgroup/pids.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.events 2>/dev/null
```

`/tmp/xray-install.sh` 不存在，说明问题出在 README 的命令那一段，install.sh 根本没开始跑。

**跑 install.sh 并记下每一条命令**（全部回车用默认）：

```sh
curl -fsSL -o /tmp/xray-install.sh https://raw.githubusercontent.com/imthnio/VPS-dajianjiedian/main/install.sh
yes "" | sh -x /tmp/xray-install.sh > /root/run.out 2> /root/run.trace
tail -n 5 /root/run.trace     # 卡住时，最后一行就是卡住的那条命令
```

**这样跑通了不等于用户那边没问题。** 上面是管道喂输入，不经过终端。“粘贴被截断”“多粘了一行”这类问题只有真的往终端里粘贴才会出现。要用伪终端模拟粘贴：

```python
# 本机运行：python3 paste.py 命令文件
import os, pty, select, sys, time
data = open(sys.argv[1], 'rb').read()          # 文件里是 README 那一行，带结尾的换行
pid, fd = pty.fork()
if pid == 0:
    os.execvp('ssh', ['ssh', '-tt', '-p', '端口', 'root@服务器'])
def rd(t):
    out, end = b'', time.time() + t
    while time.time() < end:
        if select.select([fd], [], [], 0.3)[0]:
            out += os.read(fd, 65536)
    return out
rd(3)
for i in range(0, len(data), 512):             # 像终端一样分块送
    os.write(fd, data[i:i+512]); time.sleep(0.02)
print(rd(25).decode('utf8', 'replace')[-1500:]) # 末尾是 "> " 就是被截断了
os.write(fd, b'\x03')
```

测某个 shell 一行能收多少字符：粘贴 `echo xxxx…`（3000 个 x），看 `~/.ash_history` 里那一行的长度。

---

## 5. 测试文件对应什么

| 文件 | 管什么 |
|---|---|
| `tests/test_expire.py` | 定时节点；`InstallPromptTest` 里是 README 命令的全部用例（长度、只有一行、没 curl 时装 curl、各种 wget） |
| `tests/test_dns_bootstrap.py` | 换 DNS（README 命令和 install.sh 两份）、换镜像、下到一半的脚本不运行 |
| `tests/test_ip_input.py` | 公网 IP 检测和手动输入 |
| `tests/test_lowmem.py` | 小内存机器的解压和下载 |
| `tests/test_firewall_restore.py` | 防火墙规则存盘和开机恢复 |
| `tests/test_hop_conflict.py`、`test_hop_names.py` | 端口跳跃 |
| `tests/test_route.py` | UDP 回程路由 |
| `tests/test_watch.py` | 每分钟巡检 |
| `tests/test_device_limit.py` | 设备数量限制 |
| `tests/test_quic_client.py` | Loon / Surge 节点行、阻止 QUIC |
| `tests/test_gl.py` | `gl` 命令 |
| `tests/test_wgluodi.py` | 和 WireGuard 落地脚本的配合 |
| `tests/test_round_fixes.py` | 历次全面检查修掉的零散问题 |

README 命令的测试方法：`run_line` 把命令原样取出来，把 PATH 换成只有假命令的目录、把下载地址换成 `http://example.invalid/install.sh`、把 `/tmp/xray-install.sh` 换成临时文件，然后真的用 `/bin/sh -c` 跑。所以命令里这三段文字不能改写法：`PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"`、`R=/etc/resolv.conf;`、完整的 raw.githubusercontent.com 网址。

**测试测不到的**：真实终端的行长上限、真实 busybox 的行为、真实网络。所以改了 README 命令，除了跑测试，还要在一台 Alpine 上真的粘贴一次（第 4 节）。

---

## 6. 出过的故障（按时间倒序）

每一条写：用户看到什么 → 根本原因 → 怎么修的 → 教训。

| 现象 | 根本原因 | 修法 | 教训 |
|---|---|---|---|
| Alpine 上粘贴命令后“运行到一半卡住”，停在 `>` | 命令 2110 个字符，busybox ash 一行只收 2046 个，尾巴被丢掉。测试限制的是 2400 字节，依据是“终端一行 4096 字节”，这个依据对 busybox ash 不成立 | 命令缩到 1747 个字符，测试改成限制 1800 个字符 | 上限要在真机上量出来，不能照别处的数字推 |
| 同上，或第一个提问收到一行注释 | README 代码框里有 `#` 注释行，GitHub 复制按钮整框复制 | 代码框只留命令 | 代码框里的每一行用户都会粘贴 |
| 更新内核后重启，IPv6 防火墙规则丢了 | IPv6 规则没存盘 | `_save_fw` 两个地址族都存 | |
| 下载到一半断开，半截脚本被运行 | 只看了文件第一行是不是 `#!` | curl / wget 返回非零就不算成功 | 判断“成功”要看退出码，不能只看文件长相 |
| 换 DNS 后全部 `bad address`，而且改不回去 | 把 DNS 换成 1.1.1.1 但没验证；那台机器连不上 1.1.1.1 | 换完先验证，不通就还原；重跑能修好被旧命令改坏的 DNS | 改系统设置必须先验证、能还原 |
| 换了 DNS 过一会儿又变回去 | dhcpcd 续租时重写 resolv.conf | 同时写 `/etc/resolv.conf.head` | |
| Alpine 上五个网址全 `fail:`，看不出原因 | busybox wget 没有 `ssl_client` 下不了 https，但因为“有 wget”就没装 curl；报错又被 `2>/dev/null` 吞了 | 看 `wget -V` 是不是 GNU 版；失败时显示最后 3 行报错 | “命令存在”不等于“命令能用”；报错不能吞 |
| 粘贴后卡在 `>` | 命令超过 4096 字节（bash 下的终端单行上限） | 缩短 | 和第一条是同一类问题，当时只量了 bash |
| 新节点装上连不上 | 新节点的 UDP 端口落进了别的节点的端口跳跃范围，流量被转走 | `_hop_taken` 选端口时避开 | |
| Hysteria2 客户端填 IPv6 地址连不上 | 只听了 0.0.0.0 | 双栈监听 | |

---

## 7. 几个写死的数字，改之前先看这里

| 数字 | 在哪 | 为什么是这个数 |
|---|---|---|
| README 命令 < 1800 个字符 | `tests/test_expire.py` | busybox ash 一行上限 2046 个字符，留 200 多的余量 |
| 5 个下载网址 | README 命令的 `for u in …` | 直连 + 3 个镜像 + jsDelivr。加一个镜像大约多 25 到 60 个字符，先数 |
| `--connect-timeout 10 -m 120`、`-T 15 -t 2` | README 命令 | 一个网址最多等这么久；wget 以前重试太多次，看起来像卡死 |
| `apk add --wait 90` | README 命令 | 等别的 apk 进程放锁，不然直接报锁被占 |
| 随机端口 20000-59999 | `rand_port` | |
| 64MB / 128MB | `小内存机器` 一节 | 低于这个走省内存的路径 |
