"""和 VPS-WireGuard-luodi（wg-luodi）配合的几处接线：节点启动前叫一声 wg-luodi hook，没装就跳过。"""
import unittest
from pathlib import Path

SCRIPT = (Path(__file__).resolve().parent.parent / "install.sh").read_text(encoding="utf-8")


def between(start, end):
    i = SCRIPT.index(start)
    return SCRIPT[i:SCRIPT.index(end, i)]


class WgLuodiWiringTest(unittest.TestCase):
    def test_openrc_and_nohup_call_hook_only_if_installed(self):
        svc = between("_svc_install() {", "\n_svc_restart() {")
        self.assertIn("[ -x /usr/local/bin/wg-luodi ] && /usr/local/bin/wg-luodi hook ${_si_id} >/dev/null 2>&1 || true\n", svc)
        self.assertIn('[ -x /usr/local/bin/wg-luodi ] && /usr/local/bin/wg-luodi hook "$_si_id" >/dev/null 2>&1 || true\n', svc)
        # systemd 模板不写死：wg-luodi 自己装 drop-in，没装 wg-luodi 的机器日志里不会出现找不到程序的报错
        self.assertNotIn("wg-luodi hook %i", svc)

    def test_link_port_written_before_service(self):
        i = SCRIPT.index('echo "$LINK_PORT" > "$NODE_DIR/link_port"')
        self.assertLess(SCRIPT.index('echo "$CORE" > "$NODE_DIR/core"'), i)
        self.assertLess(i, SCRIPT.index('step "[服务] 设置开机自启…"'))

    def test_port_notice_reads_state_safely(self):
        self.assertIn("if [ -r /etc/wg-luodi/state ]; then", SCRIPT)


if __name__ == "__main__":
    unittest.main()
