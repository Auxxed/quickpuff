"""The daemon's socket and what it does with what arrives on it: only this
user's processes, a bounded number at once, bounded lines, debug-only raw
commands, plain notifications, and the shell's settings in `status`."""

import asyncio
import json
import os
import socket
import stat
import struct

import pytest

from quickpuff import daemon as daemon_module
from quickpuff import paths
from quickpuff.daemon import QuickPuffDaemon, notify_text, peer_uid
from quickpuff.rpc import rpc


def make_daemon(tmp_path, monkeypatch, **kwargs):
    # No logind or BlueZ watching in these tests: just the socket.
    async def no_watch(_callback):
        raise RuntimeError("no BlueZ here")

    monkeypatch.setattr(daemon_module.bluez, "watch_disconnects", no_watch)
    d = QuickPuffDaemon(sock=tmp_path / "sock" / "quickpuff.sock", **kwargs)
    d._handoff = False
    return d


class FakeTransportSocket:
    def __init__(self, uid):
        self.uid = uid

    def getsockopt(self, level, option, size):
        assert (level, option, size) == (socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        return struct.pack("iII", 4242, self.uid, self.uid)


class FakeWriter:
    def __init__(self, uid=None):
        self.sock = None if uid is None else FakeTransportSocket(uid)
        self.closed = False
        self.sent = []

    def get_extra_info(self, name):
        return self.sock if name == "socket" else None

    def write(self, data):
        self.sent.append(data)

    async def drain(self):
        pass

    def close(self):
        self.closed = True

    async def wait_closed(self):
        pass


async def accept(d, writer):
    await d._accept(asyncio.StreamReader(), writer)


# ---- who may connect -----------------------------------------------------------


def test_peer_uid_reads_so_peercred_from_the_connection():
    assert peer_uid(FakeWriter(uid=1234)) == 1234
    assert peer_uid(FakeWriter(uid=None)) is None


def test_another_users_connection_is_closed_before_anything_is_read(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    served = []

    async def client(reader, writer):
        served.append(writer)

    monkeypatch.setattr(d, "_client", client)
    writer = FakeWriter(uid=os.geteuid() + 1)
    asyncio.run(accept(d, writer))
    assert served == [] and writer.closed


def test_a_connection_without_credentials_is_refused(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    monkeypatch.setattr(d, "_client", lambda r, w: pytest.fail("served a connection with no peer credentials"))
    writer = FakeWriter(uid=None)
    asyncio.run(accept(d, writer))
    assert writer.closed


def test_this_users_connection_is_served(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    served = []

    async def client(reader, writer):
        served.append(d._connections)

    monkeypatch.setattr(d, "_client", client)
    asyncio.run(accept(d, FakeWriter(uid=os.geteuid())))
    assert served == [1]
    assert d._connections == 0


def test_clients_past_the_cap_are_refused(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    monkeypatch.setattr(d, "_client", lambda r, w: pytest.fail("served past MAX_CLIENTS"))
    d._connections = daemon_module.MAX_CLIENTS
    writer = FakeWriter(uid=os.geteuid())
    asyncio.run(accept(d, writer))
    assert writer.closed
    assert d._connections == daemon_module.MAX_CLIENTS


def test_real_socket_checks_the_kernels_word_for_who_is_calling(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    real = os.geteuid()

    async def run():
        await d.start()
        try:
            assert (await asyncio.wait_for(rpc("ping", {}, path=d.socket_path), 5))["version"]
            # Now the daemon believes it runs as someone else: this process
            # is a stranger to it, and gets nothing.
            monkeypatch.setattr(os, "geteuid", lambda: real + 1)
            with pytest.raises(RuntimeError, match="closed the connection"):
                await asyncio.wait_for(rpc("ping", {}, path=d.socket_path), 5)
        finally:
            monkeypatch.setattr(os, "geteuid", lambda: real)
            await d.close()

    asyncio.run(run())


# ---- what may arrive -------------------------------------------------------------


async def _talk(path, payload: bytes):
    reader, writer = await asyncio.open_unix_connection(str(path))
    try:
        await reader.readline()  # the status every client gets on connecting
        writer.write(payload)
        await writer.drain()
        lines = []
        while True:
            line = await asyncio.wait_for(reader.readline(), 5)
            if not line:
                return lines, True
            lines.append(json.loads(line))
            if len(lines) >= payload.count(b"\n"):
                return lines, False
    finally:
        writer.close()


def test_an_overlong_line_drops_that_client_and_nobody_else(tmp_path, monkeypatch, caplog):
    d = make_daemon(tmp_path, monkeypatch)

    async def run():
        await d.start()
        try:
            reader, writer = await asyncio.open_unix_connection(str(d.socket_path))
            await reader.readline()
            writer.write(b"x" * (daemon_module.MAX_REQUEST_BYTES + 4096))
            await writer.drain()
            try:
                tail = await asyncio.wait_for(reader.read(), 5)
            except ConnectionResetError:
                tail = b""  # closed on us with some of it still unread
            assert tail == b""
            writer.close()
            assert (await asyncio.wait_for(rpc("ping", {}, path=d.socket_path), 5))["version"]
        finally:
            await d.close()

    asyncio.run(run())
    assert "without a newline" in caplog.text
    assert "Unhandled exception" not in caplog.text


def test_requests_that_are_not_objects_get_an_error_and_the_line_stays_open(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)

    async def run():
        await d.start()
        try:
            payload = b"[1, 2]\n" + b'{"id": 3, "cmd": "ping", "args": [1]}\n' + b"[" * 5000 + b"\n"
            payload += b'{"id": 9, "cmd": "ping"}\n'
            lines, closed = await _talk(d.socket_path, payload)
            assert not closed
            assert [line["ok"] for line in lines] == [False, False, False, True]
            assert lines[1]["id"] == 3 and "bad request" in lines[1]["error"]
            assert "bad json" in lines[2]["error"]
            assert lines[3]["id"] == 9
        finally:
            await d.close()

    asyncio.run(run())


# ---- the socket file -------------------------------------------------------------


def test_socket_and_its_directory_are_private(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    (tmp_path / "sock").mkdir(mode=0o755)

    async def run():
        await d.start()
        try:
            assert stat.S_IMODE(os.stat(d.socket_path.parent).st_mode) == 0o700
            assert stat.S_IMODE(os.lstat(d.socket_path).st_mode) == 0o600
        finally:
            await d.close()
        assert not os.path.lexists(d.socket_path)

    asyncio.run(run())


def test_a_dead_daemons_socket_is_replaced(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    d.socket_path.parent.mkdir(mode=0o700)
    stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    stale.bind(str(d.socket_path))
    stale.close()  # the file stays, nothing listens: a SIGKILLed daemon

    async def run():
        await d.start()
        try:
            assert (await asyncio.wait_for(rpc("ping", {}, path=d.socket_path), 5))["version"]
        finally:
            await d.close()

    asyncio.run(run())


@pytest.mark.parametrize("plant", ["file", "symlink", "fifo"])
def test_something_else_at_the_socket_path_is_left_and_the_daemon_refuses(tmp_path, monkeypatch, plant):
    d = make_daemon(tmp_path, monkeypatch)
    d.socket_path.parent.mkdir(mode=0o700)
    victim = tmp_path / "victim.txt"
    victim.write_text("must survive\n")
    if plant == "file":
        d.socket_path.write_text("not a socket")
    elif plant == "symlink":
        d.socket_path.symlink_to(victim)
    else:
        os.mkfifo(d.socket_path)
    before = os.lstat(d.socket_path)

    with pytest.raises(paths.RefusedFile, match="isn't a QuickPuff socket"):
        asyncio.run(d.start())
    after = os.lstat(d.socket_path)
    assert (after.st_ino, after.st_mode) == (before.st_ino, before.st_mode)
    assert victim.read_text() == "must survive\n"


def test_a_second_daemon_wont_take_a_live_daemons_socket(tmp_path, monkeypatch):
    first = make_daemon(tmp_path, monkeypatch)
    second = make_daemon(tmp_path, monkeypatch, debug=True)

    async def run():
        await first.start()
        try:
            with pytest.raises(paths.RefusedFile, match="already listening"):
                await second.start()
            assert (await asyncio.wait_for(rpc("ping", {}, path=first.socket_path), 5))["version"]
        finally:
            await first.close()

    asyncio.run(run())


def test_close_leaves_whatever_replaced_its_socket(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)

    async def run():
        await d.start()
        os.unlink(d.socket_path)
        d.socket_path.write_text("someone else's now")
        await d.close()

    asyncio.run(run())
    assert d.socket_path.read_text() == "someone else's now"


def test_daemon_without_a_runtime_dir_fails_closed(monkeypatch):
    monkeypatch.delenv("XDG_RUNTIME_DIR")
    with pytest.raises(SystemExit, match="XDG_RUNTIME_DIR"):
        asyncio.run(daemon_module.amain([]))


# ---- debug-only commands ---------------------------------------------------------


class RawPeak:
    is_connected = True

    def __init__(self):
        self.writes = []

    async def read_short(self, path, offset, size):
        return b"\x01\x02"

    async def write_short(self, path, a, b, raw):
        self.writes.append((path, raw))


@pytest.mark.parametrize("cmd,args", [("peek", {"path": "/p/x"}), ("poke", {"path": "/p/x", "hex": "00"})])
def test_raw_commands_need_the_debug_flag(tmp_path, monkeypatch, cmd, args):
    d = make_daemon(tmp_path, monkeypatch)
    peak = RawPeak()
    d.device = peak
    d._resting = True

    async def no_wake():
        raise AssertionError("a refused debug command must not wake the Peak")

    monkeypatch.setattr(d, "_wake", no_wake)
    with pytest.raises(PermissionError, match="--debug"):
        asyncio.run(d.handle(cmd, args))
    assert peak.writes == []


def test_raw_commands_work_under_debug(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch, debug=True)
    peak = RawPeak()
    d.device = peak
    assert asyncio.run(d.handle("peek", {"path": "/p/x", "size": 2}))["hex"] == "0102"
    assert asyncio.run(d.handle("poke", {"path": "/u/y", "hex": "ff00"}))["ok"]
    assert peak.writes == [("/u/y", b"\xff\x00")]


# ---- notifications ---------------------------------------------------------------


def test_notify_text_is_plain_and_short():
    hostile = "<b>Peak</b> & \x1b[31m‮evil⁦\x85 name\n" + "x" * 500
    clean = notify_text(hostile, 80)
    assert not set(clean) & set("<>&\x1b\x85\n‮⁦")
    assert len(clean) <= 80 and clean.endswith("…")
    assert notify_text("Peak   Pro\t is ready", 80) == "Peak Pro is ready"
    assert notify_text("a‏b؜c", 80) == "abc"


def test_notifications_go_through_the_absolute_notify_send_with_plain_text(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    launched = []

    class Proc:
        def __init__(self, argv, **kwargs):
            launched.append((argv, kwargs))

    monkeypatch.setattr(daemon_module.subprocess, "Popen", Proc)
    d._desktop_notify("-u critical <i>Peak</i> is ready", "At 500°F & rising\x07", urgency="bogus")
    argv, kwargs = launched[0]
    assert argv[:6] == ["/usr/bin/notify-send", "-a", "QuickPuff", "-u", "normal", "--"]
    assert argv[6] == "-u critical iPeak/i is ready"
    assert argv[7] == "At 500°F rising"
    assert len(argv) == 8
    assert kwargs["start_new_session"] and kwargs["stdin"] is daemon_module.subprocess.DEVNULL


def test_a_peak_named_by_someone_else_reaches_the_notification_plain(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    sent = []
    monkeypatch.setattr(
        daemon_module.subprocess, "Popen", lambda argv, **k: sent.append(argv)
    )
    d.status["device_name"] = "<a href='x'>Peak</a>" + "!" * 200
    asyncio.run(d._notify_clean())
    title = sent[0][6]
    assert "<" not in title and ">" not in title
    assert len(title) <= daemon_module.NOTIFY_TITLE_MAX


# ---- status carries the shell's settings ------------------------------------------


def test_status_carries_a_fresh_checked_ui_block(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    assert asyncio.run(d.handle("status", {}))["ui"] == paths.ui_settings({})
    paths.save_config({"units": "C", "showtime": "stage", "overlay_screen": "DP 2; rm", "sound_volume": 400})
    ui = asyncio.run(d.handle("status", {}))["ui"]
    assert ui == {
        "ready_animation": "rocket",
        "showtime": "stage",
        "sounds": True,
        "sound_volume": 100,
        "overlay_screen": "focused",
        "units": "C",
    }
    # Only in the answer: the status the daemon keeps and broadcasts is untouched.
    assert "ui" not in d.status


# ---- numbers that arrive on the socket ----------------------------------------------


@pytest.mark.parametrize("value", [float("nan"), float("inf"), float("-inf")])
def test_clamp_refuses_what_isnt_a_number(value):
    with pytest.raises(ValueError):
        daemon_module._clamp(value, daemon_module.MIN_TEMP_F, daemon_module.MAX_TEMP_F)


def test_a_nan_temperature_never_reaches_the_peak(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)

    class Peak:
        is_connected = True

        async def set_profile_temp_c(self, index, celsius):
            raise AssertionError(f"sent {celsius} to the heater")

    d.device = Peak()
    with pytest.raises(ValueError):
        asyncio.run(d.handle("set_profile_temp", {"index": 0, "fahrenheit": float("nan")}))


def test_stats_span_is_bounded(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    asked = []
    real = daemon_module.history.get_stats
    monkeypatch.setattr(daemon_module.history, "get_stats", lambda days=14: asked.append(days) or real(days=3))
    asyncio.run(d.handle("stats", {"days": 10**9}))
    asyncio.run(d.handle("stats", {"days": -5}))
    assert asked == [daemon_module.history.RETENTION_DAYS, 1]


def test_scan_time_is_bounded(tmp_path, monkeypatch):
    d = make_daemon(tmp_path, monkeypatch)
    asked = []

    class Scanner:
        def __init__(self, **_kwargs):
            pass

        async def scan(self, timeout):
            asked.append(timeout)
            return []

    monkeypatch.setattr(daemon_module, "PuffcoBLE", Scanner)
    asyncio.run(d.handle("scan", {"timeout": 1e9}))
    assert asked == [daemon_module.MAX_SCAN_S]


# ---- a refused config.json ----------------------------------------------------------


@pytest.fixture
def refused_config(tmp_path):
    victim = tmp_path / "victim.txt"
    victim.write_text("must survive\n")
    path = paths.config_path()
    path.parent.mkdir(parents=True)
    path.symlink_to(victim)
    return victim


def test_a_setting_that_cant_be_saved_changes_nothing(tmp_path, monkeypatch, refused_config):
    d = make_daemon(tmp_path, monkeypatch)
    before = (d.surprise_light, d.battery_saver, d.daily_limit, d.clean_every)
    with pytest.raises(paths.RefusedFile):
        asyncio.run(d.handle("set_surprise", {"enable": True}))
    with pytest.raises(paths.RefusedFile):
        asyncio.run(d.handle("set_battery_saver", {"enable": True}))
    with pytest.raises(paths.RefusedFile):
        asyncio.run(d.handle("set_daily_limit", {"limit": 5}))
    with pytest.raises(paths.RefusedFile):
        asyncio.run(d.handle("set_clean_every", {"dabs": 50}))
    assert (d.surprise_light, d.battery_saver, d.daily_limit, d.clean_every) == before
    assert refused_config.read_text() == "must survive\n"


def test_bookkeeping_that_cant_be_saved_is_skipped_not_fatal(tmp_path, monkeypatch, refused_config):
    d = make_daemon(tmp_path, monkeypatch)
    d.daily_limit = 1
    d._desktop_notify = lambda *a, **k: pytest.fail("notified without being able to note it")
    # The limit is reached, but with nowhere to note today's notice it would
    # go out again on every sync: so it doesn't go out.
    assert asyncio.run(d._check_daily_limit(3)) is False
    d._baseline_clean(120)  # the cleaning countdown, as a snapshot arrives
    assert d.clean_at_total == 120
    assert refused_config.read_text() == "must survive\n"
