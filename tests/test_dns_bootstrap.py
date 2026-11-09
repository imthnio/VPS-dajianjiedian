"""DNS 完全不通（wget 报 bad address）时：安装命令换镜像、install.sh 换公共 DNS。"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_expire import InstallPromptTest, FAIL_STUB, CURL_STUB as CURL_OK


INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def between(start, end):
    source = INSTALLER.read_text()
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


# 直连失败；第一个镜像返回网页（不是脚本）；第二个镜像给真脚本
MIRROR_CURL_STUB = """#!/bin/sh
printf '%s\\n' "$*" >> "$LOG"
out=
prev=
url=
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out=$a; fi
  prev=$a
  url=$a
done
case "$url" in
  http://example.invalid/*) exit 6 ;;
  https://v6.gh-proxy.org/*) printf '<html>blocked</html>\\n' > "$out"; exit 0 ;;
  https://gh.llkk.cc/*) cp "$PAYLOAD" "$out"; exit 0 ;;
esac
exit 22
"""

HTML_CURL_STUB = """#!/bin/sh
out=
prev=
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out=$a; fi
  prev=$a
done
printf '<html>error</html>\\n' > "$out"
exit 0
"""


class BootstrapMirrorTest(unittest.TestCase):
    run_line = InstallPromptTest.run_line
    readme_command = InstallPromptTest.readme_command

    def test_falls_back_to_mirror_when_direct_download_fails(self):
        result, logged, _out = self.run_line(
            {"curl": MIRROR_CURL_STUB, "apt-get": FAIL_STUB},
            "#!/bin/sh\nread -r ans\nprintf 'GOT %s\\n' \"$ans\"\n",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("GOT 8443", result.stdout)
        self.assertIn("https://gh.llkk.cc/", logged)
        self.assertNotIn("ghproxy.net", logged)
        self.assertNotIn("安装脚本没下载下来", result.stdout)

    def test_html_page_is_not_run_as_installer(self):
        result, _logged, out = self.run_line({"curl": HTML_CURL_STUB}, "#!/bin/sh\nprintf 'GOT ran\\n'\n")
        self.assertIn("安装脚本没下载下来", result.stdout)
        self.assertNotIn("GOT ", result.stdout)
        self.assertFalse(out.exists())

    def test_readme_command_parses_in_dash(self):
        command = self.readme_command()
        for shell in ("/bin/dash", "/usr/bin/dash", "/bin/bash"):
            if os.path.exists(shell):
                subprocess.run([shell, "-n", "-c", command], check=True)


class DnsFixTest(unittest.TestCase):
    def run_fix(self, original, has_v4=True, symlink=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            resolv = root / "resolv.conf"
            target = root / "stub-resolv.conf"
            if symlink:
                target.write_text(original)
                resolv.symlink_to(target)
            elif original is not None:
                resolv.write_text(original)
            funcs = (between("# 有没有 IPv4 默认路由", "\n# 临时换 DNS") + between("# _resolves <域名>", "\n_sha256_of() {")).replace(
                "/etc/resolv.conf", str(resolv)
            )
            route = "default via 10.0.0.1 dev eth0" if has_v4 else ""
            script = (
                "warn() { printf 'WARN %s\\n' \"$1\"; }\n"
                "info() { printf 'OK %s\\n' \"$1\"; }\n"
                'DNS64_SERVERS="2a00:1098:2b::1 2a01:4f8:c2c:123f::1"\n'
                f"ip() {{ printf '%s' '{route}'; }}\n"
                # 只有公共 DNS 能解析
                f"getent() {{ grep -qE '1\\.1\\.1\\.1|2a00:1098' '{resolv}' 2>/dev/null; }}\n"
                "nslookup() { getent \"$@\"; }\n"
                + funcs
                + "\n_dns_fix_broken; echo RC=$?\n"
            )
            result = subprocess.run(["sh", "-c", script], text=True, capture_output=True, timeout=20)
            bak = Path(str(resolv) + ".xray-node-orig")
            return (
                result,
                resolv.read_text() if resolv.exists() else None,
                resolv.is_symlink(),
                bak.is_symlink(),
                bak.read_text() if bak.exists() else None,
            )

    def test_broken_dns_with_ipv4_switches_to_public_dns(self):
        result, now, is_link, _bak_link, bak = self.run_fix("nameserver 10.255.255.1\n")
        self.assertIn("RC=0", result.stdout, result.stdout + result.stderr)
        self.assertIn("nameserver 1.1.1.1", now)
        self.assertEqual(bak, "nameserver 10.255.255.1\n")
        self.assertFalse(is_link)

    def test_broken_dns_ipv6_only_uses_dns64(self):
        result, now, _l, _bl, bak = self.run_fix("nameserver 8.8.8.8\n", has_v4=False)
        self.assertIn("RC=0", result.stdout, result.stdout + result.stderr)
        self.assertIn("nameserver 2a00:1098:2b::1", now)
        self.assertNotIn("1.1.1.1", now)
        self.assertEqual(bak, "nameserver 8.8.8.8\n")

    def test_working_dns_is_left_alone(self):
        result, now, _l, _bl, bak = self.run_fix("nameserver 1.1.1.1\n")
        self.assertIn("RC=0", result.stdout)
        self.assertEqual(now, "nameserver 1.1.1.1\n")
        self.assertIsNone(bak)
        self.assertNotIn("WARN", result.stdout)

    def test_symlinked_resolv_conf_is_backed_up_as_link(self):
        result, now, is_link, bak_link, _bak = self.run_fix("nameserver 127.0.0.53\n", symlink=True)
        self.assertIn("RC=0", result.stdout, result.stdout + result.stderr)
        self.assertFalse(is_link)
        self.assertTrue(bak_link)
        self.assertIn("nameserver 1.1.1.1", now)

    def test_called_early_in_main_flow(self):
        source = INSTALLER.read_text()
        recover = source.index("\n_dns64_recover\n")
        fix = source.index("\n_dns_fix_broken || true\n")
        banner = source.index("Xray 节点一键安装（小白版）${NC}")
        self.assertLess(recover, fix)
        self.assertLess(fix, banner)


class DnsFixStillBrokenTest(unittest.TestCase):
    def test_restores_original_when_public_dns_does_not_help(self):
        with tempfile.TemporaryDirectory() as temp:
            resolv = Path(temp) / "resolv.conf"
            resolv.write_text("nameserver 10.0.0.1\n")
            funcs = (between("# 有没有 IPv4 默认路由", "\n# 临时换 DNS") + between("# _resolves <域名>", "\n_sha256_of() {")).replace(
                "/etc/resolv.conf", str(resolv)
            )
            script = (
                "warn() { printf 'WARN %s\\n' \"$1\"; }\ninfo() { :; }\n"
                'DNS64_SERVERS="2a00:1098:2b::1"\n'
                "ip() { echo default; }\ngetent() { return 2; }\nnslookup() { return 1; }\n"
                + funcs
                + "\n_dns_fix_broken; echo RC=$?\n"
            )
            result = subprocess.run(["sh", "-c", script], text=True, capture_output=True, timeout=20)
            self.assertIn("RC=1", result.stdout, result.stdout + result.stderr)
            self.assertEqual(resolv.read_text(), "nameserver 10.0.0.1\n")
            self.assertFalse(Path(str(resolv) + ".xray-node-orig").exists())


class DnsFixDhcpcdTest(unittest.TestCase):
    def test_dhcpcd_gets_head_file_and_resolv_is_world_readable(self):
        with tempfile.TemporaryDirectory() as temp:
            resolv = Path(temp) / "resolv.conf"
            resolv.write_text("# Generated by dhcpcd\n")
            funcs = (between("# 有没有 IPv4 默认路由", "\n# 临时换 DNS") + between("# _resolves <域名>", "\n_sha256_of() {")).replace(
                "/etc/resolv.conf", str(resolv)
            )
            script = (
                "umask 077\n"
                "warn() { :; }\ninfo() { :; }\n"
                'DNS64_SERVERS="2a00:1098:2b::1"\n'
                "ip() { echo default; }\ndhcpcd() { :; }\n"
                f"getent() {{ grep -q '1\\.1\\.1\\.1' '{resolv}' 2>/dev/null; }}\n"
                "nslookup() { getent; }\n"
                + funcs
                + "\n_dns_fix_broken; echo RC=$?\n"
            )
            result = subprocess.run(["sh", "-c", script], text=True, capture_output=True, timeout=20)
            self.assertIn("RC=0", result.stdout, result.stdout + result.stderr)
            head = Path(str(resolv) + ".head")
            self.assertIn("nameserver 1.1.1.1", head.read_text())
            self.assertEqual(resolv.stat().st_mode & 0o777, 0o644)


# 安装命令里换 DNS 那一段。nslookup 假装：resolv.conf 里有 $GOOD 这个 DNS 才解析得出来。
NSLOOKUP_STUB = """#!/bin/sh
printf 'nslookup %s\\n' "$*" >> "$LOG"
[ -n "$GOOD" ] && grep -q "nameserver $GOOD" "$RESOLV"
"""


class BootstrapDnsTest(unittest.TestCase):
    run_line = InstallPromptTest.run_line
    readme_command = InstallPromptTest.readme_command

    def run_dns(self, before, good, backup=None, head=None):
        with tempfile.TemporaryDirectory() as temp:
            resolv = Path(temp) / "resolv.conf"
            resolv.write_text(before)
            bak = Path(str(resolv) + ".xray-node-orig")
            if backup is not None:
                bak.write_text(backup)
            if head is not None:
                Path(str(resolv) + ".head").write_text(head)
            old = os.environ.get("GOOD")
            os.environ["GOOD"] = good
            try:
                result, _logged, _out = self.run_line(
                    {"curl": CURL_OK, "nslookup": NSLOOKUP_STUB},
                    "#!/bin/sh\nprintf 'GOT ran\\n'\n",
                    resolv=resolv,
                )
            finally:
                if old is None:
                    del os.environ["GOOD"]
                else:
                    os.environ["GOOD"] = old
            head_path = Path(str(resolv) + ".head")
            return (result, resolv.read_text() if resolv.exists() else None,
                    bak.read_text() if bak.exists() else None,
                    head_path.read_text() if head_path.exists() else None)

    def test_working_dns_is_left_alone(self):
        result, now, bak, _h = self.run_dns("nameserver 10.0.0.1\n", "10.0.0.1")
        self.assertEqual(now, "nameserver 10.0.0.1\n")
        self.assertIsNone(bak)
        self.assertIn("GOT ran", result.stdout)

    def test_broken_dns_switches_when_public_dns_works(self):
        result, now, bak, _h = self.run_dns("nameserver 10.0.0.1\n", "1.1.1.1")
        self.assertIn("nameserver 1.1.1.1", now)
        self.assertEqual(bak, "nameserver 10.0.0.1\n")
        self.assertIn("DNS -> 1.1.1.1", result.stdout)

    def test_public_dns_unreachable_restores_original(self):
        # DE9929：原来的 DNS 一时解析不了，公共 DNS 根本连不上。以前直接换成 1.1.1.1 不还原，之后全是 bad address
        result, now, bak, _h = self.run_dns("nameserver 10.0.0.1\n", "none")
        self.assertEqual(now, "nameserver 10.0.0.1\n")
        self.assertIsNone(bak)
        self.assertIn("DNS 已还原", result.stdout)

    def test_rerun_repairs_dns_broken_by_old_command(self):
        # 旧命令已经把 DNS 换成连不上的 1.1.1.1，备份里是原来的。重新跑新命令应当换回原来的
        _r, now, bak, head = self.run_dns(
            "nameserver 1.1.1.1\nnameserver 8.8.8.8\n", "none",
            backup="nameserver 10.0.0.1\n",
            head="nameserver 1.1.1.1\nnameserver 8.8.8.8\n",
        )
        self.assertEqual(now, "nameserver 10.0.0.1\n")
        self.assertIsNone(bak)
        self.assertIsNone(head)

    def test_users_own_head_file_is_kept(self):
        _r, _now, _bak, head = self.run_dns("nameserver 10.0.0.1\n", "none", head="search lan\n")
        self.assertEqual(head, "search lan\n")


if __name__ == "__main__":
    unittest.main()
