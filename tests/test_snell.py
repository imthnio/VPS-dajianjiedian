"""Snell v5 / v6 协议支持与全面检查修复回归测试。"""

import hashlib
import os
import stat
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"
SOURCE = INSTALLER.read_text(encoding="utf-8")


def between(start, end):
    begin = SOURCE.index(start)
    return SOURCE[begin:SOURCE.index(end, begin)]


def heredoc(marker_start, marker_end):
    start = SOURCE.index(marker_start) + len(marker_start)
    return SOURCE[start:SOURCE.index(marker_end, start)]


def run_sh(script, env=None, stdin="", check=False):
    full = os.environ.copy()
    if env:
        full.update(env)
    return subprocess.run(
        ["sh", "-c", script],
        input=stdin,
        env=full,
        text=True,
        capture_output=True,
        timeout=30,
        check=check,
    )


class SnellHelpersTest(unittest.TestCase):
    def snell_dl_funcs(self):
        return (
            "info() { printf 'INFO %s\\n' \"$1\"; }\n"
            "warn() { printf 'WARN %s\\n' \"$1\"; }\n"
            "err()  { printf 'ERR %s\\n' \"$1\"; }\n"
            "step() { printf 'STEP %s\\n' \"$1\"; }\n"
            "die()  { printf 'DIE %s\\n' \"$1\"; exit 1; }\n"
            + between("_sha256_of() {", "\n# _gh_get ")
            + "\n"
            + between("# ---------- 下载 Snell 内核（v5 / v6） ----------", "\n# ---------- 1. 必须是 root ----------")
        )

    def test_arch_mapping_and_pinned_sha256(self):
        funcs = self.snell_dl_funcs()
        for mach, expect in (("amd64", "amd64"), ("arm64", "aarch64"), ("armv7", "armv7l")):
            res = run_sh(funcs + f"\nMACH={mach}; _snell_arch 5\n")
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(res.stdout.strip(), expect)
            h = run_sh(funcs + f"\n_snell_expect_sum 5.0.1 {expect}\n")
            self.assertEqual(h.returncode, 0, f"5.0.1:{expect}")
            self.assertEqual(len(h.stdout.strip()), 64)
        for mach, expect in (("amd64", "amd64"), ("arm64", "aarch64")):
            res = run_sh(funcs + f"\nMACH={mach}; _snell_arch 6\n")
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(res.stdout.strip(), expect)
            h = run_sh(funcs + f"\n_snell_expect_sum 6.0.0 {expect}\n")
            self.assertEqual(h.returncode, 0, f"6.0.0:{expect}")
            self.assertEqual(len(h.stdout.strip()), 64)
        # v6 不提供 armv7l
        self.assertNotEqual(run_sh(funcs + "\nMACH=armv7; _snell_arch 6\n").returncode, 0)
        # v4 校验值已移除
        self.assertNotEqual(run_sh(funcs + "\n_snell_expect_sum 4.1.1 amd64\n").returncode, 0)
        self.assertNotEqual(run_sh(funcs + "\n_snell_expect_sum 9.9.9 amd64\n").returncode, 0)

    def test_latest_snell_ver_parses_kb_and_falls_back(self):
        funcs = self.snell_dl_funcs()
        kb = (
            "https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-amd64.zip\n"
            "https://dl.nssurge.com/snell/snell-server-v5.0.2-linux-amd64.zip\n"
            "https://dl.nssurge.com/snell/snell-server-v5.0.1-linux-amd64.zip\n"
            "https://dl.nssurge.com/snell/snell-server-v6.0.1b1-linux-amd64.zip\n"
            "https://dl.nssurge.com/snell/snell-server-v6.0.0-linux-amd64.zip\n"
        )
        # v5 挑到最新的 5.0.2；v6 跳过 beta 只取正式版 6.0.0
        script = funcs + f"\n_http_body() {{ cat <<'KB'\n{kb}KB\n}}\nprintf '%s|%s' \"$(_latest_snell_ver 5)\" \"$(_latest_snell_ver 6)\"\n"
        res = run_sh(script)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout.strip(), "5.0.2|6.0.0")

        # 断网时两个大版本都走内置兜底
        offline = funcs + "\n_http_body() { return 1; }\nprintf '%s|%s' \"$(_latest_snell_ver 5)\" \"$(_latest_snell_ver 6)\"\n"
        res2 = run_sh(offline)
        self.assertEqual(res2.stdout.strip(), "5.0.1|6.0.0")

    def test_snell_local_ver_and_bin_ok(self):
        funcs = self.snell_dl_funcs()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            good5 = root / "snell5"
            good5.write_text("#!/bin/sh\necho 'snell-server v5.0.1' >&2\nexit 1\n")
            good5.chmod(0o755)
            good6 = root / "snell6"
            good6.write_text("#!/bin/sh\necho '2026-11-24 [server_main] <NOTIFY> snell-server v6.0.0 (Aug  7 2026)'\nexit 0\n")
            good6.chmod(0o755)
            bad_glibc = root / "bad_glibc"
            bad_glibc.write_text("#!/bin/sh\necho 'Error loading shared library ld-linux-x86-64.so.2: No such file' >&2\nexit 127\n")
            bad_glibc.chmod(0o755)
            bad_crash = root / "bad_crash"
            bad_crash.write_text("#!/bin/sh\nexit 139\n")
            bad_crash.chmod(0o755)

            self.assertEqual(run_sh(funcs + f"\n_snell_local_ver '{good5}'\n").stdout.strip(), "5.0.1")
            self.assertEqual(run_sh(funcs + f"\n_snell_local_ver '{good6}'\n").stdout.strip(), "6.0.0")
            self.assertEqual(run_sh(funcs + f"\n_snell_bin_ok '{good5}'\n").returncode, 0)
            self.assertEqual(run_sh(funcs + f"\n_snell_bin_ok '{good6}'\n").returncode, 0)
            self.assertNotEqual(run_sh(funcs + f"\n_snell_bin_ok '{bad_glibc}'\n").returncode, 0)
            self.assertNotEqual(run_sh(funcs + f"\n_snell_bin_ok '{bad_crash}'\n").returncode, 0)

    def test_dl_snell_inner_verifies_sha256_and_reports_glibc_failure(self):
        funcs = self.snell_dl_funcs()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            zpath = root / "src.zip"
            with zipfile.ZipFile(zpath, "w") as zf:
                zf.writestr("snell-server", "#!/bin/sh\necho 'snell-server v6.0.0'\nexit 0\n")
            good_sha = hashlib.sha256(zpath.read_bytes()).hexdigest()
            dest = root / "snell-server-v6"
            marks = root / "marks"

            script = (
                funcs
                + f"""
MACH=amd64
FORCE_DL=1
SNELL6_BIN="{dest}"
_ensure_unzip() {{ :; }}
pick_dldir() {{ mkdir -p "{root}/dl" && printf '%s' "{root}/dl"; }}
_latest_snell_ver() {{ printf '6.0.0'; }}
_snell_expect_sum() {{ printf '{good_sha}'; }}
_http_save() {{ cp "{zpath}" "$2"; }}
_pace_start() {{ :; }}
_pace_stop() {{ :; }}
drop_page_cache() {{ :; }}
_dns64_off() {{ :; }}
_no_ipv4_route() {{ return 1; }}
mark_our_bin() {{ echo "$1" >> "{marks}"; }}
_dl_snell_inner 6
"""
            )
            res = run_sh(script)
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertTrue(dest.exists())
            self.assertIn("SHA256 校验通过", res.stdout)
            self.assertIn("snell-server-v6", marks.read_text())

            # SHA256 不匹配必须拒装
            bad_script = script.replace(good_sha, "0" * 64)
            dest.unlink()
            res_bad = run_sh(bad_script)
            self.assertNotEqual(res_bad.returncode, 0)
            self.assertIn("SHA256 校验没通过", res_bad.stdout)
            self.assertFalse(dest.exists())

            # glibc 缺失时给出清晰的中文提示
            zbad = root / "bad.zip"
            with zipfile.ZipFile(zbad, "w") as zf:
                zf.writestr("snell-server", "#!/bin/sh\necho 'GLIBC_2.34 not found' >&2\nexit 127\n")
            bad_glibc_sha = hashlib.sha256(zbad.read_bytes()).hexdigest()
            glibc_script = script.replace(str(zpath), str(zbad)).replace(good_sha, bad_glibc_sha)
            res_g = run_sh(glibc_script)
            self.assertNotEqual(res_g.returncode, 0)
            self.assertIn("依赖 glibc", res_g.stdout)
            self.assertFalse(dest.exists())

            # armv7 上选 Snell v6 给出明确中文提示
            armv7_script = script.replace("MACH=amd64", "MACH=armv7")
            res_a = run_sh(armv7_script)
            self.assertNotEqual(res_a.returncode, 0)
            self.assertIn("不提供 32 位 ARM", res_a.stdout)

    def test_snell_ask_obfs_and_v6_mode(self):
        common = (
            "info() { printf 'INFO %s\\n' \"$1\"; }\n"
            "warn() { printf 'WARN %s\\n' \"$1\"; }\n"
            "die()  { printf 'DIE %s\\n' \"$1\"; exit 1; }\n"
            + between("ask() {", "\nrand_hex() {")
            + "\n"
            + between("_valid_host() {", "\n_resolve_host() {")
            + "\n"
            + between("_snell_ask_obfs() {", "\n# ---------- Hysteria2 正规证书：acme.sh ----------")
        )
        obfs_script = common + '\n_snell_ask_obfs\nprintf "RES=%s|%s\\n" "$SNELL_OBFS" "$SNELL_OBFS_HOST"\n'
        r_def = run_sh(obfs_script, stdin="\n")
        self.assertEqual(r_def.returncode, 0, r_def.stderr)
        self.assertIn("RES=off|", r_def.stdout)

        r_http = run_sh(obfs_script, stdin="2\nhttps://Example.COM/path\n")
        self.assertEqual(r_http.returncode, 0, r_http.stderr)
        self.assertIn("RES=http|example.com", r_http.stdout)

        r_retry = run_sh(obfs_script, stdin="9\n2\nnot a host\nwww.bing.com\n")
        self.assertEqual(r_retry.returncode, 0, r_retry.stderr)
        self.assertIn("WARN 没有这个选项", r_retry.stdout)
        self.assertIn("RES=http|www.bing.com", r_retry.stdout)

        mode_script = common + '\n_snell6_ask_mode\nprintf "MODE=%s\\n" "$SNELL_MODE"\n'
        self.assertIn("MODE=default", run_sh(mode_script, stdin="\n").stdout)
        self.assertIn("MODE=unshaped", run_sh(mode_script, stdin="2\n").stdout)
        r_raw = run_sh(mode_script, stdin="9\n3\n")
        self.assertIn("WARN 没有这个选项", r_raw.stdout)
        self.assertIn("MODE=unsafe-raw", r_raw.stdout)


class SnellClientOutputTest(unittest.TestCase):
    def cq_helpers(self):
        return between("_cq_ok() {", "\n# 更新模式：把所有老节点服务器上的")

    def test_loon_and_surge_lines_for_v5_and_v6(self):
        base = {
            "CQ_NAME": "香港Snell5",
            "CQ_HOST": "2001:db8::1",
            "CQ_PORT": "23456",
            "CQ_PASS": "0123456789abcdef0123456789abcdef",
            "CQ_OBFS": "http",
            "CQ_OBFS_HOST": "www.bing.com",
            "CQ_SNELL_MODE": "default",
        }
        out5 = run_sh(
            self.cq_helpers() + '\nprintf "L=%s\\nS=%s\\n" "$(_cq_loon_line)" "$(_cq_surge_line)"',
            env=dict(base, CQ_PROTO="snell5"),
        ).stdout.splitlines()
        self.assertEqual(
            out5[0],
            'L=香港Snell5 = Snell,2001:db8::1,23456,"0123456789abcdef0123456789abcdef",version=5,obfs=http,obfs-host=www.bing.com,udp=true,block-quic=true',
        )
        self.assertEqual(
            out5[1],
            "S=香港Snell5 = snell, 2001:db8::1, 23456, psk=0123456789abcdef0123456789abcdef, version=5, reuse=true, obfs=http, obfs-host=www.bing.com, block-quic=on",
        )

        out6 = run_sh(
            self.cq_helpers() + '\nprintf "L=%s\\nS=%s\\n" "$(_cq_loon_line)" "$(_cq_surge_line)"',
            env=dict(base, CQ_PROTO="snell6", CQ_NAME="香港Snell6", CQ_HOST="1.2.3.4", CQ_SNELL_MODE="unshaped"),
        ).stdout.splitlines()
        self.assertEqual(out6[0], "L=")
        self.assertEqual(
            out6[1],
            "S=香港Snell6 = snell, 1.2.3.4, 23456, psk=0123456789abcdef0123456789abcdef, version=6, mode=unshaped, reuse=true, block-quic=on",
        )

    def test_cq_from_nodetxt_parses_snell5_and_snell6(self):
        with tempfile.TemporaryDirectory() as tmp:
            nd5 = Path(tmp) / "1"
            nd5.mkdir()
            (nd5 / "node.txt").write_text(
                "snell://aabbccdd00112233445566778899aabb@1.2.3.4:23456?version=5&reuse=true&obfs=http&obfs-host=bing.com#HK\n"
                "节点名: 香港Snell5\n"
                "地址: 1.2.3.4\n"
                "端口: 23456\n"
                "PSK（密钥）: aabbccdd00112233445566778899aabb\n"
            )
            res = run_sh(
                self.cq_helpers()
                + f'\n_cq_from_nodetxt "{nd5}" && printf "%s|%s|%s|%s|%s" "$CQ_PROTO" "$CQ_PASS" "$CQ_OBFS" "$CQ_OBFS_HOST" "$(_cq_loon_line)"\n'
            )
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertIn("snell5|aabbccdd00112233445566778899aabb|http|bing.com|", res.stdout)
            self.assertIn("香港Snell5 = Snell,1.2.3.4,23456,", res.stdout)

            nd6 = Path(tmp) / "2"
            nd6.mkdir()
            (nd6 / "node.txt").write_text(
                "snell://aabbccdd00112233445566778899aabb@1.2.3.4:23457?version=6&mode=unshaped&reuse=true#HK6\n"
                "节点名: 香港Snell6\n"
                "地址: 1.2.3.4\n"
                "端口: 23457\n"
                "PSK（密钥）: aabbccdd00112233445566778899aabb\n"
                "传输模式: unshaped\n"
            )
            res6 = run_sh(
                self.cq_helpers()
                + f'\n_cq_from_nodetxt "{nd6}" && printf "%s|%s|%s|%s" "$CQ_PROTO" "$CQ_PASS" "$CQ_SNELL_MODE" "$(_cq_surge_line)"\n'
            )
            self.assertEqual(res6.returncode, 0, res6.stderr)
            self.assertIn("snell6|aabbccdd00112233445566778899aabb|unshaped|", res6.stdout)
            self.assertIn("version=6, mode=unshaped, reuse=true, block-quic=on", res6.stdout)

    def test_jiedian_shows_link_loon_and_surge_for_snell(self):
        jd = heredoc("cat > /usr/local/bin/jiedian <<'JDEOF'\n", "\nJDEOF\n")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nd = root / "1"
            nd.mkdir()
            (nd / "node.txt").write_text(
                "snell://aabbccdd00112233445566778899aabb@1.2.3.4:23456?version=5&reuse=true#HK\n"
                "节点名: 香港Snell5\n"
                "协议: Snell v5\n"
                "地址: 1.2.3.4\n"
                "端口: 23456\n"
                "PSK（密钥）: aabbccdd00112233445566778899aabb\n"
                "Surge 节点配置（启用 v5 QUIC 代理模式，贴到 [Proxy] 下面）:\n"
                "香港Snell5 = snell, 1.2.3.4, 23456, psk=aabbccdd00112233445566778899aabb, version=5, reuse=true\n"
                '香港Snell5 = Snell,1.2.3.4,23456,"aabbccdd00112233445566778899aabb",version=5,udp=true,block-quic=true\n'
            )
            patched = jd.replace("/etc/xray-node/nodes", str(root)).replace("/usr/local/bin/xray-node-expire", "/nonexistent")
            res = run_sh(patched)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertIn("snell://aabbccdd", res.stdout)
            self.assertIn("【2】Loon 节点", res.stdout)
            self.assertIn("香港Snell5 = Snell,1.2.3.4,23456,", res.stdout)
            self.assertIn("【3】Surge 节点", res.stdout)
            self.assertIn("香港Snell5 = snell, 1.2.3.4, 23456, psk=aabbccdd", res.stdout)


class SnellLifecycleTest(unittest.TestCase):
    def test_xray_node_run_launches_snell_v5_and_v6(self):
        run_script = heredoc("<<'RUNEOF' || return 1\n", "\nRUNEOF\n")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nodes = root / "nodes"
            for nid, core in (("1", "snell-v5"), ("2", "snell-v6")):
                d = nodes / nid
                d.mkdir(parents=True)
                (d / "core").write_text(core + "\n")
                (d / "config.conf").write_text("[snell-server]\nlisten = 0.0.0.0:23456\n")
            sn5 = root / "snell-server-v5"
            sn6 = root / "snell-server-v6"
            sn5.write_text("#!/bin/sh\necho V5 \"$@\"\n")
            sn6.write_text("#!/bin/sh\necho V6 \"$@\"\n")
            sn5.chmod(0o755)
            sn6.chmod(0o755)
            runner = root / "xray-node-run"
            runner.write_text(run_script)
            runner.chmod(0o755)
            env = {
                "XRAY_NODE_DIR": str(nodes),
                "SNELL5_BIN_PATH": str(sn5),
                "SNELL6_BIN_PATH": str(sn6),
            }
            r5 = run_sh(f'"{runner}" 1', env=env)
            r6 = run_sh(f'"{runner}" 2', env=env)
            self.assertEqual(r5.stdout.strip(), f"V5 -c {nodes}/1/config.conf")
            self.assertEqual(r6.stdout.strip(), f"V6 -c {nodes}/2/config.conf")

    def test_route_treats_snell_v5_as_udp_and_v6_as_tcp(self):
        rt = heredoc("<<'ROUTEEOF' || return 1\n", "\nROUTEEOF\n")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nodes = root / "nodes"
            for nid, core, listen in (("1", "snell-v6", "0.0.0.0:23456,[::]:23456"), ("2", "snell-v5", "::0:23457")):
                d = nodes / nid
                d.mkdir(parents=True)
                (d / "core").write_text(core + "\n")
                (d / "config.conf").write_text(f"[snell-server]\nlisten = {listen}\npsk = abc\n")
                (d / "fw_info").write_text(f"{listen.split(':')[-1]} tcp 0 0 0 4\n")
            # 直接在同一个脚本片段里测 _is_udp_node / _listen / _load
            helper_part = rt[rt.index("_is_udp_node() {"):rt.index("_node_addrs() {")]
            r6 = run_sh(f'NODES_DIR="{nodes}"\n' + helper_part + '\nid=1; _is_udp_node && echo YES || echo NO\n')
            self.assertEqual(r6.stdout.strip(), "NO", r6.stderr)
            r5 = run_sh(
                f'NODES_DIR="{nodes}"\n'
                + helper_part
                + '\nid=2; _is_udp_node && _load && printf "YES|%s|%s\\n" "$port" "$fams"\n'
            )
            self.assertEqual(r5.stdout.strip(), "YES|23457|4 6", r5.stderr)

    def test_ipv6_rebind_and_strip_for_snell5_and_snell6(self):
        rebind = between("_ipv6_rebind_nodes() {", "\n_ipv6_persist() {")
        strip = between("_ipv6_strip_links() {", "\n_ipv6_turn_off() {")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nd5 = root / "1"
            nd5.mkdir()
            cfg5 = nd5 / "config.conf"
            cfg5.write_text("[snell-server]\nlisten = ::0:23456\npsk = 0123456789abcdef0123456789abcdef\nipv6 = true\n")
            nt5 = nd5 / "node.txt"
            nt5.write_text(
                "snell://abc@[2001:db8::1]:23456?version=5&reuse=true#HK\n"
                "香港Snell5 = snell, 2001:db8::1, 23456, psk=abc, version=5, reuse=true\n"
                '香港Snell5 = Snell,2001:db8::1,23456,"abc",version=5,udp=true,block-quic=true\n'
                "香港Snell6 = snell, 1.2.3.4, 23457, psk=abc, version=6, mode=default, reuse=true, block-quic=on\n"
            )
            nd6 = root / "2"
            nd6.mkdir()
            cfg6 = nd6 / "config.conf"
            cfg6.write_text(
                "[snell-server]\nlisten = 0.0.0.0:23457,[::]:23457\npsk = 0123456789abcdef0123456789abcdef\nmode = default\ndns-ip-preference = default\n"
            )
            res = run_sh(
                "info() { printf 'INFO %s\\n' \"$1\"; }\n"
                "warn() { printf 'WARN %s\\n' \"$1\"; }\n"
                "_svc_restart() { echo RESTART $1; }\n"
                "wait_for_port() { return 0; }\n"
                + rebind + "\n" + strip
                + f'\nXRAY_NODES_DIR="{root}"\n_ipv6_rebind_nodes\n_ipv6_strip_links\n'
            )
            self.assertEqual(res.returncode, 0, res.stderr)
            new_cfg5 = cfg5.read_text()
            self.assertIn("listen = 0.0.0.0:23456", new_cfg5)
            self.assertIn("ipv6 = false", new_cfg5)
            new_cfg6 = cfg6.read_text()
            self.assertIn("listen = 0.0.0.0:23457\n", new_cfg6)
            self.assertNotIn("[::]", new_cfg6)
            self.assertIn("dns-ip-preference = ipv4-only", new_cfg6)
            new_nt5 = nt5.read_text()
            self.assertNotIn("2001:db8::1", new_nt5)
            self.assertIn("1.2.3.4", new_nt5)

    def test_snell_wiring_across_uninstall_watch_expire_and_update(self):
        # 模板清理、our_bins 卸载、更新模式、到期停止、巡检活跃检查、半截节点清理；且不再包含 snell-v4 / snell4
        self.assertIn("/etc/systemd/system/snell-v5-node@.service", SOURCE)
        self.assertIn("/etc/systemd/system/snell-v6-node@.service", SOURCE)
        self.assertIn("xray|sing-box|hysteria|snell-server-v5|snell-server-v6", SOURCE)
        self.assertIn("xray|sing-box|hysteria|snell-v5|snell-v6", SOURCE)
        self.assertIn("\n  _fix_existing_snell_ipv6\n", SOURCE)
        self.assertIn('snell-v5) systemctl is-active --quiet "snell-v5-node@$1" ;;', SOURCE)
        self.assertIn('snell-v6) systemctl is-active --quiet "snell-v6-node@$1" ;;', SOURCE)
        self.assertIn('"$WANTS/snell-v5-node@${_x_id}.service"', SOURCE)
        self.assertIn('"$WANTS/snell-v6-node@${_x_id}.service"', SOURCE)
        self.assertNotIn("snell-v4", SOURCE)
        self.assertNotIn("snell4", SOURCE)
        self.assertNotIn("snell-server-v4", SOURCE)

    def test_snell6_config_and_fix_existing_ipv6(self):
        cfg_block = between("# ---------- Snell 配置（v5 / v6） ----------", "\n# ---------- 11. 开机自启")
        # 去掉末尾的 fi（它属于外层 if/elif/else）
        cfg_body = cfg_block.rsplit("\nfi", 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nd = root / "1"
            nd.mkdir()
            script_dual = (
                "info() { :; }\ndie() { echo DIE \"$1\"; exit 1; }\n"
                "_v6_listen_ok() { return 0; }\n"
                f"PROTO=snell6\nIPVER=4\nPORT=23456\nNODE_DIR='{nd}'\n"
                "SNELL_PSK=0123456789abcdef0123456789abcdef\nSNELL_MODE=unshaped\n"
                + cfg_body
            )
            res = run_sh(script_dual)
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            txt = (nd / "config.conf").read_text()
            self.assertIn("[snell-server]", txt)
            self.assertIn("listen = 0.0.0.0:23456,[::]:23456", txt)
            self.assertIn("mode = unshaped", txt)
            self.assertIn("dns-ip-preference = default", txt)
            self.assertNotIn("obfs", txt)

            # IPv4-only + _fix_existing_snell_ipv6 升级为双栈
            script_v4 = script_dual.replace("_v6_listen_ok() { return 0; }", "_v6_listen_ok() { return 1; }")
            res4 = run_sh(script_v4)
            self.assertEqual(res4.returncode, 0, res4.stdout + res4.stderr)
            txt4 = (nd / "config.conf").read_text()
            self.assertIn("listen = 0.0.0.0:23456\n", txt4)
            self.assertIn("dns-ip-preference = ipv4-only", txt4)

            (nd / "core").write_text("snell-v6\n")
            (nd / "fw_info").write_text("23456 tcp 0 0 1 4\n")
            fix_fn = between("_fix_existing_snell_ipv6() {", "\n# ---------- 更新内核时用的小工具").replace(
                "/etc/xray-node/nodes", str(root)
            )
            fix_script = (
                "info() { echo INFO \"$1\"; }\nwarn() { echo WARN \"$1\"; }\n"
                "_v6_listen_ok() { return 0; }\n"
                "_svc_restart() { :; }\nwait_for_port() { return 0; }\n"
                "CALL=0\n_port_on_v6() { CALL=$((CALL + 1)); [ \"$CALL\" -gt 1 ]; }\n"
                "_fw_allow() { _IPT_ADDED=0; }\n_save_fw() { :; }\n"
                + fix_fn + "\n_fix_existing_snell_ipv6\n"
            )
            res_fix = run_sh(fix_script)
            self.assertEqual(res_fix.returncode, 0, res_fix.stdout + res_fix.stderr)
            txt_up = (nd / "config.conf").read_text()
            self.assertIn("listen = 0.0.0.0:23456,[::]:23456", txt_up)
            self.assertIn("dns-ip-preference = default", txt_up)


class ComprehensiveAuditFixesTest(unittest.TestCase):
    def test_device_limit_excludes_expanded_ipv6_self_outbound(self):
        """nf_conntrack 写展开的 8 段 IPv6，ip addr 写压缩 IPv6，仍必须认出是本机出站。"""
        limit_script = heredoc("<<'LIMITEOF' || return 1\n", "\nLIMITEOF\n")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bindir = root / "bin"
            bindir.mkdir()
            (bindir / "xray-node-limit").write_text(limit_script)
            (bindir / "xray-node-limit").chmod(0o700)
            (bindir / "nft").write_text("#!/bin/sh\nexit 0\n")
            (bindir / "nft").chmod(0o755)
            (bindir / "ip").write_text(
                "#!/bin/sh\n"
                "echo '2: eth0    inet6 2001:db8::1/64 scope global'\n"
            )
            (bindir / "ip").chmod(0o755)
            nodes = root / "nodes"
            (nodes / "1").mkdir(parents=True)
            (nodes / "1" / "core").write_text("hysteria\n")
            (nodes / "1" / "fw_info").write_text("443 udp 0 0 1 6\n")
            (nodes / "1" / "limit").write_text("1\n")
            proc = root / "proc"
            proc.mkdir()
            (proc / "nf_conntrack").write_text(
                # 真客户端（压缩/展开混合）
                "ipv6     10 udp      17 100 src=2001:0db8:00aa:00bb:0000:0000:0000:0002 dst=2001:0db8:0000:0000:0000:0000:0000:0001 sport=12345 dport=443 "
                "src=2001:0db8:0000:0000:0000:0000:0000:0001 dst=2001:0db8:00aa:00bb:0000:0000:0000:0002 sport=443 dport=12345 [ASSURED] mark=0 use=2\n"
                # 服务器自己连外部 QUIC UDP 443：nf_conntrack 用 8 段展开写法
                "ipv6     10 udp      17 120 src=2001:0db8:0000:0000:0000:0000:0000:0001 dst=2606:4700:4700:0000:0000:0000:0000:1111 sport=51234 dport=443 "
                "src=2606:4700:4700:0000:0000:0000:0000:1111 dst=2001:0db8:0000:0000:0000:0000:0000:0001 sport=443 dport=51234 [ASSURED] mark=0 use=2\n"
            )
            state = root / "state"
            env = {
                "PATH": f"{bindir}:/usr/bin:/bin",
                "XRAY_NODE_DIR": str(nodes),
                "XRAY_BIN_DIR": str(bindir),
                "XRAY_LIMIT_STATE": str(state),
                "XRAY_LIMIT_PROC": str(proc),
                "XRAY_LIMIT_LOG": str(root / "limit.log"),
                "XRAY_LIMIT_CONFIRM": "0",
            }
            res = run_sh(f'sh "{bindir}/xray-node-limit" tick', env=env)
            self.assertEqual(res.returncode, 0, res.stderr)
            online = [l.split()[0] for l in (state / "1.on").read_text().splitlines()]
            banned = (state / "1.ban").read_text().strip()
            self.assertEqual(online, ["2001:db8:aa:bb::/64"])
            self.assertEqual(banned, "")

    def test_resolv_restore_preserves_644_under_umask_077(self):
        fn = between("_resolv_restore() {", "\n_dfb_undo() {")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "resolv.conf"
            bak = root / "resolv.bak"
            bak.write_text("nameserver 9.9.9.9\n")
            patched = fn.replace("/etc/resolv.conf", str(target))
            res = run_sh(f'umask 077\n{patched}\n_resolv_restore "{bak}"\n')
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o644)
            self.assertEqual(target.read_text(), "nameserver 9.9.9.9\n")

    def test_acmesh_deploy_does_not_leave_world_readable_key(self):
        watch = heredoc("<<'WATCHEOF' || return 1\n", "\nWATCHEOF\n")
        deploy = watch[watch.index("_acmesh_deploy() {"):watch.index("\n_acmesh_renew() {")]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            acme = root / "acme"
            (acme / "ex.com_ecc").mkdir(parents=True)
            (acme / "ex.com_ecc" / "fullchain.cer").write_text("CERT\n")
            (acme / "ex.com_ecc" / "ex.com.key").write_text("SECRET\n")
            nd = root / "node"
            nd.mkdir()
            # 模拟默认 umask 022 且机器上没有 xray-node 组（chgrp 失败）
            res = run_sh(
                f'umask 022\nACMESH_HOME="{acme}"\nchgrp() {{ return 1; }}\n{deploy}\n_acmesh_deploy "{nd}" ex.com\n'
            )
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(stat.S_IMODE((nd / "key.pem").stat().st_mode), 0o600)

    def test_hy_hop_busy_falls_back_to_netstat_without_ss(self):
        fn = between("_hy_hop_busy() {", "\n_hy_collect_hop_ports() {")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bindir = root / "bin"
            bindir.mkdir()
            (bindir / "netstat").write_text(
                "#!/bin/sh\n"
                "echo 'Active Internet connections (only servers)'\n"
                "echo 'Proto Recv-Q Send-Q Local Address Foreign Address State'\n"
                "echo 'udp        0      0 0.0.0.0:20005 0.0.0.0:*'\n"
            )
            (bindir / "netstat").chmod(0o755)
            # 用仅含 netstat + 常见工具的 PATH，屏蔽可能存在的 ss
            for tool in ("awk", "sh"):
                for d in ("/usr/bin", "/bin"):
                    p = Path(d) / tool
                    if p.exists() and not (bindir / tool).exists():
                        (bindir / tool).symlink_to(p)
            res = run_sh(
                "port_in_use() { return 1; }\n" + fn + "\n_hy_hop_busy 20000 20010\n",
                env={"PATH": str(bindir)},
            )
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(res.stdout.strip(), "20005")

    def test_dual_stack_fw_families_covers_xray_singbox_and_snell(self):
        fw_block = between("# ---------- 12. 放行端口 ----------", "# ---------- 13. 生成节点链接 ----------")
        self.assertIn('xray)', fw_block)
        self.assertIn('sing-box)', fw_block)
        self.assertIn('snell-v5|snell-v6)', fw_block)
        self.assertIn('if [ "$_fw_dual" = "1" ]; then', fw_block)
        self.assertIn('TCP 和 UDP', fw_block)

    def test_save_fw_uses_light_restore_on_non_debian_systemd(self):
        body = between("_save_fw() {", "\n# _fw_allow ")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bindir = root / "bin"
            bindir.mkdir()
            for tool in ("systemctl",):
                p = bindir / tool
                p.write_text("#!/bin/sh\nexit 0\n")
                p.chmod(0o755)
            for tool in ("sh",):
                for d in ("/bin", "/usr/bin"):
                    if (Path(d) / tool).exists():
                        (bindir / tool).symlink_to(Path(d) / tool)
                        break
            sd_run = root / "sd_run"
            sd_run.mkdir()
            patched = body.replace("/run/systemd/system", str(sd_run)).replace("/etc/alpine-release", str(root / "no-alpine"))
            res = run_sh(
                "LOW_MEM=0\nwarn() { echo WARN \"$1\"; }\ninfo() { echo INFO \"$1\"; }\n"
                "_save_fw_light() { echo LIGHT_USED; return 0; }\n"
                + patched + "\n_save_fw 4\n",
                env={"PATH": str(bindir)},
            )
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertIn("LIGHT_USED", res.stdout)
            self.assertNotIn("WARN", res.stdout)

    def test_systemd_units_and_overcommit_chmod_644_and_no_sed_i(self):
        self.assertNotIn("sed -i ", SOURCE)
        self.assertIn("chmod 644 /etc/sysctl.d/99-xray-node-overcommit.conf", SOURCE)
        self.assertIn('chmod 644 "$_si_tpl"', SOURCE)
        self.assertIn("chmod 644 /etc/systemd/system/xray-node-fw.service", SOURCE)
        self.assertIn('chmod 644 "$SD_DIR/xray-node-limit.service"', SOURCE)
        self.assertIn('/etc/xray-node/nodes/*/config.yaml', SOURCE)
        self.assertIn('/etc/xray-node/nodes/*/config.conf', SOURCE)
        drop_block = between("_drop_partial_node() {", "\n_reap_partial_nodes() {")
        self.assertIn("install_watch_bin", drop_block)


if __name__ == "__main__":
    unittest.main()
