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

    def run_gl(self, curl, uid="0"):
        (self.mock / "id").write_text(f"#!/bin/sh\necho {uid}\n")
        (self.mock / "id").chmod(0o755)
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
        # 即使机器上有 busybox wget（不认 -t），有 curl 时也只跑 curl，不能用 wget 报错盖住 curl 的真实报错
        for name in ("wget", "busybox"):
            (self.mock / name).write_text("#!/bin/sh\necho 'BusyBox: unrecognized option: t' >&2\nexit 1\n")
            (self.mock / name).chmod(0o755)
        r = self.run_gl(CURL_FAIL)
        self.assertEqual(r.returncode, 1)
        self.assertIn("Connection timed out", r.stdout)
        self.assertNotIn("unrecognized option", r.stdout)

    def test_gl_busybox_wget_without_curl_does_not_pass_t1(self):
        self.write_gl()
        self.cache.unlink()
        # 模拟没有 curl、只有 busybox wget（带 -V 不输出 GNU Wget，且传 -t 就报错）
        (self.mock / "wget").write_text(
            "#!/bin/sh\n"
            "for a in \"$@\"; do\n"
            "  [ \"$a\" = \"-V\" ] && { echo 'BusyBox v1.36.1'; exit 0; }\n"
            "  [ \"$a\" = \"-t\" ] && { echo 'wget: unrecognized option: t' >&2; exit 1; }\n"
            "done\n"
            "out=; prev=\n"
            "for a in \"$@\"; do [ \"$prev\" = \"-O\" ] && out=$a; prev=$a; done\n"
            "printf '#!/bin/sh\\necho BB-WGET-OK\\n' > \"$out\"\n"
        )
        (self.mock / "wget").chmod(0o755)
        # 用一个没有 curl 的 PATH
        (self.mock / "id").write_text("#!/bin/sh\necho 0\n")
        (self.mock / "id").chmod(0o755)
        for tool in ("sh", "dirname", "mkdir", "rm", "mv", "chmod", "head", "grep", "tail", "sed"):
            p = subprocess.run(["sh", "-c", f"command -v {tool}"], capture_output=True, text=True).stdout.strip()
            if p and not (self.mock / tool).exists():
                (self.mock / tool).symlink_to(p)
        env = dict(self.env)
        gl_text = (self.bin / "gl").read_text().replace(
            'PATH="${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"',
            f'PATH="{self.mock}"',
        )
        (self.bin / "gl").write_text(gl_text)
        r = subprocess.run(["/bin/sh", str(self.bin / "gl")], env=env, encoding="utf-8", errors="replace", capture_output=True, timeout=20)
        self.assertIn("BB-WGET-OK", r.stdout, r.stdout + r.stderr)

    def test_foreign_gl_is_not_overwritten(self):
        (self.bin / "gl").write_text("#!/bin/sh\necho someone-else\n")
        r = self.write_gl()
        self.assertIn("WARN", r.stdout)
        self.assertIn("someone-else", (self.bin / "gl").read_text())

    def test_gl_auto_elevates_for_non_root(self):
        self.write_gl()
        (self.mock / "sudo").write_text('#!/bin/sh\nprintf "GL_SUDO %s\\n" "$*"\n')
        (self.mock / "sudo").chmod(0o755)
        r = self.run_gl(CURL_OK, uid="1000")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn(f"GL_SUDO sh {self.bin / 'gl'} x", r.stdout)

    def test_uninstall_removes_gl(self):
        source = (Path(__file__).resolve().parents[1] / "install.sh").read_text()
        self.assertIn("grep -q 'xray-node-gl' /usr/local/bin/gl 2>/dev/null && rm -f /usr/local/bin/gl", source)
        self.assertIn("chmod 755 /usr/local/bin/shanjiedian\n_write_gl_cmd\n", source)


if __name__ == "__main__":
    unittest.main()
