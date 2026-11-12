"""gl 快捷命令：输入 gl 打开主菜单（先取最新脚本，取不到用本机保存的那份）。"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_expire import between

FUNC = between("_write_gl_cmd() {", "\n# ---------- 写入 jiedian / shanjiedian")

CURL_OK = """#!/bin/sh
out=
prev=
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out=$a; fi
  prev=$a
done
printf '#!/bin/sh\\necho NEW-MENU "$@"\\n' > "$out"
"""
# 下到一半断了：文件开头是 #!，但 curl 报失败
CURL_PARTIAL = """#!/bin/sh
out=
prev=
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out=$a; fi
  prev=$a
done
printf '#!/bin/sh\\necho HALF-MENU\\n' > "$out"
echo 'curl: (18) transfer closed' >&2
exit 18
"""
CURL_FAIL = "#!/bin/sh\necho 'curl: (28) Connection timed out' >&2\nexit 28\n"


class GlTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.mock = self.root / "mock"
        self.bin.mkdir()
        self.mock.mkdir()
        self.cache = self.root / "etc" / "install.sh"
        self.env = dict(os.environ, XRAY_BIN_DIR=str(self.bin), XRAY_GL_CACHE=str(self.cache))

    def tearDown(self):
        self.tmp.cleanup()

    def write_gl(self, script_text="#!/bin/sh\n# xray-node 一键安装脚本\necho OLD-MENU\n", extra_path=""):
        me = self.root / "xray-install.sh"
        me.write_text(script_text)
        env = dict(self.env)
        if extra_path:
            env["PATH"] = extra_path + ":" + env["PATH"]
        r = subprocess.run(
            ["sh", "-c", "warn() { printf 'WARN %s\\n' \"$1\"; }\n" + FUNC + "\n_write_gl_cmd", str(me)],
            env=env, encoding="utf-8", errors="replace", capture_output=True, timeout=10,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def run_gl(self, curl):
        (self.mock / "curl").write_text(curl)
        (self.mock / "curl").chmod(0o755)
        env = dict(self.env, PATH=f"{self.mock}:{self.env['PATH']}")
        return subprocess.run(["sh", str(self.bin / "gl"), "x"], env=env, encoding="utf-8", errors="replace", capture_output=True, timeout=20)

    def test_gl_runs_latest_script(self):
        self.write_gl()
        self.assertTrue(self.cache.exists())
        r = self.run_gl(CURL_OK)
        self.assertIn("NEW-MENU x", r.stdout, r.stdout + r.stderr)
        self.assertIn("NEW-MENU", self.cache.read_text())

    def test_gl_falls_back_to_saved_copy(self):
        self.write_gl()
        r = self.run_gl(CURL_FAIL)
        self.assertIn("OLD-MENU", r.stdout, r.stdout + r.stderr)
        self.assertIn("本机保存的版本", r.stdout)

    def test_gl_does_not_run_half_downloaded_script(self):
        self.write_gl()
        # 机器上真有 wget 的话它会去连网，这里用假的顶掉
        for name in ("wget", "busybox"):
            (self.mock / name).write_text("#!/bin/sh\nexit 4\n")
            (self.mock / name).chmod(0o755)
        r = self.run_gl(CURL_PARTIAL)
        self.assertNotIn("HALF-MENU", r.stdout, r.stdout + r.stderr)
        self.assertIn("OLD-MENU", r.stdout, r.stdout + r.stderr)
        self.assertNotIn("HALF-MENU", self.cache.read_text())

    def test_gl_without_any_copy_shows_error(self):
        self.write_gl()
        self.cache.unlink()
        r = self.run_gl(CURL_FAIL)
        self.assertEqual(r.returncode, 1)
        self.assertIn("Connection timed out", r.stdout)

    def test_foreign_gl_is_not_overwritten(self):
        (self.bin / "gl").write_text("#!/bin/sh\necho someone-else\n")
        r = self.write_gl()
        self.assertIn("WARN", r.stdout)
        self.assertIn("someone-else", (self.bin / "gl").read_text())

    def test_uninstall_removes_gl(self):
        source = (Path(__file__).resolve().parents[1] / "install.sh").read_text()
        self.assertIn("grep -q 'xray-node-gl' /usr/local/bin/gl 2>/dev/null && rm -f /usr/local/bin/gl", source)
        self.assertIn("chmod 700 /usr/local/bin/shanjiedian\n_write_gl_cmd\n", source)


if __name__ == "__main__":
    unittest.main()
