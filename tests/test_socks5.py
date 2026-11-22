"""SOCKS5 协议与全面检查修复的回归测试。"""

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def between(start, end):
    source = INSTALLER.read_text()
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def run_sh(script, env=None, stdin_text=""):
    return subprocess.run(
        ["sh", "-c", script],
        input=stdin_text,
        env=env,
        text=True,
        capture_output=True,
        timeout=20,
    )


class Socks5ProtocolTest(unittest.TestCase):
    def test_socks5_menu_core_and_ports(self):
        menu = between("# ---------- 4. 问：协议 ----------", "# 内存很小的机器上已经有节点了")
        ask = between("ask() {", "\nrand_hex() {")
        script = (
            "step() { :; }\ninfo() { :; }\nwarn() { echo \"WARN $1\"; }\ndie() { echo \"DIE $1\"; exit 1; }\n"
            "_ask_node_name() { NODE_NAME=\"香港$1\"; }\n"
            + ask + "\n" + menu + "\n"
            'printf "PROTO=%s|NAME=%s|NM=%s|CORE=%s\\n" "$PROTO" "$PROTO_NAME" "$_nm_proto" "$CORE"\n'
        )
        res = run_sh(script, stdin_text="10\n")
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
        self.assertIn("PROTO=socks5|NAME=SOCKS5|NM=Socks5|CORE=xray", res.stdout)

    def test_socks5_node_name_dedup_uses_dash(self):
        fn = between("_node_name() {", "\n_name_taken() {")
        with tempfile.TemporaryDirectory() as tmp:
            nodes = Path(tmp) / "nodes"
            (nodes / "1").mkdir(parents=True)
            (nodes / "1" / "name").write_text("香港Socks5\n")
            script = (
                f"XRAY_NODES_DIR='{nodes}'\nNODE_REGION='香港'\n"
                + fn + "\n"
                "_node_name Socks5\n"
            )
            res = run_sh(script)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(res.stdout.strip(), "香港Socks5-2")

    def test_socks5_xray_config_valid_json(self):
        sec10 = between("# ---------- 10. 写配置文件 ----------", '\nelif [ "$CORE" = "hysteria" ]; then')
        sec10 = sec10.replace("mkdir -p /etc/xray-node", ":")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            node_dir = root / "node"
            node_dir.mkdir()
            fake_xray = root / "xray"
            fake_xray.write_text("#!/bin/sh\nexit 0\n")
            fake_xray.chmod(0o755)
            script = (
                "step() { :; }\ninfo() { :; }\ndie() { echo \"DIE $1\" >&2; exit 1; }\n"
                "_v6_listen_ok() { return 0; }\n"
                f"CORE=xray\nPROTO=socks5\nIPVER=4\nPORT=23456\n"
                f"SOCKS_USER='0123456789abcdef'\nSOCKS_PASS='fedcba98765432100123456789abcdef'\n"
                f"NODE_DIR='{node_dir}'\nXRAY_BIN='{fake_xray}'\n"
                + sec10 + "\nfi\n"
            )
            res = run_sh(script)
            self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
            cfg = json.loads((node_dir / "config.json").read_text())
            ib = cfg["inbounds"][0]
            self.assertEqual(ib["listen"], "::")
            self.assertEqual(ib["port"], 23456)
            self.assertEqual(ib["protocol"], "socks")
            self.assertEqual(ib["settings"]["auth"], "password")
            self.assertEqual(ib["settings"]["accounts"], [{"user": "0123456789abcdef", "pass": "fedcba98765432100123456789abcdef"}])
            self.assertIs(ib["settings"]["udp"], True)
            self.assertEqual(cfg["outbounds"], [{"protocol": "freedom"}])

    def test_socks5_links_loon_surge_nodetxt_and_jiedian(self):
        urlenc = between("_urlenc() {", "\n_node_name() {")
        cq_funcs = between("_cq_ok() {", "\n_cq_strip_xray() {")
        sec13 = between("# ---------- 13. 生成节点链接 ----------", "# ---------- 14. 保存 + jiedian 命令 ----------")
        sec14 = between("# ---------- 14. 保存 + jiedian 命令 ----------", "\nwrite_helper_cmds")
        jiedian_body = between("cat > /usr/local/bin/jiedian <<'JDEOF'\n", "\nJDEOF").split("\n", 1)[1]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            node_dir = root / "nodes" / "1"
            node_dir.mkdir(parents=True)
            script = (
                "step() { :; }\ninfo() { :; }\nwarn() { :; }\ndie() { echo \"DIE $1\" >&2; exit 1; }\n"
                + urlenc + "\n" + cq_funcs + "\n"
                f"PROTO=socks5\nPROTO_NAME=SOCKS5\nNODE_NAME='香港Socks5'\n"
                f"SERVER_IP='203.0.113.10'\nLINK_IP='203.0.113.10'\n"
                f"PORT=23456\nLINK_PORT=23456\nIPVER=4\nNODE_KIND=permanent\n"
                f"SOCKS_USER='aabbccddeeff0011'\nSOCKS_PASS='11223344556677889900aabbccddeeff'\n"
                f"NODE_DIR='{node_dir}'\n"
                + sec13 + "\n" + sec14 + "\n"
                'printf "LINK=%s\\nLOON=%s\\n" "$LINK" "$LOON_LINE"\n'
                'CQ_PROTO=""; CQ_USER=""; CQ_PASS=""; CQ_HOST=""; CQ_PORT=""; CQ_NAME=""\n'
                f'_cq_from_nodetxt "{node_dir}"\n'
                'printf "RT_PROTO=%s|RT_USER=%s|RT_PASS=%s\\n" "$CQ_PROTO" "$CQ_USER" "$CQ_PASS"\n'
                'printf "RT_LOON=%s\\n" "$(_cq_loon_line)"\n'
                'printf "RT_SURGE=%s\\n" "$(_cq_surge_line)"\n'
            )
            res = run_sh(script)
            self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
            expected_link = "socks5://aabbccddeeff0011:11223344556677889900aabbccddeeff@203.0.113.10:23456#%E9%A6%99%E6%B8%AFSocks5"
            expected_loon = '香港Socks5 = SOCKS5,203.0.113.10,23456,aabbccddeeff0011,"11223344556677889900aabbccddeeff",udp=true,block-quic=true'
            expected_surge = "香港Socks5 = socks5, 203.0.113.10, 23456, aabbccddeeff0011, 11223344556677889900aabbccddeeff, udp-relay=true, block-quic=on"
            self.assertIn(f"LINK={expected_link}", res.stdout)
            self.assertIn(f"LOON={expected_loon}", res.stdout)
            self.assertIn("RT_PROTO=socks5|RT_USER=aabbccddeeff0011|RT_PASS=11223344556677889900aabbccddeeff", res.stdout)
            self.assertIn(f"RT_LOON={expected_loon}", res.stdout)
            self.assertIn(f"RT_SURGE={expected_surge}", res.stdout)

            nt = (node_dir / "node.txt").read_text()
            self.assertIn("用户名: aabbccddeeff0011", nt)
            self.assertIn("密码: 11223344556677889900aabbccddeeff", nt)
            self.assertIn("https://t.me/socks?server=203.0.113.10&port=23456&user=aabbccddeeff0011&pass=11223344556677889900aabbccddeeff", nt)
            self.assertIn("type: socks5", nt)
            self.assertIn(expected_loon, nt)
            self.assertIn(expected_surge, nt)

            # Verify jiedian extracts both the socks5:// link and the SOCKS5 Loon line
            jiedian_script = jiedian_body.replace("/etc/xray-node/nodes", str(root / "nodes"))
            jres = run_sh(jiedian_script)
            self.assertEqual(jres.returncode, 0, jres.stderr + jres.stdout)
            self.assertIn(expected_link, jres.stdout)
            self.assertIn(expected_loon, jres.stdout)

    def test_socks5_ipv6_link_brackets(self):
        urlenc = between("_urlenc() {", "\n_node_name() {")
        sec13 = between("# ---------- 13. 生成节点链接 ----------", "# ---------- 14. 保存 + jiedian 命令 ----------")
        with tempfile.TemporaryDirectory() as tmp:
            node_dir = Path(tmp)
            script = (
                "step() { :; }\n" + urlenc + "\n"
                f"PROTO=socks5\nNODE_NAME='v6Socks5'\nSERVER_IP='2001:db8::1'\nLINK_IP='[2001:db8::1]'\n"
                f"LINK_PORT=1080\nSOCKS_USER='u1'\nSOCKS_PASS='p1'\nNODE_DIR='{node_dir}'\n"
                + sec13 + "\nprintf '%s\\n' \"$LINK\"\n"
            )
            res = run_sh(script)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(res.stdout.strip(), "socks5://u1:p1@[2001:db8::1]:1080#v6Socks5")


class AuditFixesRegressionTest(unittest.TestCase):
    def test_gen_uuid_fallback_is_rfc4122_v4(self):
        rand_hex = between("rand_hex() {", "\n# 查某个端口")
        gen_uuid = between("gen_uuid() {", "\n# base64 是把任意内容")
        # Force fallback path by replacing /proc/sys/kernel/random/uuid with nonexistent path
        gen_uuid_fb = gen_uuid.replace("/proc/sys/kernel/random/uuid", "/nonexistent/uuid")
        res = run_sh(rand_hex + "\n" + gen_uuid_fb + "\ngen_uuid\n")
        self.assertEqual(res.returncode, 0, res.stderr)
        u = res.stdout.strip()
        self.assertRegex(u, r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

    def test_ss_pass_falls_back_when_openssl_fails(self):
        sec7 = between("# ---------- 7. 随机生成 UUID / 密码 ----------", "# ---------- 8. 下载内核 ----------")
        rand_hex = between("rand_hex() {", "\n# 查某个端口")
        gen_uuid = between("gen_uuid() {", "\n# base64 是把任意内容")
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp) / "bin"
            bindir.mkdir()
            bad_openssl = bindir / "openssl"
            bad_openssl.write_text("#!/bin/sh\nexit 1\n")
            bad_openssl.chmod(0o755)
            script = (
                "step() { :; }\ninfo() { :; }\ndie() { echo \"DIE $1\" >&2; exit 1; }\n"
                + rand_hex + "\n" + gen_uuid + "\n"
                "PROTO=ss\n" + sec7 + "\n"
                'printf "SS_PASS=%s\\n" "$SS_PASS"\n'
            )
            env = dict(os.environ, PATH=f"{bindir}:/usr/bin:/bin")
            res = run_sh(script, env=env)
            self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
            m = re.search(r"SS_PASS=(\S+)", res.stdout)
            self.assertIsNotNone(m, res.stdout)
            self.assertEqual(len(m.group(1)), 24)

    def test_xray_dualstack_fallback_to_ipv4_in_11b(self):
        sec11b = between("_svc_recheck() {", "\n# 端口跳跃：不靠")
        with tempfile.TemporaryDirectory() as tmp:
            node_dir = Path(tmp) / "node"
            node_dir.mkdir()
            (node_dir / "config.json").write_text('{\n  "inbounds": [ { "listen": "::", "port": 23456 } ]\n}\n')
            script = (
                "warn() { echo \"WARN $1\"; }\n"
                "wait_for_port() { echo \"WAIT $1 $2\"; return 0; }\n"
                "_svc_restart() { echo \"RESTART $1\"; }\n"
                "pgrep() { return 0; }\n"
                "CORE=xray\nPROTO=ss\nIPVER=4\nPORT=23456\nNODE_ID=1\n"
                f"NODE_DIR='{node_dir}'\nXRAY_LISTEN='::'\n_SVC_PROTOS='tcp udp'\n_svc_listen_ok=0\nSVC_UNIT=''\n"
                + sec11b + "\n"
                'printf "OK=%s|LISTEN=%s\\n" "$_svc_listen_ok" "$XRAY_LISTEN"\n'
            )
            res = run_sh(script)
            self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
            self.assertIn("RESTART 1", res.stdout)
            self.assertIn("WAIT 23456 tcp", res.stdout)
            self.assertIn("WAIT 23456 udp", res.stdout)
            self.assertIn("OK=1|LISTEN=0.0.0.0", res.stdout)
            self.assertIn('"listen": "0.0.0.0"', (node_dir / "config.json").read_text())

    def test_save_fw_falls_back_to_light_when_iptables_persistent_fails(self):
        body = between("_save_fw() {", "\n# _fw_allow ")
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp) / "bin"
            bindir.mkdir()
            for name in ("iptables-save", "apt-get", "rc-update"):
                stub = bindir / name
                stub.write_text("#!/bin/sh\nexit 0\n")
                stub.chmod(0o755)
            initd = Path(tmp) / "init.d"
            initd.mkdir()
            patched = body.replace("/etc/init.d", str(initd))
            script = (
                "LOW_MEM=0\nwarn() { echo \"WARN $1\"; }\ninfo() { echo \"INFO $1\"; }\n"
                "_apt_do() { return 1; }\n"
                "_save_fw_light() { echo LIGHT_FALLBACK; return 0; }\n"
                + patched + "\n_save_fw 4\n"
            )
            env = dict(os.environ, PATH=f"{bindir}:/usr/bin:/bin")
            if any(Path(d, n).exists() for d in ("/usr/bin", "/bin") for n in ("ufw", "firewall-cmd", "netfilter-persistent")):
                self.skipTest("host has ufw/firewalld/netfilter-persistent in /usr/bin")
            res = run_sh(script, env=env)
            self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
            self.assertIn("LIGHT_FALLBACK", res.stdout)


if __name__ == "__main__":
    unittest.main()
