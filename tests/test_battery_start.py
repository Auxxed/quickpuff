"""battery_start: the charge just before a dab heated, logged with the cycle
so battery per dab measures that dab alone."""

import asyncio

import pytest

import quickpuff.daemon as daemon_mod
from quickpuff import history
from quickpuff.constants import OperatingState
from quickpuff.daemon import QuickPuffDaemon

IDLE = int(OperatingState.IDLE)
PREHEAT = int(OperatingState.HEAT_CYCLE_PREHEAT)
ACTIVE = int(OperatingState.HEAT_CYCLE_ACTIVE)
FADE = int(OperatingState.HEAT_CYCLE_FADE)


class ScriptedPeak:
    """Answers each quick poll with the next (state, battery) and lets go after the last."""

    def __init__(self, script):
        self.script = list(script)
        self.is_connected = True

    async def poll_fast(self):
        state, battery = self.script.pop(0)
        if not self.script:
            self.is_connected = False
        return {"operating_state_id": state, "battery": battery}

    async def get_total_dabs(self):
        raise RuntimeError("not scripted")


@pytest.fixture(autouse=True)
def quick_polls(monkeypatch):
    monkeypatch.setattr(daemon_mod, "poll_delay", lambda *a: 0)
    monkeypatch.setattr(daemon_mod, "snapshot_kind", lambda *a: None)
    monkeypatch.setattr(daemon_mod, "QTIP_REMINDER_DELAY_S", 0)


def run(tmp_path, script, start=(IDLE, 80), d=None):
    d = d or QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d._desktop_notify = lambda *a, **k: None
    d.battery_saver = False
    d.status.update({"operating_state_id": start[0], "battery": start[1]})
    d.device = ScriptedPeak(script)

    async def go():
        d._start_poll()
        await asyncio.wait_for(d._poll_task, timeout=2)
        for task in list(d._tasks):
            task.cancel()

    asyncio.run(go())
    return d, history._load()["events"]


def test_a_dab_logs_the_charge_from_before_it_heated(tmp_path):
    _, events = run(tmp_path, [(PREHEAT, 80), (ACTIVE, 79), (IDLE, 76)])
    assert [e.get("battery_start") for e in events] == [80]
    assert events[0]["battery"] == 76


def test_a_dab_started_from_the_last_ones_fade_borrows_no_start(tmp_path):
    # The second dab began before the first had cooled, so the first one's
    # start would charge it for both.
    _, events = run(
        tmp_path,
        [(PREHEAT, 80), (ACTIVE, 79), (FADE, 77), (PREHEAT, 77), (ACTIVE, 76), (IDLE, 73)],
    )
    assert len(events) == 2
    assert events[0]["battery_start"] == 80
    assert "battery_start" not in events[1]


def test_an_aborted_preheat_leaves_no_start_behind(tmp_path):
    d, events = run(tmp_path, [(PREHEAT, 80), (IDLE, 80)])
    assert events == [] and d._battery_at_start is None


def test_connecting_forgets_the_last_links_session(tmp_path, monkeypatch):
    """A start, a reached temperature and a cycle from before a drop or a
    rest must not land on a session the new link sees."""

    class ConnectingPeak:
        is_connected = True
        address = "AA:BB:CC:11:22:33"

        def __init__(self, **kwargs):
            pass

        async def connect(self):
            pass

        async def require_peak_pro(self):
            pass

        async def snapshot(self, include_profiles=True):
            return {"operating_state_id": IDLE, "battery": 60, "serial": "S1"}

    monkeypatch.setattr(daemon_mod, "PuffcoBLE", ConnectingPeak)
    d = QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d._battery_at_start = 90
    d._session_reached_temp = True
    d._cycle_ts = 123.0
    d._start_poll = lambda: None
    asyncio.run(d._connect(None, "AA:BB:CC:11:22:33", sync=False))
    assert d.device is not None
    assert d._battery_at_start is None
    assert d._session_reached_temp is False
    assert d._cycle_ts is None
