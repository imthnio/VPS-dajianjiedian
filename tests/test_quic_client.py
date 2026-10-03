"""拦截 QUIC 改成客户端开关的测试：服务器配置里不再拦 UDP 443；Loon / Surge 行写好 block-quic；
老节点更新时能把服务器端的拦截去掉（失败就换回原配置），node.txt 换成新说明。"""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def between(start, end):
    source = INSTALLER.read_text()
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def helpers():
    return between("_cq_ok() {", "\n# 更新模式：把所有老节点服务器上的")


def sh(script, env=None, check=True):
    full = os.environ.copy()
    full.update(env or {})
    return subprocess.run(["sh", "-c", script], env=full, check=check, timeout=60,
                          capture_output=True, text=True)


# 旧版脚本写出来的配置（和当时的模板一字不差）
OLD_XRAY = """{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 8388,
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-128-gcm",
        "password": "MDEyMzQ1Njc4OWFiY2RlZg==",
        "network": "tcp,udp"
      }
    }
  ],
  "routing": { "rules": [ { "type": "field", "network": "udp", "port": "443", "outboundTag": "block" } ] },
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ]
}
"""

OLD_SINGBOX = """{
  "log": { "level": "warning" },
  "inbounds": [
    { "type": "tuic", "listen": "0.0.0.0", "listen_port": 8443 }
  ],
  "outbounds": [ { "type": "direct" } ],
  "route": { "rules": [ { "network": "udp", "port": 443, "action": "reject" } ] }
}
"""

OLD_HY = """listen: ":8443"
auth:
  type: password
  password: "abc"

ignoreClientBandwidth: true
speedTest: false

# 拦截 QUIC：经过节点的 UDP 443（QUIC/HTTP3）直接拒绝，App 会自动改走 TCP，更快更稳。
# 只管“经过节点出去”的流量，不影响 Hysteria2 自己收发的 UDP。
acl:
  inline:
    - reject(all, udp/443)

masquerade:
  type: string
"""

OLD_VLESS_TXT = """==============================================
 你的节点（复制下面整行，粘贴到客户端导入）
==============================================
vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.samsung.com&fp=chrome&pbk=PUBKEYabc-_123&sid=0a1b2c3d&type=tcp#%E9%A6%99%E6%B8%AF
----------------------------------------------
节点名: 香港Vless-Reality
协议: VLESS + REALITY + Vision
地址: 1.2.3.4
端口: 443
UUID: 11111111-2222-3333-4444-555555555555
伪装域名: www.samsung.com
拦截 QUIC: 已在服务器上打开。经过节点的 UDP 443（QUIC/HTTP3）会被拒绝，App 自动改走 TCP，更快更稳，客户端不用另外设置。
想在客户端也拦：Loon 打开 block-quic；Clash / mihomo 在 rules 最前面加一行 - AND,((NETWORK,UDP),(DST-PORT,443)),REJECT
----------------------------------------------
种类: 永久节点
以后想看节点，直接输入: jiedian
==============================================
"""


class ServerSideRemovedTest(unittest.TestCase):
    def test_no_server_side_quic_block_left(self):
        source = INSTALLER.read_text()
        self.assertEqual(source.count('  "outbounds": [ { "protocol": "freedom" } ]\n'), 4)
        self.assertNotIn('{ "protocol": "blackhole", "tag": "block" }', source)
        self.assertNotIn("${SB_ROUTE}", source)
        self.assertNotIn("SB_ROUTE=", source)
        self.assertNotIn("不支持服务器端拦截 QUIC", source)
        code = "\n".join(l for l in source.splitlines() if not l.lstrip().startswith("#"))
        self.assertNotIn("已在服务器上打开", code)
        write_cfg = between("_hy_write_config() {", "\n_hy_listen_for() {")
        self.assertNotIn("acl:", write_cfg)
        self.assertNotIn("reject(", write_cfg)

    def test_update_mode_runs_the_migration(self):
        source = INSTALLER.read_text()
        self.assertIn("_hy_fix_existing_ipv6; _quic_unblock_all; break ;;", source)


class ClientLineTest(unittest.TestCase):
    BASE = {"CQ_NAME": "香港测试", "CQ_HOST": "1.2.3.4", "CQ_PORT": "443",
            "CQ_UUID": "11111111-2222-3333-4444-555555555555", "CQ_PASS": "pw123",
            "CQ_SNI": "www.samsung.com", "CQ_PBK": "PUBKEYabc-_123", "CQ_SID": "0a1b2c3d",
            "CQ_PATH": "/abc123"}

    def lines(self, proto, **over):
        env = dict(self.BASE, CQ_PROTO=proto, **over)
        out = sh(helpers() + '\nprintf "L=%s\\nS=%s\\n" "$(_cq_loon_line)" "$(_cq_surge_line)"', env).stdout
        loon, surge = out.split("\n")[0][2:], out.split("\n")[1][2:]
        return loon, surge

    def test_vless_reality(self):
        loon, surge = self.lines("vless")
        self.assertEqual(loon, '香港测试 = VLESS,1.2.3.4,443,"11111111-2222-3333-4444-555555555555",'
                               'transport=tcp,flow=xtls-rprx-vision,public-key="PUBKEYabc-_123",'
                               'short-id=0a1b2c3d,over-tls=true,sni=www.samsung.com,udp=true,block-quic=true')
        self.assertEqual(surge, "")  # Surge 没有 VLESS

    def test_trojan_reality(self):
        loon, surge = self.lines("trojan")
        self.assertEqual(loon, '香港测试 = Trojan,1.2.3.4,443,"pw123",transport=tcp,public-key="PUBKEYabc-_123",'
                               'short-id=0a1b2c3d,sni=www.samsung.com,udp=true,block-quic=true')
        self.assertEqual(surge, "")  # Surge 的 Trojan 没有 REALITY

    def test_vmess_ws(self):
        loon, surge = self.lines("vmess")
        self.assertEqual(loon, '香港测试 = VMess,1.2.3.4,443,auto,"11111111-2222-3333-4444-555555555555",'
                               'transport=ws,alterId=0,path=/abc123,over-tls=false,udp=true,block-quic=true')
        self.assertEqual(surge, "香港测试 = vmess, 1.2.3.4, 443, username=11111111-2222-3333-4444-555555555555, "
                                "ws=true, ws-path=/abc123, vmess-aead=true, block-quic=on")

    def test_shadowsocks_2022(self):
        loon, surge = self.lines("ss", CQ_PASS="MDEyMzQ1Njc4OWFiY2RlZg==")
        self.assertEqual(loon, '香港测试 = Shadowsocks,1.2.3.4,443,2022-blake3-aes-128-gcm,'
                               '"MDEyMzQ1Njc4OWFiY2RlZg==",udp=true,block-quic=true')
        self.assertEqual(surge, "香港测试 = ss, 1.2.3.4, 443, encrypt-method=2022-blake3-aes-128-gcm, "
                                "password=MDEyMzQ1Njc4OWFiY2RlZg==, udp-relay=true, block-quic=on")

    def test_anytls_reality(self):
        loon, surge = self.lines("anytls")
        self.assertEqual(loon, '香港测试 = AnyTLS,1.2.3.4,443,"pw123",sni=www.samsung.com,'
                               'public-key="PUBKEYabc-_123",short-id=0a1b2c3d,udp=true,block-quic=true')
        self.assertEqual(surge, "")

    def test_tuic_only_surge(self):
        loon, surge = self.lines("tuic")
        self.assertEqual(loon, "")  # Loon 不支持 TUIC
        self.assertEqual(surge, "香港测试 = tuic-v5, 1.2.3.4, 443, uuid=11111111-2222-3333-4444-555555555555, "
                                "password=pw123, alpn=h3, sni=www.samsung.com, skip-cert-verify=true, block-quic=on")

    def test_ipv6_address_kept_bare(self):
        loon, _ = self.lines("ss", CQ_HOST="2001:db8::1")
        self.assertTrue(loon.startswith("香港测试 = Shadowsocks,2001:db8::1,443,"))

    def test_bad_values_give_no_line(self):
        for over in ({"CQ_PASS": 'a,b'}, {"CQ_PASS": 'a"b'}, {"CQ_PASS": ""}, {"CQ_NAME": "a=b"}, {"CQ_HOST": ""}):
            loon, surge = self.lines("ss", **over)
            self.assertEqual((loon, surge), ("", ""), over)

    def test_section_mentions_every_app(self):
        env = dict(self.BASE, CQ_PROTO="vless")
        out = sh(helpers() + "\n_cq_section", env).stdout
        self.assertIn("服务器上不拦", out)
        self.assertIn("block-quic=true", out)
        self.assertIn("block-quic = all-proxy", out)
        self.assertIn("AND,((NETWORK,UDP),(DST-PORT,443)),REJECT", out)
        self.assertIn('"action": "reject"', out)
        self.assertNotIn("已在服务器上打开", out)

    def test_hy2_surge_line(self):
        snippet = between("      # Surge：自签证书用证书指纹锁定", "      # mihomo（Clash Meta")
        env = {"HY2_PIN": "AB" * 32, "HY2_DOMAIN": "", "HY2_USE_OBFS": "1", "HY2_OBFS": "obfspw",
               "HY_MPORT": "443,20000-20010", "NODE_NAME": "美国Hysteria2", "SERVER_IP": "1.2.3.4",
               "LINK_PORT": "443", "HY2_PASS": "hexpass", "HY2_SNI": "www.samsung.com"}
        out = sh(snippet, env).stdout.splitlines()
        self.assertEqual(out[1], '美国Hysteria2 = hysteria2, 1.2.3.4, 443, password=hexpass, sni=www.samsung.com, '
                                 'server-cert-fingerprint-sha256=' + "AB" * 32 + ', salamander-password=obfspw, '
                                 'port-hopping="443;20000-20010", port-hopping-interval=30, block-quic=on')
        env.update({"HY2_DOMAIN": "hy.example.com", "HY2_USE_OBFS": "0", "HY_MPORT": ""})
        out = sh(snippet, env).stdout.splitlines()
        self.assertEqual(out[1], "美国Hysteria2 = hysteria2, 1.2.3.4, 443, password=hexpass, sni=www.samsung.com, "
                                 "skip-cert-verify=false, block-quic=on")


class StripOldConfigTest(unittest.TestCase):
    def strip(self, func, text):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "c"
            p.write_text(text)
            return sh(helpers() + f'\n{func} "{p}"', check=False)

    def test_xray(self):
        res = self.strip("_cq_strip_xray", OLD_XRAY)
        self.assertEqual(res.returncode, 0)
        cfg = json.loads(res.stdout)
        self.assertEqual(cfg["outbounds"], [{"protocol": "freedom"}])
        self.assertNotIn("routing", cfg)
        self.assertEqual(cfg["inbounds"][0]["port"], 8388)
        # 已经是新配置 / 你自己改过的：不动
        self.assertEqual(self.strip("_cq_strip_xray", res.stdout).returncode, 1)
        edited = OLD_XRAY.replace('"port": "443"', '"port": "443,80"')
        self.assertEqual(self.strip("_cq_strip_xray", edited).returncode, 1)

    def test_singbox(self):
        res = self.strip("_cq_strip_singbox", OLD_SINGBOX)
        self.assertEqual(res.returncode, 0)
        cfg = json.loads(res.stdout)
        self.assertEqual(cfg["outbounds"], [{"type": "direct"}])
        self.assertNotIn("route", cfg)
        self.assertEqual(self.strip("_cq_strip_singbox", res.stdout).returncode, 1)

    def test_hysteria(self):
        res = self.strip("_cq_strip_hysteria", OLD_HY)
        self.assertEqual(res.returncode, 0)
        self.assertNotIn("acl:", res.stdout)
        self.assertNotIn("拦截 QUIC", res.stdout)
        self.assertIn("speedTest: false\n\nmasquerade:", res.stdout)
        # acl 里还有你自己加的规则：整段不动
        mine = OLD_HY.replace("    - reject(all, udp/443)\n", "    - reject(all, udp/443)\n    - direct(all)\n")
        self.assertEqual(self.strip("_cq_strip_hysteria", mine).returncode, 1)
        self.assertEqual(self.strip("_cq_strip_hysteria", res.stdout).returncode, 1)


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.root = Path(self._t.name)
        self.nodes = self.root / "nodes"
        self.nodes.mkdir()
        self.log = self.root / "log"
        self.log.write_text("")

    def tearDown(self):
        self._t.cleanup()

    def node(self, nid, core, cfg_name, cfg, txt=OLD_VLESS_TXT):
        d = self.nodes / str(nid)
        d.mkdir()
        (d / "core").write_text(core + "\n")
        (d / cfg_name).write_text(cfg)
        (d / "node.txt").write_text(txt)
        return d

    def run_migrate(self, port_ok=True, xray_bin="/nonexistent"):
        stubs = (
            'info() { printf "INFO %s\\n" "$1"; }\nwarn() { printf "WARN %s\\n" "$1"; }\n'
            '_svc_restart() { printf "restart %s\\n" "$1" >> "$LOG"; }\n'
            '_node_port() { printf "443 tcp"; }\n'
            'wait_for_port() { printf "wait %s %s\\n" "$1" "$2" >> "$LOG"; [ "$PORT_OK" = 1 ]; }\n'
            f'XRAY_BIN={xray_bin}; SB_BIN=/nonexistent\n'
        )
        func = between("_quic_unblock_all() {", "\n_hy_fix_existing_ipv6() {")
        return sh(stubs + helpers() + "\n" + func + "\n_quic_unblock_all",
                  {"XRAY_NODES_DIR": str(self.nodes), "LOG": str(self.log), "PORT_OK": "1" if port_ok else "0"})

    def test_success_strips_and_rewrites_node_txt(self):
        d = self.node(1, "xray", "config.json", OLD_XRAY)
        res = self.run_migrate()
        self.assertIn("已去掉服务器端拦 QUIC", res.stdout)
        self.assertNotIn("blackhole", (d / "config.json").read_text())
        self.assertFalse((d / "config.json.bak-quic").exists())
        self.assertEqual(self.log.read_text().splitlines(), ["restart 1", "wait 443 tcp"])
        txt = (d / "node.txt").read_text()
        self.assertNotIn("已在服务器上打开", txt)
        self.assertNotIn("想在客户端也拦", txt)
        self.assertIn('香港Vless-Reality = VLESS,1.2.3.4,443,"11111111-2222-3333-4444-555555555555",'
                      'transport=tcp,flow=xtls-rprx-vision,public-key="PUBKEYabc-_123",short-id=0a1b2c3d,'
                      'over-tls=true,sni=www.samsung.com,udp=true,block-quic=true', txt)
        self.assertTrue(txt.rstrip().endswith("=============================================="))
        self.assertIn("种类: 永久节点", txt)
        # 再跑一次什么都不变
        before = txt
        self.log.write_text("")
        self.run_migrate()
        self.assertEqual((d / "node.txt").read_text(), before)
        self.assertEqual(self.log.read_text(), "")

    def test_failed_restart_rolls_back(self):
        d = self.node(2, "sing-box", "config.json", OLD_SINGBOX)
        res = self.run_migrate(port_ok=False)
        self.assertIn("已换回原来的配置", res.stdout)
        self.assertEqual((d / "config.json").read_text(), OLD_SINGBOX)
        self.assertFalse((d / "config.json.bak-quic").exists())
        self.assertEqual(self.log.read_text().splitlines(), ["restart 2", "wait 443 tcp", "restart 2"])
        # 服务器上还在拦，node.txt 也保持原样
        self.assertIn("已在服务器上打开", (d / "node.txt").read_text())

    def fake_xray(self, ok):
        # 和真 Xray 一样：配置文件不是 .json 结尾就认不出来
        p = self.root / "xray"
        p.write_text('#!/bin/sh\ncase "$3" in *.json) ;; *) exit 1 ;; esac\n'
                     'printf "%s\\n" "$3" >> "$LOG"\n' + ("exit 0\n" if ok else "exit 1\n"))
        p.chmod(0o755)
        return str(p)

    def test_checked_by_core_before_swap(self):
        d = self.node(5, "xray", "config.json", OLD_XRAY)
        self.run_migrate(xray_bin=self.fake_xray(True))
        log = self.log.read_text().splitlines()
        self.assertEqual(log[0], f"{d}/config.noquic.json")
        self.assertEqual(log[1:], ["restart 5", "wait 443 tcp"])
        self.assertNotIn("blackhole", (d / "config.json").read_text())
        self.assertEqual(sorted(p.name for p in d.iterdir()), ["config.json", "core", "node.txt"])

    def test_check_failure_keeps_everything(self):
        d = self.node(6, "xray", "config.json", OLD_XRAY)
        res = self.run_migrate(xray_bin=self.fake_xray(False))
        self.assertIn("配置校验没通过", res.stdout)
        self.assertEqual((d / "config.json").read_text(), OLD_XRAY)
        self.assertEqual((d / "node.txt").read_text(), OLD_VLESS_TXT)
        self.assertNotIn("restart", self.log.read_text())
        self.assertEqual(sorted(p.name for p in d.iterdir()), ["config.json", "core", "node.txt"])

    def test_hysteria_node_and_untouched_custom_config(self):
        hy_txt = OLD_VLESS_TXT.replace("vless://", "hysteria2://")
        d = self.node(3, "hysteria", "config.yaml", OLD_HY, hy_txt)
        mine = OLD_XRAY.replace('"port": "443"', '"port": "443,80"')
        d2 = self.node(4, "xray", "config.json", mine)
        self.run_migrate()
        self.assertNotIn("acl:", (d / "config.yaml").read_text())
        self.assertIn("上面给 Loon / Surge 粘贴的那几行已经写好这个开关", (d / "node.txt").read_text())
        self.assertEqual((d2 / "config.json").read_text(), mine)
        self.assertEqual(self.log.read_text().splitlines(), ["restart 3", "wait 443 tcp"])


if __name__ == "__main__":
    unittest.main()
