"""端口跳跃小程序 xray-node-hop、节点名、链接编码的测试（全部用假的 nft / iptables，不碰真防火墙）。"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from urllib.parse import quote

INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def between(start, end):
    source = INSTALLER.read_text()
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


NFT_MOCK = r'''#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_LOG"
if [ "$1" = "-f" ]; then
  input=$(cat)
  printf '%s\n' "$input" >> "$NFT_INPUT"
  case "$input" in
    *"table inet xray_node_hop"*) [ -n "$NFT_NO_INET" ] && { echo "Error: Could not process rule: No such file or directory" >&2; exit 1; } ;;
  esac
  case "$input" in
    *"table ip6 xray_node_hop"*) [ -n "$NFT_NO_IP6" ] && { echo "Error: ip6 nat missing" >&2; exit 1; } ;;
  esac
  case "$input" in
    *redirect*) printf '%s\n' "$input" > "$NFT_STATE" ;;
  esac
  exit 0
fi
if [ "$1" = "list" ]; then
  [ -f "$NFT_STATE" ] && grep -q "table $3 $4" "$NFT_STATE" && cat "$NFT_STATE" && exit 0
  exit 1
fi
if [ "$1" = "delete" ]; then
  [ -f "$NFT_STATE" ] && grep -q "table $3 $4" "$NFT_STATE" && rm -f "$NFT_STATE"
  exit 0
fi
exit 0
'''

IPT_MOCK = r'''#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >> "$MOCK_LOG"
case "$*" in
  *"-S PREROUTING"*) [ -f "$IPT_STATE.$(basename "$0")" ] && echo "-A PREROUTING -p udp -m udp --dport 20000 -j XRAY-NODE-HOP-7"; exit 0 ;;
  *"-S XRAY-NODE-HOP-7"*) [ -f "$IPT_STATE.$(basename "$0")" ] && echo "-A XRAY-NODE-HOP-7 -p udp -j REDIRECT --to-ports 443"; exit 0 ;;
  *"-A PREROUTING"*) : > "$IPT_STATE.$(basename "$0")" ;;
  *"-X XRAY-NODE-HOP-7"*) rm -f "$IPT_STATE.$(basename "$0")" ;;
esac
exit 0
'''


class HopHelperTest(unittest.TestCase):
    def setup_root(self, root, tools=("nft",), family="4"):
        bindir = root / "bin"
        bindir.mkdir()
        mock = root / "mock"
        mock.mkdir()
        for tool in tools:
            path = mock / tool
            path.write_text(NFT_MOCK if tool == "nft" else IPT_MOCK)
            path.chmod(0o755)
        node = root / "nodes" / "7"
        node.mkdir(parents=True)
        (node / "hop").write_text(f"main=443\nports=20000,30000-30010\nfamily={family}\n")
        env = {
            "PATH": f"{mock}:/usr/bin:/bin",
            "XRAY_BIN_DIR": str(bindir),
            "XRAY_NODE_DIR": str(root / "nodes"),
            "XRAY_HOP_STATE": str(root / "state"),
            "XRAY_HOP_MODPROBE": "false",
            "MOCK_LOG": str(root / "mock.log"),
            "NFT_INPUT": str(root / "nft.input"),
            "NFT_STATE": str(root / "nft.state"),
            "IPT_STATE": str(root / "ipt"),
            "TMPDIR": str(root),
        }
        subprocess.run(
            ["sh", "-c", between("install_hop_bin() {", "\n# ---------- IPv6 开关") + "\ninstall_hop_bin"],
            env=env, check=True, timeout=10,
        )
        return bindir / "xray-node-hop", env

    def run_hop(self, hop, env, *args, **extra):
        e = dict(env)
        e.update(extra)
        return subprocess.run([str(hop), *args], env=e, capture_output=True, text=True, timeout=10)

    def test_nft_inet_table_redirects_every_hop_port_to_the_main_port(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hop, env = self.setup_root(root)
            up = self.run_hop(hop, env, "up", "7")
            self.assertEqual(up.returncode, 0, up.stderr)
            rules = (root / "nft.state").read_text()
            self.assertIn("table inet xray_node_hop_7", rules)
            self.assertIn("type nat hook prerouting priority -100", rules)
            self.assertIn("meta nfproto ipv4 fib daddr type local udp dport 20000 counter redirect to :443", rules)
            self.assertIn("udp dport 30000-30010 counter redirect to :443", rules)
            self.assertEqual((root / "state" / "7").read_text(), "nft-inet 4\n")
            check = self.run_hop(hop, env, "check", "7")
            self.assertEqual(check.returncode, 0)
            self.assertIn("nft-inet 4", check.stdout)
            down = self.run_hop(hop, env, "down", "7")
            self.assertEqual(down.returncode, 0)
            self.assertFalse((root / "nft.state").exists())
            self.assertFalse((root / "state" / "7").exists())
            self.assertNotEqual(self.run_hop(hop, env, "check", "7").returncode, 0)

    def test_old_kernel_without_inet_nat_falls_back_to_ip_tables_and_keeps_partial_family(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hop, env = self.setup_root(root, family="46")
            up = self.run_hop(hop, env, "up", "7", NFT_NO_INET="1", NFT_NO_IP6="1")
            self.assertEqual(up.returncode, 0, up.stderr)
            self.assertEqual((root / "state" / "7").read_text(), "nft 4\n")
            self.assertIn("table ip xray_node_hop_7", (root / "nft.state").read_text())

    def test_iptables_path_when_there_is_no_nft(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hop, env = self.setup_root(root, tools=("iptables", "ip6tables"), family="46")
            up = self.run_hop(hop, env, "up", "7")
            self.assertEqual(up.returncode, 0, up.stderr)
            log = (root / "mock.log").read_text()
            self.assertIn("iptables -w -t nat -N XRAY-NODE-HOP-7", log)
            self.assertIn("iptables -w -t nat -A XRAY-NODE-HOP-7 -p udp -j REDIRECT --to-ports 443", log)
            self.assertIn("-m addrtype --dst-type LOCAL --dport 30000:30010 -j XRAY-NODE-HOP-7", log)
            self.assertIn("ip6tables -w -t nat -N XRAY-NODE-HOP-7", log)
            self.assertEqual((root / "state" / "7").read_text(), "iptables 46\n")
            self.assertEqual(self.run_hop(hop, env, "check", "7").returncode, 0)
            self.run_hop(hop, env, "down", "7")
            self.assertIn("iptables -w -t nat -X XRAY-NODE-HOP-7", (root / "mock.log").read_text())

    def test_probe_leaves_nothing_behind_and_missing_hop_file_is_a_no_op(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hop, env = self.setup_root(root)
            probe = self.run_hop(hop, env, "probe", XRAY_HOP_PROBE_FAMILY="4")
            self.assertEqual(probe.returncode, 0, probe.stderr)
            self.assertIn("udp dport 1 counter redirect to :2", (root / "nft.input").read_text())
            self.assertFalse((root / "nft.state").exists())
            (root / "nodes" / "7" / "hop").unlink()
            self.assertEqual(self.run_hop(hop, env, "up", "7").returncode, 0)
            self.assertFalse((root / "nft.state").exists())
            self.assertEqual(self.run_hop(hop, env, "up", "abc").returncode, 2)

    def test_failure_reports_the_system_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hop, env = self.setup_root(root, tools=())
            up = self.run_hop(hop, env, "up", "7")
            self.assertEqual(up.returncode, 1)
            self.assertIn("端口跳跃没打开", up.stderr)


class NodeNameTest(unittest.TestCase):
    def sh(self, script, env=None):
        funcs = between("_cc_name() {", "\n# ---------- 机器类型")
        return subprocess.run(["sh", "-c", funcs + "\n" + script], capture_output=True,
                              text=True, check=True, timeout=10, env=env).stdout

    def test_urlenc_matches_python(self):
        for name in ("香港Vless-Reality", "美国Hysteria2", "未知地区Shadowsocks2", "a b&c#d"):
            self.assertEqual(self.sh(f"_urlenc '{name}'"), quote(name, safe="-._~"))

    def test_country_code_to_chinese(self):
        self.assertEqual(self.sh("_cc_name HK"), "香港\n")
        self.assertEqual(self.sh("_cc_name US"), "美国\n")
        self.assertEqual(self.sh("_cc_name ZZ"), "ZZ\n")

    def test_duplicate_names_get_a_number(self):
        with tempfile.TemporaryDirectory() as temp:
            nodes = Path(temp)
            for i, name in ((1, "香港Vless-Reality"), (2, "香港Vless-Reality2")):
                (nodes / str(i)).mkdir()
                (nodes / str(i) / "name").write_text(name)
            env = dict(os.environ, XRAY_NODES_DIR=str(nodes), NODE_REGION="香港")
            self.assertEqual(self.sh("_node_name Vless-Reality", env), "香港Vless-Reality3")
            self.assertEqual(self.sh("_node_name Hysteria2", env), "香港Hysteria2")
            env.pop("NODE_REGION")
            self.assertEqual(self.sh("_node_name TUIC", env), "未知地区TUIC")


class QuicBlockTest(unittest.TestCase):
    def test_every_core_blocks_udp_443(self):
        source = INSTALLER.read_text()
        self.assertEqual(source.count('"network": "udp", "port": "443", "outboundTag": "block"'), 4)
        self.assertIn('"action": "reject"', source)
        self.assertIn("reject(all, udp/443)", source)
        self.assertIn("AND,((NETWORK,UDP),(DST-PORT,443)),REJECT", source)


if __name__ == "__main__":
    unittest.main()
