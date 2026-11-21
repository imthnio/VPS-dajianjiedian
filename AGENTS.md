# 改这个项目之前，先把这份文件读完

> **不管你是人还是 AI（Claude、Codex、Cursor、Gemini、Copilot……），改任何代码、加任何功能、排查任何故障之前，先从头到尾读完这份文件，再动手。**
> 这里写的是这个项目吃过亏换来的规矩、完整排障手册和历史故障记录。跳过它，大概率会把已经修好的问题再弄坏一次。
> 本文件只写查得到的事实。行号会变，所以只写**章节标题和函数名**，用 `grep -n '标题或函数名' install.sh` 定位。
> **每次改完要回头更新本文件：** 修了一个新故障，就在第 7 节补上“现象 → 原因 → 改哪里”，第 9 节加一行。定了一条新规矩，也写进来。

---

## 1. 提交方式：直接推 main，不要分支，不要 PR

- **不建分支、不开 Pull Request。** 改完、测试通过，直接 `git commit` 到 `main`，然后 `git push origin main`。
- 原因：用户装节点用的是 README 里那一行命令，它直接下载 `main` 分支上的 `install.sh`。代码不在 `main` 上，就等于没修。
- 提交身份只写项目作者本人：
  ```
  imthnio <254405926+imthnio@users.noreply.github.com>
  ```
  提交前用 `git config user.email` 检查一下（注意中间是 `+`，不是 `.`）。
- **不加** `Co-Authored-By`、"Generated with ..." 之类的 AI 或第三方署名。
- 提交说明写中文，照着 `git log` 的风格：
  - 第一行一句话，说**用户会看到什么变化**（例如“只有 busybox wget 时先装 curl；下载失败显示真实报错”）。
  - 空一行，正文写**为什么**：之前出了什么问题、根本原因是什么、怎么改的。
- 推之前测试必须全部通过（见第 5 节）。

---

## 2. 项目结构与装完后机器上的文件

给小白用的一键搭代理节点脚本：SSH 连上 VPS，粘贴 README 里的一行命令，全程中文提问，一路回车也能装好。

| 仓库文件 | 作用 |
|---|---|
| `README.md` | 给用户看的说明，内容尽量少。**里面那一行安装命令是唯一入口**：自动识别系统、没 curl 先装、DNS 坏了换、GitHub 连不上换镜像，然后下载 `install.sh` 运行。 |
| `install.sh` | 全部逻辑，一个 POSIX sh 文件，约 8000 行。装节点、更新内核、节点管理都在这里。开头是很长的注释（用法和“名词小词典”），后面按 `# ---------- 编号. 标题 ----------` 分节（搜 `# ----------` 看目录）。 |
| `AGENTS.md` | 本文件：给所有 AI 和维护者看的唯一手册（开发规矩 + 排障手册 + 历史故障）。 |
| `tests/*.py` | Python unittest。从 `install.sh` / `README.md` 里切出片段，用假命令（stub）在本机跑。 |

**装好以后服务器上的文件清单：**

| 路径 | 内容 |
|---|---|
| `/etc/xray-node/nodes/<编号>/` | 一个节点一个目录，互不影响 |
| `…/config.json`、`config.yaml` 或 `config.conf` | 内核配置（Xray、sing-box 用 json；官方 Hysteria2 用 yaml；Snell v4/v5 用 conf） |
| `…/core` | 这个节点用哪个内核：`xray` / `sing-box` / `hysteria` / `snell-v4` / `snell-v5` |
| `…/node.txt` | 给用户看的全部参数和链接，`jiedian all` 显示的就是它 |
| `…/name`、`…/link_port` | 节点名；NAT 小鸡的公网映射端口 |
| `…/fw_info` | 这个节点放行了哪些端口（第一行是“端口 协议”），删节点时照着撤销 |
| `…/hop` | Hysteria2 端口跳跃的范围 |
| `…/cert.pem`、`key.pem`、`pubpin` | 自签证书和它的指纹（Hysteria2 / TUIC） |
| `…/expire` | 定时节点的到期时间 |
| `/etc/xray-node/install.sh` | 上次运行的脚本副本，`gl` 断网时用 |
| `/etc/xray-node/our_bins` | 哪些内核是本脚本装的（卸载时只删这些） |
| `/etc/xray-node/rules.v4`、`rules.v6` | 存盘的防火墙规则 |
| `/usr/local/bin/xray`、`sing-box`、`hysteria`、`snell-server-v4`、`snell-server-v5` | 各协议对应的内核 |
| `/usr/local/bin/jiedian`、`shanjiedian`、`gl` | 三个快捷命令（`gl` 打开主菜单，先取最新 `install.sh`，取不到用 `/etc/xray-node/install.sh`） |
| `/usr/local/bin/xray-node-watch` | 每分钟巡检：补端口跳跃规则、回程路由、证书续期时开关 80/443 |
| `/usr/local/bin/xray-node-hop`、`-route`、`-limit`、`-expire`、`-fw-restore`、`-run` | 端口跳跃、回程路由、设备限制、到点删除、开机恢复防火墙、启动包装 |
| `/var/log/xray-node-watch.log`、`-limit.log`、`-expire.log` | 后台小程序的日志 |
| `/etc/resolv.conf.xray-node-orig` | 换 DNS 之前的备份（没换过就没有） |

- 服务名：systemd 是 `xray-node@<编号>`、`hysteria-node@<编号>`、`singbox-node@<编号>`、`snell-v4-node@<编号>`、`snell-v5-node@<编号>` 模板实例；Alpine（OpenRC）是 `xray-node-<编号>`，用 `rc-status` 看。
- **所有后台小程序都是 `install.sh` 里用 heredoc 写出来的**（`install_hop_bin`、`install_route_bin`、`install_watch_bin`、`install_expire_bins`、`install_limit_bin`、`write_helper_cmds`、`_write_gl_cmd`）。改它们要改 `install.sh` 里的这些函数，不是改机器上的文件；用户重跑一次脚本就会被覆盖成新的。

---

## 3. 硬性约束（每一条都踩过坑）

### 运行环境

- **只用 POSIX sh。** 脚本要在 dash（Debian/Ubuntu）、busybox ash（Alpine）里跑，不能用 bash 专有写法：
  - 不能用 `[[ ]]`、数组、`${var//a/b}`、`<<<`、`function` 关键字、`local`、`source`。
  - 改完跑 `sh -n install.sh`，有 dash 的话再跑 `dash -n install.sh`。
- **要兼容 busybox 版本的命令。** Alpine、NAT 小鸡上的 `grep`、`sed`、`awk`、`wget`、`ps`、`ip` 都可能是 busybox 版，GNU 专有选项（如 `grep` 的 BRE `\|`、busybox `wget -t`）会直接报错或失效。用到 GNU 专有选项时，先检测，再给退路。
- **“命令存在”不等于“命令能用”。** 典型例子：busybox `wget` 没装 `ssl_client` 时下不了任何 https，但 `command -v wget` 照样成功。判断“能不能干活”要看真实能力（比如 `wget -V | grep 'GNU Wget'`），别只看有没有这个命令。
- **64MB 内存的机器也要装得上。** 解压、下载要边下边落盘，别把整个文件读进内存。见 `install.sh` 的“小内存机器”一节。
- 支持的系统：Debian / Ubuntu / Alpine（OpenRC）/ CentOS / Arch，x86_64 和 ARM64。还有只有 IPv6、没有 curl、PATH 不全的精简 NAT / LXC 小鸡。

### README 里的安装命令

- **只有一条，不要再加 `bash <(curl …)` 那种短命令。** Alpine 默认没有 bash 也没有 curl，短命令在那里根本跑不起来。所有“自动识别”都必须放在这一行里。
- README 只放这一行和必要的几句话，不要写长篇说明（作者要求）。
- **必须是一行**，不能用 heredoc（`<<`），否则粘贴后会卡在 `>` 提示符。
- **长度必须少于 1800 个字符**（有测试）。Alpine 的 busybox ash 一行只收 2046 个字符，多出来的直接丢掉，命令没收尾就停在 `>`，用户看到的是“运行到一半卡住”。往命令里加东西之前先数：`grep '^PATH=' README.md | python3 -c 'import sys; print(len(sys.stdin.read().strip()))'`。
- **代码框里只能有这一行命令**，不能有 `#` 注释行。GitHub 的复制按钮会复制整个代码框，多出来的行会被粘贴进终端，被当成对安装提问的回答。步骤说明写在代码框外面。
- 改了这条命令，除了跑测试，还要在一台 Alpine 上真的粘贴一次（测试用的是 `sh -c`，不经过终端，量不出行长上限，做法见第 8 节）。
- 必须能在 dash 里解析通过（有测试）。
- 每一步先打一行字（`[1/3] 检查 DNS` 这种），否则用户会以为卡死了。
- **出错时必须让用户看得到真实报错。** 不要用 `2>/dev/null` 把错误整个吞掉。失败时至少打出最后几行错误，这样用户把输出发来，一眼就能看出原因。

### 跟用户交互

- 所有提示、报错都写**中文大白话**，面向完全不懂 Linux 的人。
- 每个问题都要有默认值，回车就能继续。
- `ask()` 从标准输入读，不要改成读 `/dev/tty`（有测试检查）。
- 加了新功能，要同步更新：`install.sh` 开头的用法注释、装完时打印的提示（用户从这里知道 `jiedian`、`shanjiedian`、`gl` 怎么用），必要时还有“名词小词典”。**README 不写功能说明。**

---

## 4. 修 bug 的规矩 & 动手前快速检查

### 修 bug 原则：先找到根本原因，再动手

这个项目吃过的亏：同一个“安装脚本下载不下来”的问题，前后修了好几次（换 DNS、加镜像、改重试次数），都没修好。原因有三个：
1. **报错被藏起来了。** 下载那一步用了 `2>/dev/null`，用户贴回来的只有一串 `fail:`，每次修复都是在猜。
2. **测试把错误的假设锁死了。** 有个用例的假 busybox wget 下 https 总能成功，还专门检查“只有 busybox wget 时不能装 curl”，结果正确的修法反而让测试失败。
3. **测试在 macOS 上跑不全**（只链接了 `/bin`，`grep`、`sed`、`tail` 在 `/usr/bin`），有些路径实际没测到。

所以：
- 先查第 6、7 节：按屏幕上最后一行字找到出问题的章节，看是不是出过的故障。
- 用户报故障时，先从他贴的输出里找证据（系统是什么、哪一步没打字、哪一步失败）。证据不够，先让输出能说清原因，而不是再猜一个修法。
- 写假命令（stub）时，要模仿真实程序**会失败的样子**，不能只模仿成功。
- 测试与真实行为冲突时，改测试，不要为了让测试通过而保留错误行为。
- **改系统设置（DNS、防火墙、软件源等）必须先验证改完能用，不能用就还原。**
- 安装命令和 `install.sh` 里有两份换 DNS 的逻辑，改一份要对照另一份，两边都要有测试（`tests/test_dns_bootstrap.py`）。

### 动手前快速检查清单

- [ ] 读完了本文件
- [ ] 只用了 POSIX sh，busybox 也能跑
- [ ] 用户看到的文字是中文大白话，问题都有默认值
- [ ] 出错时报错能显示给用户，没有被吞掉
- [ ] 改了功能就同步了 `install.sh` 开头的注释和装完时的提示（README 保持只有一行命令）
- [ ] `sh -n install.sh` 和全部测试通过
- [ ] 修的是故障：已经把现象、原因、改法补进本文件第 7、9 节
- [ ] 改了 README 的安装命令：字符数少于 1800，并且在 Alpine 上真的粘贴过一次
- [ ] 以 `imthnio` 的身份直接提交到 `main` 并推送，没有分支、没有 PR、没有 AI 署名

---

## 5. 测试与测试文件对照表

```bash
sh -n install.sh
dash -n install.sh   # 有 dash 时跑一下
cd tests && python3 -m unittest discover
```

- 两百多个用例，大约 1 到 2 分钟跑完，**必须全部通过才能推送**。macOS 和 Linux 都能跑。
- 测试用 `between("开始标记", "结束标记")` 从 `install.sh` 里切出函数单独运行。**这些标记就是 `install.sh` 里的注释行或函数开头**（例如 `# 有没有 IPv4 默认路由`、`_have_curl() {`）。改了这些注释或函数名，对应测试会找不到片段而失败，要同时改测试。
- README 里的安装命令会被测试原样取出来运行（换掉下载地址和 PATH），所以命令里这三段文字不能改写法：`PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"`、`R=/etc/resolv.conf;`、完整的 `raw.githubusercontent.com` 网址。
- 修 bug 时，先写一个能复现这个 bug 的用例，再修。
- **测试测不到的**：真实终端的行长上限、真实 busybox 的行为、真实网络。改了 README 命令要在 Alpine 真机粘贴验证（见第 8 节）。

| 测试文件 | 管什么 |
|---|---|
| `tests/test_expire.py` | 定时节点；`InstallPromptTest` 里是 README 命令的全部用例（长度、只有一行、没 curl 时装 curl、各种 wget） |
| `tests/test_dns_bootstrap.py` | 换 DNS（README 命令和 `install.sh` 两份）、换镜像、下到一半的脚本不运行 |
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
| `tests/test_snell.py` | Snell v4 / v5 下载、校验、配置、客户端行、生命周期与全面检查修复回归 |
| `tests/test_round_fixes.py` | 历次全面检查修掉的零散问题 |

---

## 6. 一次安装从头到尾走哪些步骤

**判断卡在哪：看屏幕上最后一行字，对下表找到章节。**

### 第一段：README 里的安装命令（在用户的交互 shell 里直接执行）

| 屏幕上打的字 | 在做什么 | 失败时的表现 |
|---|---|---|
| （什么都没打，停在 `>`） | 命令没被 shell 完整收到 | 见 7.1 |
| `[1/3] 检查 DNS` | `getent hosts github.com` 或 `nslookup github.com`。解析不了就把 `/etc/resolv.conf` 换成公共 DNS（没有 IPv4 默认路由的机器换成 DNS64），换完再验证，还不通就还原 | `公共 DNS 也不通，DNS 已还原` |
| `[2/3] 装 curl` | 只有“没有 curl，wget 也不是 GNU 版”时才出现。依次试 apt-get / apk / dnf / yum / pacman | 包管理器自己的报错原样显示 |
| `[3/3] 下载 <网址>` | 依次试 5 个网址：GitHub 直连、3 个镜像、jsDelivr。有 curl 用 curl，否则用 wget。下载到 `/tmp/xray-install.sh`，退出码为 0 且第一行是 `#!` 才算成功 | 每个失败的网址打一行 `fail: <网址>` 和最后 3 行真实报错；全失败打 `安装脚本没下载下来` |
| 之后的字都来自 `install.sh` | `sh /tmp/xray-install.sh` | |

### 第二段：`install.sh`（按 `# ---------- 编号. 标题 ----------` 顺序往下走）

| 屏幕上打的字 | `install.sh` 里的章节 |
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
| `[下载] 获取 Xray 内核…` | `8. 下载内核`（`dl_xray` / `dl_singbox` / `dl_hysteria` / `dl_snell`，GitHub 下载走 `_gh_get`、校验走 `_verify_dl`，Snell 走 `dl.nssurge.com` + 内置 SHA256） |
| `[密钥] 生成 REALITY 密钥…` | `9. REALITY 密钥对` |
| `[检查] 验证伪装域名从这台 VPS 是否可用…` | `9c. REALITY 伪装域名可用性检查` |
| `[配置] 写入配置…` | `10. 写配置文件`（Hysteria2、sing-box 各有单独一节） |
| `[服务] 设置开机自启…` | `11. 开机自启`（`_svc_install`）和 `11b. 硬检查：端口必须真的在监听`（`wait_for_port`、`_svc_recheck`） |
| 放行端口的提示 | `12. 放行端口`（`_fw_allow`、`_save_fw`） |
| `[完成] 生成你的节点…` | `13. 生成节点链接`、`14. 保存 + jiedian 命令`（`write_helper_cmds`） |
| `检查 BBR 加速…` | `14b. BBR 加速` |
| `节点 N 安装完成` | `15. 显示结果` |

---

## 7. 排障手册：现象 → 原因 → 改哪里

### 7.1 粘贴后什么都不运行，光标停在 `>`（用户说“运行到一半卡住”）

- **原因**：shell 没收到完整的命令，还在等后半句。已经确认过的两种来源：
  1. **命令太长被截断。** Alpine 的登录 shell 是 busybox ash，它的行编辑器一行最多收 **2046 个字符**（实测 Alpine 3.20，busybox 1.36.1；中文算 1 个字符），多出来的直接丢掉。命令尾巴没了，`case … esac`、`for … done` 没收尾，就停在 `>`。bash（Debian / Ubuntu / CentOS）没有这个上限，所以只有 Alpine 出问题，很容易漏测。
  2. **命令里有 heredoc（`<<`）或没配对的引号。**
- **证据怎么拿**：服务器上 `awk '{print length($0)}' ~/.ash_history` 看最后几行长度。正好 2046 就是被截断了。`sed -n '$p' ~/.ash_history | tail -c 200` 能看到截在哪。
- **怎么改**：缩短 README 里的命令。现在是 1781 个字符，测试限制在 1800 以内（`tests/test_expire.py` 的 `readme_command`）。超了就砍别的，不要去放宽测试里的上限。
- **已经用掉的省字办法**：`;` 后面不留空格；`h(){ q command -v $1; }` 代替重复的 `q command -v`；apt 的两次尝试合成函数 `i`；去掉了 zypper 和下载全失败后的 ping 诊断。
- **还要注意**：命令里不能有 Tab 字符（交互 shell 里会触发补全）；`!` 后面要跟空格或在单引号里（bash 交互模式会把 `!词` 当历史展开）。

### 7.2 粘贴后第一个问题就报“输入不对”，或者多出一行 `# 3. 按提示回答问题…`

- **原因**：GitHub 代码框右上角的复制按钮会复制**整个代码框**，多出来的行会被当成对安装提问的回答。
- **怎么改**：README 的 ```` ```bash ```` 代码框里**只放那一行命令**，步骤说明写在代码框外面。测试 `readme_command` 检查代码框只有一行。

### 7.3 `[1/3] 检查 DNS` 之后很久没动静

- `getent` / `nslookup` 在等 DNS 超时。resolv.conf 里每个 nameserver 都不通时，要等“nameserver 个数 × 超时秒数 × 重试次数”。
- 看 `/etc/resolv.conf`、`ip route`、`ip -6 route`。只有 IPv6 的机器应该被换成 `2a00:1098:2b::1`（DNS64）。
- 逻辑有两份，改一份要对照另一份：README 命令里的那段，和 `install.sh` 的 `_dns_fix_broken`（`DNS 坏了` 一节）。测试在 `tests/test_dns_bootstrap.py`。
- 备份文件是 `/etc/resolv.conf.xray-node-orig`；有 dhcpcd 的机器还会写 `/etc/resolv.conf.head`（不然 dhcpcd 续租时把 resolv.conf 冲回去）。

### 7.4 `[3/3] 下载` 五个网址全是 `fail:`

- 先看每个 `fail:` 下面的 3 行报错，不要猜：

| 报错里的字 | 原因 | 改哪里 |
|---|---|---|
| `bad address` / `Could not resolve host` | DNS 不通 | 7.3 |
| `ssl_client` / `not an http or ftp url` / `TLS` | wget 是 busybox 版，没装 `ssl_client`，下不了 https | 命令里 `[2/3] 装 curl` 的判断条件（看 `wget -V` 是不是 `GNU Wget`） |
| `Network unreachable` / `Connection timed out`，只在直连那一行 | 只有 IPv6 的机器连不上 GitHub，或 GitHub 被墙 | 正常，后面的镜像会接上。镜像也全挂了就换镜像列表 |
| `404` / `403` | 镜像站下线或改规则了 | 换掉那个镜像（命令里的 `for u in …`；`install.sh` 里的 `GH_MIRRORS`，两边一起改） |
| `transfer closed` / 退出码 18 | 下到一半断了 | 已处理：curl 返回非零就不算成功，换下一个网址 |

- 下载成功的判断是“curl 或 wget 返回 0，文件非空，第一行以 `#!` 开头”。镜像站返回一个 HTML 错误页时，靠第一行不是 `#!` 挡住。

### 7.5 `[准备] 检查系统工具…` 卡住或失败

- 章节 `2. 装依赖`。apt 被别的进程锁住、dpkg 上次没配置完、软件源连不上（只有 IPv6 的机器）都在这里处理：`_apt_do`、`_timeout_cmd`（没有 `timeout` 命令时自己用后台进程加 `kill` 实现）。
- Alpine：`apk add --wait 90`，等别的 apk 进程放锁最多 90 秒。
- 失败时走 `_dep_fail`，必须把包管理器的真实报错显示出来。

### 7.6 `正在检测公网 IP…` 卡住，或地址不对

- `get_ip`（`0. 打印小工具` 一节）。依次问几个查 IP 的网站，每个都有超时。NAT 小鸡只有 busybox wget 时也要能查到。
- 查不到会让用户手动输入，可以填 IP 也可以填域名（`_valid_ip`、`_valid_host`、`_resolve_host`）。测试在 `tests/test_ip_input.py`。
- 地区查不到只影响默认节点名（`_geo_cc`、`_cc_name`），不影响安装。

### 7.7 `[下载] 获取 … 内核…` 卡住或失败

- 章节 `下载三个内核`、`下载 Snell 内核（v4 / v5）` 和 `下载工具` 三节。顺序：查最新版 → 下载 → SHA256 校验（`_gh_expect_sum` / `_snell_expect_sum`、`_verify_dl`）→ 解压 → 试运行确认能用。
- GitHub 连不上：`_gh_get` 自动换镜像；只有 IPv6 的机器临时开 DNS64（`_dns64_on` / `_dns64_off`，脚本中途被杀掉时下次启动由 `_dns64_recover` 还原）。`dl.nssurge.com` 也只有 IPv4，纯 IPv6 机器由 `_snell_prepare` 临时开 DNS64。
- 官方 `snell-server` 依赖 glibc，Alpine（musl）原生跑不起来；`_snell_bin_ok` 试运行失败时会直接给出中文说明。
- 小内存机器（64MB / 128MB）：`小内存机器的特殊处理` 一节。`prepare_low_memory` 会加 swap、清缓存；解压用 `_unpack_drip` 边解边写盘，不把整个文件读进内存。sing-box 解压后约 80MB，64MB 的机器装不下，会明说。测试在 `tests/test_lowmem.py`。
- 被 OOM 杀掉的表现是进程突然消失、没有报错。用 `dmesg | tail`、容器里看 `/sys/fs/cgroup/memory.events` 的 `oom_kill`。

### 7.8 `[检查] 验证伪装域名…` 不通过

- 章节 `9c`。从这台 VPS 对伪装域名做一次 TLS 1.3 握手。不通过说明这台机器访问不了那个网站，换一个伪装域名即可，不是脚本的 bug。

### 7.9 `[服务] 设置开机自启…` 之后报“端口没有在监听”

- 章节 `11` 和 `11b`。`_svc_install` 按系统选 systemd 模板服务或 OpenRC 服务（Alpine）；`wait_for_port` 等端口起来；`_svc_recheck` 再查一遍。
- 查法：systemd 用 `systemctl status xray-node@<编号>`（Hysteria2 是 `hysteria-node@<编号>`）和 `journalctl -u … -n 50`；OpenRC 用 `rc-service xray-node-<编号> status`，日志在 `/var/log/xray-node-*`。
- 手动跑一次内核最直接：`/usr/local/bin/xray run -c /etc/xray-node/nodes/<编号>/config.json`，报错会直接打出来。
- 没装完的节点目录下次运行时由 `2a. 清理上次没装完的半截节点` 自动清掉（`_reap_partial_nodes`）。

### 7.10 装完了，客户端连不上

按这个顺序查，前一步通过再查后一步：
1. **服务在不在跑、端口在不在听**：`ss -lntup | grep <端口>`（没有 ss 用 `netstat -lntup`）。
2. **服务器自己的防火墙**：`12. 放行端口`（`_fw_allow`）。规则存盘走 `_save_fw`，重启后由 `/usr/local/bin/xray-node-fw-restore` 恢复，存盘文件是 `/etc/xray-node/rules.v4`、`rules.v6`。测试在 `tests/test_firewall_restore.py`。
3. **云厂商的安全组**：脚本改不到，装完的提示里会让用户自己去控制台放行。
4. **NAT 小鸡的端口映射**：服务商给的公网端口和节点端口不一样时，要在“公网映射端口”那一问里填公网端口（存在节点目录的 `link_port`）。
5. **UDP 节点（Hysteria2 / TUIC / Shadowsocks）回程走错网卡**：多网卡、多 IP 的机器。小程序 `xray-node-route` 负责加策略路由，`回程路由小程序` 一节，测试在 `tests/test_route.py`。
6. **端口跳跃失效**：Hysteria2。LXC / OpenVZ 小鸡常常没有 nat 转发权限，`_hy_hop_probe` 会先试，做不了就关掉跳跃并说明。防火墙重启会清掉转发规则，巡检 `xray-node-watch` 每分钟补回来。新节点的端口不能落进别的节点的跳跃范围（`_hop_taken`，测试 `tests/test_hop_conflict.py`）。
7. **客户端填的是 IPv6 地址但节点只听 IPv4**：`Hysteria2 的 IPv4 / IPv6 双栈` 一节（`_hy_listen_for`、`_v6_listen_ok`）。
8. **服务器时间不对**：VMess 对时间敏感。

### 7.11 提问被自动跳过，或者报“没有读到你的选择”

- `ask()` 从标准输入读。脚本是被管道 / heredoc 喂给 sh 的时候，标准输入已经结束，`1. 必须是 root` 一节里会 `exec < /dev/tty` 把键盘接回来。没有终端（面板、cloud-init、`ssh 主机 '命令'`）时接不回来，`ask` 读失败就 `die`，不会把空输入当成回车。
- **不要把 `ask` 改成直接读 `/dev/tty`**：测试是用管道喂答案的，会卡住（有测试检查）。

### 7.12 重新运行时的问题（主菜单、更新内核、定时节点、设备限制）

- 主菜单在 `2d`。更新内核在 `内核升级` 和 `U. 更新模式` 两节：只装正式版（`_ver_stable`），先备份旧内核，下载失败就删备份并说明旧内核没动。
- 更新时顺带做的迁移都在 `阻止 QUIC` 一节后半段：`_quic_unblock_all`、`_hy_fix_existing_ipv6`、`_fix_existing_json_ipv6`、`_hy_migrate_hop_all`。老节点升级后出问题先看这几个函数。
- `gl` 命令先取最新的 `install.sh`，取不到用 `/etc/xray-node/install.sh`（`_write_gl_cmd`，测试 `tests/test_gl.py`）。
- 定时节点到点删除：`定时节点的“到点删除”程序` 一节，日志 `/var/log/xray-node-expire.log`，测试 `tests/test_expire.py`。
- 限制节点能连几台设备：`设备数量限制` 一节，小程序 `xray-node-limit`，日志 `/var/log/xray-node-limit.log`，测试 `tests/test_device_limit.py`。

---

## 8. 怎么在真机上复现（不要靠猜）

用户给了服务器就上去跑。本地测试用的是假命令，真机才有真的 busybox、真的网络。

**先看现场**（只读，不改东西）：

```sh
head -4 /etc/os-release; uname -m; free -m; df -h /
cat /etc/resolv.conf; ip route; ip -6 route
tail -5 ~/.ash_history ~/.bash_history 2>/dev/null   # 用户实际粘贴进去的是什么
ls -la /tmp/xray-install.sh /etc/xray-node 2>&1       # 脚本下载下来没有、装到哪一步
cat /sys/fs/cgroup/pids.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.events 2>/dev/null
```

`/tmp/xray-install.sh` 不存在，说明问题出在 README 的命令那一段，`install.sh` 根本没开始跑。

**跑 `install.sh` 并记下每一条命令**（全部回车用默认）：

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

## 9. 历史故障记录与写死的数字

### 出过的故障（按时间倒序）

| 现象 | 根本原因 | 修法 | 教训 |
|---|---|---|---|
| IPv6 机器上 UDP 443 节点开启 1 台设备限制后，服务器本机发起 IPv6 QUIC 出站仍可能把用户挤掉 | `/proc/net/nf_conntrack` 记录展开的 8 段 IPv6（如 `2001:0db8:0000:...`），`ip -o addr show` 输出压缩 IPv6（`2001:db8::1`），直接字符串比对失配 | `xray-node-limit` 的 `_seen` 增加 `norm()` 把 IPv6 统一展开成规范 8 段后再存入/比对 `loc` | 比对内核表和 `ip` 输出的 IPv6 地址必须先规范化，不能直接字符串相等 |
| 双栈机器新装 Xray / sing-box / Snell 节点在纯 iptables 防火墙上 IPv6 连不上 | 新装时节点已监听 `::` / `::0`，但第 12 节 `_FW_FAMILIES` 只对 Hysteria2 放行双栈，其它协议漏加 `ip6tables` 规则 | 第 12 节按实际双栈监听状态统一设置 `_FW_FAMILIES`（`4 6` / `6 4`），并在安全组提示标明 TCP/UDP 与映射端口 | 监听双栈就必须同步放行 IPv4/IPv6 两个地址族的防火墙 |
| 换 DNS 失败还原后 `/etc/resolv.conf` 变成 `0600`；systemd 单元文件与 `99-xray-node-overcommit.conf` 权限为 `0600`；acme.sh 续期部署私钥时短时 `0644` | 主脚本 `umask 077` 下新建/还原的系统文件未显式 `chmod 644`；`xray-node-watch` 在默认 `umask 022` 下先写私钥再 `chmod` | `_resolv_restore`、overcommit sysctl 配置及所有生成的 systemd unit/timer 显式 `chmod 644`；`_acmesh_deploy` 在子 shell `umask 077` 下写私钥再按组设 `640`/`600` | `umask 077` 写系统文件必 `chmod 644`，非 `umask 077` 的后台脚本写私钥必先收紧 `umask` |
| 全新机器装到第 12 节放行端口后在写 `node.txt` 前失败，已放行的防火墙规则未撤销；无 `ss` 机器上端口跳跃范围跳过占用检查；非 Debian/Alpine 纯 iptables 重启丢规则 | `_drop_partial_node` 依赖尚未安装的 `xray-node-watch`；`_hy_hop_busy` 无 `ss` 直接放行；`_save_fw` 对非 apt/Alpine 系统未回退 `_save_fw_light` | `_drop_partial_node` 缺 `xray-node-watch` 时先写出再撤销；`_hy_hop_busy` 补充 `netstat` 与 `/proc/net/udp*` 回退；`_save_fw` 在 systemd/OpenRC 上回退 `_save_fw_light` | 清理、检测、持久化路径都要考虑工具缺失和非 Debian 发行版 |
| UDP 443 节点开启 1 台设备限制后，正常用户在访问 QUIC 站点时自己被挤掉 | 服务器自己往外连 UDP 443 时，`nf_conntrack` 的回包 `sport=443`，`_seen` 把服务器本机 IP 当成第二台客户端设备 | `_seen` 先读本机网卡地址，排除 `src` 为本机地址的出站连接 | 解析 `nf_conntrack` 时必须区分客户端入站和本机同端口出站 |
| Hysteria2 填域名、不开混淆且节点端口选 443（或 80）时，证书到期后续期失败 | `HY_TCP_MASQ=1` 让 Hysteria2 长期占用 TCP `$PORT`，与 `acme.sh` 续期临时监听端口冲突 | `$PORT` 等于 `acme.sh` 验证端口（80 或 443）时不开启 `HY_TCP_MASQ` | 节点 TCP 伪装监听不能占用 ACME 独立验证端口 |
| 关闭 IPv6 后，以 `xray-node` 普通用户运行的 Hysteria2 读不到 `/etc/gai.conf` | 脚本开头 `umask 077`，新建 `/etc/gai.conf`（及 cron 文件）权限为 `0600` | `_ipv6_gai`、`_ipv6_sysctl_block`、`_ipv6_persist` 和 `/etc/cron.d/*` 写完显式 `chmod 644` | `umask 077` 下写给系统或非 root 进程读的文件必须显式 `chmod 644` |
| Alpine 下载失败只显示 BusyBox `Usage: wget` 盖住 curl 报错；或带 `ssl_client` 的 busybox wget 仍失败 | `curl` 失败后仍无条件跑 `wget -t 2`（`gl` 里是 `wget -t 1`），而 busybox wget 不认 `-t` | 有 `curl` 时只跑 `curl`；只有 GNU wget 才传 `-t`（README 命令和 `_write_gl_cmd` 同步） | 兜底命令不能在主命令失败时无条件覆盖报错；GNU 专有选项要先测再传 |
| 常规 Debian/Ubuntu/Alma/Alpine 报“当前内核不支持 BBR” | 多数发行版把 `tcp_bbr` 编成模块，加载前不在 `tcp_available_congestion_control` 里 | 检查前先 `modprobe tcp_bbr` | 内核能力检查前要考虑可加载模块 |
| VMess 中文节点链接在严格客户端导入失败 | `vmess://` 用了 URL-safe 去填充的 `b64url`（`-`/`_` 且无 `=`），标准要求标准 Base64 | `vmess://` 改为 `base64 \| tr -d '\n'` | 协议链接编码要按客户端标准（标准 Base64 vs Base64URL） |
| 老版 Hysteria2 节点在新增第二个 Hysteria2 节点后重启报 `Permission denied` | 共享模板 `hysteria-node@.service` 切成 `User=xray-node`，但 `_svc_install` 只改了新节点目录权限 | `_svc_install` 切 `xray-node` 时同步给全部已有 Hysteria2 节点调 `_hy_perms` | 改共享 systemd 模板的运行用户时，必须同步迁移所有已有实例的权限 |
| 纯 IPv6 或带 AAAA 记录的域名申请 Hysteria2 正式证书总是 `Connection refused` | `_hy_acmesh_issue` 没传 `--listen-v6`，`acme.sh` 只听 IPv4 | `IPVER=6` 或 `_v6_listen_ok` 时给 `acme.sh` 加 `--listen-v6` | Let's Encrypt 优先连 AAAA，证书申请监听也要双栈 |
| 用 IPv6 SSH 关 IPv6 时脚本中途被杀，节点改到一半、IPv6 又开着 | `_ipv6_turn_off` 试写完立刻 `trap - HUP`，还没改节点和写开机配置就收到 SSH 断连的 `SIGHUP` | 整个 `_ipv6_turn_off` 期间保持 `trap '' HUP`，结束前再恢复 | 断开当前连接的操作要把 `HUP` 忽略延续到全部收尾完成 |
| Alpine 上粘贴命令后“运行到一半卡住”，停在 `>` | 命令 2110 个字符，busybox ash 一行只收 2046 个，尾巴被丢掉。测试限制的是 2400 字节，依据是“终端一行 4096 字节”，这个依据对 busybox ash 不成立 | 命令缩到 1781 个字符，测试改成限制 1800 个字符 | 上限要在真机上量出来，不能照别处的数字推 |
| 同上，或第一个提问收到一行注释 | README 代码框里有 `#` 注释行，GitHub 复制按钮整框复制 | 代码框只留命令 | 代码框里的每一行用户都会粘贴 |
| 更新内核后重启，IPv6 防火墙规则丢了 | IPv6 规则没存盘 | `_save_fw` 两个地址族都存 | |
| 下载到一半断开，半截脚本被运行 | 只看了文件第一行是不是 `#!` | curl / wget 返回非零就不算成功 | 判断“成功”要看退出码，不能只看文件长相 |
| 换 DNS 后全部 `bad address`，而且改不回去 | 把 DNS 换成 1.1.1.1 但没验证；那台机器连不上 1.1.1.1 | 换完先验证，不通就还原；重跑能修好被旧命令改坏的 DNS | 改系统设置必须先验证、能还原 |
| 换了 DNS 过一会儿又变回去 | dhcpcd 续租时重写 resolv.conf | 同时写 `/etc/resolv.conf.head` | |
| Alpine 上五个网址全 `fail:`，看不出原因 | busybox wget 没有 `ssl_client` 下不了 https，但因为“有 wget”就没装 curl；报错又被 `2>/dev/null` 吞了 | 看 `wget -V` 是不是 GNU 版；失败时显示最后 3 行报错 | “命令存在”不等于“命令能用”；报错不能吞 |
| 粘贴后卡在 `>` | 命令超过 4096 字节（bash 下的终端单行上限） | 缩短 | 和 Alpine 截断是同一类问题，当时只量了 bash |
| 新节点装上连不上 | 新节点的 UDP 端口落进了别的节点的端口跳跃范围，流量被转走 | `_hop_taken` 选端口时避开 | |
| Hysteria2 客户端填 IPv6 地址连不上 | 只听了 0.0.0.0 | 双栈监听 | |

### 几个写死的数字，改之前先看这里

| 数字 | 在哪 | 为什么是这个数 |
|---|---|---|
| README 命令 < 1800 个字符 | `tests/test_expire.py` | busybox ash 一行上限 2046 个字符，留 200 多的余量 |
| 5 个下载网址 | README 命令的 `for u in …` | 直连 + 3 个镜像 + jsDelivr。加一个镜像大约多 25 到 60 个字符，先数 |
| `--connect-timeout 10 -m 120`、`-T 15 -t 2` | README 命令 | 一个网址最多等这么久；wget 以前重试太多次，看起来像卡死 |
| `apk add --wait 90` | README 命令 | 等别的 apk 进程放锁，不然直接报锁被占 |
| 随机端口 20000-59999 | `rand_port` | |
| 64MB / 128MB | `小内存机器` 一节 | 低于这个走省内存的路径 |
