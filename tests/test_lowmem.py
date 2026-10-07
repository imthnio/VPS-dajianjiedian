"""小内存机器（64MB 容器）装内核：边解压边落盘、下载时催写盘。直接跑 install.sh 里抽出来的函数，不需要 root。"""

import os
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path


INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def between(start, end):
    source = INSTALLER.read_text(encoding="utf-8")
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


HELPERS = between('_PACE_PID=""', "_http_save() {")


def run_sh(script, cwd):
    return subprocess.run(["sh", "-c", HELPERS + "\n" + script], cwd=cwd, capture_output=True, timeout=60)


class UnpackDripTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        # 不是 4MB 的整数倍，最后一段是零头
        self.payload = os.urandom(9 * 1024 * 1024 + 123)
        with zipfile.ZipFile(self.dir / "x.zip", "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("xray", self.payload)
            z.writestr("README.md", "hi")
        (self.dir / "in").mkdir()
        (self.dir / "in" / "sing-box").write_bytes(self.payload)
        with tarfile.open(self.dir / "s.tar.gz", "w:gz") as t:
            t.add(self.dir / "in" / "sing-box", arcname="in/sing-box")

    def tearDown(self):
        self.tmp.cleanup()

    def test_zip_member_written_whole(self):
        res = run_sh("LOW_MEM=1; _unpack_drip zip x.zip xray out", self.dir)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual((self.dir / "out").read_bytes(), self.payload)

    def test_tgz_member_written_whole(self):
        res = run_sh("LOW_MEM=1; _unpack_drip tgz s.tar.gz in/sing-box out", self.dir)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual((self.dir / "out").read_bytes(), self.payload)

    def test_not_low_memory_uses_old_path(self):
        res = run_sh("LOW_MEM=0; _unpack_drip zip x.zip xray out", self.dir)
        self.assertEqual(res.returncode, 1)
        self.assertFalse((self.dir / "out").exists())

    def test_missing_member_leaves_nothing(self):
        res = run_sh("LOW_MEM=1; _unpack_drip zip x.zip nope out", self.dir)
        self.assertEqual(res.returncode, 1)
        self.assertFalse((self.dir / "out").exists())

    def test_dd_without_these_flags_falls_back(self):
        res = run_sh(
            "dd() { echo 'dd: unknown operand iflag' >&2; return 1; }\n"
            "LOW_MEM=1; _unpack_drip zip x.zip xray out", self.dir)
        self.assertEqual(res.returncode, 1)
        self.assertFalse((self.dir / "out").exists())

    def test_unknown_dd_output_does_not_loop_forever(self):
        res = run_sh(
            "dd() { cat >/dev/null; echo 'something else' >&2; }\n"
            "LOW_MEM=1; _unpack_drip zip x.zip xray out", self.dir)
        self.assertEqual(res.returncode, 1)

    def test_truncated_output_is_rejected(self):
        # 解压出来比包里记的少，就不能当成功
        res = run_sh(
            "unzip() { case \"$1\" in -l) echo ' 99999999  01-01-2026 00:00   xray';; "
            "-p) head -c 2000000 /dev/zero;; esac; }\n"
            "LOW_MEM=1; _unpack_drip zip x.zip xray out", self.dir)
        self.assertEqual(res.returncode, 1)
        self.assertFalse((self.dir / "out").exists())

    def test_cp_bin_copies_and_keeps_executable(self):
        for low in ("0", "1"):
            (self.dir / "src").write_bytes(self.payload)
            os.chmod(self.dir / "src", 0o755)
            res = run_sh("LOW_MEM=%s; _cp_bin src dst" % low, self.dir)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual((self.dir / "dst").read_bytes(), self.payload)
            self.assertTrue(os.access(self.dir / "dst", os.X_OK))
            os.remove(self.dir / "dst")


class PaceTest(unittest.TestCase):
    def test_only_runs_on_low_memory_and_stops(self):
        with tempfile.TemporaryDirectory() as d:
            res = run_sh(
                "LOW_MEM=0; _pace_start; echo \"a=$_PACE_PID\"\n"
                "LOW_MEM=1; _pace_start; p=$_PACE_PID; _pace_start; [ \"$p\" = \"$_PACE_PID\" ] && echo same\n"
                "kill -0 \"$p\" && echo alive; _pace_stop; echo \"b=$_PACE_PID\"\n"
                "kill -0 \"$p\" 2>/dev/null || echo gone", d)
            self.assertEqual(res.stdout.decode().split(), ["a=", "same", "alive", "b=", "gone"], res.stderr)

    def test_helper_exits_when_installer_dies(self):
        with tempfile.TemporaryDirectory() as d:
            res = subprocess.run(
                ["sh", "-c", "sh -c '" + "LOW_MEM=1\n" + HELPERS.replace("'", "'\\''")
                 + "\n_pace_start; echo $_PACE_PID' ; "],
                cwd=d, capture_output=True, timeout=30)
            pid = int(res.stdout.decode().strip())
            import time
            for _ in range(40):
                try:
                    os.kill(pid, 0)
                except OSError:
                    return
                time.sleep(0.1)
            self.fail("催写盘的后台进程在脚本退出后没有停")


if __name__ == "__main__":
    unittest.main()
