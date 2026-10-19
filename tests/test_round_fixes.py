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
            + between("_no_ipv4_route() {", "\n# 临时换 DNS")
            + "\n"
            + between("_gh_hint() {", "\n# 下载的安装包")
            + "\nprintf '[%s]' \"$(_gh_hint)\"\n"
        )
        return run_sh(script).stdout

    def test_hint_only_without_ipv4_route(self):
        hint = self.hint("")
        self.assertIn("GitHub 只有 IPv4", hint)
        self.assertIn("IPv6 镜像和公共 NAT64", hint)
        self.assertIn("WARP", hint)
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
        body = between("_dl_xray_inner() {", "\n}\n")
        self.assertLess(body.index('Xray 已存在，直接用现有的'), body.index("_ensure_unzip"))


class MigrationHelperTest(unittest.TestCase):
    def test_helpers_refreshed_right_after_migration(self):
        block = between('info "迁移完成：老节点已转为节点 1', "# ---------- 2d.")
        self.assertIn("write_helper_cmds", block.split("else", 1)[0])


class RealityFingerprintTest(unittest.TestCase):
    def run_ask(self, answers, od_stub=""):
        script = (
            "warn() { echo \"WARN $1\"; }\ninfo() { :; }\ndie() { echo \"DIE $1\"; exit 1; }\n"
            + od_stub
            + between("ask() {", "\nrand_hex() {") + "\n"
            + between("_reality_rand_fp() {", "\n# 写 Hysteria2 的配置文件")
            + "\n_reality_ask_fp\necho \"FP=$REALITY_FP\"\n"
        )
        return subprocess.run(["sh", "-c", script], input=answers, text=True, capture_output=True, timeout=10)

    def test_default_is_random_from_three(self):
        seen = set()
        for _ in range(30):
            out = self.run_ask("\n").stdout
            seen.add(out.strip().rsplit(": ", 1)[-1])
        self.assertTrue(seen <= {"FP=chrome", "FP=firefox", "FP=safari"}, seen)
        self.assertGreater(len(seen), 1)

    def test_fixed_choices_and_retry(self):
        self.assertIn("FP=chrome", self.run_ask("2\n").stdout)
        self.assertIn("FP=safari", self.run_ask("3\n").stdout)
        out = self.run_ask("9\n4\n").stdout
        self.assertIn("WARN 没有这个选项", out)
        self.assertIn("FP=firefox", out)

    def test_random_falls_back_to_chrome_without_od(self):
        out = self.run_ask("1\n", "od() { return 1; }\n").stdout
        self.assertIn("FP=chrome", out)

    def test_links_never_have_empty_fp(self):
        source = INSTALLER.read_text()
        self.assertNotIn("sort -R", source)
        self.assertNotIn("&fp=${REALITY_FP}&", source)
        self.assertEqual(source.count("&fp=${REALITY_FP:-chrome}&"), 3)


class Hy2DomainTest(unittest.TestCase):
    def run_ask(self, answer, busy=""):
        script = (
            "warn() { echo \"WARN $1\"; }\ninfo() { echo \"INFO $1\"; }\ndie() { echo \"DIE $1\"; exit 1; }\n"
            + between("ask() {", "\nrand_hex() {") + "\n"
            + "port_in_use() { case \" " + busy + " \" in *\" $1 \"*) return 0 ;; esac; return 1; }\n"
            + between("_hy_ask_domain() {", "\n# REALITY 客户端指纹")
            + "\n_hy_ask_domain\necho \"D=$HY2_DOMAIN T=$HY2_ACME_TYPE H=$HY2_CERT_HOST\"\n"
        )
        result = subprocess.run(["sh", "-c", script], input=answer, text=True, capture_output=True, timeout=10)
        return result.stdout.strip().splitlines()[-1], result.stdout

    def test_no_domain_uses_default_self_signed(self):
        self.assertEqual(self.run_ask("\n")[0], "D= T= H=www.samsung.com")

    def test_domain_always_tries_acme_without_dns_precheck(self):
        # 不管解析到哪（CDN、NAT），都直接去申请；URL 形式也认
        self.assertEqual(self.run_ask("https://My.Example.org/\n")[0],
                         "D=my.example.org T=http H=my.example.org")
        self.assertEqual(self.run_ask("my.example.org\n", "80")[0],
                         "D=my.example.org T=tls H=my.example.org")

    def test_ports_busy_falls_back_to_self_signed_for_that_domain(self):
        last, out = self.run_ask("my.example.org\n", "80 443")
        self.assertEqual(last, "D= T= H=my.example.org")
        self.assertIn("WARN 这台机器的 TCP 80 和 443 都被别的程序占着", out)

    def test_not_a_domain(self):
        last, out = self.run_ask("abc\n")
        self.assertEqual(last, "D= T= H=www.samsung.com")
        self.assertIn("不像域名", out)

    def test_self_signed_cert_and_sni_follow_domain(self):
        source = INSTALLER.read_text()
        self.assertIn('cert --host "$HY2_CERT_HOST"', source)
        self.assertIn("HY2_SNI=${HY2_DOMAIN:-$HY2_CERT_HOST}", source)


class Hy2AcmeShTest(unittest.TestCase):
    """acme.sh 申请 / 续期：续期只能用 --renew（沿用私钥），公钥指纹不变。用假的 acme.sh，不联网。"""

    STUBS = 'info() { echo "INFO $1"; }\nwarn() { echo "WARN $1"; }\n_pkg_add() { echo "PKG $*"; }\n_log() { echo "LOG $1"; }\n'

    def make_cert(self, d, name):
        # 固定一把 EC 私钥，每次签一张新证书：模拟“续期证书变了，私钥没变”
        key = os.path.join(d, "fixed.key")
        if not os.path.exists(key):
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", key], check=True,
                           capture_output=True)
        out = os.path.join(d, name)
        subprocess.run(["openssl", "req", "-x509", "-new", "-key", key, "-out", out, "-days", "90",
                        "-subj", "/CN=hy2.example.org"], check=True, capture_output=True)
        return key, out

    def fake_acmesh(self, home, log, rc=0, cert_days=90):
        # 假 acme.sh：记下参数；--issue / --renew 时往 <域名>_ecc 里放证书
        script = f"""#!/bin/sh
echo "$*" >> {log}
[ {rc} = 0 ] || exit {rc}
dom=""; prev=""
for a in "$@"; do [ "$prev" = "-d" ] && dom="$a"; prev="$a"; done
mkdir -p {home}/"$dom"_ecc
cp {home}/../fixed.key {home}/"$dom"_ecc/"$dom".key
openssl req -x509 -new -key {home}/../fixed.key -out {home}/"$dom"_ecc/fullchain.cer -days {cert_days} -subj /CN="$dom" 2>/dev/null
"""
        path = os.path.join(home, "acme.sh")
        Path(path).write_text(script)
        os.chmod(path, 0o755)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = self.tmp.name
        self.home = os.path.join(self.d, "home")
        self.nodes = os.path.join(self.d, "nodes")
        os.makedirs(self.home)
        os.makedirs(os.path.join(self.nodes, "1"))
        self.log = os.path.join(self.d, "calls")
        self.make_cert(self.d, "dummy.pem")

    def tearDown(self):
        self.tmp.cleanup()

    def issue(self, rc=0):
        self.fake_acmesh(self.home, self.log, rc)
        script = (self.STUBS + between("_sha256_of() {", "\n# _gh_get ") + "\n"
                  + between("_timeout_cmd() {", "\n_apt_do() {") + "\n"
                  + between("_hy_acmesh_issue() {", "\n# 写 Hysteria2 的配置文件")
                  + "\n_hy_acmesh_get() { return 0; }\n"
                  + f"ACMESH_HOME={self.home} NODE_DIR={self.nodes}/1 HY2_DOMAIN=hy2.example.org HY2_ACME_TYPE=http\n"
                  + "_hy_acmesh_issue; echo \"RC=$? PUB=$HY2_PUBPIN\"\n")
        return run_sh(script).stdout

    def watch(self, body, window=2764800):
        script = (self.STUBS + between("_acmesh_deploy() {", "\n_acme_tick() {") + "\n"
                  + f"NODES_DIR={self.nodes} ACMESH_HOME={self.home} ACME_WINDOW={window}\n" + body)
        return run_sh(script).stdout

    def pubpin(self, cert):
        pub = subprocess.run(["openssl", "x509", "-in", cert, "-pubkey", "-noout"], capture_output=True, check=True).stdout
        der = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "der"], input=pub, capture_output=True,
                             check=True).stdout
        import hashlib
        return hashlib.sha256(der).hexdigest().upper()

    def test_issue_deploys_cert_and_pubkey_pin(self):
        out = self.issue()
        node = os.path.join(self.nodes, "1")
        self.assertIn("RC=0", out)
        self.assertEqual(Path(node, "acme_sh").read_text().strip(), "hy2.example.org")
        pin = self.pubpin(os.path.join(node, "cert.pem"))
        self.assertIn(f"PUB={pin}", out)
        self.assertEqual(Path(node, "pubpin").read_text().strip(), pin)
        calls = Path(self.log).read_text()
        self.assertIn("--issue -d hy2.example.org --server letsencrypt --keylength ec-256 --standalone --httpport 80", calls)

    def test_issue_failure_keeps_self_signed(self):
        node = os.path.join(self.nodes, "1")
        Path(node, "cert.pem").write_text("SELF")
        out = self.issue(rc=1)
        self.assertIn("RC=1", out)
        self.assertFalse(os.path.exists(os.path.join(node, "acme_sh")))
        self.assertEqual(Path(node, "cert.pem").read_text(), "SELF")

    def test_renew_uses_renew_not_issue_and_keeps_pubkey(self):
        self.issue()
        node = os.path.join(self.nodes, "1")
        before_pin = self.pubpin(os.path.join(node, "cert.pem"))
        before_cert = Path(node, "cert.pem").read_text()
        Path(self.log).write_text("")
        # 证书剩 90 天，窗口设成 100 天：要续期
        out = self.watch("_acmesh_renew 1; echo RC=$?\n", window=100 * 86400)
        self.assertIn("RC=0", out)
        calls = Path(self.log).read_text()
        self.assertIn("--renew -d hy2.example.org --ecc --force", calls)
        self.assertNotIn("--issue", calls)
        self.assertNotIn("always-force-new-domain-key", calls)
        self.assertNotEqual(Path(node, "cert.pem").read_text(), before_cert)
        self.assertEqual(self.pubpin(os.path.join(node, "cert.pem")), before_pin)

    def test_fresh_cert_is_copied_without_renewing(self):
        self.issue()
        Path(self.log).write_text("")
        out = self.watch("_acmesh_renew 1; echo RC=$?\n")
        self.assertIn("RC=0", out)
        self.assertEqual(Path(self.log).read_text(), "")

    def test_forget_keeps_domain_used_by_other_node(self):
        self.issue()
        os.makedirs(os.path.join(self.nodes, "2"))
        Path(self.nodes, "2", "acme_sh").write_text("hy2.example.org\n")
        ecc = os.path.join(self.home, "hy2.example.org_ecc")
        self.watch("_acmesh_forget 1\n")
        self.assertTrue(os.path.isdir(ecc))
        subprocess.run(["rm", "-rf", os.path.join(self.nodes, "2")])
        self.watch("_acmesh_forget 1\n")
        self.assertFalse(os.path.isdir(ecc))

    def test_static_wiring(self):
        source = INSTALLER.read_text()
        write_cfg = between("_hy_write_config() {", "\n_hy_listen_for() {")
        self.assertNotIn("acme:", write_cfg)
        self.assertRegex(source, r"\nACMESH_SHA256=[0-9a-f]{64}\n")
        self.assertIn('tls-pubkey-sha256=${HY2_PUBPIN}', source)
        # 巡检：有 acme_sh 的节点就算没有 fw_acme 也要续期；删节点先 acme-forget
        self.assertIn('[ -f "${_ad}fw_acme" ] || [ -f "${_ad}acme_sh" ] || continue', source)
        self.assertEqual(source.count("acme-forget \"$_d_id\""), 2)


class AlpineOpenRCTest(unittest.TestCase):
    """在 64MB 的 Alpine（OpenRC、busybox）上实测发现的问题。"""

    def test_openrc_services_are_supervised(self):
        source = INSTALLER.read_text()
        fn = between("_openrc_bg() {", "\n# 从系统随机数源")
        with tempfile.TemporaryDirectory() as d:
            Path(d, "supervise-daemon").write_text("#!/bin/sh\n")
            os.chmod(os.path.join(d, "supervise-daemon"), 0o755)
            with_sd = run_sh(f"PATH={d}:$PATH\n" + fn + "\n_openrc_bg")
        self.assertIn('supervisor="supervise-daemon"', with_sd.stdout)
        self.assertIn("respawn_max=0", with_sd.stdout)
        without = run_sh("PATH=/nonexistent\n" + fn + "\n_openrc_bg")
        self.assertEqual(without.stdout, 'command_background="yes"')
        # 节点、到点删除、巡检三个 OpenRC 服务都要被看着
        self.assertEqual(source.count("$(_openrc_bg)"), 2)
        self.assertIn('_ao_bg=\'supervisor="supervise-daemon"', source)
        # 函数要定义在脚本前面：write_helper_cmds / arm_expire_watch 在主流程前段就会调用
        self.assertLess(source.index("_openrc_bg() {"), source.index("\nwrite_helper_cmds\n"))

    def test_service_rewrite_stops_old_process_first(self):
        source = INSTALLER.read_text()
        block = between('  elif command -v rc-service >/dev/null 2>&1; then', 'RCEOF')
        self.assertIn('rc-service "$_si_svc" stop', block)
        self.assertIn('pkill -f "$_si_cfg"', between('rc-service "$_si_svc" zap', 'rc-service "$_si_svc" start'))

    def test_update_mode_supervises_existing_openrc_nodes(self):
        source = INSTALLER.read_text()
        self.assertIn("grep -q '^supervisor=\"supervise-daemon\"' \"/etc/init.d/xray-node-$_u3\"", source)

    def test_no_pgrep_x(self):
        # busybox 的 pgrep -x 匹配不到进程名
        code = [l for l in INSTALLER.read_text().splitlines() if not l.lstrip().startswith("#")]
        self.assertFalse([l for l in code if "pgrep -x" in l])

    def test_readonly_proc_write_is_silent(self):
        self.assertIn("{ printf '1\\n' > /proc/sys/vm/overcommit_memory; } 2>/dev/null", INSTALLER.read_text())

    def test_cert_pin_without_openssl(self):
        with tempfile.TemporaryDirectory() as d:
            key = os.path.join(d, "k.pem")
            cert = os.path.join(d, "c.pem")
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                            "-days", "1", "-subj", "/CN=www.samsung.com"], check=True, capture_output=True)
            want = subprocess.run(f"openssl x509 -in {cert} -outform der | openssl dgst -sha256", shell=True,
                                  capture_output=True, text=True).stdout.split()[-1].upper()
            fns = between("_sha256_of() {", "\n# _gh_get ") + "\n" + between("_cert_pin() {", "\n_timeout_cmd() {")
            # 把 openssl 藏起来，只留 base64 / sha256 工具
            bindir = os.path.join(d, "bin")
            os.makedirs(bindir)
            for tool in ("awk", "base64", "rm", "tr", "sha256sum", "shasum", "perl", "cat"):
                p = subprocess.run(["sh", "-c", f"command -v {tool}"], capture_output=True, text=True).stdout.strip()
                if p:
                    os.symlink(p, os.path.join(bindir, tool))
            got = run_sh(f"PATH={bindir}\n" + fns + f"\n_cert_pin {cert}")
            self.assertEqual(got.stdout, want)

    def test_tuic_surge_line_pins_cert(self):
        fn = between("_cq_ok() {", "\n_cq_surge_line() {") + "\n" + between("_cq_surge_line() {", "\n_cq_section() {")
        env = ('CQ_PROTO=tuic CQ_NAME=n CQ_HOST=1.2.3.4 CQ_PORT=443 CQ_UUID=u CQ_PASS=p\n')
        pinned = run_sh(fn + "\n" + env + "CQ_PIN=" + "AB" * 32 + "\n_cq_surge_line")
        self.assertIn("server-cert-fingerprint-sha256=" + "AB" * 32, pinned.stdout)
        self.assertNotIn("skip-cert-verify=true", pinned.stdout)
        old = run_sh(fn + "\n" + env + "CQ_PIN=\n_cq_surge_line")
        self.assertIn("skip-cert-verify=true", old.stdout)
