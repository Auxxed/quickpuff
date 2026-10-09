"""Demo mode in the daemon: every client sees a heat cycle, and nothing real
happens. Nothing reaches the Peak, nothing lands in history, and none of a
real session's after-effects (Q-tip, Surprise me, the daily limit, battery
saver, the cleaning countdown) go off."""

import asyncio
import copy
import json
import time

import pytest

import quickpuff.daemon as daemon_mod
from quickpuff import history
from quickpuff.cli import print_status, print_waybar
from quickpuff.constants import OperatingState
from quickpuff.daemon import LOCAL_COMMANDS, LOCK_FREE_COMMANDS, QuickPuffDaemon
from quickpuff.paths import load_config

IDLE = int(OperatingState.IDLE)
PREHEAT = int(OperatingState.HEAT_CYCLE_PREHEAT)
ACTIVE = int(OperatingState.HEAT_CYCLE_ACTIVE)
FADE = int(OperatingState.HEAT_CYCLE_FADE)

PROFILES = [
    {"index": i, "name": name, "temp_f": temp, "temp_c": round((temp - 32) / 1.8, 1), "time": 30, "color": color}
    for i, (name, temp, color) in enumerate(
        [("Mine", 500, "#ff6a1a"), ("Evening", 520, "#3dd68c"), ("Hot", 540, "#ff4d4d"), ("Hotter", 560, "#ffffff")]
    )
]


class Listener:
    """A client on the socket, keeping everything broadcast to it."""

    def __init__(self):
        self.events = []

    def write(self, blob):
        self.events.append(json.loads(blob))

    async def drain(self):
        pass

    def close(self):
        pass

    def statuses(self):
        return [e["data"] for e in self.events if e["event"] == "status"]


class TattlePeak:
    """A connected Peak that writes down anything it's asked to do."""

    is_connected = True
    address = "AA:BB:CC:11:22:33"
    device_mac = None

    def __init__(self):
        self.calls = []

    def __getattr__(self, name):
        def record(*args, **kwargs):
            self.calls.append(name)
            return asyncio.sleep(0)

        return record


class IdlePeak(TattlePeak):
    """Answers the poll loop's quick polls with an idle Peak, like a real one."""

    async def poll_fast(self):
        self.calls.append("poll_fast")
        return {
            "connected": True,
            "operating_state": "Idle",
            "operating_state_id": IDLE,
            "battery": 64,
            "heater_temp_c": 27.2,
            "heater_temp_f": 81,
            "state_elapsed_s": None,
            "state_total_s": None,
        }


@pytest.fixture(autouse=True)
def quick_ticks(monkeypatch):
    monkeypatch.setattr(daemon_mod, "DEMO_TICK_S", 0.005)


def connected(tmp_path, peak=None):
    d = QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d.sent = []
    d._desktop_notify = lambda title, body, urgency="normal": d.sent.append((title, body))
    d.device = peak or TattlePeak()
    d.status.update(
        {
            "connected": True,
            "device_name": "Delly",
            "operating_state": "Idle",
            "operating_state_id": IDLE,
            "heater_temp_c": 27.2,
            "heater_temp_f": 81,
            "battery": 64,
            "charge_source": "Unplugged",
            "current_profile": 1,
            "profiles": copy.deepcopy(PROFILES),
        }
    )
    return d


def disconnected(tmp_path):
    d = QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d.sent = []
    d._desktop_notify = lambda title, body, urgency="normal": d.sent.append((title, body))
    return d


def skip_to(d, seconds):
    """Jump the playing demo to `seconds` after it began."""
    d._demo.started = time.monotonic() - seconds


def runs(values):
    return [v for i, v in enumerate(values) if i == 0 or values[i - 1] != v]


def profile(status, index):
    return next(p for p in status["profiles"] if p["index"] == index)


# ------------------------------------------------------------ what clients see


def test_status_answers_with_the_demo_while_the_real_status_stays_put(tmp_path):
    d = connected(tmp_path)

    async def go():
        started = await d.handle("demo", {})
        assert (started["profile"], started["name"], started["temp_f"]) == (1, "Evening", 520)
        assert (started["preheat"], started["session"], started["cooldown"]) == (12, 20, 6)
        assert started["stock_peak"] is False

        skip_to(d, 5)
        shown = await d.handle("status", {})
        assert (shown["operating_state_id"], shown["operating_state"]) == (PREHEAT, "Preheating")
        assert 81 < shown["heater_temp_f"] < 520
        assert shown["heater_temp_c"] == pytest.approx((shown["heater_temp_f"] - 32) / 1.8, abs=0.5)
        assert shown["state_total_s"] == 12
        assert shown["state_elapsed_s"] == pytest.approx(5, abs=0.2)
        assert shown["demo"] == {"active": True, "badge": True, "phase": "preheat"}
        assert shown["connected"] is True and shown["device_name"] == "Delly"
        assert shown["heat_trace"]["points"][0] == [0.0, 80.0]

        skip_to(d, 14)
        shown = await d.handle("status", {})
        assert shown["operating_state_id"] == ACTIVE
        assert abs(shown["heater_temp_f"] - 520) <= 5
        assert shown["state_total_s"] == 20
        # A real session runs for the profile's time: the tile matches the countdown.
        assert profile(shown, 1)["time"] == 20
        assert shown["heat_trace"]["ready_at"] == 12.0

        skip_to(d, 34)
        shown = await d.handle("status", {})
        assert (shown["operating_state_id"], shown["demo"]["phase"]) == (FADE, "fade")

        # Underneath, the real Peak is exactly as it was.
        assert d.status["operating_state_id"] == IDLE and d.status["heater_temp_f"] == 81
        assert d.status["battery"] == 64 and "demo" not in d.status
        assert profile(d.status, 1)["time"] == 30
        assert d.heat_trace.as_status() is None
        await d.handle("demo_stop", {})

    asyncio.run(go())


def test_pick_a_profile_and_the_lengths(tmp_path):
    d = connected(tmp_path)

    async def go():
        started = await d.handle("demo", {"profile": 3, "preheat": 20, "session": 30, "cooldown": 2})
        assert (started["name"], started["temp_f"]) == ("Hotter", 560)
        assert (started["preheat"], started["session"], started["cooldown"]) == (20, 30, 2)
        shown = await d.handle("status", {})
        assert shown["current_profile"] == 3 and d.status["current_profile"] == 1

        # Too short a preheat would slip between two of the bar's polls.
        started = await d.handle("demo", {"preheat": 1, "session": 999, "cooldown": -5})
        assert (started["preheat"], started["session"], started["cooldown"]) == (6, 180, 0)

        with pytest.raises(ValueError):
            await d.handle("demo", {"profile": 7})
        await d.handle("demo_stop", {})

    asyncio.run(go())


def test_the_badge_can_be_left_off(tmp_path, capsys):
    d = connected(tmp_path)

    async def go():
        await d.handle("demo", {"badge": False})
        quiet = await d.handle("status", {})
        await d.handle("demo", {})
        badged = await d.handle("status", {})
        await d.handle("demo_stop", {})
        return quiet, badged

    quiet, badged = asyncio.run(go())
    assert quiet["demo"]["badge"] is False and badged["demo"]["badge"] is True
    print_status(badged, False, "F")
    assert capsys.readouterr().out.splitlines()[0].endswith("·  demo")
    print_status(quiet, False, "F")
    assert "demo" not in capsys.readouterr().out.splitlines()[0]


def test_the_battery_dips_a_few_percent_over_the_session(tmp_path):
    d = connected(tmp_path)

    async def go():
        await d.handle("demo", {})
        skip_to(d, 0.5)
        start = (await d.handle("status", {}))["battery"]
        skip_to(d, 33)
        end = (await d.handle("status", {}))["battery"]
        await d.handle("demo_stop", {})
        return start, end

    start, end = asyncio.run(go())
    assert start == 64 and 3 <= start - end <= 4
    assert d.status["battery"] == 64


def test_every_status_broadcast_carries_the_demo(tmp_path):
    d = connected(tmp_path)
    listener = Listener()
    d.clients.add(listener)

    async def go():
        await d.handle("demo", {})
        await asyncio.sleep(0.05)
        ticks = listener.statuses()
        # The ticker streams frames a few times a second.
        assert len(ticks) >= 3
        assert all(s["demo"]["active"] and s["operating_state_id"] == PREHEAT for s in ticks)
        # Whatever else sends a status while it plays sends the demo's.
        listener.events.clear()
        await d._broadcast_event("status", d.status)
        assert listener.statuses()[-1]["demo"]["active"] is True
        # Other events pass through untouched.
        await d._broadcast_event("notify", {"title": "x", "body": "y"})
        assert listener.events[-1] == {"event": "notify", "data": {"title": "x", "body": "y"}}
        await d.handle("demo_stop", {})

    asyncio.run(go())


def test_it_ends_by_itself_after_idle_and_hands_back_the_real_status(tmp_path):
    d = connected(tmp_path)
    listener = Listener()
    d.clients.add(listener)

    async def go():
        await d.handle("demo", {})
        task = d._demo_task
        length = d._demo.run.length_s
        skip_to(d, length - 1)
        await asyncio.sleep(0.03)
        last = listener.statuses()[-1]
        assert (last["operating_state_id"], last["demo"]["phase"]) == (IDLE, "idle")
        skip_to(d, length + 0.1)
        await asyncio.wait_for(task, 1)
        assert d._demo is None and d._demo_task is None
        final = listener.statuses()[-1]
        assert "demo" not in final and final["heater_temp_f"] == 81
        assert "demo" not in await d.handle("status", {})

    asyncio.run(go())


def test_stop_hands_back_at_once(tmp_path):
    d = connected(tmp_path)
    listener = Listener()
    d.clients.add(listener)

    async def go():
        await d.handle("demo", {})
        task = d._demo_task
        assert await d.handle("demo_stop", {}) == {"stopped": True}
        await asyncio.sleep(0)
        assert task.cancelled() and d._demo is None
        assert "demo" not in listener.statuses()[-1]
        assert "demo" not in await d.handle("status", {})
        assert await d.handle("demo_stop", {}) == {"stopped": False}

    asyncio.run(go())


def test_asking_again_starts_a_fresh_take(tmp_path):
    d = connected(tmp_path)

    async def go():
        await d.handle("demo", {})
        first = d._demo_task
        skip_to(d, 20)
        await d.handle("demo", {"profile": 0})
        await asyncio.sleep(0)
        assert first.cancelled()
        shown = await d.handle("status", {})
        assert shown["demo"]["phase"] == "preheat" and shown["current_profile"] == 0
        await d.handle("demo_stop", {})

    asyncio.run(go())


def test_refuses_while_the_peak_really_heats(tmp_path):
    for state in (PREHEAT, ACTIVE, FADE):
        d = connected(tmp_path)
        d.status["operating_state_id"] = state
        with pytest.raises(RuntimeError, match="heating for real"):
            asyncio.run(d.handle("demo", {}))
        assert d._demo is None


def test_a_real_cycle_starting_mid_demo_takes_over(tmp_path):
    d = connected(tmp_path)
    listener = Listener()
    d.clients.add(listener)

    async def go():
        await d.handle("demo", {})
        task = d._demo_task
        # Someone presses the Peak's own button.
        d.status.update({"operating_state_id": PREHEAT, "operating_state": "Preheating"})
        await asyncio.wait_for(task, 1)
        assert d._demo is None
        last = listener.statuses()[-1]
        assert last["operating_state_id"] == PREHEAT and "demo" not in last

    asyncio.run(go())


def test_with_no_peak_it_plays_on_a_stock_one(tmp_path):
    d = disconnected(tmp_path)

    async def go():
        started = await d.handle("demo", {})
        assert started["stock_peak"] is True
        assert (started["profile"], started["name"], started["temp_f"]) == (2, "High", 530)
        shown = await d.handle("status", {})
        await d.handle("demo_stop", {})
        return shown

    shown = asyncio.run(go())
    assert shown["connected"] is True and shown["resting"] is False
    assert shown["device_name"] == "QuickPuff"
    assert shown["product"]["label"] == "Peak Pro Onyx"
    assert shown["product"]["marketing_name"] == "Onyx"
    assert shown["current_profile"] == 2
    assert [p["temp_f"] for p in shown["profiles"]] == [490, 510, 530, 545]
    assert [p["color"] for p in shown["profiles"]] == ["#3b9eff", "#3dd68c", "#ff4d4d", "#ffffff"]
    assert 85 <= shown["battery"] <= 87
    assert d.status["connected"] is False and d.status["profiles"] == []


def test_a_peak_without_profiles_or_at_rest_gets_the_stock_one_too(tmp_path):
    no_profiles = connected(tmp_path)
    no_profiles.status["profiles"] = []
    resting = connected(tmp_path)
    resting.status.update({"connected": False, "resting": True, "operating_state": "Resting", "operating_state_id": -1})
    for d in (no_profiles, resting):
        started = asyncio.run(d.handle("demo", {}))
        assert started["stock_peak"] is True and started["name"] == "High"


def test_a_link_lost_mid_demo_leaves_the_show_running(tmp_path):
    d = connected(tmp_path)

    async def go():
        await d.handle("demo", {})
        skip_to(d, 15)
        d.status = d._empty_status()  # disconnected underneath it
        shown = await d.handle("status", {})
        await d.handle("demo_stop", {})
        return shown

    shown = asyncio.run(go())
    assert shown["connected"] is True and shown["operating_state_id"] == ACTIVE
    assert [p["name"] for p in shown["profiles"]] == ["Mine", "Evening", "Hot", "Hotter"]


def test_a_profile_that_failed_to_read_heats_to_the_stock_temperature(tmp_path):
    d = connected(tmp_path)
    d.status["profiles"][2].update(temp_f=0, temp_c=0)

    async def go():
        started = await d.handle("demo", {"profile": 2})
        shown = await d.handle("status", {})
        await d.handle("demo_stop", {})
        return started, shown

    started, shown = asyncio.run(go())
    assert started["temp_f"] == 530
    assert profile(shown, 2)["temp_f"] == 530 and profile(d.status, 2)["temp_f"] == 0


def test_stop_ends_the_demo_without_a_peak_to_bother(tmp_path):
    d = disconnected(tmp_path)
    d._resting = True
    woken = []

    async def wake():
        woken.append(True)

    d._wake = wake

    async def go():
        await d.handle("demo", {})
        assert await d.handle("stop_heat", {}) == {"ok": True}
        assert d._demo is None

    asyncio.run(go())
    assert woken == []


def test_stop_during_a_demo_still_reaches_a_connected_peak(tmp_path):
    # Its own button may have started a real cycle the poll hasn't seen yet.
    peak = TattlePeak()
    d = connected(tmp_path, peak)

    async def go():
        await d.handle("demo", {})
        await d.handle("stop_heat", {})

    asyncio.run(go())
    assert d._demo is None and peak.calls == ["stop_heat_cycle"]


def test_starting_a_real_heat_ends_the_demo(tmp_path):
    peak = TattlePeak()
    d = connected(tmp_path, peak)
    listener = Listener()
    d.clients.add(listener)

    async def go():
        await d.handle("demo", {})
        await d.handle("start_heat", {})

    asyncio.run(go())
    assert peak.calls == ["start_heat_cycle"]
    assert d._demo is None and "demo" not in listener.statuses()[-1]


def test_a_heat_start_that_fails_leaves_the_demo_playing(tmp_path):
    d = disconnected(tmp_path)

    async def go():
        await d.handle("demo", {})
        with pytest.raises(RuntimeError, match="Not connected"):
            await d.handle("start_heat", {})
        assert d._demo is not None
        await d.handle("demo_stop", {})

    asyncio.run(go())


def test_notify_sends_the_ready_notification_as_it_becomes_ready(tmp_path):
    d = disconnected(tmp_path)
    listener = Listener()
    d.clients.add(listener)

    async def go():
        await d.handle("demo", {"notify": True})
        await asyncio.sleep(0.02)
        assert d.sent == []  # still preheating
        skip_to(d, 12.1)
        await asyncio.sleep(0.02)
        skip_to(d, 20)
        await asyncio.sleep(0.02)
        await d.handle("demo_stop", {})

    asyncio.run(go())
    ready = ("QuickPuff is ready", "At 530°F. Your session has started.")
    assert d.sent == [ready]
    notes = [e["data"] for e in listener.events if e["event"] == "notify"]
    assert notes == [{"title": ready[0], "body": ready[1]}]


# ------------------------------------------------------- nothing real happens


def test_demo_commands_never_wake_or_wait_on_the_peak():
    assert {"demo", "demo_stop"} <= LOCAL_COMMANDS
    assert {"demo", "demo_stop"} <= LOCK_FREE_COMMANDS


def test_a_resting_peak_stays_resting_and_battery_saver_sees_no_activity(tmp_path):
    d = connected(tmp_path)
    d._resting = True
    woken = []

    async def wake():
        woken.append(True)

    d._wake = wake
    asyncio.run(d.handle("demo", {}))
    assert woken == []
    # Using the panel or CLI holds battery saver off; a demo isn't using the Peak.
    assert d._last_user_cmd == float("-inf")


def watch_side_effects(d, monkeypatch):
    """Arm every real after-effect, and note any that fire."""
    fired = []

    def note(name):
        def record(*args, **kwargs):
            fired.append(name)
            return asyncio.sleep(0)

        return record

    for name in ("record_cycle", "record_battery", "record_total", "record_device_sessions", "set_note"):
        monkeypatch.setattr(history, name, note(f"history.{name}"))
    for name in (
        "_notify_ready",
        "_notify_qtip",
        "_notify_clean",
        "_surprise_next",
        "_check_daily_limit",
        "_count_session",
        "_refresh_clean",
        "_save_clean",
        "_schedule_saver_sleep",
        "_cancel_saver_sleep",
        "_rest",
        "_wake",
        "_sync_usage_safe",
    ):
        monkeypatch.setattr(d, name, note(name))
    d.qtip_reminder = True
    d.surprise_light = True
    d.battery_saver = True
    d.daily_limit = 1
    return fired


def test_a_whole_demo_touches_nothing_real(tmp_path, monkeypatch):
    peak = TattlePeak()
    d = connected(tmp_path, peak)
    fired = watch_side_effects(d, monkeypatch)
    listener = Listener()
    d.clients.add(listener)
    history_before = copy.deepcopy(history._load())
    config_before = load_config()
    status_before = copy.deepcopy({k: v for k, v in d.status.items() if k != "telemetry"})

    async def go():
        await d.handle("demo", {})
        task = d._demo_task
        for t in (3, 11.9, 12.1, 20, 31.9, 32.1, 37.9, 38.1, 41):
            skip_to(d, t)
            await asyncio.sleep(0.02)
            await d.handle("status", {})
        skip_to(d, 60)
        await asyncio.wait_for(task, 1)

    asyncio.run(go())
    # The clients saw a whole session...
    shown = [s["operating_state_id"] for s in listener.statuses() if s.get("demo")]
    assert runs(shown) == [PREHEAT, ACTIVE, FADE, IDLE]
    # ...and nothing happened: nothing asked of the Peak, nothing recorded,
    # no reminder, no new light, no limit, no battery saver, no countdown.
    assert peak.calls == []
    assert fired == []
    assert d._tasks == set()
    assert history._load() == history_before
    assert load_config() == config_before
    assert {k: v for k, v in d.status.items() if k != "telemetry"} == status_before
    assert d.heat_trace.as_status() is None


def test_the_poll_loop_keeps_to_the_real_peak_through_a_demo(tmp_path, monkeypatch):
    monkeypatch.setattr(daemon_mod, "poll_delay", lambda *a: 0.005)
    monkeypatch.setattr(daemon_mod, "snapshot_kind", lambda *a: None)
    peak = IdlePeak()
    d = connected(tmp_path, peak)
    fired = watch_side_effects(d, monkeypatch)
    listener = Listener()
    d.clients.add(listener)
    history_before = copy.deepcopy(history._load())

    async def go():
        d._start_poll()
        await d.handle("demo", {})
        task = d._demo_task
        for t in (5, 12.5, 25, 33, 39):
            skip_to(d, t)
            await asyncio.sleep(0.03)
            # The loop is reading the real, idle Peak the whole time.
            assert d.status["operating_state_id"] == IDLE
        skip_to(d, 60)
        await asyncio.wait_for(task, 1)
        await asyncio.sleep(0.02)
        d._stop_poll()

    asyncio.run(go())
    statuses = listener.statuses()
    assert runs([s["operating_state_id"] for s in statuses if s.get("demo")]) == [PREHEAT, ACTIVE, FADE, IDLE]
    assert "demo" not in statuses[-1] and statuses[-1]["operating_state_id"] == IDLE
    # Plain polling and nothing more: no writes, no session recorded or synced.
    assert set(peak.calls) == {"poll_fast"}
    assert fired == []
    assert history._load() == history_before
    assert d.heat_trace.as_status() is None


# ------------------------------------------------------------------ the bar


def bar_class(d, capsys, seconds):
    skip_to(d, seconds)
    print_waybar(asyncio.run(d.handle("status", {})))
    return json.loads(capsys.readouterr().out)["class"]


def test_the_bar_goes_preheat_ready_cool_idle_like_a_real_cycle(tmp_path, capsys):
    d = disconnected(tmp_path)
    asyncio.run(d.handle("demo", {}))
    length = d._demo.run.length_s
    classes = [bar_class(d, capsys, tenth / 10) for tenth in range(int(length * 10))]
    assert runs(classes) == ["preheat", "ready", "cool", "idle"]
    # The same classes a real cycle gets.
    for state, css in ((PREHEAT, "preheat"), (ACTIVE, "ready"), (FADE, "cool")):
        print_waybar({"connected": True, "battery": 80, "heater_temp_f": 500, "operating_state_id": state})
        assert json.loads(capsys.readouterr().out)["class"] == css


@pytest.mark.parametrize("first_poll", [0.1, 1.0, 2.5, 4.0, 5.0])
def test_the_bar_catches_the_ready_moment_whenever_it_first_looks(tmp_path, capsys, first_poll):
    # BarWidget.qml polls every 5 s, every 1 s once it sees a preheat, and
    # plays the ready animation when the class goes preheat -> ready.
    d = disconnected(tmp_path)
    asyncio.run(d.handle("demo", {"preheat": 1}))  # held to the shortest the bar can't miss
    t, seen, played = first_poll, "idle", False
    while t < d._demo.run.length_s:
        now = bar_class(d, capsys, t)
        played = played or (seen, now) == ("preheat", "ready")
        seen = now
        t += 1 if now == "preheat" else 5
    assert played
