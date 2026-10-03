"""回程路由小程序 xray-node-route 的测试。

用一个假的 ip 命令模拟“策略路由把默认出口改到 VPN 网卡”的机器，不碰真的路由表。
真网络上的验证（私有网络命名空间里的 veth + L2TP 一样的策略路由）在提交说明里。
"""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"
SOURCE = INSTALLER.read_text()


def between(start, end):
    begin = SOURCE.index(start)
    return SOURCE[begin:SOURCE.index(end, begin)]


def route_script():
    begin = SOURCE.index("<<'ROUTEEOF'")
    begin = SOURCE.index("\n", begin) + 1
    return SOURCE[begin:SOURCE.index("\nROUTEEOF\n", begin)] + "\n"


# 假的 ip：网络情况写在 $NET（json），规则存在 $NET.rules<4|6>。
# route get 带 sport 时，如果有匹配这个端口的规则，就返回 lookup 表里的出口。
FAKE_IP = r'''#!/usr/bin/env python3
import json, os, re, sys
net = json.load(open(os.environ["NET"]))
a = sys.argv[1:]
with open(os.environ["NET"] + ".log", "a") as f:
    f.write(" ".join(a) + "\n")
oneline = False
if a and a[0] == "-o":
    oneline = True; a = a[1:]
fam = "4"
if a and a[0] in ("-4", "-6"):
    fam = a[0][1]; a = a[1:]
rf = os.environ["NET"] + ".rules" + fam
rules = [l.rstrip("\n") for l in open(rf)] if os.path.exists(rf) else net.get("rules" + fam, [])
def save():
    open(rf, "w").write("".join(l + "\n" for l in rules))
if a[:2] == ["addr", "show"]:
    dev = a[3] if len(a) > 3 and a[2] == "dev" else None
    for d, addrs in net["addrs" + fam].items():
        if dev and d != dev:
            continue
        for x in addrs:
            print("2: %s    inet%s %s/24 scope global %s" % (d, "6" if fam == "6" else "", x, d))
    sys.exit(0)
if a[:2] == ["route", "show"]:
    t = a[3]
    for line in net.get("routes" + fam, []):
        if t == "all" or ("table " not in line and t == "main"):
            print(line)
    sys.exit(0)
if a[:2] == ["route", "get"]:
    if "sport" in a:
        if net.get("old_ip"):
            sys.stderr.write('Error: argument "ipproto" is wrong\n'); sys.exit(1)
        port = a[a.index("sport") + 1]
        for l in sorted(rules, key=lambda l: int(l.split(":")[0])):
            if ("sport %s lookup " % port) in l:
                t = l.split(" lookup ")[1].split()[0]
                print(net["fixed" + fam].get(t, net["get" + fam])); sys.exit(0)
    print(net["get" + fam]); sys.exit(0)
if a[:2] == ["rule", "show"]:
    for l in rules:
        print(l)
    sys.exit(0)
if a[:2] == ["rule", "add"]:
    if net.get("old_kernel"):
        sys.stderr.write("Error: Unknown attribute\n"); sys.exit(2)
    pref = a[a.index("pref") + 1]
    rest = " ".join(a[a.index("pref") + 2:])
    rest = rest.replace("ipproto udp", "ipproto " + net.get("ipproto_name", "udp"))
    rules.append("%s:\tfrom all %s" % (pref, rest)); save(); sys.exit(0)
if a[:2] == ["rule", "del"]:
    pref = a[a.index("pref") + 1]
    port = a[a.index("sport") + 1]
    keep = [l for l in rules if not (l.startswith(pref + ":") and (" sport %s " % port) in l and " iif lo " in l)]
    if len(keep) == len(rules):
        sys.exit(2)
    rules[:] = keep; save(); sys.exit(0)
sys.exit(0)
'''

L2TP_RULES = ["0:\tfrom all lookup local",
              "8900:\tfrom all uidrange 999-999 lookup main",
              "8904:\tfrom all fwmark 0x24680 lookup main",
              "8915:\tfrom all lookup main suppress_prefixlength 0",
              "8920:\tfrom all lookup 24680",
              "32766:\tfrom all lookup main",
              "32767:\tfrom all lookup default"]

L2TP_NET = {
    "addrs4": {"eth0": ["217.60.237.64"], "l2tp-aa": ["81.187.228.68"]},
    "addrs6": {"eth0": ["2001:db8:e::64"], "l2tp-aa": ["2001:db8:a::68"]},
    "routes4": ["default via 217.60.237.1 dev eth0 proto static",
                "default via 81.187.228.1 dev l2tp-aa table 24680"],
    "routes6": ["default via 2001:db8:e::1 dev eth0 metric 1024",
                "default via 2001:db8:a::1 dev l2tp-aa table 24680 metric 1024"],
    "get4": "1.1.1.1 via 81.187.228.1 dev l2tp-aa table 24680 src 81.187.228.68 uid 0",
    "get6": "2606:4700:4700::1111 from :: via 2001:db8:a::1 dev l2tp-aa table 24680 src 2001:db8:a::68 metric 1024",
    "fixed4": {"main": "1.1.1.1 via 217.60.237.1 dev eth0 src 217.60.237.64 uid 0"},
    "fixed6": {"main": "2606:4700:4700::1111 from :: via 2001:db8:e::1 dev eth0 src 2001:db8:e::64 metric 1024"},
    "rules4": L2TP_RULES, "rules6": L2TP_RULES,
}

PLAIN_NET = dict(L2TP_NET, **{
    "get4": "1.1.1.1 via 217.60.237.1 dev eth0 src 217.60.237.64 uid 0",
    "get6": "2606:4700:4700::1111 from :: via 2001:db8:e::1 dev eth0 src 2001:db8:e::64 metric 1024",
    "rules4": ["0:\tfrom all lookup local", "32766:\tfrom all lookup main", "32767:\tfrom all lookup default"],
    "rules6": ["0:\tfrom all lookup local", "32766:\tfrom all lookup main", "32767:\tfrom all lookup default"],
})


class RouteBase(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.root = Path(self._t.name)
        self.nodes = self.root / "nodes"
        self.nodes.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "ip").write_text(FAKE_IP)
        (self.bin / "ip").chmod(0o755)
        self.script = self.root / "xray-node-route"
        self.script.write_text(route_script())
        self.script.chmod(0o755)
        self.net = self.root / "net.json"
        self.use_net(L2TP_NET)

    def tearDown(self):
        self._t.cleanup()

    def use_net(self, net):
        self.net.write_text(json.dumps(net))

    def rules(self, fam="4"):
        p = Path(str(self.net) + ".rules" + fam)
        if p.exists():
            return p.read_text().splitlines()
        return json.loads(self.net.read_text())["rules" + fam]

    def ours(self, fam="4"):
        return [l for l in self.rules(fam) if " iif lo ipproto " in l]

    def node(self, nid, core="hysteria", listen=":19188", port=19188, addr="217.60.237.64", addr6="2001:db8:e::64",
             proto="shadowsocks"):
        d = self.nodes / str(nid)
        d.mkdir()
        (d / "core").write_text(core + "\n")
        if core == "hysteria":
            (d / "config.yaml").write_text(f'listen: "{listen}"\nauth:\n  type: password\n')
            (d / "fw_info").write_text(f"{port} udp 0 0 0 4\n{port} udp 0 0 0 6\n")
        else:
            key = "type" if core == "sing-box" else "protocol"
            (d / "config.json").write_text(
                '{\n  "inbounds": [ { "listen": "%s", "port": %d, "%s": "%s" } ]\n}\n' % (listen, port, key, proto))
            (d / "fw_info").write_text(f"{port} tcp 0 0 0 4\n" + (f"{port} udp 0 0 0 4\n" if proto != "vless" else ""))
        txt = f"节点名: 测试\n地址: {addr}\n"
        if addr6:
            txt += f"IPv6 地址: {addr6}\n"
        (d / "node.txt").write_text(txt)
        return d

    def route(self, *args, check=False):
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", NET=str(self.net),
                   XRAY_NODE_DIR=str(self.nodes), XRAY_ROUTE_STATE=str(self.root / "state"))
        return subprocess.run(["sh", str(self.script), *args], env=env, capture_output=True, text=True,
                              timeout=60, check=check)


class RouteRuleTest(RouteBase):
    def test_l2tp_box_gets_v4_and_v6_rule_before_its_policy(self):
        self.node(1)
        self.assertEqual(self.route("up", "1").returncode, 0)
        self.assertEqual(self.ours("4"), ["8890:\tfrom all iif lo ipproto udp sport 19188 lookup main"])
        self.assertEqual(self.ours("6"), ["8890:\tfrom all iif lo ipproto udp sport 19188 lookup main"])
        show = self.route("show", "1").stdout
        self.assertIn("IPv4：回包本来会从 l2tp-aa 发出去，已加规则让 UDP 19188 的回包走 eth0（规则优先级 8890，查路由表 main）", show)
        self.assertIn("IPv6：", show)
        self.assertEqual(self.route("check", "1").returncode, 0)
        # 再跑一次不叠规则
        self.route("up", "1")
        self.assertEqual(len(self.ours("4")), 1)

    def test_normal_box_adds_nothing(self):
        self.use_net(PLAIN_NET)
        self.node(1)
        self.route("up", "1")
        self.assertEqual(self.ours("4") + self.ours("6"), [])
        self.assertEqual(self.route("show", "1").stdout, "")
        self.assertEqual(self.route("check", "1").returncode, 0)
        self.assertEqual(self.route("need").returncode, 1)

    def test_tcp_only_node_is_left_alone(self):
        self.node(3, core="xray", listen="0.0.0.0", port=443, proto="vless")
        self.route("up", "3")
        self.assertEqual(self.ours("4"), [])
        log = Path(str(self.net) + ".log").read_text()
        self.assertNotIn("rule add", log)

    def test_shadowsocks_and_tuic_are_udp_nodes(self):
        self.node(2, core="xray", listen="0.0.0.0", port=8388)
        self.node(4, core="sing-box", listen="::", port=8443, proto="tuic")
        self.route("up", "2")
        self.route("up", "4")
        self.assertEqual(sorted(self.ours("4")), ["8889:\tfrom all iif lo ipproto udp sport 8443 lookup main",
                                                  "8890:\tfrom all iif lo ipproto udp sport 8388 lookup main"])
        # 0.0.0.0 只听 IPv4，不加 IPv6 规则；:: 两种都听
        self.assertEqual(self.ours("6"), ["8890:\tfrom all iif lo ipproto udp sport 8443 lookup main"])

    def test_pref_goes_below_any_other_policy_rule(self):
        net = dict(L2TP_NET, rules4=["0:\tfrom all lookup local", "5210:\tfrom all fwmark 0x80000/0xff0000 lookup main",
                                     "5270:\tfrom all lookup 52", "8890:\tfrom all ipproto udp sport 19188 lookup main",
                                     "32766:\tfrom all lookup main"])
        self.use_net(net)
        self.node(1, listen="0.0.0.0:19188", addr6="")
        self.route("up", "1")
        self.assertIn("5209:\tfrom all iif lo ipproto udp sport 19188 lookup main", self.rules("4"))
        # 你自己手动加的规则（没有 iif lo）不算我们的，拆的时候不碰
        self.route("down", "1")
        self.assertIn("8890:\tfrom all ipproto udp sport 19188 lookup main", self.rules("4"))
        self.assertEqual(self.ours("4"), [])

    def test_numeric_ipproto_output_is_understood(self):
        self.use_net(dict(L2TP_NET, ipproto_name="17"))
        self.node(1)
        self.route("up", "1")
        self.assertEqual(self.route("check", "1").returncode, 0)
        self.route("down", "1")
        self.assertEqual(self.ours("4"), [])

    def test_clients_using_the_vpn_address_need_no_rule(self):
        self.node(1, addr="81.187.228.68", addr6="2001:db8:a::68")
        self.route("up", "1")
        self.assertEqual(self.ours("4") + self.ours("6"), [])

    def test_public_iface_default_in_other_table(self):
        net = dict(L2TP_NET, routes4=["default via 81.187.228.1 dev l2tp-aa",
                                      "default via 217.60.237.1 dev eth0 table 100"],
                   fixed4={"100": "1.1.1.1 via 217.60.237.1 dev eth0 src 217.60.237.64 uid 0"},
                   get4="1.1.1.1 via 81.187.228.1 dev l2tp-aa src 81.187.228.68 uid 0")
        self.use_net(net)
        self.node(1, listen="0.0.0.0:19188", addr6="")
        self.route("up", "1")
        self.assertEqual(self.ours("4"), ["8890:\tfrom all iif lo ipproto udp sport 19188 lookup 100"])

    def test_old_kernel_is_reported_and_not_retried(self):
        self.use_net(dict(L2TP_NET, old_kernel=True))
        self.node(1, listen="0.0.0.0:19188", addr6="")
        self.assertEqual(self.route("up", "1").returncode, 3)
        self.assertIn("内核太老（4.17 以前）", self.route("show", "1").stdout)
        self.assertEqual(self.route("check", "1").returncode, 0)

    def test_rule_that_does_not_help_is_removed(self):
        self.use_net(dict(L2TP_NET, fixed4={}))
        self.node(1, listen="0.0.0.0:19188", addr6="")
        self.assertNotEqual(self.route("up", "1").returncode, 0)
        self.assertEqual(self.ours("4"), [])
        self.assertIn("已经拆掉", self.route("show", "1").stdout)

    def test_vpn_going_away_removes_rule(self):
        self.node(1)
        self.route("up", "1")
        self.use_net(dict(PLAIN_NET, rules4=self.rules("4"), rules6=self.rules("6")))
        Path(str(self.net) + ".rules4").unlink()
        Path(str(self.net) + ".rules6").unlink()
        self.assertEqual(self.route("check", "1").returncode, 1)
        self.route("up", "1")
        self.assertEqual(self.ours("4") + self.ours("6"), [])

    def test_down_works_after_node_dir_is_gone(self):
        d = self.node(1)
        self.route("up", "1")
        for f in d.iterdir():
            f.unlink()
        d.rmdir()
        self.route("down", "1")
        self.assertEqual(self.ours("4") + self.ours("6"), [])
        self.assertFalse((self.root / "state" / "1").exists())

    def test_need_only_with_udp_node_and_policy(self):
        self.node(3, core="xray", listen="0.0.0.0", port=443, proto="vless")
        self.assertEqual(self.route("need").returncode, 1)
        self.node(1)
        self.assertEqual(self.route("need").returncode, 0)

    def test_bad_id(self):
        self.assertEqual(self.route("up", "../1").returncode, 2)


class WiringTest(unittest.TestCase):
    def test_service_templates_call_route_on_start_and_stop(self):
        svc = between("_svc_install() {", "\n_svc_restart() {")
        self.assertIn('_si_rt_pre="ExecStartPre=-${_si_plus}/usr/local/bin/xray-node-route up %i"', svc)
        self.assertIn('_si_rt_post="ExecStopPost=-${_si_plus}/usr/local/bin/xray-node-route down %i"', svc)
        self.assertIn("${_si_rt_pre}\nExecStart=${_si_tpl_exec}\n${_si_hop_post}\n${_si_rt_post}\n", svc)
        self.assertIn("/usr/local/bin/xray-node-route up ${_si_id} >/dev/null 2>&1 || true\n}\nstop_post() {", svc)
        self.assertIn("/usr/local/bin/xray-node-route down ${_si_id} >/dev/null 2>&1 || true\n}", svc)
        self.assertIn('/usr/local/bin/xray-node-route up "$_si_id" >/dev/null 2>&1 || true\n    pkill', svc)
        self.assertIn("install_route_bin || true", svc)

    def test_delete_expire_partial_and_uninstall_remove_rules(self):
        self.assertIn('[ -x "$_x_rt" ] && "$_x_rt" down "$_d_id"', between("_delete_node() {", "\n_expire_lock() {"))
        self.assertIn("/usr/local/bin/xray-node-route down \"$_x_id\"", between("_stop_remove_svc() {", "\n_del_node() {"))
        self.assertIn("/usr/local/bin/xray-node-route down \"$_dp_id\"", between("_drop_partial_node() {", "\n_reap_partial_nodes() {"))
        un = between("_uninstall_all() {", "\n_clean_choice() {")
        self.assertIn("rm -f /usr/local/bin/xray-node-route", un)
        self.assertIn("/run/xray-node-route", un)

    def test_watch_heals_and_arms_for_route(self):
        w = between("<<'WATCHEOF'", "\nWATCHEOF\n")
        self.assertIn('ROUTE="$BIN_DIR/xray-node-route"', w)
        self.assertIn("  _heal_hop\n  _heal_route\n}", w)
        self.assertIn('[ -x "$ROUTE" ] && "$ROUTE" need >/dev/null 2>&1 && return 0', w)
        self.assertIn('xray) systemctl is-active --quiet "xray-node@$1" ;;', w)

    def test_update_mode_refreshes_routes(self):
        self.assertIn("    _route_refresh_all\n    # 刷新 jiedian / shanjiedian", SOURCE)
        self.assertIn('  /usr/local/bin/xray-node-route up "$NODE_ID" >/dev/null 2>&1\n  _route_note "$NODE_ID" "$PORT"', SOURCE)

    def note(self, show):
        fn = between("_route_note() {", "\n# 更新模式：给老节点装上回程路由")
        with tempfile.TemporaryDirectory() as t:
            b = Path(t) / "xray-node-route"
            b.write_text("#!/bin/sh\nprintf '%s' \"$SHOW\"\n")
            b.chmod(0o755)
            env = dict(os.environ, XRAY_BIN_DIR=t, SHOW=show)
            return subprocess.run(["sh", "-c", 'info() { echo "OK $1"; }\nwarn() { echo "WARN $1"; }\n' + fn +
                                   '\n_route_note 1 19188'], env=env, capture_output=True, text=True,
                                  timeout=30, check=True).stdout

    def test_route_note_texts(self):
        self.assertEqual(self.note(""), "")
        out = self.note("IPv4：回包本来会从 l2tp-aa 发出去，已加规则让 UDP 19188 的回包走 eth0（规则优先级 8890，查路由表 main）")
        self.assertIn("策略路由", out)
        self.assertIn("  IPv4：回包本来会从 l2tp-aa", out)
        self.assertIn("OK 这条规则只管本机从 UDP 19188 发出的包", out)
        self.assertIn("升级到 4.17", self.note("IPv4：回包会从 l2tp-aa 发出去（应该走 eth0），但内核太老（4.17 以前），加不了按端口分的规则"))
        self.assertIn("脚本修不了", self.note("IPv4：…但找不到走 eth0 的路由表，没法自动修"))


if __name__ == "__main__":
    unittest.main()
