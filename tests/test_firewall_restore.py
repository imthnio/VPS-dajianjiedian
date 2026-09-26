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
            r"(port_in_use\(\) \{.*?\n\})\n\nrand_port",
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
            r"(wait_for_port\(\) \{.*?\n\})\n\n# 小内存机器",
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
        self.assertEqual(query["insecure"], ["1"])
        self.assertEqual(query["pinSHA256"], [pin])
        self.assertEqual(query["pcs"], [pin])

    def test_existing_hysteria_link_is_repaired_without_changing_credentials(self):
        source = INSTALLER.read_text()
        match = re.search(
            r"(write_helper_cmds\(\) \{.*?\n\})\n\n_hy_export_env",
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
                    ["sh", "-c", function + "\nwrite_helper_cmds"],
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
            r"(if \[ -f /etc/xray-node/node\.txt \] && \[ ! -d /etc/xray-node/nodes \]; then.*?\nfi)\n\n# 已经装过节点",
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


if __name__ == "__main__":
    unittest.main()


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
