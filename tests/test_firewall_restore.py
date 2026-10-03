"""Run the installer's generated firewall restore script without root privileges."""

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


class FirewallRestoreTest(unittest.TestCase):
    def test_restores_only_owned_rules_and_is_idempotent(self):
        source = INSTALLER.read_text()
        match = re.search(
            r"cat > /usr/local/bin/xray-node-fw-restore <<'FWEOF' \|\| return 1\n(.*?)\nFWEOF",
            source,
            re.S,
        )
        self.assertIsNotNone(match)

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            nodes = root / "nodes"
            for node, rule in (
                ("1", "12345 tcp 0 0 1 4\n"),
                ("2", "23456 udp 0 0 1 6\n"),
                ("3", "34567 tcp 1 0 0 4\n"),
            ):
                directory = nodes / node
                directory.mkdir(parents=True)
                (directory / "fw_info").write_text(rule)

            restore = root / "restore.sh"
            restore.write_text(match.group(1) + "\n")
            mock_bin = root / "bin"
            mock_bin.mkdir()
            mock = mock_bin / "iptables"
            mock.write_text(
                "#!/bin/sh\n"
                'op=$1; shift; key="$(basename "$0") $*"\n'
                'case "$op" in\n'
                '  -C) grep -Fqx "$key" "$MOCK_STATE" ;;\n'
                '  -I) case "$key" in *"--dport $MOCK_DENY "*) exit 1 ;; esac\n'
                '      printf "%s\\n" "$key" >> "$MOCK_STATE" ;;\n'
                '  *) exit 2 ;;\n'
                "esac\n"
            )
            mock.chmod(0o755)
            (mock_bin / "ip6tables").symlink_to(mock)
            state = root / "state"
            existing = "iptables INPUT -p tcp --dport 22 -j ACCEPT"
            state.write_text(existing + "\n")
            env = os.environ.copy()
            env.update({
                "PATH": f"{mock_bin}:{os.environ['PATH']}",
                "XRAY_NODE_DIR": str(nodes),
                "MOCK_STATE": str(state),
                "MOCK_DENY": "",
            })

            for _ in range(2):
                subprocess.run(["sh", str(restore)], env=env, check=True)
            self.assertEqual(
                state.read_text().splitlines(),
                [
                    existing,
                    "iptables INPUT -p tcp --dport 12345 -j ACCEPT",
                    "ip6tables INPUT -p udp --dport 23456 -j ACCEPT",
                ],
            )

            state.write_text(existing + "\n")
            env["MOCK_DENY"] = "23456"
            failed = subprocess.run(["sh", str(restore)], env=env, check=False)
            self.assertNotEqual(failed.returncode, 0)


class PortCheckTest(unittest.TestCase):

    def test_port_in_use_proc_fallback_detects_occupied_ports(self):
        """Without ss/netstat, occupied ports must not look free (else install can false-succeed)."""
        source = INSTALLER.read_text()
        match = re.search(
            r"(port_in_use\(\) \{.*?\n\})\n\n(?:#[^\n]*\n)*rand_port",
            source,
            re.S,
        )
        self.assertIsNotNone(match)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            net = root / "net"
            net.mkdir()
            (net / "tcp").write_text(
                "sl local_address rem_address st\n"
                "0: 00000000:3039 00000000:0000 0A\n"
            )
            (net / "udp").write_text(
                "sl local_address rem_address st\n"
                "0: 00000000:5BA0 00000000:0000 07\n"
            )
            function = match.group(1).replace("/proc/net", str(net))
            stubs = "command() { return 1; }; "
            for port, proto, expected in (
                (12345, "tcp", 0),
                (23456, "udp", 0),
                (12346, "tcp", 1),
                (12345, "udp", 1),
            ):
                result = subprocess.run(
                    ["sh", "-c", stubs + function + f"\nport_in_use {port} {proto}"],
                )
                self.assertEqual(result.returncode, expected, (port, proto))

    def test_proc_fallback_requires_a_matching_socket(self):
        source = INSTALLER.read_text()
        match = re.search(
            r"(wait_for_port\(\) \{.*?\n\})\n\n(?:#[^\n]*\n)*# 小内存机器",
            source,
            re.S,
        )
        self.assertIsNotNone(match)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            net = root / "net"
            net.mkdir()
            (net / "tcp").write_text(
                "sl local_address rem_address st\n"
                "0: 00000000:3039 00000000:0000 0A\n"
            )
            (net / "udp").write_text(
                "sl local_address rem_address st\n"
                "0: 00000000:5BA0 00000000:0000 07\n"
            )
            function = match.group(1).replace("/proc/net", str(net))
            stubs = "command() { return 1; }; sleep() { :; }; "
            for port, proto, expected in (
                (12345, "tcp", 0),
                (23456, "udp", 0),
                (12346, "tcp", 1),
                (12345, "udp", 1),
            ):
                result = subprocess.run(
                    ["sh", "-c", stubs + function + f"\nwait_for_port {port} {proto} 1"],
                )
                self.assertEqual(result.returncode, expected, (port, proto))


class HysteriaLinkTest(unittest.TestCase):
    def test_self_signed_link_enables_pin_verification(self):
        source = INSTALLER.read_text()
        match = re.search(r'^\s*(LINK="hysteria2://[^"\n]+")$', source, re.M)
        self.assertIsNotNone(match)
        pin = "A" * 64
        env = os.environ.copy()
        env.update({
            "HY2_PASS": "secret",
            "HY2_OBFS": "ab" * 16,
            "LINK_IP": "203.0.113.1",
            "LINK_PORT": "443",
            "HY2_PIN": pin,
        })
        result = subprocess.run(
            ["sh", "-c", match.group(1) + "\nprintf '%s\\n' \"$LINK\""],
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        url = urlsplit(result.stdout.strip())
        query = parse_qs(url.query)
        self.assertEqual(url.scheme, "hysteria2")
        self.assertEqual(url.hostname, "203.0.113.1")
        self.assertEqual(url.port, 443)
        self.assertEqual(query["insecure"], ["1"])
        self.assertEqual(query["pinSHA256"], [pin])
        self.assertEqual(query["pcs"], [pin])
        self.assertEqual(query["obfs"], ["salamander"])
        self.assertEqual(query["obfs-password"], ["ab" * 16])
        self.assertNotIn("mport", query)

    def test_hop_ports_go_in_mport_and_leave_the_main_port_alone(self):
        source = INSTALLER.read_text()
        match = re.search(r'^\s*(LINK="hysteria2://[^"\n]+")$', source, re.M)
        self.assertIsNotNone(match)
        pin = "A" * 64
        env = os.environ.copy()
        env.update({
            "HY2_PASS": "secret",
            "HY2_OBFS": "cd" * 16,
            "LINK_IP": "203.0.113.1",
            "LINK_PORT": "443",
            "HY2_PIN": pin,
            "HY_MPORT": "443,20000,20001",
        })
        result = subprocess.run(
            ["sh", "-c", match.group(1) + "\nprintf '%s\\n' \"$LINK\""],
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        url = urlsplit(result.stdout.strip())
        query = parse_qs(url.query)
        self.assertEqual(url.port, 443)
        self.assertNotIn(",", url.netloc)
        self.assertEqual(query["mport"], ["443,20000,20001"])
        self.assertEqual(query["obfs"], ["salamander"])

    def test_existing_hysteria_link_is_repaired_without_changing_credentials(self):
        source = INSTALLER.read_text()
        match = re.search(
            r"(write_helper_cmds\(\) \{.*?\n\})\n\n(?:#[^\n]*\n)*_hy_export_env",
            source,
            re.S,
        )
        self.assertIsNotNone(match)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "bin").mkdir()
            node = root / "nodes" / "1"
            node.mkdir(parents=True)
            (node / "core").write_text("hysteria\n")
            old_link = (
                "hysteria2://secret@203.0.113.1:443/"
                "?sni=www.samsung.com&pinSHA256=" + "A" * 64 + "#xray-node"
            )
            info = node / "node.txt"
            info.write_text(old_link + "\n")
            function = match.group(1).replace(
                "/usr/local/bin", str(root / "bin")
            ).replace(
                "/etc/xray-node/nodes", str(root / "nodes")
            )
            for _ in range(2):
                subprocess.run(
                    ["sh", "-c", "install_expire_bins() { :; }\narm_expire_watch() { :; }\n" + function + "\nwrite_helper_cmds"],
                    check=True,
                )
            updated = info.read_text().strip()
            self.assertEqual(
                updated,
                old_link.replace("?sni=", "?insecure=1&sni="),
            )


class LegacyMigrationTest(unittest.TestCase):
    def migration_script(self, root):
        source = INSTALLER.read_text()
        match = re.search(
            r"(if \[ -f /etc/xray-node/node\.txt \] && \[ ! -d /etc/xray-node/nodes \]; then.*?\nfi)\n\n(?:#[^\n]*\n)*# 已经装过节点",
            source,
            re.S,
        )
        self.assertIsNotNone(match)
        return match.group(1).replace(
            "/etc/xray-node", str(root / "etc" / "xray-node")
        ).replace(
            "/usr/local/etc/xray", str(root / "old-xray")
        ).replace(
            "/usr/local/etc/sing-box", str(root / "old-sing-box")
        ).replace(
            "/run/systemd/system", str(root / "run" / "systemd" / "system")
        ).replace(
            "/etc/systemd/system", str(root / "etc" / "systemd" / "system")
        )

    def test_missing_config_preserves_legacy_node_details(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            old = root / "etc" / "xray-node"
            old.mkdir(parents=True)
            info = old / "node.txt"
            info.write_text("legacy credentials\n")
            (old / "core").write_text("xray\n")
            result = subprocess.run(
                ["sh", "-c", "step() { :; }\ndie() { exit 2; }\n" + self.migration_script(root)],
            )
            self.assertEqual(result.returncode, 2)
            self.assertEqual(info.read_text(), "legacy credentials\n")
            self.assertFalse((old / "nodes").exists())

    def test_failed_new_service_restores_old_service_and_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            old = root / "etc" / "xray-node"
            old.mkdir(parents=True)
            (root / "old-xray").mkdir()
            (root / "run" / "systemd" / "system").mkdir(parents=True)
            info = old / "node.txt"
            info.write_text("协议: vless\n端口: 12345\nlegacy credentials\n")
            config = root / "old-xray" / "config.json"
            config.write_text('{"inbounds": []}\n')
            (old / "core").write_text("xray\n")
            service_log = root / "service.log"
            stubs = (
                'step() { :; }; warn() { :; }; info() { :; }; sleep() { :; }; '
                'pkill() { :; }; ss() { :; }; _svc_install() { :; }; '
                'wait_for_port() { return 1; }; die() { exit 2; }; '
                'systemctl() { printf "%s\\n" "$*" >> "$SERVICE_LOG"; '
                'case "$1" in is-active) return 1 ;; esac; }; '
            )
            env = os.environ.copy()
            env["SERVICE_LOG"] = str(service_log)
            result = subprocess.run(
                ["sh", "-c", stubs + self.migration_script(root)], env=env
            )
            self.assertEqual(result.returncode, 2)
            self.assertEqual(info.read_text(), "协议: vless\n端口: 12345\nlegacy credentials\n")
            self.assertEqual(config.read_text(), '{"inbounds": []}\n')
            self.assertFalse((old / "nodes").exists())
            self.assertIn("start xray", service_log.read_text().splitlines())

    def test_old_service_is_removed_only_after_new_service_listens(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            old = root / "etc" / "xray-node"
            old.mkdir(parents=True)
            (root / "old-xray").mkdir()
            (root / "run" / "systemd" / "system").mkdir(parents=True)
            old_unit = root / "etc" / "systemd" / "system" / "xray.service"
            old_unit.parent.mkdir(parents=True)
            old_unit.write_text("legacy unit\n")
            (old / "node.txt").write_text("协议: vless\n端口: 12345\n")
            (old / "core").write_text("xray\n")
            config = root / "old-xray" / "config.json"
            config.write_text('{"inbounds": []}\n')
            service_log = root / "service.log"
            stubs = (
                'step() { :; }; warn() { :; }; info() { :; }; sleep() { :; }; '
                'pkill() { :; }; ss() { :; }; _svc_install() { :; }; '
                'write_helper_cmds() { echo helpers >> "$SERVICE_LOG.helpers"; }; '
                'wait_for_port() { return 0; }; die() { exit 2; }; '
                'systemctl() { printf "%s\\n" "$*" >> "$SERVICE_LOG"; }; '
            )
            env = os.environ.copy()
            env["SERVICE_LOG"] = str(service_log)
            subprocess.run(
                ["sh", "-c", stubs + self.migration_script(root)],
                env=env,
                check=True,
            )
            self.assertFalse(config.exists())
            self.assertFalse((old / "node.txt").exists())
            self.assertFalse(old_unit.exists())
            self.assertEqual(
                (old / "nodes" / "1" / "config.json").read_text(),
                '{"inbounds": []}\n',
            )
            self.assertEqual(
                service_log.read_text().splitlines(),
                ["stop xray", "is-active --quiet xray-node@1", "disable xray", "daemon-reload"],
            )
            # 迁移成功后马上换新版 jiedian/shanjiedian，老版 xiezai 不能留着
            self.assertEqual(Path(str(service_log) + ".helpers").read_text(), "helpers\n")


class XrayListenTest(unittest.TestCase):
    def test_xray_inbounds_bind_listen_by_ipver(self):
        """Pure IPv6 installs must not leave Xray on default 0.0.0.0-only (false success)."""
        source = INSTALLER.read_text()
        self.assertIn('if [ "$IPVER" = "6" ]; then XRAY_LISTEN="::"; else XRAY_LISTEN="0.0.0.0"; fi', source)
        self.assertEqual(source.count('"listen": "$XRAY_LISTEN"'), 4)
        # Each Xray protocol inbound must include the listen field.
        for proto in ("vless", "trojan", "vmess", "shadowsocks"):
            self.assertIn(f'"protocol": "{proto}"', source)
            idx = source.find(f'"protocol": "{proto}"')
            window = source[max(0, idx - 120):idx]
            self.assertIn('"listen": "$XRAY_LISTEN"', window, msg=proto)


class IPv6ValidationTest(unittest.TestCase):
    def function(self):
        source = INSTALLER.read_text()
        match = re.search(r"(_valid_ip\(\) \{.*?\n\})\n\n(?:#[^\n]*\n)*# gh_api_dl", source, re.S)
        self.assertIsNotNone(match)
        return match.group(1)

    def accepts(self, value, version="6"):
        result = subprocess.run(
            ["sh", "-c", self.function() + f"\n_valid_ip {version} \"$1\"", "sh", value],
        )
        return result.returncode == 0

    def test_rejects_text_and_short_groups_and_accepts_real_addresses(self):
        self.assertTrue(self.accepts("2001:db8::1"))
        self.assertTrue(self.accepts("[2001:db8::1]"))
        self.assertTrue(self.accepts("2001:0db8:0000:0000:0000:0000:0000:0001"))
        self.assertFalse(self.accepts("error: no address"))
        self.assertFalse(self.accepts("dead:beef"))
        self.assertFalse(self.accepts("2001:db8::1::2"))
        self.assertFalse(self.accepts(":::"))
        self.assertTrue(self.accepts("203.0.113.10", "4"))
        self.assertFalse(self.accepts("203.0.113.256", "4"))


class FstabSwapTest(unittest.TestCase):
    def append_function(self):
        source = INSTALLER.read_text()
        match = re.search(r"(_fstab_append_swap\(\) \{.*?\n\})\n\n(?:#[^\n]*\n)*# 64MB", source, re.S)
        self.assertIsNotNone(match)
        return match.group(1)

    def test_missing_newline_does_not_glue_root_line(self):
        with tempfile.TemporaryDirectory() as temp:
            fstab = Path(temp) / "fstab"
            fstab.write_bytes(b"/dev/vda1 / ext4 defaults 0 1")
            env = os.environ.copy()
            env["XRAY_FSTAB"] = str(fstab)
            subprocess.run(
                ["sh", "-c", self.append_function() + "\n_fstab_append_swap"],
                env=env,
                check=True,
            )
            lines = fstab.read_text().splitlines()
            self.assertEqual(lines[0], "/dev/vda1 / ext4 defaults 0 1")
            self.assertEqual(lines[1], "/xray-node.swap none swap sw 0 0")

    def test_glued_line_is_split(self):
        with tempfile.TemporaryDirectory() as temp:
            fstab = Path(temp) / "fstab"
            fstab.write_text("/dev/vda1 / ext4 defaults 0 1/xray-node.swap none swap sw 0 0\n")
            env = os.environ.copy()
            env["XRAY_FSTAB"] = str(fstab)
            subprocess.run(
                ["sh", "-c", self.append_function() + "\n_fstab_append_swap"],
                env=env,
                check=True,
            )
            self.assertEqual(
                fstab.read_text().splitlines(),
                [
                    "/dev/vda1 / ext4 defaults 0 1",
                    "/xray-node.swap none swap sw 0 0",
                ],
            )


class PartialNodeTest(unittest.TestCase):
    def functions(self):
        source = INSTALLER.read_text()
        start = source.index("_drop_partial_node() {")
        end = source.index("\n_abort_partial_node() {")
        return source[start:end]

    def test_reap_removes_unfinished_node_and_stops_its_unit(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            nodes = root / "nodes"
            bad = nodes / "3"
            good = nodes / "2"
            bad.mkdir(parents=True)
            good.mkdir()
            (bad / "core").write_text("hysteria\n")
            (bad / "config.yaml").write_text("listen: 1\n")
            (good / "node.txt").write_text("keep\n")
            (good / "core").write_text("xray\n")
            sd = root / "systemd"
            sd.mkdir()
            log = root / "svc.log"
            env = os.environ.copy()
            env.update({
                "XRAY_NODES_DIR": str(nodes),
                "XRAY_SYSTEMD_RUN": str(sd),
                "SVC_LOG": str(log),
            })
            stubs = (
                'warn() { :; }; '
                'systemctl() { printf "%s\\n" "$*" >> "$SVC_LOG"; }; '
                'pkill() { printf "%s\\n" "$*" >> "$SVC_LOG"; return 0; }; '
            )
            subprocess.run(
                ["sh", "-c", stubs + self.functions() + "\n_reap_partial_nodes"],
                env=env,
                check=True,
            )
            self.assertFalse(bad.exists())
            self.assertTrue((good / "node.txt").exists())
            logged = log.read_text().splitlines()
            self.assertIn("stop hysteria-node@3", logged)
            self.assertIn("disable hysteria-node@3", logged)
            self.assertTrue(any("config.yaml" in line for line in logged))
            self.assertFalse(any("nodes/2" in line or line.endswith("@2") for line in logged))


class DeleteNodeSelectionTest(unittest.TestCase):
    def menu_script(self, nodes):
        source = INSTALLER.read_text()
        start = source.index("cat > /usr/local/bin/shanjiedian <<'XZEOF'\n")
        start += len("cat > /usr/local/bin/shanjiedian <<'XZEOF'\n")
        script = source[start:source.index("\nXZEOF\n", start)]
        script = script.replace(
            '_del_node() {\n  _d_id="$1"\n',
            '_del_node() {\n  _d_id="$1"\n'
            '  printf "%s\\n" "$_d_id" >> "$DELETE_LOG"\n'
            '  return 0\n',
            1,
        )
        script = script.replace(
            '_uninstall_all() {\n',
            '_uninstall_all() {\n  printf "UNINSTALL\\n" >> "$DELETE_LOG"\n  return 0\n',
            1,
        )
        return script.replace("NODES_DIR=/etc/xray-node/nodes", f"NODES_DIR={nodes}", 1)

    def run_menu(self, answers, node_ids=("2", "5")):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            nodes = root / "nodes"
            for node_id in node_ids:
                directory = nodes / node_id
                directory.mkdir(parents=True)
                (directory / "node.txt").write_text("协议: vless\n端口: 443\n")
            log = root / "deleted"
            env = os.environ.copy()
            env["DELETE_LOG"] = str(log)
            result = subprocess.run(
                ["sh", "-c", self.menu_script(nodes)],
                input=answers,
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            logged = log.read_text() if log.exists() else ""
            return result, logged

    def test_menu_deletes_the_real_node_id(self):
        result, logged = self.run_menu("2\n")
        self.assertIn("2) 删除节点 2", result.stdout)
        self.assertIn("5) 删除节点 5", result.stdout)
        self.assertLess(result.stdout.index("2) 删除节点 2"), result.stdout.index("5) 删除节点 5"))
        self.assertEqual(logged.splitlines(), ["2"])

        missed, missed_log = self.run_menu("1\n")
        self.assertIn("没有这个编号", missed.stdout)
        self.assertEqual(missed_log, "")

    def test_next_number_deletes_every_node(self):
        shown, shown_log = self.run_menu("\n", ("1", "2", "3"))
        self.assertIn("1) 删除节点 1", shown.stdout)
        self.assertIn("2) 删除节点 2", shown.stdout)
        self.assertIn("3) 删除节点 3", shown.stdout)
        self.assertIn("4) 删除全部节点并卸载干净", shown.stdout)
        self.assertNotIn("all", shown.stdout.lower())
        self.assertEqual(shown_log, "")

        confirmed, confirmed_log = self.run_menu("4\ny\n", ("1", "2", "3"))
        self.assertEqual(confirmed_log.splitlines(), ["UNINSTALL"])

        refused, refused_log = self.run_menu("4\n\n", ("1", "2", "3"))
        self.assertIn("已取消", refused.stdout)
        self.assertNotIn("UNINSTALL", refused_log)

        word, word_log = self.run_menu("all\n", ("1", "2", "3"))
        self.assertIn("输入不对", word.stdout)
        self.assertNotIn("UNINSTALL", word_log)

        # 节点编号有空档时，不能把下一个菜单序号当成那个节点。
        # 节点是 2 和 5，删除全部是 6。输入 4 什么都不删，输入 2 只删节点 2。
        gap, gap_log = self.run_menu("4\ny\n")
        self.assertNotIn("UNINSTALL", gap_log)
        self.assertEqual(gap_log, "")
        self.assertIn("6) 删除全部节点并卸载干净", gap.stdout)

        only_two, only_log = self.run_menu("6\ny\n")
        self.assertEqual(only_log.splitlines(), ["UNINSTALL"])

    def test_leading_zero_still_selects_the_real_node(self):
        result, logged = self.run_menu("02\n")
        self.assertEqual(logged.splitlines(), ["2"])
        self.assertIn("5) 删除节点 5", result.stdout)


class ServerAddressTest(unittest.TestCase):
    def functions(self):
        source = INSTALLER.read_text()
        start = source.index("get_ip() {")
        end = source.index("\n# gh_api_dl ")
        return source[start:end]

    def run_get(self, version, ip_stub, curl_ip):
        script = (
            "ip() {\n"
            + ip_stub
            + "\n}\n"
            + "curl() { printf '%s\\n' '"
            + curl_ip
            + "'; }\n"
            + self.functions()
            + "\nget_ip "
            + version
            + "\n"
        )
        return subprocess.run(["sh", "-c", script], text=True, capture_output=True)

    def test_public_nic_address_is_kept_when_curl_sees_the_tunnel(self):
        result = self.run_get(
            "4",
            '''
            case "$*" in
              "-4 route show default table main") echo "default via 192.0.2.1 dev eth0";;
              "-4 -o addr show dev eth0 scope global") echo "2: eth0 inet 203.0.113.10/24 scope global eth0";;
              *) return 1;;
            esac
            ''',
            "198.51.100.8",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "203.0.113.10")

    def test_private_nic_without_tunnel_uses_the_nat_address(self):
        result = self.run_get(
            "4",
            '''
            case "$*" in
              "-4 route show default table main") echo "default via 10.0.0.1 dev eth0";;
              "-4 -o addr show dev eth0 scope global") echo "2: eth0 inet 10.0.0.5/24 scope global eth0";;
              "-4 addr show dev l2tp-aa") return 1;;
              *) return 1;;
            esac
            ''',
            "203.0.113.9",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "203.0.113.9")

    def test_private_nic_with_tunnel_does_not_publish_the_tunnel_address(self):
        result = self.run_get(
            "4",
            '''
            case "$*" in
              "-4 route show default table main") echo "default via 10.0.0.1 dev eth0";;
              "-4 -o addr show dev eth0 scope global") echo "2: eth0 inet 10.0.0.5/24 scope global eth0";;
              "-4 addr show dev l2tp-aa") echo "8: l2tp-aa inet 198.51.100.10/32 scope global";;
              *) return 1;;
            esac
            ''',
            "198.51.100.8",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("198.51.100.8", result.stdout)


class HysteriaHopTest(unittest.TestCase):
    def source_between(self, start, end):
        source = INSTALLER.read_text()
        begin = source.index(start)
        return source[begin:source.index(end, begin)]

    def test_config_turns_on_salamander_and_drops_the_builtin_404(self):
        source = INSTALLER.read_text()
        self.assertIn("type: salamander", source)
        self.assertIn("sniGuard: dns-san", source)
        self.assertNotIn('type: "404"', source)
        self.assertIn("请设置你的端口跳跃%s:", source)
        self.assertIn("salamander-password=${HY2_OBFS}", source)
        self.assertNotIn('salamander-password=\\"${HY2_OBFS}\\"', source)
        self.assertIn("block-quic=true", source)
        self.assertNotIn("block-quic=false", source)
        self.assertIn("HYSTERIA_FIREWALL_BACKEND=${HY2_FW_BACKEND}", source)
        self.assertIn("改用 iptables 再试一次。", source)

    def run_collect(self, answers, port="443", link_port="443"):
        function = self.source_between("_hy_hop_taken() {", "\n_hy_listen_for() {")
        script = (
            "warn() { printf 'WARN %s\\n' \"$1\"; }\n"
            "info() { printf 'INFO %s\\n' \"$1\"; }\n"
            "die() { printf 'DIE %s\\n' \"$1\" >&2; exit 1; }\n"
            "port_in_use() { [ \"$1\" = 9 ]; }\n"
            f"PORT={port}\nLINK_PORT={link_port}\n"
            + function
            + "\n_hy_collect_hop_ports\nprintf 'HOPS=%s\\n' \"$HY_HOP_PORTS\"\n"
        )
        return subprocess.run(
            ["sh", "-c", script],
            input=answers,
            text=True,
            capture_output=True,
            check=True,
        )

    def test_ports_are_asked_one_by_one_until_a_blank_line(self):
        result = self.run_collect("20000\n443\n9\n20000\n20001\n\n")
        self.assertIn("HOPS=20000,20001\n", result.stdout)
        self.assertIn("请设置你的端口跳跃1:", result.stdout)
        self.assertIn("请设置你的端口跳跃2:", result.stdout)
        self.assertIn("请设置你的端口跳跃3:", result.stdout)
        self.assertIn("这个端口已经用过了", result.stdout)
        self.assertIn("已经有程序在用", result.stdout)

    def test_two_blank_answers_turn_hopping_off(self):
        result = self.run_collect("\n\n")
        self.assertIn("HOPS=\n", result.stdout)
        self.assertIn("改为不开启端口跳跃", result.stdout)

    def test_enter_keeps_hopping_off_and_a_bad_number_asks_again(self):
        function = self.source_between("ask() {", "\nrand_hex() {")
        function += "\n" + self.source_between("_hy_hop_taken() {", "\n_hy_listen_for() {")
        script = (
            "warn() { printf 'WARN %s\\n' \"$1\"; }\n"
            "info() { printf 'INFO %s\\n' \"$1\"; }\n"
            "die() { printf 'DIE %s\\n' \"$1\" >&2; exit 1; }\n"
            "err() { printf 'ERR %s\\n' \"$1\" >&2; }\n"
            "port_in_use() { return 1; }\n"
            "PORT=443\nLINK_PORT=443\n"
            + function
            + "\n_hy_ask_hop\nprintf 'HOPS=%s\\n' \"$HY_HOP_PORTS\"\n"
        )
        off = subprocess.run(
            ["sh", "-c", script],
            input="\n",
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertIn("HOPS=\n", off.stdout)
        self.assertIn("不开启端口跳跃", off.stdout)
        again = subprocess.run(
            ["sh", "-c", script],
            input="9\n1\n20000\n\n",
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertIn("没有这个选项，请重新选择", again.stdout)
        self.assertIn("HOPS=20000\n", again.stdout)
        self.assertIn("请设置你的端口跳跃1:", again.stdout)


class HysteriaIpv6ListenTest(unittest.TestCase):
    def source_between(self, start, end):
        source = INSTALLER.read_text()
        begin = source.index(start)
        return source[begin:source.index(end, begin)]

    def test_single_stack_stays_single_and_dual_uses_wildcard(self):
        function = self.source_between("_hy_listen_for() {", "\n_hy_set_listen() {")
        checks = (
            ("443 4", "0.0.0.0:443"),
            ("443 6", "[::]:443"),
            ("443 4 dual", ":443"),
            ("8443 6 yes", ":8443"),
        )
        for args, expected in checks:
            result = subprocess.run(
                ["sh", "-c", function + f"\n_hy_listen_for {args}\n"],
                text=True,
                capture_output=True,
                check=True,
            )
            self.assertEqual(result.stdout, expected, args)

    def test_existing_ipv4_hysteria_starts_listening_on_ipv6(self):
        function = self.source_between("_hy_set_listen() {", "\n_node_port() {")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            nodes = root / "nodes"
            ipv4 = nodes / "1"
            ipv6 = nodes / "2"
            other = nodes / "4"
            for directory in (ipv4, ipv6, other):
                directory.mkdir(parents=True)
            (ipv4 / "core").write_text("hysteria\n")
            (ipv4 / "config.yaml").write_text(
                'listen: "0.0.0.0:443"\ntls:\n  cert: /tmp/cert.pem\n'
            )
            (ipv4 / "node.txt").write_text(
                "==============================================\n"
                "hysteria2://secret@203.0.113.8:443/"
                "?insecure=1&sni=www.samsung.com&pinSHA256="
                + "ab" * 32
                + "#xray-node\n"
                "协议: Hysteria2\n"
            )
            (ipv4 / "fw_info").write_text("443 udp 0 0 1 4\n")
            (ipv6 / "core").write_text("hysteria\n")
            (ipv6 / "config.yaml").write_text('listen: "[::]:444"\n')
            (other / "core").write_text("xray\n")
            (other / "config.json").write_text("{}\n")
            restart_log = root / "restart.log"
            script = function.replace("/etc/xray-node/nodes", str(nodes))
            stubs = (
                "_hy_local_ipv6() { printf '%s' '2001:db8::20'; }\n"
                "_svc_restart() { printf '%s\\n' \"restart $1\" >> \"$RESTART_LOG\"; }\n"
                "wait_for_port() { return 0; }\n"
                "info() { :; }\n"
                "warn() { :; }\n"
                "_fw_allow() { :; }\n"
                "_save_fw() { :; }\n"
            )
            env = os.environ.copy()
            env["RESTART_LOG"] = str(restart_log)
            env["PATH"] = "/bin:/usr/bin"
            subprocess.run(
                ["sh", "-c", stubs + script + "\n_hy_fix_existing_ipv6\n_hy_fix_existing_ipv6\n"],
                env=env,
                check=True,
            )
            config = (ipv4 / "config.yaml").read_text()
            self.assertIn('listen: ":443"', config)
            self.assertIn("tls:", config)
            self.assertNotIn("0.0.0.0", config)
            self.assertFalse((ipv4 / "config.yaml.bak-ipv6").exists())
            saved = (ipv4 / "node.txt").read_text()
            self.assertEqual(saved.count("hysteria2://"), 2)
            self.assertIn("hysteria2://secret@[2001:db8::20]:443/", saved)
            self.assertIn("pinSHA256=" + "ab" * 32, saved)
            self.assertEqual((ipv6 / "config.yaml").read_text(), 'listen: "[::]:444"\n')
            self.assertEqual((other / "config.json").read_text(), "{}\n")
            self.assertEqual(restart_log.read_text().splitlines(), ["restart 1"])

    def test_failed_ipv6_listen_restores_ipv4_config(self):
        function = self.source_between("_hy_set_listen() {", "\n_node_port() {")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            node = root / "nodes" / "7"
            node.mkdir(parents=True)
            original = 'listen: "0.0.0.0:8443"\nauth:\n  password: "keep"\n'
            (node / "core").write_text("hysteria\n")
            (node / "config.yaml").write_text(original)
            (node / "node.txt").write_text(
                "hysteria2://secret@203.0.113.8:8443/?insecure=1&sni=www.samsung.com#xray-node\n"
            )
            restart_log = root / "restart.log"
            script = function.replace("/etc/xray-node/nodes", str(node.parent))
            stubs = (
                "_hy_local_ipv6() { printf '%s' '2001:db8::20'; }\n"
                "_svc_restart() { printf '%s\\n' \"restart $1\" >> \"$RESTART_LOG\"; }\n"
                "wait_for_port() { return 1; }\n"
                "info() { :; }\n"
                "warn() { :; }\n"
            )
            env = os.environ.copy()
            env["RESTART_LOG"] = str(restart_log)
            env["PATH"] = "/bin:/usr/bin"
            subprocess.run(
                ["sh", "-c", stubs + script + "\n_hy_fix_existing_ipv6\n"],
                env=env,
                check=True,
            )
            self.assertEqual((node / "config.yaml").read_text(), original)
            self.assertFalse((node / "config.yaml.bak-ipv6").exists())
            self.assertEqual((node / "node.txt").read_text().count("hysteria2://"), 1)
            self.assertEqual(restart_log.read_text().splitlines(), ["restart 7", "restart 7"])

    def test_ipv6_rewrite_keeps_hop_ports(self):
        function = self.source_between("_hy_set_listen() {", "\n_node_port() {")
        with tempfile.TemporaryDirectory() as temp:
            node = Path(temp) / "nodes" / "3"
            node.mkdir(parents=True)
            (node / "core").write_text("hysteria\n")
            (node / "config.yaml").write_text('listen: "0.0.0.0:443,20000,20001"\n')
            (node / "node.txt").write_text(
                "hysteria2://secret@203.0.113.8:12345/"
                "?insecure=1&mport=12345,20000,20001#xray-node\n"
            )
            (node / "fw_info").write_text("443 udp 0 0 1 4\n")
            script = function.replace("/etc/xray-node/nodes", str(node.parent))
            stubs = (
                "_hy_local_ipv6() { printf '%s' '2001:db8::20'; }\n"
                "_svc_restart() { :; }\n"
                "wait_for_port() { return 0; }\n"
                "info() { :; }\n"
                "warn() { :; }\n"
                "_fw_allow() { :; }\n"
                "_save_fw() { :; }\n"
            )
            subprocess.run(
                ["sh", "-c", stubs + script + "\n_hy_fix_existing_ipv6\n"],
                env=dict(os.environ, PATH="/bin:/usr/bin"),
                check=True,
            )
            self.assertIn('listen: ":443,20000,20001"', (node / "config.yaml").read_text())
            saved = (node / "node.txt").read_text().splitlines()
            links = [line for line in saved if line.startswith("hysteria2://")]
            self.assertEqual(len(links), 2)
            self.assertIn("mport=12345,20000,20001", links[0])
            self.assertIn("@[2001:db8::20]:443/", links[1])
            self.assertIn("mport=443,20000,20001", links[1])
            self.assertNotIn("mport=12345", links[1])


if __name__ == "__main__":
    unittest.main()
