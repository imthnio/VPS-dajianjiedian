# 改这个项目之前，先把这份文件读完

> **不管你是人还是 AI（Claude、Codex、Cursor、Copilot……），改任何代码、加任何功能之前，先从头到尾读完这份文件，再动手。**
> 这里写的是这个项目吃过亏换来的规矩。跳过它，大概率会把已经修好的问题再弄坏一次。

`CLAUDE.md`、`GEMINI.md`、`.cursorrules`、`.github/copilot-instructions.md` 都是指向本文件的链接，内容完全一样。

**每次动手前要读两份文件，每次都读，不要凭上次的印象：**

1. 本文件 `AGENTS.md`：规矩。怎么提交、哪些写法不能用、测试怎么跑。
2. [TROUBLESHOOTING.md](TROUBLESHOOTING.md)：排障手册。用户报了什么现象、出在哪一段代码、怎么改、以前出过哪些故障。

**每次改完要回头更新这两份文件：** 修了一个新故障，就在 TROUBLESHOOTING.md 第 2 节加上“现象 → 原因 → 改哪里”，第 6 节加一行。定了一条新规矩，就写进本文件。这两份文件过时了，下一个来改的人就会把同样的坑再踩一遍。

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
  - 第一行一句话，说**用户会看到什么变化**（例如"只有 busybox wget 时先装 curl；下载失败显示真实报错"）。
  - 空一行，正文写**为什么**：之前出了什么问题、根本原因是什么、怎么改的。
- 推之前测试必须全部通过（见第 5 节）。

## 2. 这个项目是什么

给小白用的一键搭代理节点脚本：SSH 连上 VPS，粘贴 README 里的一行命令，全程中文提问，一路回车也能装好。

| 文件 | 作用 |
|---|---|
| `README.md` | 给用户看的说明，内容尽量少。**里面那一行安装命令是唯一入口**：自动识别系统、没 curl 先装、DNS 坏了换、GitHub 连不上换镜像，然后下载 install.sh 运行。 |
| `install.sh` | 全部逻辑，一个 POSIX sh 文件，约 8000 行。装节点、更新内核、节点管理都在这里。 |
| `TROUBLESHOOTING.md` | 排障手册：用户报故障时按“现象 → 出在哪一段 → 怎么改”查。里面有安装流程和 install.sh 章节的对照表、机器上的文件清单、真机复现方法、出过的故障。**修完一个新故障，把它补进去。** |
| `tests/*.py` | Python unittest。从 `install.sh` / `README.md` 里切出片段，用假命令（stub）在本机跑。 |

装好以后机器上会有：

- `/etc/xray-node/nodes/<编号>/`：一个节点一个目录，互不影响。
- `jiedian`、`shanjiedian`、`gl` 三个快捷命令（`gl` 打开主菜单，先取最新 install.sh，取不到用 `/etc/xray-node/install.sh`），由 `install.sh` 里"写入 jiedian / shanjiedian 两个快捷命令"那一节生成。
- 几个后台小程序：`xray-node-watch`（每分钟巡检）、`xray-node-hop`（端口跳跃）、`xray-node-route`（回程路由）、`xray-node-expire`（定时节点到点删除）。它们都由 install.sh 写出来。

`install.sh` 的结构：

- 开头是很长的注释：用法和一份"名词小词典"。看不懂某个词，先去那里查。
- 后面按 `# ---------- 编号. 标题 ----------` 分节：前半部分是工具函数（下载、DNS、防火墙、各个小程序），后半部分从"1. 必须是 root"开始，按安装顺序往下走，一直到"15. 显示结果"。
- 找功能时，直接搜 `# ----------` 看目录。

## 3. 硬性约束（每一条都踩过坑）

### 运行环境

- **只用 POSIX sh。** 脚本要在 dash（Debian/Ubuntu）、busybox ash（Alpine）里跑，不能用 bash 专有写法：
  - 不能用 `[[ ]]`、数组、`${var//a/b}`、`<<<`、`function` 关键字、`local`、`source`。
  - 改完跑 `sh -n install.sh`，有 dash 的话再跑 `dash -n install.sh`。
- **要兼容 busybox 版本的命令。** Alpine、NAT 小鸡上的 `grep`、`sed`、`awk`、`wget`、`ps`、`ip` 都可能是 busybox 版，GNU 专有选项会直接报错。用到 GNU 专有选项时，先检测，再给退路。
- **"命令存在"不等于"命令能用"。** 典型例子：busybox `wget` 没装 `ssl_client` 时下不了任何 https，但 `command -v wget` 照样成功。判断"能不能干活"要看真实能力（比如 `wget -V | grep 'GNU Wget'`），别只看有没有这个命令。
- **64MB 内存的机器也要装得上。** 解压、下载要边下边落盘，别把整个文件读进内存。见"小内存机器"一节。
- 支持的系统：Debian / Ubuntu / Alpine（OpenRC）/ CentOS / Arch，x86_64 和 ARM64。还有只有 IPv6、没有 curl、PATH 不全的精简 NAT / LXC 小鸡。

### README 里的安装命令

- **只有一条，不要再加 `bash <(curl …)` 那种短命令。** Alpine 默认没有 bash 也没有 curl，短命令在那里根本跑不起来。所有"自动识别"都必须放在这一行里。
- README 只放这一行和必要的几句话，不要写长篇说明（作者要求）。

- **必须是一行**，不能用 heredoc（`<<`），否则粘贴后会卡在 `>` 提示符。
- **长度必须少于 1800 个字符**（有测试）。Alpine 的 busybox ash 一行只收 2046 个字符，多出来的直接丢掉，命令没收尾就停在 `>`，用户看到的是“运行到一半卡住”。以前按“终端单行 4096 字节”限制在 2400 字节，命令长到 2110 个字符时测试照样通过，在 Alpine 上实际出了问题。往命令里加东西之前先数：`grep '^PATH=' README.md | python3 -c 'import sys; print(len(sys.stdin.read().strip()))'`。
- **代码框里只能有这一行命令**，不能有 `#` 注释行。GitHub 的复制按钮会复制整个代码框，多出来的行会被粘贴进终端，被当成对安装提问的回答。步骤说明写在代码框外面。
- 改了这条命令，除了跑测试，还要在一台 Alpine 上真的粘贴一次（测试用的是 `sh -c`，不经过终端，量不出行长上限）。做法见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 第 4 节。
- 必须能在 dash 里解析通过（有测试）。
- 每一步先打一行字（`[1/3] 检查 DNS` 这种），否则用户会以为卡死了。
- **出错时必须让用户看得到真实报错。** 不要用 `2>/dev/null` 把错误整个吞掉。失败时至少打出最后几行错误，这样用户把输出发来，一眼就能看出原因。

### 跟用户交互

- 所有提示、报错都写**中文大白话**，面向完全不懂 Linux 的人。
- 每个问题都要有默认值，回车就能继续。
- `ask()` 从标准输入读，不要改成读 `/dev/tty`（有测试检查）。
- 加了新功能，要同步更新：`install.sh` 开头的用法注释、装完时打印的提示（用户从这里知道 `jiedian`、`shanjiedian`、`gl` 怎么用），必要时还有"名词小词典"。**README 不写功能说明。**

## 4. 修 bug 的规矩：先找到根本原因，再动手

这个项目吃过的亏：同一个"安装脚本下载不下来"的问题，前后修了好几次（换 DNS、加镜像、改重试次数），都没修好。原因有三个：

1. **报错被藏起来了。** 下载那一步用了 `2>/dev/null`，用户贴回来的只有一串 `fail:`，每次修复都是在猜。
2. **测试把错误的假设锁死了。** 有个用例的假 busybox wget 下 https 总能成功，还专门检查"只有 busybox wget 时不能装 curl"，结果正确的修法反而让测试失败。
3. **测试在 macOS 上跑不全**（只链接了 `/bin`，`grep`、`sed`、`tail` 在 `/usr/bin`），有些路径实际没测到。

所以：

- 先翻 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)：按屏幕上最后一行字找到出问题的章节，看是不是出过的故障。
- 用户报故障时，先从他贴的输出里找证据（系统是什么、哪一步没打字、哪一步失败）。证据不够，先让输出能说清原因，而不是再猜一个修法。
- 写假命令（stub）时，要模仿真实程序**会失败的样子**，不能只模仿成功。
- 测试与真实行为冲突时，改测试，不要为了让测试通过而保留错误行为。
- **改系统设置（DNS、防火墙、软件源等）必须先验证改完能用，不能用就还原。** 安装命令以前把 DNS 换成 1.1.1.1 却不检查，机器连不上 1.1.1.1 时 DNS 就被改坏了，而且没改回去。
- 安装命令和 install.sh 里有两份换 DNS 的逻辑，改一份要对照另一份，两边都要有测试（`tests/test_dns_bootstrap.py`）。

## 5. 测试

```bash
sh -n install.sh
cd tests && python3 -m unittest discover
```

- 两百多个用例，大约 1 到 2 分钟跑完，**必须全部通过才能推送**。macOS 和 Linux 都能跑。
- 测试用 `between("开始标记", "结束标记")` 从 `install.sh` 里切出函数单独运行。**这些标记就是 install.sh 里的注释行或函数开头**（例如 `# 有没有 IPv4 默认路由`、`_have_curl() {`）。改了这些注释或函数名，对应测试会找不到片段而失败，要同时改测试。
- README 里的安装命令会被测试原样取出来运行（换掉下载地址和 PATH），所以改它一定要跑测试。
- 修 bug 时，先写一个能复现这个 bug 的用例，再修。

## 6. 动手前快速检查

- [ ] 这一次动手前，读完了这份文件和 TROUBLESHOOTING.md
- [ ] 只用了 POSIX sh，busybox 也能跑
- [ ] 用户看到的文字是中文大白话，问题都有默认值
- [ ] 出错时报错能显示给用户，没有被吞掉
- [ ] 改了功能就同步了 install.sh 开头的注释和装完时的提示（README 保持只有一行命令）
- [ ] `sh -n install.sh` 和全部测试通过
- [ ] 修的是故障：已经把现象、原因、改法补进 TROUBLESHOOTING.md
- [ ] 改了 README 的安装命令：字符数少于 1800，并且在 Alpine 上真的粘贴过一次
- [ ] 以 imthnio 的身份直接提交到 `main` 并推送，没有分支、没有 PR、没有 AI 署名
