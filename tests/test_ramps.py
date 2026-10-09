"""Heat ramps: planning steps, playing them through a session, stopping when
you take over, and the probe that learns how a Peak takes them."""

import asyncio

import pytest

import quickpuff.daemon as daemon_mod
from quickpuff import ramps
from quickpuff.constants import OperatingState
from quickpuff.daemon import QuickPuffDaemon
from quickpuff.paths import load_config, save_config

ACTIVE = int(OperatingState.HEAT_CYCLE_ACTIVE)
IDLE = int(OperatingState.IDLE)
PREHEAT = int(OperatingState.HEAT_CYCLE_PREHEAT)


# ------------------------------------------------------------- planning

def test_live_plans_every_change_within_the_range():
    actions = ramps.plan([(0, -40), (20, 0), (30, 200)], 520, "live")
    assert actions == [{"at": 0, "target_f": 480.0}, {"at": 20, "target_f": 520.0}, {"at": 30, "target_f": 620.0}]


def test_boost_only_goes_up_and_at_most_36_degrees():
    actions = ramps.plan([(10, 30), (20, 0), (30, 60)], 520, "boost", session_s=45)
    assert [a["boost_f"] for a in actions] == [30.0, 36.0]
    assert actions[0]["boost_s"] == 10.0 and actions[1]["boost_s"] == 15.0


def test_steps_past_the_end_of_the_session_are_dropped():
    assert [a["at"] for a in ramps.plan([(10, 10), (50, 20)], 500, "live", session_s=45)] == [10]


@pytest.mark.parametrize("bad", [[], [(500, 10)], [(10, 400)], [(1, 1)] * 9, [("x", 1)], [[1, 2, 3]]])
def test_bad_steps_are_refused(bad):
    with pytest.raises((ValueError, TypeError)):
        ramps.normalize(bad)


def test_parse_steps_reads_seconds_and_offsets():
    assert ramps.parse_steps(["30:+40", "15:20"]) == [(15.0, 20.0), (30.0, 40.0)]
    with pytest.raises(ValueError):
        ramps.parse_steps(["15+20"])


def test_every_preset_is_valid():
    for name in ramps.PRESETS:
        assert ramps.steps_for(name) and ramps.describe(name)["label"]


# ------------------------------------------------------------- the daemon

class HeaterPeak:
    is_connected = True

    def __init__(self, takes_live=True):
        self.takes_live = takes_live
        self.target = 270.0  # °C-ish stand-in, kept in °F here
        self.target_f = 520.0
        self.calls = []

    async def get_live_target_f(self):
        return self.target_f

    async def set_live_target_f(self, f):
        self.calls.append(("target", f))
        if self.takes_live:
            self.target_f = f

    async def live_boost(self, f, s):
        self.calls.append(("boost", f, s))

    async def set_live_boost(self, f, s):
        self.calls.append(("boost-setting", f, s))

    async def start_heat_cycle(self):
        self.calls.append(("start",))

    async def stop_heat_cycle(self):
        self.calls.append(("stop",))

    async def boost_heat_cycle(self):
        self.calls.append(("boost-button",))


@pytest.fixture(autouse=True)
def fast(monkeypatch):
    real_sleep = asyncio.sleep

    async def quick(seconds, *a, **k):
        await real_sleep(0)

    monkeypatch.setattr(daemon_mod.asyncio, "sleep", quick)


def daemon(tmp_path, peak):
    d = QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d._desktop_notify = lambda *a, **k: None
    d.device = peak
    d.status["current_profile"] = 1
    d.status["operating_state_id"] = ACTIVE
    d.status["profiles"] = [{"index": 1, "name": "High", "temp_f": 520, "time": 45, "boost_temp_f": 15, "boost_time": 15}]
    return d


def test_set_ramp_stores_presets_and_custom_steps(tmp_path):
    d = daemon(tmp_path, HeaterPeak())
    asyncio.run(d._set_ramp({"index": 1, "preset": "rise"}))
    assert load_config()["ramps"] == {"1": "rise"}
    assert d.status["ramps"]["1"]["label"] == "Rise"
    asyncio.run(d._set_ramp({"index": 2, "steps": [[20, 10], [5, 5]]}))
    assert load_config()["ramps"]["2"] == [[5.0, 5.0], [20.0, 10.0]]
    asyncio.run(d._set_ramp({"index": 1, "off": True}))
    assert "1" not in load_config()["ramps"]
    with pytest.raises(ValueError):
        asyncio.run(d._set_ramp({"index": 1, "preset": "volcano"}))


def play(d):
    async def go():
        d._maybe_start_ramp()
        if d._ramp_task:
            await d._ramp_task

    asyncio.run(go())


def test_a_boost_ramp_plays_each_step_then_puts_the_boost_back(tmp_path):
    peak = HeaterPeak()
    d = daemon(tmp_path, peak)
    save_config({**load_config(), "ramps": {"1": "rise"}})
    play(d)
    assert peak.calls[:2] == [("boost", 20.0, 15.0), ("boost", 36.0, 15.0)]
    assert peak.calls[-1] == ("boost-setting", 15.0, 15.0)
    assert d.status["ramp_running"] is None


def test_a_live_ramp_moves_the_target_and_restores_it(tmp_path):
    peak = HeaterPeak()
    d = daemon(tmp_path, peak)
    save_config({**load_config(), "ramps": {"1": "low"}, "ramp_method": "live"})
    play(d)
    assert [c[1] for c in peak.calls if c[0] == "target"] == [480.0, 500.0, 520.0, 520.0]


def test_no_ramp_no_writes(tmp_path):
    peak = HeaterPeak()
    d = daemon(tmp_path, peak)
    play(d)
    assert peak.calls == []


def test_a_ramp_stops_when_the_session_does(tmp_path):
    peak = HeaterPeak()
    d = daemon(tmp_path, peak)
    save_config({**load_config(), "ramps": {"1": "cloud"}})
    d.status["operating_state_id"] = IDLE
    play(d)
    assert [c for c in peak.calls if c[0] == "boost"] == []


def test_your_heat_command_cancels_a_running_ramp(tmp_path):
    peak = HeaterPeak()
    d = daemon(tmp_path, peak)
    save_config({**load_config(), "ramps": {"1": "cloud"}})

    async def go():
        d._maybe_start_ramp()
        task = d._ramp_task
        await d.handle("stop_heat", {})
        assert task.cancelled() or task.done() or d._ramp_task is None
        await asyncio.gather(task, return_exceptions=True)

    asyncio.run(go())
    assert ("stop",) in peak.calls


def test_the_probe_needs_a_yes(tmp_path):
    d = daemon(tmp_path, HeaterPeak())
    d.status["operating_state_id"] = IDLE
    with pytest.raises(ValueError):
        asyncio.run(d._ramp_probe({}))


def test_the_probe_finds_live_targets_and_always_stops_the_cycle(tmp_path):
    peak = HeaterPeak(takes_live=True)
    d = daemon(tmp_path, peak)
    d.status["operating_state_id"] = IDLE
    original_start = peak.start_heat_cycle

    async def start():
        await original_start()
        d.status["operating_state_id"] = ACTIVE
        d.status["temp_f"] = 545.0  # the heater following the new target

    peak.start_heat_cycle = start
    report = asyncio.run(d._ramp_probe({"confirm": True}))
    assert report["method"] == "live" and report["readback_f"] == 545.0
    assert ("stop",) in peak.calls and peak.calls[-1] == ("target", 520.0)
    assert load_config()["ramp_method"] == "live" and load_config()["ramp_probed"] is True


def test_a_peak_that_ignores_live_targets_gets_boost(tmp_path):
    peak = HeaterPeak(takes_live=False)
    d = daemon(tmp_path, peak)
    d.status["operating_state_id"] = IDLE
    original_start = peak.start_heat_cycle

    async def start():
        await original_start()
        d.status["operating_state_id"] = ACTIVE
        d.status["temp_f"] = 521.0

    peak.start_heat_cycle = start
    assert asyncio.run(d._ramp_probe({"confirm": True}))["method"] == "boost"
    assert ("stop",) in peak.calls
