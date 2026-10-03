"""巡检小程序 xray-node-watch 的测试：端口跳跃规则自愈、证书端口开关、挂上/卸掉巡检。

全部用假的 systemctl / iptables / ufw / firewall-cmd / openssl / xray-node-hop，不碰真防火墙。
"""

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def between(start, end):
    source = INSTALLER.read_text()
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


# 假的端口跳跃小程序：check 看状态文件，up 写状态文件（HOP_FAIL 时失败）
HOP_MOCK = r'''#!/bin/sh
printf 'hop %s\n' "$*" >> "$MOCK_LOG"
case "$1" in
  check) [ -f "$HOP_STATE/$2" ] ;;
  up) [ -f "$HOP_FAIL" ] && { echo "boom" >&2; exit 1; }; : > "$HOP_STATE/$2" ;;
  *) exit 0 ;;
esac
'''

# 假的 systemctl：is-active 看 $ACTIVE_DIR/<单元名>，其它命令只记日志
SYSTEMCTL_MOCK = r'''#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$MOCK_LOG"
if [ "$1" = "is-active" ]; then
  [ "$2" = "--quiet" ] && shift
  [ -f "$ACTIVE_DIR/$2" ]
  exit $?
fi
exit 0
'''

# 假的 iptables / ip6tables：规则存成文件，-C 查、-I 加、-D 删
IPT_MOCK = r'''#!/bin/sh
name=$(basename "$0")
printf '%s %s\n' "$name" "$*" >> "$MOCK_LOG"
op=$1; shift
key=$(printf '%s' "$*" | tr ' /' '__')
case "$op" in
  -C) [ -f "$IPT_DIR/$name.$key" ] ;;
  -I) : > "$IPT_DIR/$name.$key" ;;
  -D) [ -f "$IPT_DIR/$name.$key" ] && rm -f "$IPT_DIR/$name.$key" ;;
  *) exit 0 ;;
esac
'''

# 假的 openssl：OPENSSL_OK 文件存在 = 证书还很新
OPENSSL_MOCK = r'''#!/bin/sh
printf 'openssl %s\n' "$*" >> "$MOCK_LOG"
[ -f "$OPENSSL_OK" ]
'''

LOG_MOCK = r'''#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >> "$MOCK_LOG"
exit 1
'''


class WatchTestBase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        r = self.root
        for d in ("bin", "mock", "nodes", "state", "hopstate", "active", "ipt", "sd", "sdrun", "cron"):
            (r / d).mkdir()
        self.log = r / "mock.log"
        self.log.write_text("")
        mocks = {
            "systemctl": SYSTEMCTL_MOCK,
            "iptables": IPT_MOCK,
            "ip6tables": IPT_MOCK,
            "openssl": OPENSSL_MOCK,
            # 下面这些不该被用到；万一用到也只记日志，绝不会碰到真防火墙
            "ufw": LOG_MOCK,
            "firewall-cmd": LOG_MOCK,
            "nft": LOG_MOCK,
            "netfilter-persistent": LOG_MOCK,
            "rc-service": LOG_MOCK,
            "rc-update": LOG_MOCK,
        }
        for name, body in mocks.items():
            p = r / "mock" / name
            p.write_text(body)
            p.chmod(0o755)
        hop = r / "bin" / "xray-node-hop"
        hop.write_text(HOP_MOCK)
        hop.chmod(0o755)
        env = os.environ.copy()
        env["XRAY_BIN_DIR"] = str(r / "bin")
        subprocess.run(
            ["sh", "-c", between("install_watch_bin() {", "\n# 挂上 / 卸掉巡检") + "\ninstall_watch_bin"],
            env=env,
            check=True,
            timeout=30,
        )
        self.watch = r / "bin" / "xray-node-watch"
        self.assertTrue(os.access(self.watch, os.X_OK))
        self.assertFalse((r / "bin" / "xray-node-watch.tmp").exists())

    def tearDown(self):
        self._tmp.cleanup()

    def env(self, systemd=True):
        r = self.root
        env = {
            "PATH": f"{r / 'mock'}:/usr/bin:/bin",
            "MOCK_LOG": str(self.log),
            "HOP_STATE": str(r / "hopstate"),
            "HOP_FAIL": str(r / "hop_fail"),
            "ACTIVE_DIR": str(r / "active"),
            "IPT_DIR": str(r / "ipt"),
            "OPENSSL_OK": str(r / "openssl_ok"),
            "XRAY_NODE_DIR": str(r / "nodes"),
            "XRAY_BIN_DIR": str(r / "bin"),
            "XRAY_WATCH_STATE": str(r / "state"),
            "XRAY_SYSTEMD_DIR": str(r / "sd"),
            "XRAY_SYSTEMD_RUN": str(r / ("sdrun" if systemd else "no-sdrun")),
            "XRAY_INITD": str(r / "no-initd"),
            "XRAY_CRON_DIR": str(r / "cron"),
            "XRAY_WATCH_PID": str(r / "watch.pid"),
            "XRAY_WATCH_LOG": str(r / "watch.log"),
            "XRAY_FW_UNIT_DIRS": str(r / "sd"),
        }
        return env

    def run_watch(self, *args, systemd=True, check=True):
        return subprocess.run(
            [str(self.watch), *args],
            env=self.env(systemd),
            check=check,
            timeout=60,
            capture_output=True,
            text=True,
        )

    def node(self, nid, hop=False, done=True, active=True, acme=None):
        d = self.root / "nodes" / str(nid)
        d.mkdir()
        (d / "core").write_text("hysteria\n")
        if hop:
            (d / "hop").write_text("ports=20000-20010\ntarget=443\nfamily=4\n")
        if done:
            (d / "node.txt").write_text("ok\n")
        if active:
            (self.root / "active" / f"hysteria-node@{nid}").write_text("")
        if acme is not None:
            (d / "fw_acme").write_text(acme)
            (d / "fw_acme.state").write_text("open\n")
        return d

    def logged(self):
        return self.log.read_text().splitlines()

    def clear_log(self):
        self.log.write_text("")


class HealTest(WatchTestBase):
    def test_heal_only_active_finished_hop_nodes(self):
        self.node(1, hop=True)
        self.node(2, hop=True, active=False)
        self.node(3, hop=True, done=False)
        self.node(4)
        self.run_watch("tick")
        log = self.logged()
        self.assertIn("hop check 1", log)
        self.assertIn("hop up 1", log)
        self.assertFalse(any(line.startswith("hop") and line.endswith((" 2", " 3", " 4")) for line in log), log)
        self.assertIn("已经补回", (self.root / "watch.log").read_text())

    def test_present_rules_are_left_alone(self):
        self.node(1, hop=True)
        (self.root / "hopstate" / "1").write_text("")
        self.run_watch("tick")
        self.assertIn("hop check 1", self.logged())
        self.assertNotIn("hop up 1", self.logged())

    def test_failed_heal_backs_off_for_five_minutes(self):
        self.node(1, hop=True)
        (self.root / "hop_fail").write_text("")
        self.run_watch("tick")
        self.assertIn("hop up 1", self.logged())
        fail = self.root / "state" / "hop-1.fail"
        self.assertTrue(fail.exists())
        self.clear_log()
        self.run_watch("tick")
        self.assertNotIn("hop up 1", self.logged())
        old = time.time() - 600
        os.utime(fail, (old, old))
        (self.root / "hop_fail").unlink()
        self.clear_log()
        self.run_watch("tick")
        self.assertIn("hop up 1", self.logged())
        self.assertFalse(fail.exists())

    def test_without_systemd_uses_rc_service_status(self):
        self.node(1, hop=True)
        # 假 rc-service 永远返回 1 = 没在跑，所以不补
        self.run_watch("tick", systemd=False)
        self.assertIn("rc-service xray-node-1 status", self.logged())
        self.assertNotIn("hop up 1", self.logged())


class ArmTest(WatchTestBase):
    def test_arm_systemd_without_firewall_unit(self):
        self.node(1, hop=True)
        self.run_watch("arm")
        sd = self.root / "sd"
        self.assertTrue((sd / "xray-node-watch.service").exists())
        timer = (sd / "xray-node-watch.timer").read_text()
        self.assertIn("OnUnitActiveSec=60", timer)
        self.assertFalse((sd / "xray-node-watch-fw.service").exists())
        self.assertIn("systemctl enable --now xray-node-watch.timer", self.logged())

    def test_arm_systemd_hooks_present_firewall_units(self):
        self.node(1, hop=True)
        sd = self.root / "sd"
        (sd / "nftables.service").write_text("[Unit]\n")
        (sd / "ufw.service").write_text("[Unit]\n")
        self.run_watch("arm")
        hook = (sd / "xray-node-watch-fw.service").read_text()
        self.assertIn("After=nftables.service ufw.service", hook)
        self.assertIn("PartOf=nftables.service ufw.service", hook)
        self.assertIn("ReloadPropagatedFrom=nftables.service ufw.service", hook)
        self.assertIn("tick --now", hook)
        self.assertIn("WantedBy=multi-user.target nftables.service ufw.service", hook)
        self.assertNotIn("firewalld", hook)
        self.assertIn("systemctl restart xray-node-watch-fw.service", self.logged())
        # 防火墙服务被卸掉后再 arm：钩子撤掉
        (sd / "nftables.service").unlink()
        (sd / "ufw.service").unlink()
        self.clear_log()
        self.run_watch("arm")
        self.assertFalse((sd / "xray-node-watch-fw.service").exists())
        self.assertIn("systemctl disable --now xray-node-watch-fw.service", self.logged())

    def test_arm_disarms_when_no_node_needs_it(self):
        d = self.node(1, hop=True)
        sd = self.root / "sd"
        (sd / "nftables.service").write_text("[Unit]\n")
        self.run_watch("arm")
        (d / "hop").unlink()
        self.clear_log()
        self.run_watch("arm")
        for name in ("xray-node-watch.service", "xray-node-watch.timer", "xray-node-watch-fw.service"):
            self.assertFalse((sd / name).exists(), name)
        self.assertIn("systemctl disable --now xray-node-watch.timer", self.logged())
        # 再卸一次什么都不做
        self.clear_log()
        self.run_watch("disarm")
        self.assertEqual(self.logged(), [])

    def test_cron_fallback_and_disarm(self):
        self.node(1, acme="80 tcp 0 0 1 4\n")
        self.run_watch("arm", systemd=False)
        cron = (self.root / "cron" / "xray-node-watch").read_text()
        self.assertIn(f"* * * * * root {self.watch} tick", cron)
        self.run_watch("disarm", systemd=False)
        self.assertFalse((self.root / "cron" / "xray-node-watch").exists())


class AcmeTest(WatchTestBase):
    RULE = "iptables.INPUT_-p_tcp_--dport_80_-j_ACCEPT"

    def acme_node(self, cert=True):
        d = self.node(5, acme="80 tcp 0 0 1 4\n")
        (self.root / "ipt" / self.RULE).write_text("")
        if cert:
            (d / "acme" / "certificates").mkdir(parents=True)
            (d / "acme" / "certificates" / "a.example.com.crt").write_text("x")
        return d

    def deletes(self):
        return [line for line in self.logged() if line.startswith("iptables -D")]

    def test_fresh_cert_closes_once(self):
        d = self.acme_node()
        (self.root / "openssl_ok").write_text("")
        self.run_watch("tick", "--now")
        self.assertEqual(len(self.deletes()), 1)
        self.assertFalse((self.root / "ipt" / self.RULE).exists())
        self.assertEqual((d / "fw_acme.state").read_text().strip(), "closed")
        # 已经关着：不再 -D（免得删掉你后来自己加的同样规则）
        self.clear_log()
        self.run_watch("tick", "--now")
        self.run_watch("acme-close", "5")
        self.assertEqual(self.deletes(), [])

    def test_expiring_cert_reopens(self):
        d = self.acme_node()
        (d / "fw_acme.state").write_text("closed\n")
        (self.root / "ipt" / self.RULE).unlink()
        self.run_watch("tick", "--now")
        self.assertTrue((self.root / "ipt" / self.RULE).exists())
        self.assertEqual((d / "fw_acme.state").read_text().strip(), "open")
        # 已经开着：不重复加
        self.clear_log()
        self.run_watch("tick", "--now")
        self.assertFalse(any(line.startswith("iptables -I") for line in self.logged()))

    def test_no_cert_yet_keeps_open(self):
        d = self.acme_node(cert=False)
        (self.root / "openssl_ok").write_text("")
        self.run_watch("tick", "--now")
        self.assertEqual(self.deletes(), [])
        self.assertEqual((d / "fw_acme.state").read_text().strip(), "open")

    def test_hourly_stamp_skips_acme_without_now(self):
        self.acme_node()
        (self.root / "openssl_ok").write_text("")
        (self.root / "state" / "acme.stamp").write_text("")
        self.run_watch("tick")
        self.assertEqual(self.deletes(), [])
        self.run_watch("tick", "--now")
        self.assertEqual(len(self.deletes()), 1)

    def test_inactive_node_closes_port(self):
        d = self.acme_node()
        (self.root / "active" / "hysteria-node@5").unlink()
        self.run_watch("tick", "--now")
        self.assertEqual(len(self.deletes()), 1)
        self.assertEqual((d / "fw_acme.state").read_text().strip(), "closed")

    def test_installing_node_is_not_touched(self):
        d = self.acme_node()
        (d / "node.txt").unlink()
        (self.root / "openssl_ok").write_text("")
        self.run_watch("tick", "--now")
        self.assertEqual(self.deletes(), [])

    def test_drop_closes_and_forgets(self):
        d = self.acme_node()
        self.run_watch("acme-drop", "5")
        self.assertEqual(len(self.deletes()), 1)
        self.assertFalse((d / "fw_acme").exists())
        self.assertFalse((d / "fw_acme.state").exists())
        self.run_watch("acme-drop", "5")
        self.assertEqual(len(self.deletes()), 1)

    def test_bad_id_rejected(self):
        res = self.run_watch("acme-drop", "../x", check=False)
        self.assertEqual(res.returncode, 2)

    def test_undo_partial_record(self):
        rec = self.root / "fw_info"
        rec.write_text("443 udp 1 1 0 4\n8443 tcp 0 0 1 6\nbad line\n")
        (self.root / "ipt" / "ip6tables.INPUT_-p_tcp_--dport_8443_-j_ACCEPT").write_text("")
        self.run_watch("undo", str(rec))
        log = self.logged()
        self.assertIn("ufw delete allow 443/udp", log)
        self.assertIn("firewall-cmd --permanent --remove-port=443/udp", log)
        self.assertIn("ip6tables -D INPUT -p tcp --dport 8443 -j ACCEPT", log)
        self.assertFalse(any(line.startswith("iptables ") for line in log))


class PartialNodeAcmeTest(unittest.TestCase):
    def test_drop_partial_node_undoes_opened_ports(self):
        source = INSTALLER.read_text()
        start = source.index("_drop_partial_node() {")
        end = source.index("\n_abort_partial_node() {")
        funcs = source[start:end]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bindir = root / "bin"
            bindir.mkdir()
            log = root / "w.log"
            w = bindir / "xray-node-watch"
            w.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$W_LOG"\n')
            w.chmod(0o755)
            node = root / "nodes" / "9"
            node.mkdir(parents=True)
            (node / "core").write_text("hysteria\n")
            (node / "fw_acme").write_text("80 tcp 0 0 1 4\n")
            (node / "fw_acme.state").write_text("open\n")
            (node / "fw_info").write_text("443 udp 0 0 1 4\n")
            env = os.environ.copy()
            env.update({
                "XRAY_BIN_DIR": str(bindir),
                "XRAY_NODES_DIR": str(root / "nodes"),
                "XRAY_SYSTEMD_RUN": str(root / "none"),
                "W_LOG": str(log),
            })
            # 没有 systemd（XRAY_SYSTEMD_RUN 指向不存在的目录），pkill 换成空函数
            stubs = 'warn() { :; }; pkill() { return 0; }; '
            subprocess.run(["sh", "-c", stubs + funcs + "\n_reap_partial_nodes"], env=env, check=True, timeout=30)
            self.assertFalse(node.exists())
            self.assertEqual(log.read_text().splitlines(), [f"undo {node}/fw_acme", f"undo {node}/fw_info"])


class InstallerWiringTest(unittest.TestCase):
    def test_acme_ports_tracked_separately_and_cleaned(self):
        source = INSTALLER.read_text()
        self.assertNotIn("fw_info.acme", source)
        self.assertIn('_fw_allow "$_acme_port" tcp "$_acme_fam" "$NODE_DIR/fw_acme"', source)
        self.assertIn('"$_hap_watch" acme-close "$NODE_ID"', source)
        self.assertIn('"$_hap_watch" acme-drop "$NODE_ID"', source)

    def test_ctrl_c_runs_partial_cleanup(self):
        source = INSTALLER.read_text()
        i = source.index("trap _abort_partial_node EXIT\n")
        self.assertIn("trap 'exit 130' INT TERM HUP", source[i:i + 200])
        dns_off = between("_dns64_off() {", "\n}\n")
        self.assertNotIn("trap - INT TERM HUP", dns_off)

    def test_delete_and_uninstall_remove_watch(self):
        source = INSTALLER.read_text()
        expire = between("_delete_node() {", "\n}\n")
        self.assertIn('"$_x_watch" acme-drop "$_d_id"', expire)
        self.assertIn('"$_x_watch" arm', expire)
        del_node = between("_del_node() {", "\n}\n")
        self.assertIn("xray-node-watch acme-drop", del_node)
        uninstall = between("_uninstall_all() {", "\n}\n")
        self.assertIn("xray-node-watch disarm", uninstall)
        self.assertIn("/usr/local/bin/xray-node-watch ", uninstall)
        helpers = between("write_helper_cmds() {", "\n# ---------- 服务")
        self.assertIn("arm_node_watch || true", helpers)


if __name__ == "__main__":
    unittest.main()
