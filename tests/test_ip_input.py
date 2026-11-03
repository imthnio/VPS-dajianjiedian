"""NAT 小鸡：只有 busybox wget 时也要能测出公网 IP；手动输入时接受商家给的域名。"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def between(start, end):
    source = INSTALLER.read_text()
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def run_sh(script):
    return subprocess.run(["sh", "-c", script], text=True, capture_output=True, timeout=20)


class WgetOnlyGetIpTest(unittest.TestCase):
    def test_wget_without_ip_version_flag(self):
        # 网卡上只有内网地址，没有 curl，wget 一带 -4 就报错（busybox 就是这样）
        with tempfile.TemporaryDirectory() as bindir:
            # PATH 里只放脚本要用的基本工具，没有 curl
            for tool in ["awk", "tr", "wc", "grep", "sed", "cat"]:
                found = shutil.which(tool)
                if found:
                    os.symlink(found, os.path.join(bindir, tool))
            script = (
                "PATH=" + bindir + "\n"
                "ip() { case \"$*\" in *route*) echo 'default via 10.0.0.1 dev eth0' ;;"
                " *addr*eth0*) echo '2: eth0 inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0' ;; esac; }\n"
                "wget() { for a in \"$@\"; do [ \"$a\" = -4 ] && return 1; done; printf '203.0.113.7\\n'; }\n"
                + between("get_ip() {", "\n# gh_api_dl ")
                + "\nget_ip 4\n"
            )
            result = run_sh(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "203.0.113.7")


class ValidHostTest(unittest.TestCase):
    def check(self, value):
        script = between("_valid_host() {", "\n_resolve_host() {") + "\n_valid_host '" + value + "'\n"
        return run_sh(script).returncode == 0

    def test_accepts_provider_domain(self):
        self.assertTrue(self.check("meb3.sunver.de"))
        self.assertTrue(self.check("NAT-1.Example.com"))

    def test_rejects_garbage(self):
        for bad in ["", "foo", "1.2.3", "1.2.3.4", "-a.com", "a..com", "a.com.", "a b.com", "a.com/x"]:
            self.assertFalse(self.check(bad), bad)


if __name__ == "__main__":
    unittest.main()
