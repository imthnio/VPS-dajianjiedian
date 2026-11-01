"""设备数量限制 xray-node-limit 和 shanjiedian 里“限制节点能连几台设备”的测试。

用假的 /proc/net/tcp、连接跟踪表和假的 nft，不碰真防火墙。
"""

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def heredoc(marker_start, marker_end):
    source = INSTALLER.read_text()
    start = source.index(marker_start) + len(marker_start)
    return source[start:source.index(marker_end, start)]


TCP_HEADER = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"


def tcp_line(local, remote, state="01"):
    return f"   0: {local} {remote} {state} 00000000:00000000 00:00000000 00000000     0        0 1 1\n"


# 假的 nft：-f 时把规则存下来，delete/list 按文件处理
NFT_MOCK = r'''#!/bin/sh
case "$1" in
  -f) cat > "$NFT_RULES.tmp"; mv "$NFT_RULES.tmp" "$NFT_RULES" ;;
  delete) rm -f "$NFT_RULES" ;;
  list) [ -f "$NFT_RULES" ] ;;
esac
exit 0
'''


# 假的 iptables：只记日志；INPUT 里有没有跳到我们链的规则，看 $IPT_LOG 旁边的 ipt.jump 文件
IPT_MOCK = r'''#!/bin/sh
name=$(basename "$0")
printf '%s %s\n' "$name" "$*" >> "$IPT_LOG"
jump="$(dirname "$IPT_LOG")/$name" ; [ "$name" = iptables ] && jump="$(dirname "$IPT_LOG")/ipt.jump"
case "$*" in
  "-w -C INPUT -j XRAY_NODE_LIMIT") [ -f "$jump" ] ;;
  "-w -I INPUT 1 -j XRAY_NODE_LIMIT") : > "$jump" ;;
  "-w -D INPUT -j XRAY_NODE_LIMIT") [ -f "$jump" ] && rm -f "$jump" ;;
  *) exit 0 ;;
esac
'''


class LimitBinTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        script = heredoc("<<'LIMITEOF' || return 1\n", "\nLIMITEOF\n")
        (self.bin / "xray-node-limit").write_text(script)
        (self.bin / "xray-node-limit").chmod(0o700)
        (self.bin / "nft").write_text(NFT_MOCK)
        (self.bin / "nft").chmod(0o755)
        self.nodes = self.root / "nodes"
        self.proc = self.root / "proc"
        self.proc.mkdir()
        self.state = self.root / "state"
        self.env = os.environ.copy()
        self.env.update(
            PATH=f"{self.bin}:/usr/bin:/bin",
            XRAY_NODE_DIR=str(self.nodes),
            XRAY_BIN_DIR=str(self.bin),
            XRAY_LIMIT_STATE=str(self.state),
            XRAY_LIMIT_PROC=str(self.proc),
            XRAY_LIMIT_LOG=str(self.root / "limit.log"),
            XRAY_LIMIT_CONFIRM="0",
            NFT_RULES=str(self.root / "nft.rules"),
        )

    def tearDown(self):
        self.temp.cleanup()

    def node(self, node_id, fw_info, limit=None, core="xray"):
        directory = self.nodes / node_id
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "fw_info").write_text(fw_info)
        (directory / "core").write_text(core + "\n")
        if limit is not None:
            (directory / "limit").write_text(f"{limit}\n")
        return directory

    def tcp(self, *remotes, port="01BB", v6=()):
        (self.proc / "tcp").write_text(
            TCP_HEADER
            + tcp_line(f"00000000:{port}", "00000000:0000", "0A")
            + "".join(tcp_line(f"0100000A:{port}", f"{r}:D431") for r in remotes)
        )
        (self.proc / "tcp6").write_text(
            TCP_HEADER + "".join(tcp_line(f"{'0' * 32}:{port}", f"{r}:D431") for r in v6)
        )

    def run_limit(self, *args, check=True):
        return subprocess.run(
            ["sh", str(self.bin / "xray-node-limit"), *args],
            env=self.env, text=True, capture_output=True, check=check,
        )

    def online(self, node_id="1"):
        path = self.state / f"{node_id}.on"
        return sorted(line.split()[0] for line in path.read_text().splitlines()) if path.exists() else []

    def banned(self, node_id="1"):
        path = self.state / f"{node_id}.ban"
        return sorted(line.split()[0] for line in path.read_text().splitlines()) if path.exists() else []

    def test_reads_tcp_v4_v6_and_mapped_addresses(self):
        self.node("1", "443 tcp 0 0 1 4\n443 tcp 0 0 1 6\n", limit=10)
        # 1.2.3.4、::ffff:5.6.7.8、2001:db8:1:2::5，另有一条别的端口和一条本机连接不算
        self.tcp(
            "04030201", "0100007F",
            v6=("0000000000000000FFFF000008070605", "B80D01200200010000000000" + "05000000"),
        )
        with (self.proc / "tcp").open("a") as f:
            f.write(tcp_line("0100000A:0050", "09090909:D431"))
        self.run_limit("tick")
        self.assertEqual(self.online(), ["1.2.3.4", "2001:db8:1:2::/64", "5.6.7.8"])

    def test_udp_counts_replied_conntrack_entries_including_port_hopping(self):
        self.node("1", "443 udp 0 0 1 4\n443 tcp 0 0 1 4\n", limit=10, core="hysteria")
        self.tcp("04030201")  # Hysteria2 的 TCP 是伪装网站，不算设备
        (self.proc / "nf_conntrack").write_text(
            "ipv4     2 udp      17 170 src=9.9.9.9 dst=10.0.0.1 sport=5000 dport=30000 "
            "src=10.0.0.1 dst=9.9.9.9 sport=443 dport=5000 [ASSURED] mark=0 use=2\n"
            "ipv4     2 udp      17 20 src=8.8.8.8 dst=10.0.0.1 sport=1 dport=443 [UNREPLIED] "
            "src=10.0.0.1 dst=8.8.8.8 sport=443 dport=1 mark=0 use=2\n"
            "ipv6     10 udp      17 100 src=2001:db8:aa:bb:1::2 dst=2001:db8::1 sport=1 dport=443 "
            "src=2001:db8::1 dst=2001:db8:aa:bb:1::2 sport=443 dport=1 [ASSURED] mark=0 use=2\n"
            "ipv4     2 tcp      6 100 ESTABLISHED src=7.7.7.7 dst=10.0.0.1 sport=1 dport=443 "
            "src=10.0.0.1 dst=7.7.7.7 sport=443 dport=1 [ASSURED] mark=0 use=2\n"
        )
        self.run_limit("tick")
        self.assertEqual(self.online(), ["2001:db8:aa:bb::/64", "9.9.9.9"])

    def test_third_device_kicks_the_oldest_and_bans_only_that_node(self):
        self.node("1", "443 tcp 0 0 1 4\n", limit=2)
        self.state.mkdir()
        now = int(time.time())
        # 1.1.1.1 最早连上，2.2.2.2 后来
        (self.state / "1.on").write_text(f"1.1.1.1 {now - 300} {now - 5} 1\n2.2.2.2 {now - 100} {now - 5} 1\n")
        self.tcp("01010101", "02020202", "03030303")
        self.run_limit("tick")
        self.assertEqual(self.online(), ["2.2.2.2", "3.3.3.3"])
        self.assertEqual(self.banned(), ["1.1.1.1"])
        rules = (self.root / "nft.rules").read_text()
        self.assertIn("ip saddr 1.1.1.1 tcp dport 443 drop", rules)
        self.assertNotIn("2.2.2.2", rules)

        # 被挤掉的设备旧连接还在表里，也不能再算进来
        self.run_limit("tick")
        self.assertEqual(self.online(), ["2.2.2.2", "3.3.3.3"])
        self.assertEqual(self.banned(), ["1.1.1.1"])

        # 到时间放开；它再连上就挤掉当时最早的 2.2.2.2，以此循环
        (self.state / "1.ban").write_text(f"1.1.1.1 {now - 1}\n")
        self.run_limit("tick")
        self.assertEqual(self.online(), ["1.1.1.1", "3.3.3.3"])
        self.assertEqual(self.banned(), ["2.2.2.2"])
        self.assertIn("ip saddr 2.2.2.2 tcp dport 443 drop", (self.root / "nft.rules").read_text())

    def test_short_lived_probe_is_not_counted(self):
        self.env["XRAY_LIMIT_CONFIRM"] = "30"
        self.node("1", "443 tcp 0 0 1 4\n", limit=1)
        self.state.mkdir()
        now = int(time.time())
        (self.state / "1.on").write_text(f"1.1.1.1 {now - 300} {now - 5} 1\n")
        self.tcp("01010101", "09090909")
        self.run_limit("tick")
        self.assertEqual(self.banned(), [])
        # 探测走了以后直接忘掉
        self.tcp("01010101")
        self.run_limit("tick")
        self.assertEqual(self.online(), ["1.1.1.1"])

    def test_idle_device_frees_its_slot(self):
        self.node("1", "443 tcp 0 0 1 4\n", limit=1)
        self.state.mkdir()
        now = int(time.time())
        (self.state / "1.on").write_text(f"1.1.1.1 {now - 900} {now - 600} 1\n")
        self.tcp("02020202")
        self.run_limit("tick")
        self.assertEqual(self.online(), ["2.2.2.2"])
        self.assertEqual(self.banned(), [])

    def test_removing_limit_releases_everyone(self):
        directory = self.node("1", "443 tcp 0 0 1 4\n", limit=1)
        self.state.mkdir()
        now = int(time.time())
        (self.state / "1.on").write_text(f"1.1.1.1 {now - 300} {now - 5} 1\n")
        self.tcp("01010101", "02020202")
        self.run_limit("tick")
        self.assertTrue((self.root / "nft.rules").exists())
        (directory / "limit").unlink()
        self.run_limit("clear", "1")
        self.run_limit("tick")
        self.assertFalse((self.root / "nft.rules").exists())
        self.assertFalse((self.state / "1.ban").exists())

    def test_falls_back_to_iptables_when_nft_fails(self):
        (self.bin / "nft").write_text("#!/bin/sh\nexit 1\n")
        for name in ("iptables", "ip6tables"):
            (self.bin / name).write_text(IPT_MOCK)
            (self.bin / name).chmod(0o755)
        self.env["IPT_LOG"] = str(self.root / "ipt.log")
        self.node("1", "443 tcp 0 0 1 4\n", limit=1)
        self.state.mkdir()
        now = int(time.time())
        (self.state / "1.on").write_text(f"1.1.1.1 {now - 300} {now - 5} 1\n")
        self.tcp("01010101", "02020202")
        self.run_limit("tick")
        log = (self.root / "ipt.log").read_text()
        self.assertIn("iptables -w -A XRAY_NODE_LIMIT -s 1.1.1.1 -p tcp --dport 443 -j DROP", log)
        self.assertIn("iptables -w -I INPUT 1 -j XRAY_NODE_LIMIT", log)
        self.assertNotIn("ip6tables -w -A", log)
        self.assertEqual((self.state / "backend").read_text().strip(), "ipt")

        # 防火墙重载把跳转规则清掉了：下一次巡检补回来
        (self.root / "ipt.log").write_text("")
        (self.root / "ipt.jump").unlink()
        self.run_limit("tick")
        self.assertIn("iptables -w -I INPUT 1 -j XRAY_NODE_LIMIT", (self.root / "ipt.log").read_text())

    def test_arm_without_limits_does_nothing_and_with_limit_starts_loop(self):
        self.env.update(
            XRAY_SYSTEMD_RUN=str(self.root / "no-systemd"),
            XRAY_INITD=str(self.root / "no-initd"),
            XRAY_CRON_DIR=str(self.root / "cron"),
            XRAY_LIMIT_PID=str(self.root / "limit.pid"),
            XRAY_LIMIT_INTERVAL="1",
        )
        (self.root / "cron").mkdir()
        self.node("1", "443 tcp 0 0 1 4\n")
        self.run_limit("arm")
        self.assertFalse((self.root / "cron" / "xray-node-limit").exists())
        (self.nodes / "1" / "limit").write_text("2\n")
        self.run_limit("arm")
        self.assertIn("xray-node-limit ensure", (self.root / "cron" / "xray-node-limit").read_text())
        pid = int((self.root / "limit.pid").read_text())
        try:
            os.kill(pid, 0)
        finally:
            (self.nodes / "1" / "limit").unlink()
            self.run_limit("arm")
        self.assertFalse((self.root / "cron" / "xray-node-limit").exists())
        self.assertFalse((self.root / "limit.pid").exists())


class LimitCleanupTest(unittest.TestCase):
    def test_every_delete_path_releases_devices(self):
        source = INSTALLER.read_text()

        def body(start):
            begin = source.index(start)
            return source[begin:source.index("\n}\n", begin)]

        del_node = body("_del_node() {")
        self.assertIn("xray-node-limit clear", del_node)
        self.assertIn("xray-node-limit arm", del_node)
        expire = body("_delete_node() {")
        self.assertIn('"$_x_lim" clear "$_d_id"', expire)
        self.assertIn('"$_x_lim" arm', expire)
        uninstall = body("_uninstall_all() {")
        self.assertIn("xray-node-limit disarm", uninstall)
        self.assertIn("rm -f /usr/local/bin/xray-node-limit", uninstall)
        helpers = body("write_helper_cmds() {")
        self.assertIn("arm_device_limit || true", source[source.index("write_helper_cmds() {"):source.index("\n# ---------- 服务")])
        self.assertTrue(helpers)
        # 函数要在主流程调用前定义好
        self.assertLess(source.index("arm_device_limit() {"), source.index("\narm_device_limit || true\n_NODE_COUNT=0"))


class LimitMenuTest(unittest.TestCase):
    def menu_script(self, nodes, limit_bin):
        script = heredoc("cat > /usr/local/bin/shanjiedian <<'XZEOF'\n", "\nXZEOF\n")
        script = script.replace("/usr/local/bin/xray-node-limit", str(limit_bin))
        return script.replace("NODES_DIR=/etc/xray-node/nodes", f"NODES_DIR={nodes}", 1)

    def run_menu(self, answers, node_ids=("2", "5"), limits=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            nodes = root / "nodes"
            for node_id in node_ids:
                directory = nodes / node_id
                directory.mkdir(parents=True)
                (directory / "node.txt").write_text("协议: vless\n端口: 443\n")
                (directory / "fw_info").write_text("443 tcp 0 0 1 4\n")
                if limits and node_id in limits:
                    (directory / "limit").write_text(limits[node_id] + "\n")
            log = root / "limit.log"
            limit_bin = root / "xray-node-limit"
            limit_bin.write_text(f'#!/bin/sh\necho "$*" >> {log}\n[ "$1" = udp-ok ] && exit 1\nexit 0\n')
            limit_bin.chmod(0o755)
            result = subprocess.run(
                ["sh", "-c", self.menu_script(nodes, limit_bin)],
                input=answers, text=True, capture_output=True, check=True,
            )
            values = {
                node_id: (nodes / node_id / "limit").read_text().strip()
                for node_id in node_ids if (nodes / node_id / "limit").exists()
            }
            calls = log.read_text().splitlines() if log.exists() else []
            return result, values, calls

    def test_menu_entry_follows_delete_all(self):
        result, _, _ = self.run_menu("0\n")
        self.assertIn("6) 删除全部节点并卸载干净", result.stdout)
        self.assertIn("7) 限制节点能连几台设备", result.stdout)

    def test_set_limit_for_a_node(self):
        result, values, calls = self.run_menu("7\n5\n2\n")
        self.assertEqual(values, {"5": "2"})
        self.assertIn("arm", calls)
        self.assertIn("最多 2 台设备", result.stdout)

    def test_zero_removes_limit_and_releases_devices(self):
        result, values, calls = self.run_menu("7\n2\n0\n", limits={"2": "3"})
        self.assertEqual(values, {})
        self.assertIn("clear 2", calls)
        self.assertIn("不限制", result.stdout)

    def test_bad_input_changes_nothing(self):
        for answers in ("7\n3\n2\n", "7\n2\nabc\n", "7\n2\n\n", "7\n0\n"):
            _, values, _ = self.run_menu(answers, limits={"2": "3"})
            self.assertEqual(values, {"2": "3"}, answers)

    def test_node_list_shows_current_limit(self):
        result, _, _ = self.run_menu("0\n", limits={"5": "2"})
        self.assertIn("最多 2 台设备", result.stdout)


if __name__ == "__main__":
    unittest.main()
