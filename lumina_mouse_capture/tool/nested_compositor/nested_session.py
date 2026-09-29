#!/usr/bin/env python3
"""A nested, isolated, headless GNOME Shell for checking pointer capture.

Nothing here touches the desktop of the person at the machine:
- gnome-shell --headless --wayland runs under bwrap with /dev/dri,
  /sys/class/drm and /run/udev hidden (software rendering, no GPU);
- on a private D-Bus (dbus-run-session), with private HOME/XDG directories,
  GSETTINGS_BACKEND=memory, and its own runtime dir;
- input comes from Mutter's RemoteDesktop API on that private bus.

Used by capture_probe checks (`python3 nested_session.py probe <capture_probe>`)
and by lumina's input smoke (test/smoke/input_smoke_test.dart), which drives
the same session from Dart through `serve` (JSON commands on stdin).
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

WAYLAND_DISPLAY = "lmc-0"
KEY_c, KEY_r, KEY_q, KEY_F4, KEY_Escape = 0x63, 0x72, 0x71, 0xFFC1, 0xFF1B
BTN_LEFT = 0x110


class NestedShell:
    """Starts and stops the nested shell; `env()` is what a client needs."""

    def __init__(self, work_dir=None, x11=False):
        self.work = work_dir or tempfile.mkdtemp(prefix="lmc_nested_")
        # The runtime dir holds the Wayland socket, whose path must stay
        # under 108 bytes: a short symlink points at it.
        self.run_dir = os.path.join(self.work, "run")
        self.runtime = tempfile.mkdtemp(prefix="lmc", dir="/tmp")
        os.rmdir(self.runtime)
        os.makedirs(self.run_dir, mode=0o700, exist_ok=True)
        os.symlink(self.run_dir, self.runtime)
        for d in ("home", "config", "data", "cache", "tmp"):
            os.makedirs(os.path.join(self.work, d), exist_ok=True)
        self.x11 = x11
        self.proc = None
        self.bus_address = None
        self.log_path = os.path.join(self.work, "shell.log")

    def start(self, timeout=30):
        bus_file = os.path.join(self.work, "bus_address")
        inner = (
            f"echo $DBUS_SESSION_BUS_ADDRESS > {bus_file}; exec gnome-shell --headless --wayland "
            f"{'' if self.x11 else '--no-x11 '}--virtual-monitor 1280x800 --wayland-display={WAYLAND_DISPLAY}"
        )
        w = self.work
        cmd = [
            "bwrap", "--dev-bind", "/", "/",
            "--tmpfs", "/dev/dri", "--tmpfs", "/sys/class/drm", "--tmpfs", "/run/udev",
            # Xwayland's filesystem sockets stay private; clients reach it
            # through the abstract socket.
            *(["--perms", "1777", "--tmpfs", "/tmp/.X11-unix"] if self.x11 else []),
            "--unshare-pid", "--die-with-parent",
            "env", "-i", "PATH=/usr/bin:/bin",
            f"HOME={w}/home", f"XDG_RUNTIME_DIR={self.runtime}",
            f"XDG_CONFIG_HOME={w}/config", f"XDG_DATA_HOME={w}/data", f"XDG_CACHE_HOME={w}/cache",
            f"TMPDIR={w}/tmp", "LIBGL_ALWAYS_SOFTWARE=1",
            "__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json",
            "GSETTINGS_BACKEND=memory",
            "dbus-run-session", "--", "bash", "-c", inner,
        ]
        self.log = open(self.log_path, "w")
        self.proc = subprocess.Popen(cmd, stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True)
        socket = os.path.join(self.runtime, WAYLAND_DISPLAY)
        deadline = time.time() + timeout
        while time.time() < deadline:
            if os.path.exists(socket) and os.path.exists(bus_file) and open(bus_file).read().strip():
                self.bus_address = open(bus_file).read().strip()
                # The shell registers RemoteDesktop shortly after the socket.
                time.sleep(1.5)
                return self
            if self.proc.poll() is not None:
                break
            time.sleep(0.2)
        raise RuntimeError(f"nested gnome-shell did not start; see {self.log_path}")

    def x11_display(self, timeout=15):
        """The nested shell's Xwayland display (`:N`), from its log."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            for line in open(self.log_path, errors="replace"):
                if "Using public X11 display" in line:
                    return line.split("Using public X11 display", 1)[1].split(",")[0].strip()
            time.sleep(0.2)
        raise RuntimeError(f"no Xwayland display in {self.log_path}")

    def env(self, extra=None):
        """The environment of a client of the nested shell (and only it)."""
        env = {
            k: v for k, v in os.environ.items()
            if k not in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "XAUTHORITY")
        }
        env.update({
            "WAYLAND_DISPLAY": WAYLAND_DISPLAY,
            "XDG_RUNTIME_DIR": self.runtime,
            "GDK_BACKEND": "wayland",
            "DBUS_SESSION_BUS_ADDRESS": self.bus_address,
            "LIBGL_ALWAYS_SOFTWARE": "1",
            "__EGL_VENDOR_LIBRARY_FILENAMES": "/usr/share/glvnd/egl_vendor.d/50_mesa.json",
            "NO_AT_BRIDGE": "1",
        })
        env.pop("LUMINA_MOUSE_CAPTURE", None)
        if extra:
            env.update(extra)
        return env

    def _shell_pids(self):
        out = subprocess.run(["pgrep", "-g", str(self.proc.pid), "-x", "gnome-shell"],
                             capture_output=True, text=True).stdout
        return [int(p) for p in out.split()]

    def stop(self):
        displays = []
        if self.x11:
            for line in open(self.log_path, errors="replace"):
                if "X11 display" in line:
                    displays += [w.strip(",()") for w in line.split() if w.strip(",()").startswith(":")]
        if self.proc and self.proc.poll() is None:
            # The shell first, so it removes its Xwayland sockets and locks;
            # then the rest of the session.
            for pid in self._shell_pids():
                os.kill(pid, signal.SIGTERM)
            deadline = time.time() + 10
            while time.time() < deadline and self._shell_pids():
                time.sleep(0.2)
            os.killpg(self.proc.pid, signal.SIGTERM)
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                os.killpg(self.proc.pid, signal.SIGKILL)
                self.proc.wait(5)
        try:
            os.unlink(self.runtime)
        except OSError:
            pass
        # A lock file of a display this shell named, if it outlived the shell.
        for d in set(displays):
            lock = f"/tmp/.X{d.lstrip(':')}-lock"
            if os.path.exists(lock) and not self._abstract_socket_listening(d):
                try:
                    os.unlink(lock)
                except OSError:
                    pass
        shutil.rmtree(self.work, ignore_errors=True)

    @staticmethod
    def _abstract_socket_listening(display):
        name = f"@/tmp/.X11-unix/X{display.lstrip(':')}"
        out = subprocess.run(["ss", "-xl"], capture_output=True, text=True).stdout
        return any(name == col for line in out.splitlines() for col in line.split())


class RemoteInput:
    """Mutter's RemoteDesktop API on the nested shell's private bus."""

    def __init__(self, bus_address):
        self.bus = Gio.DBusConnection.new_for_address_sync(
            bus_address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)
        path = self._call("/org/gnome/Mutter/RemoteDesktop", "org.gnome.Mutter.RemoteDesktop",
                          "CreateSession", None)[0]
        self.session = path
        self._call(path, "org.gnome.Mutter.RemoteDesktop.Session", "Start", None)
        # The shell's screenshot service only answers a few well-known
        # callers; on this private bus those names are free to take.
        # GNOME Shell <= 48 allows org.gnome.Screenshot; 49+ dropped it and
        # allows the GNOME portal backend (ui/screenshot.js DBusSenderChecker).
        for name in ("org.gnome.Screenshot", "org.freedesktop.impl.portal.desktop.gnome"):
            self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                               GLib.Variant("(su)", (name, 4)), None, Gio.DBusCallFlags.NONE, 5000, None)
        self._recording = None
        self._shot_lock = threading.Lock()

    def _call(self, path, iface, method, args):
        return self.bus.call_sync("org.gnome.Mutter.RemoteDesktop", path, iface, method, args,
                                  None, Gio.DBusCallFlags.NONE, 5000, None).unpack()

    def _session(self, method, args):
        self._call(self.session, "org.gnome.Mutter.RemoteDesktop.Session", method, args)

    def move(self, dx, dy):
        self._session("NotifyPointerMotionRelative", GLib.Variant("(dd)", (float(dx), float(dy))))

    def button(self, pressed, button=BTN_LEFT):
        self._session("NotifyPointerButton", GLib.Variant("(ib)", (button, pressed)))

    def click(self):
        self.button(True)
        time.sleep(0.05)
        self.button(False)

    def key(self, keysym):
        self._session("NotifyKeyboardKeysym", GLib.Variant("(ub)", (keysym, True)))
        time.sleep(0.03)
        self._session("NotifyKeyboardKeysym", GLib.Variant("(ub)", (keysym, False)))

    def screenshot(self, path, cursor=True):
        """The nested screen, cursor included, as a PNG."""
        # One screenshot at a time: the recorder thread and a `shot` command
        # share this bus connection, and GNOME Shell 49+ refuses a second
        # call from the same sender while one runs ("There is an ongoing
        # operation for this sender").
        with self._shot_lock:
            self.bus.call_sync("org.gnome.Shell.Screenshot", "/org/gnome/Shell/Screenshot", "org.gnome.Shell.Screenshot",
                               "Screenshot", GLib.Variant("(bbs)", (cursor, False, path)), None,
                               Gio.DBusCallFlags.NONE, 5000, None)

    def start_recording(self, directory, fps=30):
        """Screenshots at [fps] into [directory] until stop_recording()."""
        os.makedirs(directory, exist_ok=True)
        state = {"stop": False, "frames": []}

        def run():
            interval = 1.0 / fps
            nxt = time.time()
            while not state["stop"]:
                path = os.path.join(directory, f"frame_{len(state['frames']):05d}.png")
                t = time.time()
                try:
                    self.screenshot(path)
                    state["frames"].append({"path": path, "t": t})
                except GLib.Error:
                    pass
                nxt += interval
                delay = nxt - time.time()
                if delay > 0:
                    time.sleep(delay)
                else:
                    nxt = time.time()

        state["thread"] = threading.Thread(target=run, daemon=True)
        state["thread"].start()
        self._recording = state

    def stop_recording(self):
        state = self._recording
        if not state:
            return []
        state["stop"] = True
        state["thread"].join(10)
        self._recording = None
        return state["frames"]

    def stop(self):
        self.stop_recording()
        try:
            self._session("Stop", None)
        except GLib.Error:
            pass


class JsonLines:
    """Collects a client's JSON stdout lines."""

    def __init__(self, proc):
        self.events = []
        self.lock = threading.Lock()
        self.proc = proc
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for raw in self.proc.stdout:
            line = raw.decode(errors="replace").strip()
            if not line.startswith("{"):
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            ev["t"] = time.time()
            with self.lock:
                self.events.append(ev)

    def since(self, index, kind=None):
        with self.lock:
            return [e for e in self.events[index:] if kind is None or e.get("ev") == kind]

    def mark(self):
        with self.lock:
            return len(self.events)

    def wait(self, kind, since=0, timeout=10.0, predicate=None):
        deadline = time.time() + timeout
        while time.time() < deadline:
            for e in self.since(since, kind):
                if predicate is None or predicate(e):
                    return e
            time.sleep(0.05)
        raise AssertionError(f"no {kind} event within {timeout}s; got {self.since(since)[-8:]}")


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"  ok: {message}", flush=True)


def probe(binary):
    """Drives capture_probe through lock, relative motion, release and loss."""
    shell = NestedShell()
    app = decoy = None
    try:
        shell.start()
        app = subprocess.Popen([binary], env=shell.env(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        out = JsonLines(app)
        remote = RemoteInput(shell.bus_address)
        support = out.wait("support", timeout=20)
        # GNOME opens the Activities overview at start-up; Esc closes it.
        remote.key(KEY_Escape)
        time.sleep(1.0)
        check(support["kind"] == "wayland" and support["lock"] and support["relative"],
              f"the nested compositor offers a Wayland lock with relative motion: {support}")

        # Bring the pointer onto the window.
        for _ in range(60):
            if out.since(0, "pointer"):
                break
            remote.move(15, 10)
            time.sleep(0.05)
        check(bool(out.since(0, "pointer")), f"the pointer is over the probe window; events: {out.since(0)[-6:]}")

        m = out.mark()
        remote.key(KEY_c)
        out.wait("capture", since=m, predicate=lambda e: e["ok"])
        out.wait("locked", since=m)
        check(True, "c captured and the compositor locked the pointer")

        m = out.mark()
        for _ in range(20):
            remote.move(10, 0)
            time.sleep(0.02)
        remote.move(0, -5)
        time.sleep(0.5)
        motion = out.since(m, "motion")
        pointer = out.since(m, "pointer")
        sum_dx = sum(e["dx"] for e in motion)
        sum_dy = sum(e["dy"] for e in motion)
        check(abs(sum_dx - 200) <= 1 and abs(sum_dy + 5) <= 1,
              f"relative moves arrive as deltas: {sum_dx:.1f}, {sum_dy:.1f} (expected 200, -5)")
        check(not pointer, f"a locked pointer does not move ({len(pointer)} pointer events)")

        # Far past every edge of the 1280x800 screen: still deltas.
        m = out.mark()
        for _ in range(100):
            remote.move(40, -30)
        time.sleep(0.6)
        sum_dx = sum(e["dx"] for e in out.since(m, "motion"))
        sum_dy = sum(e["dy"] for e in out.since(m, "motion"))
        check(abs(sum_dx - 4000) <= 2 and abs(sum_dy + 3000) <= 2,
              f"4000 px right and 3000 px up (past the screen edges) still arrive: {sum_dx:.0f}, {sum_dy:.0f}")

        m = out.mark()
        remote.key(KEY_r)
        out.wait("release", since=m)
        time.sleep(0.3)
        for _ in range(5):
            remote.move(4, 0)
            time.sleep(0.05)
        time.sleep(0.4)
        after = out.since(m, "pointer")
        check(bool(after) and not out.since(m, "motion"),
              f"released: the pointer moves again and no deltas arrive ({len(after)} pointer events)")
        first = after[0]
        check(abs(first["x"] - 500) < 40 and abs(first["y"] - 350) < 40,
              f"the pointer reappears at the capture centre (hint): {first['x']:.0f},{first['y']:.0f} ~ 500,350")

        m = out.mark()
        remote.click()
        out.wait("locked", since=m)
        check(True, "a click captures again and the lock activates")

        m = out.mark()
        decoy = subprocess.Popen([binary, "--decoy"], env=shell.env(), stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
        out.wait("lost", since=m, timeout=15)
        check(True, "another window taking focus ends the capture with lost")
        remote.stop()
        print("PROBE PASSED", flush=True)
        return 0
    finally:
        for p in (decoy, app):
            if p and p.poll() is None:
                p.terminate()
                try:
                    p.wait(5)
                except subprocess.TimeoutExpired:
                    p.kill()
        shell.stop()


def probe_x11(binary):
    """capture_probe on the nested shell's Xwayland: the X11 grab + warp path."""
    shell = NestedShell(x11=True)
    app = decoy = None
    try:
        shell.start()
        display = shell.x11_display()
        env = shell.env({"GDK_BACKEND": "x11", "DISPLAY": display})
        env.pop("WAYLAND_DISPLAY")
        auth = [f for f in os.listdir(shell.run_dir) if f.startswith(".mutter-Xwaylandauth")]
        if auth:
            env["XAUTHORITY"] = os.path.join(shell.run_dir, auth[0])
        app = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        out = JsonLines(app)
        remote = RemoteInput(shell.bus_address)
        support = out.wait("support", timeout=30)
        check(support["kind"] == "x11", f"the probe runs on X11 ({display}): {support}")
        remote.key(KEY_Escape)
        time.sleep(1.0)
        for _ in range(60):
            if out.since(0, "pointer"):
                break
            remote.move(15, 10)
            time.sleep(0.05)
        check(bool(out.since(0, "pointer")), "the pointer is over the probe window")
        m = out.mark()
        remote.key(KEY_c)
        out.wait("locked", since=m)
        check(True, "c grabbed the pointer and warped it to the centre")
        time.sleep(0.3)
        m = out.mark()
        for _ in range(20):
            remote.move(10, 0)
            time.sleep(0.03)
        time.sleep(0.5)
        sum_dx = sum(e["dx"] for e in out.since(m, "motion"))
        check(abs(sum_dx - 200) <= 6, f"X11 deltas sum to the moves: {sum_dx:.0f} (expected 200)")
        m = out.mark()
        for _ in range(60):
            remote.move(40, 0)
            time.sleep(0.01)
        time.sleep(0.5)
        sum_dx = sum(e["dx"] for e in out.since(m, "motion"))
        check(sum_dx > 2000, f"2400 px right, past the screen edge, still arrives: {sum_dx:.0f}")
        m = out.mark()
        remote.key(KEY_r)
        out.wait("release", since=m)
        time.sleep(0.3)
        remote.move(5, 0)
        time.sleep(0.4)
        check(not out.since(m, "motion"), "released: no deltas")
        m = out.mark()
        remote.key(KEY_c)
        out.wait("locked", since=m)
        decoy = subprocess.Popen([binary, "--decoy"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        out.wait("lost", since=m, timeout=15)
        check(True, "another window taking focus ends the X11 capture with lost")
        remote.stop()
        print("PROBE X11 PASSED", flush=True)
        return 0
    finally:
        for p in (decoy, app):
            if p and p.poll() is None:
                p.terminate()
                try:
                    p.wait(5)
                except subprocess.TimeoutExpired:
                    p.kill()
        shell.stop()


def serve():
    """JSON commands on stdin, one reply line each, for a Dart driver:
    {"cmd":"start"} → {"ok":true,"env":{...}}; {"cmd":"input"} (after the
    client's window is up); {"cmd":"move","dx":..,"dy":..};
    {"cmd":"key","keysym":..}; {"cmd":"click"}; {"cmd":"shot","path":..};
    {"cmd":"record","dir":..,"fps":30} / {"cmd":"stop_record"} →
    {"frames":[{"path","t"}]}; {"cmd":"stop"}."""
    shell = remote = None
    for raw in sys.stdin:
        req = json.loads(raw)
        try:
            cmd = req["cmd"]
            if cmd == "start":
                shell = NestedShell(work_dir=req.get("work")).start()
                reply = {"ok": True, "env": shell.env()}
            elif cmd == "input":
                remote = RemoteInput(shell.bus_address)
                reply = {"ok": True}
            elif cmd == "move":
                remote.move(req["dx"], req["dy"])
                reply = {"ok": True}
            elif cmd == "key":
                remote.key(req["keysym"])
                reply = {"ok": True}
            elif cmd == "click":
                remote.click()
                reply = {"ok": True}
            elif cmd == "shot":
                remote.screenshot(req["path"])
                reply = {"ok": True, "path": req["path"]}
            elif cmd == "record":
                remote.start_recording(req["dir"], req.get("fps", 30))
                reply = {"ok": True}
            elif cmd == "stop_record":
                reply = {"ok": True, "frames": remote.stop_recording()}
            elif cmd == "stop":
                if remote:
                    remote.stop()
                if shell:
                    shell.stop()
                print(json.dumps({"ok": True}), flush=True)
                return 0
            else:
                reply = {"ok": False, "error": f"unknown command {cmd}"}
        except Exception as e:  # noqa: BLE001 — reported to the driver
            reply = {"ok": False, "error": str(e)}
        print(json.dumps(reply), flush=True)
    if shell:
        shell.stop()
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "probe":
        sys.exit(probe(sys.argv[2]))
    if len(sys.argv) >= 3 and sys.argv[1] == "probe-x11":
        sys.exit(probe_x11(sys.argv[2]))
    if len(sys.argv) >= 2 and sys.argv[1] == "serve":
        sys.exit(serve())
    print(__doc__)
    sys.exit(2)
