"""审查中发现的问题的回归测试：直接跑 install.sh 里抽出来的函数，不需要 root。"""

import base64
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def between(start, end):
    source = INSTALLER.read_text()
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def run_sh(script, env=None):
    return subprocess.run(["sh", "-c", script], text=True, capture_output=True, env=env, timeout=20)


class GetIpChoiceTest(unittest.TestCase):
    def run_get(self, version, ip_stub, curl_ip="198.51.100.99"):
        script = (
            "ip() {\n" + ip_stub + "\n}\n"
            "curl() { printf '%s\\n' '" + curl_ip + "'; }\n"
            + between("get_ip() {", "\n# gh_api_dl ")
            + "\nget_ip " + version + "\n"
        )
        return run_sh(script)

    def test_public_address_after_private_one_on_same_nic(self):
        result = self.run_get("4", '''
            case "$*" in
              "-4 route show default table main") echo "default via 10.0.0.1 dev eth0";;
              "-4 -o addr show dev eth0 scope global")
                echo "2: eth0 inet 10.0.0.5/24 scope global eth0"
                echo "2: eth0 inet 203.0.113.20/24 scope global secondary eth0";;
              *) return 1;;
            esac''')
        self.assertEqual(result.stdout.strip(), "203.0.113.20", result.stderr)

    def test_ipv6_temporary_and_ula_addresses_are_skipped(self):
        result = self.run_get("6", '''
            case "$*" in
              "-6 route show default table main") echo "default via fe80::1 dev eth0";;
              "-6 -o addr show dev eth0 scope global")
                echo "2: eth0 inet6 2001:db8::aaaa/64 scope global temporary dynamic"
                echo "2: eth0 inet6 fd00::5/64 scope global"
                echo "2: eth0 inet6 2001:db8::10/64 scope global dynamic mngtmpaddr";;
              *) return 1;;
            esac''', curl_ip="2001:db8::aaaa")
        self.assertEqual(result.stdout.strip(), "2001:db8::10", result.stderr)


class SaveFirewallTest(unittest.TestCase):
    def test_ufw_or_firewalld_never_pulls_in_iptables_persistent(self):
        body = between("_save_fw() {", "\n# _fw_allow ")
        for tool in ("ufw", "firewall-cmd"):
            with tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                bindir = root / "bin"
                bindir.mkdir()
                log = root / "log"
                for name in (tool, "iptables-save", "apt-get"):
                    stub = bindir / name
                    stub.write_text(f"#!/bin/sh\necho {name} \"$@\" >> {log}\n")
                    stub.chmod(0o755)
                script = (
                    "LOW_MEM=0\n"
                    "warn() { echo \"WARN $1\"; }\ninfo() { echo \"INFO $1\"; }\n"
                    "_apt_do() { echo apt_do \"$@\" >> " + str(log) + "; return 0; }\n"
                    "_save_fw_light() { echo LIGHT; return 0; }\n"
                    + body + "\n_save_fw 4\n"
                )
                env = dict(os.environ, PATH=f"{bindir}:/usr/bin:/bin")
                result = run_sh(script, env)
                logged = log.read_text() if log.exists() else ""
                self.assertIn("LIGHT", result.stdout, tool)
                self.assertNotIn("iptables-persistent", logged, tool)

    def test_plain_iptables_still_uses_iptables_persistent(self):
        body = between("_save_fw() {", "\n# _fw_allow ")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bindir = root / "bin"
            bindir.mkdir()
            log = root / "log"
            for name in ("iptables-save", "apt-get"):
                stub = bindir / name
                stub.write_text("#!/bin/sh\nexit 0\n")
                stub.chmod(0o755)
            script = (
                "LOW_MEM=0\nwarn() { :; }\ninfo() { :; }\n"
                "_apt_do() { echo \"$@\" >> " + str(log) + "; return 0; }\n"
                "_save_fw_light() { echo LIGHT; }\n" + body + "\n_save_fw 4\n"
            )
            # 故意不把 /usr/sbin 放进来：真机上的 ufw / netfilter-persistent 不能影响结果
            env = dict(os.environ, PATH=f"{bindir}:/usr/bin:/bin")
            if any(Path(d, n).exists() for d in ("/usr/bin", "/bin") for n in ("ufw", "firewall-cmd", "netfilter-persistent")):
                self.skipTest("host has ufw/firewalld/netfilter-persistent in /usr/bin")
            run_sh(script, env)
            self.assertIn("iptables-persistent", log.read_text())


class LatestTagFallbackTest(unittest.TestCase):
    def test_api_failure_falls_back_to_release_redirect(self):
        script = (
            "_http_body() { return 22; }\n"
            "curl() { printf '%s' 'https://github.com/SagerNet/sing-box/releases/tag/v1.99.3'; }\n"
            + between("_latest_tag_web() {", "\n# _cached_ver_ok ")
            + "\n_latest_tag SagerNet/sing-box\n"
        )
        result = run_sh(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "1.99.3")

    def test_redirect_to_non_tag_page_fails(self):
        script = (
            "_http_body() { return 22; }\n"
            "curl() { printf '%s' 'https://github.com/login'; }\n"
            + between("_latest_tag_web() {", "\n# _cached_ver_ok ")
            + "\n_latest_tag SagerNet/sing-box\n"
        )
        result = run_sh(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


class ShadowsocksKeyTest(unittest.TestCase):
    def test_fallback_key_without_openssl_is_16_bytes(self):
        source = INSTALLER.read_text()
        line = next(l for l in source.splitlines() if l.strip().startswith("SS_PASS=$(head -c 16"))
        for _ in range(20):
            result = run_sh(line.strip() + '\nprintf "%s" "$SS_PASS"\n', dict(os.environ, LC_ALL="C.UTF-8"))
            self.assertEqual(len(base64.b64decode(result.stdout)), 16, result.stdout)


class UninstallNoteTest(unittest.TestCase):
    def test_uninstall_mentions_ipv6_that_stays_off(self):
        body = between("_uninstall_all() {", "\necho \"==================== 节点管理")
        self.assertIn("99-xray-node-ipv6.conf", body)
        self.assertIn("开启 IPv6", body)


class HysteriaVersionFallbackTest(unittest.TestCase):
    def test_hysteria_version_survives_api_rate_limit(self):
        for redirect in ("https://github.com/apernet/hysteria/releases/tag/app/v2.12.3",
                         "https://github.com/apernet/hysteria/releases/tag/app%2Fv2.12.3"):
            script = (
                "_http_body() { return 22; }\n"
                "curl() { printf '%s' '" + redirect + "'; }\n"
                + between("_latest_tag_web() {", "\n_latest_tag() {")
                + between("_latest_hysteria_ver() {", "\n_hysteria_local_ver() {")
                + "\n_latest_hysteria_ver\n"
            )
            result = run_sh(script)
            self.assertEqual(result.stdout, "2.12.3", result.stderr)


class ExpireBinsCleanupTest(unittest.TestCase):
    def run_drop(self, with_node):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bindir = root / "bin"; bindir.mkdir()
            nodes = root / "nodes"; nodes.mkdir()
            if with_node:
                (nodes / "1").mkdir()
            for name in ("xray-node-expire", "xray-node-run", "xray-node-expire-loop", "jiedian-other"):
                (bindir / name).write_text("x")
            script = between("_drop_expire_bins_if_unused() {", "\narm_expire_watch() {") + "\n_drop_expire_bins_if_unused\n"
            run_sh(script, dict(os.environ, XRAY_NODE_DIR=str(nodes), XRAY_BIN_DIR=str(bindir)))
            return sorted(p.name for p in bindir.iterdir())

    def test_removed_when_no_nodes(self):
        self.assertEqual(self.run_drop(False), ["jiedian-other"])

    def test_kept_when_a_node_exists(self):
        self.assertEqual(len(self.run_drop(True)), 4)


class DualLinkHeaderTest(unittest.TestCase):
    def test_ipv6_strip_also_fixes_the_two_line_header(self):
        with tempfile.TemporaryDirectory() as temp:
            node = Path(temp) / "1"
            node.mkdir()
            (node / "node.txt").write_text(
                " 你的节点（两行是同一个节点：第一行用 IPv4，第二行用 IPv6。不确定就复制第一行）\n"
                "hysteria2://p@203.0.113.2:443/?insecure=1#xray-node\n"
                "hysteria2://p@[2001:db8::2]:443/?insecure=1#xray-node\n"
            )
            script = between("_ipv6_strip_links() {", "\n_ipv6_turn_off() {") + "\n_ipv6_strip_links\n"
            run_sh(script, dict(os.environ, XRAY_NODES_DIR=temp))
            text = (node / "node.txt").read_text()
            self.assertNotIn("两行", text)
            self.assertNotIn("[2001:db8::2]", text)
            self.assertIn("203.0.113.2:443", text)


class PortRetryTest(unittest.TestCase):
    def run_block(self, answers):
        block = between("_port_try=0\n", 'info "端口：$PORT"')
        script = (
            "warn() { echo \"WARN $1\"; }\nerr() { echo \"ERR $1\"; }\ndie() { err \"$1\"; exit 1; }\n"
            + between("ask() {", "\nrand_hex() {")
            + "\nport_in_use() { [ \"$1\" = 8443 ]; }\n_PORT_PROTO=tcp\n_DEF_PORT=30000\n"
            + block + "\necho \"PORT=$PORT\"\n"
        )
        return subprocess.run(["sh", "-c", script], input=answers, text=True, capture_output=True, timeout=10)

    def test_busy_port_is_asked_again(self):
        result = self.run_block("8443\n\n")
        self.assertIn("WARN 端口 8443/TCP 已被其他程序占用", result.stdout)
        self.assertIn("30000（这个是空闲的）", result.stdout)
        self.assertIn("PORT=30000", result.stdout)

    def test_gives_up_after_three_busy_answers(self):
        result = self.run_block("8443\n8443\n8443\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERR 端口 8443/TCP 已被其他程序占用", result.stdout)


class NftDropChainTest(unittest.TestCase):
    RULESET = """table ip filter {
\tchain INPUT {
\t\ttype filter hook input priority filter; policy drop;
\t}
}
table inet firewalld {
\tchain filter_INPUT {
\t\ttype filter hook input priority filter + 10; policy accept;
\t}
}
table inet my_fw {
\tchain input {
\t\ttype filter hook input priority filter; policy drop;
\t\tct state established,related accept
\t}
\tchain forward {
\t\ttype filter hook forward priority filter; policy drop;
\t}
}
"""

    def test_only_native_drop_input_chains_are_reported(self):
        with tempfile.TemporaryDirectory() as temp:
            nft = Path(temp) / "nft"
            (Path(temp) / "ruleset").write_text(self.RULESET)
            nft.write_text(f"#!/bin/sh\ncat {temp}/ruleset\n")
            nft.chmod(0o755)
            script = between("_nft_drop_chains() {", "\n_set_expire_choice() {") + "\n_nft_drop_chains\n"
            result = run_sh(script, dict(os.environ, PATH=f"{temp}:/usr/bin:/bin"))
            self.assertEqual(result.stdout.strip().splitlines(), ["inet my_fw input"])


if __name__ == "__main__":
    unittest.main()


class NatPrivateNicTest(GetIpChoiceTest):
    def test_private_only_nic_uses_egress_address(self):
        result = self.run_get("4", '''
            case "$*" in
              "-4 route show default table main") echo "default via 10.55.0.1 dev eth0";;
              "-4 -o addr show dev eth0 scope global") echo "2: eth0 inet 10.55.0.2/24 scope global eth0";;
              *) return 1;;
            esac''')
        self.assertEqual(result.stdout.strip(), "198.51.100.99", result.stderr)


class Ipv6OnlyTest(unittest.TestCase):
    def hint(self, v4_route):
        script = (
            "ip() { case \"$*\" in \"-4 route show default\") printf '%s' '" + v4_route + "';; esac; }\n"
            + between("_gh_hint() {", "\n_latest_tag() {")
            + "\nprintf '[%s]' \"$(_gh_hint)\"\n"
        )
        return run_sh(script).stdout

    def test_hint_only_without_ipv4_route(self):
        self.assertIn("GitHub 不支持 IPv6", self.hint(""))
        self.assertEqual(self.hint("default via 203.0.113.1 dev eth0"), "[]")

    def test_download_errors_carry_hint(self):
        source = INSTALLER.read_text()
        for core in ("Xray", "sing-box", "Hysteria2"):
            self.assertIn(core + ' 下载失败：到 GitHub 的网络不稳定，稍等几分钟后重跑脚本试试$(_gh_hint)', source)

    def test_ipv6_default_when_no_ipv4_route(self):
        block = between("_ipdef=1\n", 'ask "请选择" "$_ipdef" _ipver')
        self.assertIn('ip -4 route show default', block)
        self.assertIn('_ipdef=2', block)

    def test_unzip_only_needed_for_download(self):
        body = between("dl_xray() {", "\n}\n")
        self.assertLess(body.index('Xray 已存在，直接用现有的'), body.index("_ensure_unzip"))


class MigrationHelperTest(unittest.TestCase):
    def test_helpers_refreshed_right_after_migration(self):
        block = between('info "迁移完成：老节点已转为节点 1', "# ---------- 2d.")
        self.assertIn("write_helper_cmds", block.split("else", 1)[0])
