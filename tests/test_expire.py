"""Timed nodes are a separate menu and are deleted completely when due."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


def source_text():
    return INSTALLER.read_text()


def between(start, end):
    source = source_text()
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


class MenuSplitTest(unittest.TestCase):
    def test_kind_menu_is_separate_from_the_original_questions(self):
        source = source_text()
        self.assertIn("1) 永久节点（一直有效）", source)
        self.assertIn("2) 定时节点（到时间后彻底失效）", source)
        self.assertIn("3) 关闭 IPv6（这台服务器以后只通过 IPv4 访问网站和 App，效果和没有 IPv6 一样。重启后也保持关闭）", source)
        self.assertIn("4) 开启 IPv6（恢复使用。服务商没分配地址的话，打开后仍然没有 IPv6）", source)
        self.assertIn("5) 关闭或开启 IPv6（不添加节点。关掉后，这台服务器只通过 IPv4 访问网站和 App）", source)
        self.assertIn("7) 1 周（7 天）", source)
        self.assertIn("2) 添加节点（下一步再选永久节点或定时节点，旧节点不受影响）", source)
        self.assertIn("3) 节点管理（查看所有节点、删除某个节点）", source)
        self.assertIn("4) 取消，什么都不做", source)
        self.assertIn("[1/4] 节点里填你服务器的哪个公网地址？", source)
        self.assertIn("[2/4] 选一个协议", source)
        self.assertIn("[3/4] 节点用哪个端口？", source)
        self.assertIn("[4/4] REALITY 伪装成哪个网站？", source)
        protocol = between("[2/4] 选一个协议", "[3/4] 节点用哪个端口？")
        self.assertNotIn("定时节点", protocol)
        self.assertNotIn("1 小时", protocol)
        self.assertIn('_si_tpl_exec="/usr/local/bin/xray-node-run %i"', source)

    def test_duration_choices_and_menus(self):
        body = between("_set_expire_choice() {", "\ninstall_expire_bins() {")
        ask = between("ask() {", "\nrand_hex() {")
        helpers = (
            "info() { printf 'INFO %s\\n' \"$1\"; }\n"
            "warn() { printf 'WARN %s\\n' \"$1\"; }\n"
            + ask
            + "\n"
            + body
        )

        def run(stdin):
            result = subprocess.run(
                ["sh", "-c", helpers + "\n_choose_node_kind\nprintf 'RESULT %s %s\\n' \"$EXPIRE_AFTER\" \"$EXPIRE_LABEL\""],
                input=stdin,
                text=True,
                capture_output=True,
                timeout=10,
                check=True,
            )
            self.assertEqual(result.stderr, "", result.stderr)
            return result.stdout

        self.assertIn("RESULT 0 ", run("\n"))
        self.assertIn("永久节点", run("1\n"))
        self.assertIn("WARN 没有这个选项，按永久节点安装", run("9\n"))
        week = run("2\n7\n")
        self.assertIn("RESULT 604800 1 周", week)
        self.assertIn("定时节点", week)
        self.assertIn("RESULT 3600 1 小时", run("2\n1\n"))
        self.assertIn("RESULT 86400 24 小时", run("2\n\n"))
        self.assertIn("WARN 没有这个选项，按 24 小时算", run("2\n8\n"))

        lone = subprocess.run(
            ["sh", "-c", helpers + "\n_set_expire_choice 3 && printf '%s\\n' \"$EXPIRE_AFTER\"\n_set_expire_choice 0"],
            text=True,
            capture_output=True,
            timeout=10,
        )
        self.assertNotEqual(lone.returncode, 0)
        self.assertEqual(lone.stdout.strip(), "21600")


class IPv6SwitchTest(unittest.TestCase):
    def script(self, extra=""):
        body = between("_set_expire_choice() {", "\ninstall_expire_bins() {")
        ask = between("ask() {", "\nrand_hex() {")
        return (
            "info() { printf 'INFO %s\\n' \"$1\"; }\n"
            "warn() { printf 'WARN %s\\n' \"$1\"; }\n"
            + ask
            + "\n"
            + body
            + "\n"
            + extra
        )

    def env_for(self, root):
        proc = Path(root) / "proc"
        for name in ("all", "default", "lo", "eth0"):
            directory = proc / name
            directory.mkdir(parents=True)
            (directory / "disable_ipv6").write_text("0\n")
        systemd = Path(root) / "systemd"
        run = Path(root) / "run"
        systemd.mkdir()
        run.mkdir()
        nodes = Path(root) / "nodes"
        nodes.mkdir()
        bindir = Path(root) / "bin"
        bindir.mkdir()
        systemctl = bindir / "systemctl"
        systemctl.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$SYSTEMCTL_LOG\"\nexit 0\n"
        )
        systemctl.chmod(0o755)
        env = os.environ.copy()
        env.update(
            {
                "XRAY_IPV6_CONF": str(Path(root) / "sysctl.d" / "99-xray-node-ipv6.conf"),
                "XRAY_IPV6_PROC": str(proc),
                "XRAY_SYSCTL_CONF": str(Path(root) / "sysctl.conf"),
                "XRAY_GAI_CONF": str(Path(root) / "gai.conf"),
                "XRAY_NODES_DIR": str(nodes),
                "XRAY_SYSTEMD_DIR": str(systemd),
                "XRAY_SYSTEMD_RUN": str(run),
                "XRAY_IPV6_HAS_V4": "1",
                "SYSTEMCTL_LOG": str(Path(root) / "systemctl.log"),
                "PATH": str(bindir) + os.pathsep + env.get("PATH", ""),
            }
        )
        return env, proc, nodes

    def test_kind_menu_disables_ipv6_then_installs_a_permanent_node(self):
        with tempfile.TemporaryDirectory() as root:
            env, proc, _nodes = self.env_for(root)
            result = subprocess.run(
                ["sh", "-c", self.script("_choose_node_kind\nprintf 'RESULT %s\\n' \"$NODE_KIND\"\n")],
                input="3\n1\n",
                text=True,
                capture_output=True,
                timeout=10,
                check=True,
                env=env,
            )
            self.assertEqual(result.stderr, "", result.stderr)
            self.assertIn("RESULT permanent", result.stdout)
            self.assertIn("IPv6 已关闭", result.stdout)
            self.assertEqual((proc / "all" / "disable_ipv6").read_text().strip(), "1")
            self.assertEqual((proc / "eth0" / "disable_ipv6").read_text().strip(), "1")
            conf = Path(env["XRAY_IPV6_CONF"]).read_text()
            self.assertIn("net.ipv6.conf.all.disable_ipv6 = 1", conf)
            sysctl = Path(env["XRAY_SYSCTL_CONF"]).read_text()
            self.assertEqual(sysctl.count("# xray-node-ipv6 begin"), 1)
            self.assertIn("precedence ::ffff:0:0/96  100  # xray-node-ipv6", Path(env["XRAY_GAI_CONF"]).read_text())
            unit = Path(root) / "systemd" / "xray-node-ipv6.service"
            self.assertIn("disable_ipv6", unit.read_text())
            self.assertIn("enable xray-node-ipv6.service", Path(env["SYSTEMCTL_LOG"]).read_text())

    def test_enabling_ipv6_removes_the_persistent_switch(self):
        with tempfile.TemporaryDirectory() as root:
            env, proc, _nodes = self.env_for(root)
            subprocess.run(
                ["sh", "-c", self.script("_choose_node_kind\n")],
                input="3\n4\n5\n",
                text=True,
                capture_output=True,
                timeout=10,
                check=True,
                env=env,
            )
            self.assertEqual((proc / "all" / "disable_ipv6").read_text().strip(), "0")
            self.assertFalse(Path(env["XRAY_IPV6_CONF"]).exists())
            self.assertFalse((Path(root) / "systemd" / "xray-node-ipv6.service").exists())
            self.assertNotIn("xray-node-ipv6", Path(env["XRAY_SYSCTL_CONF"]).read_text())
            self.assertNotIn("xray-node-ipv6", Path(env["XRAY_GAI_CONF"]).read_text())

    def test_ipv6_ssh_and_ipv6_only_host_need_a_yes(self):
        with tempfile.TemporaryDirectory() as root:
            env, proc, _nodes = self.env_for(root)
            env["SSH_CONNECTION"] = "2001:db8::10 50000 2001:db8::20 22"
            refused = subprocess.run(
                ["sh", "-c", self.script("_choose_node_kind\nprintf 'RESULT %s\\n' \"$NODE_KIND\"\n")],
                input="3\nn\n1\n",
                text=True,
                capture_output=True,
                timeout=10,
                check=True,
                env=env,
            )
            self.assertIn("保持 IPv6 可用", refused.stdout)
            self.assertEqual((proc / "all" / "disable_ipv6").read_text().strip(), "0")
            self.assertIn("RESULT permanent", refused.stdout)

            env["XRAY_IPV6_HAS_V4"] = "0"
            env.pop("SSH_CONNECTION")
            only = subprocess.run(
                ["sh", "-c", self.script("_choose_node_kind\nprintf 'DONE\\n'\n")],
                input="3\nn\n5\n",
                text=True,
                capture_output=True,
                timeout=10,
                check=True,
                env=env,
            )
            self.assertIn("没有 IPv4", only.stdout)
            self.assertIn("已退出，没有安装节点", only.stdout)
            self.assertNotIn("DONE", only.stdout)
            self.assertEqual((proc / "all" / "disable_ipv6").read_text().strip(), "0")

    def test_disabling_ipv6_rebinds_dual_stack_listeners_to_ipv4(self):
        with tempfile.TemporaryDirectory() as root:
            env, _proc, nodes = self.env_for(root)
            hy = nodes / "3"
            hy.mkdir()
            (hy / "config.yaml").write_text('listen: ":444"\n')
            (hy / "fw_info").write_text("444 udp 0 0 0 4\n")
            (hy / "node.txt").write_text(
                "hysteria2://pass@1.2.3.4:444/?insecure=1#xray-node\n"
                "IPv6 链接（同一个节点）:\n"
                "hysteria2://pass@[2001:db8::1]:444/?insecure=1#xray-node\n"
                "IPv6 地址: 2001:db8::1\n"
                "Hysteria2 = Hysteria2,1.2.3.4,444,pw\n"
                "Hysteria2 = Hysteria2,2001:db8::1,444,pw\n"
            )
            xray = nodes / "4"
            xray.mkdir()
            (xray / "config.json").write_text('{ "listen": "::" }\n')
            (xray / "fw_info").write_text("443 tcp 0 0 0 6\n")
            v6 = nodes / "5"
            v6.mkdir()
            (v6 / "config.yaml").write_text('listen: "[::]:555"\n')
            log = Path(root) / "restart.log"
            env["RESTART_LOG"] = str(log)
            extra = (
                "_hy_set_listen() { printf 'listen: \"%s\"\\n' \"$2\" > \"$1\"; }\n"
                "_svc_restart() { printf '%s\\n' \"$1\" >> \"$RESTART_LOG\"; }\n"
                "wait_for_port() { return 0; }\n"
                "_ipv6_turn_off\n"
            )
            result = subprocess.run(
                ["sh", "-c", self.script(extra)],
                input="",
                text=True,
                capture_output=True,
                timeout=10,
                check=True,
                env=env,
            )
            self.assertEqual(result.stderr, "", result.stderr)
            self.assertEqual((hy / "config.yaml").read_text(), 'listen: "0.0.0.0:444"\n')
            self.assertFalse((hy / "config.yaml.bak-ipv6off").exists())
            self.assertIn('"listen": "0.0.0.0"', (xray / "config.json").read_text())
            self.assertEqual((v6 / "config.yaml").read_text(), 'listen: "0.0.0.0:555"\n')
            self.assertEqual(log.read_text().splitlines(), ["3", "4", "5"])
            self.assertIn("节点 3 已改为只听 IPv4", result.stdout)
            kept = (hy / "node.txt").read_text()
            self.assertIn("hysteria2://pass@1.2.3.4:444/", kept)
            self.assertIn("Hysteria2 = Hysteria2,1.2.3.4,444,pw", kept)
            self.assertNotIn("2001:db8::1", kept)
            self.assertNotIn("IPv6 链接", kept)

    def test_readme_bootstrap_is_valid_shell(self):
        readme = (INSTALLER.parent / "README.md").read_text()
        start = readme.index("sh <<'EOF'\n") + len("sh <<'EOF'\n")
        body = readme[start:readme.index("\nEOF\n", start)]
        subprocess.run(["sh", "-n"], input=body, text=True, check=True)


class ExpireScriptTest(unittest.TestCase):
    def generate(self, root):
        functions = between("_set_expire_choice() {", "\nwrite_helper_cmds() {")
        bins = root / "bin"
        env = os.environ.copy()
        env["XRAY_BIN_DIR"] = str(bins)
        subprocess.run(
            ["sh", "-c", "warn() { :; }\ninfo() { :; }\n" + functions + "\ninstall_expire_bins"],
            env=env,
            check=True,
            timeout=10,
        )
        for name in ("xray-node-expire", "xray-node-run", "xray-node-expire-loop"):
            subprocess.run(["sh", "-n", str(bins / name)], check=True)
        return bins

    def mocks(self, root):
        mock = root / "mock"
        mock.mkdir()
        (mock / "systemctl").write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$SYSTEMCTL_LOG\"\n"
            "case \"$1\" in is-enabled) exit 1 ;; esac\nexit 0\n"
        )
        (mock / "iptables").write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$IPTABLES_LOG\"\nexit 0\n"
        )
        (mock / "pkill").write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$PKILL_LOG\"\nexit 0\n"
        )
        (mock / "sleep").write_text("#!/bin/sh\nexit 0\n")
        (mock / "nohup").write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$NOHUP_LOG\"\nexit 0\n"
        )
        for item in mock.iterdir():
            item.chmod(0o755)
        return mock

    def env_for(self, root, nodes, mock):
        env = os.environ.copy()
        env.update({
            "PATH": f"{mock}:/bin:/usr/bin",
            "XRAY_NODE_DIR": str(nodes),
            "XRAY_EXPIRE_LOG": str(root / "expire.log"),
            "XRAY_EXPIRE_LOCK": str(root / "xray-node-expire.lock"),
            "XRAY_SYSTEMD_RUN": str(root / "run"),
            "XRAY_SYSTEMD_DIR": str(root / "systemd"),
            "XRAY_SYSTEMD_WANTS": str(root / "wants"),
            "XRAY_INITD": str(root / "init.d"),
            "XRAY_RUNLEVEL": str(root / "runlevel"),
            "XRAY_CRON_DIR": str(root / "cron"),
            "SYSTEMCTL_LOG": str(root / "systemctl.log"),
            "IPTABLES_LOG": str(root / "iptables.log"),
            "PKILL_LOG": str(root / "pkill.log"),
            "NOHUP_LOG": str(root / "nohup.log"),
        })
        (root / "run").mkdir()
        (root / "systemd").mkdir()
        (root / "wants").mkdir()
        (root / "init.d").mkdir()
        (root / "runlevel").mkdir()
        return env

    def test_sweep_deletes_only_due_nodes_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bins = self.generate(root)
            mock = self.mocks(root)
            nodes = root / "nodes"
            now = 1_700_000_000
            specs = {
                "1": ("xray", None, "1111 tcp 0 0 1 4\n", "keep-permanent"),
                "2": ("hysteria", str(now - 10), "2222 udp 0 0 1 4\n", "due"),
                "3": ("xray", str(now + 100000), "3333 tcp 0 0 1 4\n", "keep-future"),
                "4": ("sing-box", "soon", "4444 tcp 0 0 1 4\n", "keep-garbage"),
            }
            for node_id, (core, expire, fw, marker) in specs.items():
                directory = nodes / node_id
                directory.mkdir(parents=True)
                (directory / "core").write_text(core + "\n")
                (directory / "node.txt").write_text(marker + "\n")
                (directory / "fw_info").write_text(fw)
                (directory / "config.json").write_text("{}\n")
                (directory / "config.yaml").write_text("listen: 1\n")
                if expire is not None:
                    (directory / "expire").write_text(expire + "\n")
            odd = nodes / "notanid"
            odd.mkdir()
            (odd / "expire").write_text(str(now - 10) + "\n")
            (odd / "node.txt").write_text("odd\n")
            env = self.env_for(root, nodes, mock)
            env["PATH"] = f"{mock}:/bin:/usr/bin"

            date_wrap = root / "date-bin"
            date_wrap.mkdir()
            (date_wrap / "date").write_text(
                "#!/bin/sh\n"
                "if [ \"$1\" = \"+%s\" ]; then printf '%s\\n' '1700000000'; exit 0; fi\n"
                "exec /bin/date \"$@\"\n"
            )
            (date_wrap / "date").chmod(0o755)
            env["PATH"] = f"{date_wrap}:{mock}:/bin:/usr/bin"

            for _ in range(2):
                subprocess.run([str(bins / "xray-node-expire")], env=env, check=True, timeout=10)

            self.assertTrue((nodes / "1" / "node.txt").exists())
            self.assertFalse((nodes / "2").exists())
            self.assertEqual((nodes / "3" / "node.txt").read_text(), "keep-future\n")
            self.assertEqual((nodes / "4" / "node.txt").read_text(), "keep-garbage\n")
            self.assertEqual((odd / "node.txt").read_text(), "odd\n")
            self.assertIn("节点 2 已到时间", (root / "expire.log").read_text())
            logged = (root / "systemctl.log").read_text().splitlines()
            self.assertIn("stop hysteria-node@2", logged)
            self.assertIn("disable hysteria-node@2", logged)
            self.assertNotIn("stop xray-node@1", logged)
            self.assertNotIn("stop xray-node@3", logged)
            self.assertNotIn("stop singbox-node@4", logged)
            iptables = (root / "iptables.log").read_text()
            self.assertIn("--dport 2222", iptables)
            self.assertNotIn("--dport 1111", iptables)
            self.assertNotIn("--dport 3333", iptables)
            self.assertIn("config.yaml", (root / "pkill.log").read_text())

            kept = subprocess.run(
                [str(bins / "xray-node-expire"), "--delete", "3"],
                env=env,
                check=True,
                timeout=10,
            )
            self.assertEqual(kept.returncode, 0)
            self.assertTrue((nodes / "3").exists())
            outside = root / "outside"
            outside.mkdir()
            (outside / "node.txt").write_text("safe\n")
            subprocess.run(
                [str(bins / "xray-node-expire"), "--delete", "../outside"],
                env=env,
                check=True,
                timeout=10,
            )
            self.assertEqual((outside / "node.txt").read_text(), "safe\n")

    def test_held_lock_waits_and_stale_lock_is_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bins = self.generate(root)
            mock = self.mocks(root)
            nodes = root / "nodes" / "8"
            nodes.mkdir(parents=True)
            (nodes / "core").write_text("xray\n")
            (nodes / "expire").write_text("1\n")
            (nodes / "node.txt").write_text("due\n")
            env = self.env_for(root, nodes.parent, mock)
            lock = root / "xray-node-expire.lock"
            lock.mkdir()
            held = subprocess.run(
                [str(bins / "xray-node-expire")],
                env=env,
                check=True,
                timeout=10,
            )
            self.assertEqual(held.returncode, 0)
            self.assertTrue((nodes / "node.txt").exists())
            os.utime(lock, (1_000_000_000, 1_000_000_000))
            subprocess.run([str(bins / "xray-node-expire")], env=env, check=True, timeout=10)
            self.assertFalse(nodes.exists())

    def test_last_due_node_removes_the_watch(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bins = self.generate(root)
            mock = self.mocks(root)
            nodes = root / "nodes" / "6"
            nodes.mkdir(parents=True)
            (nodes / "core").write_text("xray\n")
            (nodes / "expire").write_text("1\n")
            env = self.env_for(root, nodes.parent, mock)
            timer = root / "systemd" / "xray-node-expire.timer"
            timer.write_text("old\n")
            (root / "cron").mkdir()
            (root / "cron" / "xray-node-expire").write_text("old\n")
            subprocess.run([str(bins / "xray-node-expire")], env=env, check=True, timeout=10)
            self.assertFalse(nodes.exists())
            self.assertFalse(timer.exists())
            self.assertFalse((root / "cron" / "xray-node-expire").exists())
            self.assertIn("disable --now xray-node-expire.timer", (root / "systemctl.log").read_text())

    def test_wrapper_refuses_due_node_and_starts_the_others(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bins = self.generate(root)
            mock = self.mocks(root)
            xray = mock / "xray"
            xray.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$MOCK_LOG\"\nexit 0\n")
            xray.chmod(0o755)
            hysteria = mock / "hysteria"
            hysteria.write_text(xray.read_text())
            hysteria.chmod(0o755)
            nodes = root / "nodes"
            due = nodes / "2"
            future = nodes / "3"
            permanent = nodes / "4"
            hy = nodes / "5"
            for directory in (due, future, permanent, hy):
                directory.mkdir(parents=True)
                (directory / "config.json").write_text("{}\n")
                (directory / "config.yaml").write_text("listen: 1\n")
            (due / "core").write_text("xray\n")
            (due / "expire").write_text("1\n")
            (due / "fw_info").write_text("2222 tcp 0 0 1 4\n")
            (future / "core").write_text("xray\n")
            (future / "expire").write_text("4102444800\n")
            (permanent / "core").write_text("xray\n")
            (hy / "core").write_text("hysteria\n")
            (hy / "expire").write_text("4102444800\n")
            wants = root / "wants" / "xray-node@2.service"
            env = self.env_for(root, nodes, mock)
            wants.write_text("enabled\n")
            (root / "init.d" / "xray-node-2").write_text("init\n")
            env["MOCK_LOG"] = str(root / "mock.log")
            env["XRAY_BIN_PATH"] = str(xray)
            env["HY_BIN_PATH"] = str(hysteria)
            env["SYSTEMCTL_LOG"] = str(root / "systemctl.log")

            subprocess.run([str(bins / "xray-node-run"), "2"], env=env, check=True, timeout=10)
            self.assertFalse(due.exists())
            self.assertFalse(wants.exists())
            self.assertFalse((root / "init.d" / "xray-node-2").exists())
            self.assertFalse((root / "mock.log").exists())
            self.assertNotIn("stop ", (root / "systemctl.log").read_text() if (root / "systemctl.log").exists() else "")

            subprocess.run([str(bins / "xray-node-run"), "3"], env=env, check=True, timeout=10)
            subprocess.run([str(bins / "xray-node-run"), "4"], env=env, check=True, timeout=10)
            subprocess.run([str(bins / "xray-node-run"), "5"], env=env, check=True, timeout=10)
            started = (root / "mock.log").read_text().splitlines()
            self.assertIn(f"-config {future / 'config.json'}", started)
            self.assertIn(f"-config {permanent / 'config.json'}", started)
            self.assertIn(f"server -c {hy / 'config.yaml'}", started)
            self.assertTrue(future.exists())
            self.assertTrue(permanent.exists())


class ArmWatchTest(unittest.TestCase):
    def functions(self):
        return between("_set_expire_choice() {", "\nwrite_helper_cmds() {")

    def test_systemd_timer_tracks_expire_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bins = root / "bin"
            nodes = root / "nodes" / "1"
            nodes.mkdir(parents=True)
            run = root / "run"
            run.mkdir()
            systemd = root / "systemd"
            systemd.mkdir()
            mock = root / "mock"
            mock.mkdir()
            (mock / "systemctl").write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$SYSTEMCTL_LOG\"\n"
                "case \"$1\" in is-enabled) exit 1 ;; esac\nexit 0\n"
            )
            (mock / "systemctl").chmod(0o755)
            env = os.environ.copy()
            env.update({
                "PATH": f"{mock}:/bin:/usr/bin",
                "XRAY_BIN_DIR": str(bins),
                "XRAY_NODE_DIR": str(nodes.parent),
                "XRAY_SYSTEMD_DIR": str(systemd),
                "XRAY_SYSTEMD_RUN": str(run),
                "XRAY_CRON_DIR": str(root / "no-cron"),
                "SYSTEMCTL_LOG": str(root / "systemctl.log"),
            })
            script = "info() { printf 'INFO %s\\n' \"$1\"; }\nwarn() { printf 'WARN %s\\n' \"$1\"; }\n"
            subprocess.run(
                ["sh", "-c", script + self.functions() + "\ninstall_expire_bins\narm_expire_watch"],
                env=env,
                check=True,
                timeout=10,
            )
            self.assertFalse((systemd / "xray-node-expire.timer").exists())
            (nodes / "expire").write_text("4102444800\n")
            subprocess.run(
                ["sh", "-c", script + self.functions() + "\narm_expire_watch"],
                env=env,
                check=True,
                timeout=10,
            )
            timer = (systemd / "xray-node-expire.timer").read_text()
            self.assertIn("OnUnitActiveSec=60", timer)
            self.assertIn("AccuracySec=1s", timer)
            self.assertIn("Persistent=true", timer)
            service = (systemd / "xray-node-expire.service").read_text()
            self.assertIn(f"ExecStart={bins / 'xray-node-expire'}", service)
            self.assertIn("enable --now xray-node-expire.timer", (root / "systemctl.log").read_text())
            (nodes / "expire").unlink()
            subprocess.run(
                ["sh", "-c", script + self.functions() + "\narm_expire_watch"],
                env=env,
                check=True,
                timeout=10,
            )
            self.assertFalse((systemd / "xray-node-expire.timer").exists())

    def test_cron_and_background_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bins = root / "bin"
            nodes = root / "nodes" / "1"
            nodes.mkdir(parents=True)
            (nodes / "expire").write_text("4102444800\n")
            cron = root / "cron"
            cron.mkdir()
            mock = root / "mock"
            mock.mkdir()
            (mock / "nohup").write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$NOHUP_LOG\"\nexit 0\n")
            (mock / "nohup").chmod(0o755)
            env = os.environ.copy()
            env.update({
                "PATH": f"{mock}:/bin:/usr/bin",
                "XRAY_BIN_DIR": str(bins),
                "XRAY_NODE_DIR": str(nodes.parent),
                "XRAY_CRON_DIR": str(cron),
                "XRAY_SYSTEMD_RUN": str(root / "missing-run"),
                "XRAY_SYSTEMD_DIR": str(root / "missing-systemd"),
                "NOHUP_LOG": str(root / "nohup.log"),
            })
            script = "info() { :; }\nwarn() { printf 'WARN %s\\n' \"$1\"; }\n"
            subprocess.run(
                ["sh", "-c", script + self.functions() + "\ninstall_expire_bins\narm_expire_watch"],
                env=env,
                check=True,
                timeout=10,
                capture_output=True,
                text=True,
            )
            text = (cron / "xray-node-expire").read_text()
            self.assertIn(f"* * * * * root {bins / 'xray-node-expire'}", text)
            self.assertFalse((root / "nohup.log").exists())
            (nodes / "expire").unlink()
            subprocess.run(
                ["sh", "-c", script + self.functions() + "\narm_expire_watch"],
                env=env,
                check=True,
                timeout=10,
            )
            self.assertFalse((cron / "xray-node-expire").exists())

            (nodes / "expire").write_text("4102444800\n")
            env["XRAY_CRON_DIR"] = str(root / "no-cron")
            env["XRAY_EXPIRE_PID"] = str(root / "loop.pid")
            warned = subprocess.run(
                ["sh", "-c", script + self.functions() + "\narm_expire_watch"],
                env=env,
                check=True,
                timeout=10,
                capture_output=True,
                text=True,
            )
            self.assertIn("已在后台看着到期时间", warned.stdout)
            # 父进程退出时后台 mock 可能还没写完日志。pid 文件是同步写的，用来确认已经拉起巡检。
            pid = (root / "loop.pid").read_text().strip()
            self.assertRegex(pid, r"^[0-9]+$")
            subprocess.run(["kill", pid], check=False)


class SyntaxTest(unittest.TestCase):
    def test_installer_parses(self):
        subprocess.run(["sh", "-n", str(INSTALLER)], check=True)


if __name__ == "__main__":
    unittest.main()
