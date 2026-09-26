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


if __name__ == "__main__":
    unittest.main()
