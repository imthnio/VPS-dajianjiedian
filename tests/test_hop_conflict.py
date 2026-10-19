"""新节点的 UDP 端口、跳跃端口不能和已有节点的端口跳跃端口重叠（重叠的包会被转给别的节点）。"""
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = (Path(__file__).resolve().parent.parent / "install.sh").read_text(encoding="utf-8")


def func(name):
    i = SCRIPT.index(f"\n{name}() {{") + 1
    return SCRIPT[i:SCRIPT.index("\n}\n", i) + 3]


class HopConflictTest(unittest.TestCase):
    def run_taken(self, lo, hi):
        with tempfile.TemporaryDirectory() as d:
            n = Path(d) / "3"
            n.mkdir()
            (n / "hop").write_text("main=40000\nports=20000-20100,30001\nfamily=4\n")
            code = func("_hop_taken") + f'XRAY_NODES_DIR="{d}"\n_hop_taken {lo} {hi}\n'
            r = subprocess.run(["sh", "-c", code], capture_output=True, text=True, timeout=10)
            return r.returncode, r.stdout

    def test_inside_range(self):
        self.assertEqual(self.run_taken(20050, 20050), (0, "3"))

    def test_range_overlap_and_single_and_main(self):
        self.assertEqual(self.run_taken(19990, 20000)[0], 0)
        self.assertEqual(self.run_taken(30001, 30001)[0], 0)
        self.assertEqual(self.run_taken(40000, 40000)[0], 0)

    def test_free(self):
        self.assertEqual(self.run_taken(20101, 30000), (1, ""))

    def test_wired_into_prompts(self):
        self.assertIn('_hop_taken "$_p" "$_p"', func("rand_port"))
        self.assertIn('_port_hop_id=$(_hop_taken "$PORT" "$PORT")', SCRIPT)
        self.assertIn('_hh_own=$(_hop_taken "$_hh_lo" "$_hh_hi")', func("_hy_collect_hop_ports"))


if __name__ == "__main__":
    unittest.main()
