import asyncio
import random

import cbor2
import pytest

import quickpuff.daemon as daemon_mod
from quickpuff import saved_lights
from quickpuff.constants import OperatingState
from quickpuff.daemon import QuickPuffDaemon
from quickpuff.moods import ADVANCED_STYLES, PALETTES, surprise_pick
from quickpuff.paths import load_config
from quickpuff.utils import PuffcoUtils

PREHEAT = int(OperatingState.HEAT_CYCLE_PREHEAT)
ACTIVE = int(OperatingState.HEAT_CYCLE_ACTIVE)
IDLE = int(OperatingState.IDLE)


# ------------------------------------------------------------- the pick

def test_pick_is_a_built_in_palette_and_a_lively_tempo():
    look = surprise_pick(random.Random(1), advanced=True, saved_ids=[])
    assert look["colors"] in PALETTES.values()
    assert 0.35 <= look["tempo"] <= 0.7
    assert look["key"].startswith(look["style"] + "/")


def test_old_firmware_never_gets_lava_or_confetti():
    rng = random.Random(2)
    styles = {surprise_pick(rng, advanced=False, saved_ids=[])["style"] for _ in range(300)}
    assert styles and not styles & set(ADVANCED_STYLES)


def test_never_the_same_look_twice_in_a_row():
    rng = random.Random(3)
    last = None
    for _ in range(200):
        look = surprise_pick(rng, advanced=True, saved_ids=["a1"], last=last)
        assert look["key"] != last
        last = look["key"]


def test_saved_lights_come_up_sometimes():
    rng = random.Random(4)
    picks = [surprise_pick(rng, advanced=True, saved_ids=["a1", "b2"]) for _ in range(400)]
    saved = [p for p in picks if "saved" in p]
    assert 40 < len(saved) < 160
    assert {p["saved"] for p in saved} == {"a1", "b2"}


def test_a_lone_saved_light_that_just_played_gives_way_to_a_cycle():
    rng = random.Random(5)
    rng.random = lambda: 0.0  # always reach for saved lights
    look = surprise_pick(rng, advanced=True, saved_ids=["a1"], last="saved/a1")
    assert "saved" not in look and look["colors"] in PALETTES.values()


# ------------------------------------------------------------- the daemon

class FakePeak:
    is_connected = True

    def __init__(self, raw: bytes, api: str = "AW"):
        self.raw = {1: raw}
        self.api = PuffcoUtils.revision_string_to_number(api)
        self.cycles = []

    async def get_current_profile(self):
        return 1

    async def get_profile_colour_raw(self, index=None):
        return self.raw[index]

    async def get_api_version(self):
        return self.api

    async def set_profile_cycle(self, index, style, colors, tempo, *, inhale=False):
        self.cycles.append((index, style, colors, tempo))
        self.raw[index] = cbor2.dumps({"style": style, "colors": colors})

    async def set_profile_light_raw(self, index, raw):
        self.raw[index] = raw


@pytest.fixture(autouse=True)
def no_delays(monkeypatch):
    monkeypatch.setattr(daemon_mod, "SURPRISE_DELAY_S", 0)
    monkeypatch.setattr(daemon_mod, "QTIP_REMINDER_DELAY_S", 0)


def daemon(tmp_path, peak):
    d = QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d._desktop_notify = lambda *a, **k: None
    d.device = peak
    d.status["profiles"] = [{"index": 1, "name": "High"}]
    return d


def session(d):
    async def go():
        await d._track_session_end(PREHEAT, ACTIVE)
        await d._track_session_end(ACTIVE, IDLE)
        await asyncio.gather(*list(d._tasks))

    asyncio.run(go())


def test_off_by_default_and_leaves_the_light_alone(tmp_path):
    peak = FakePeak(b"\xa1\x61x\x01")
    d = daemon(tmp_path, peak)
    assert d.status["surprise_light"] is False
    session(d)
    assert peak.cycles == []


def test_saves_your_light_first_then_changes_it(tmp_path):
    original = b"\xa1\x65moods\x01"  # stands in for an exclusive mood
    peak = FakePeak(original)
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_surprise(True))
    assert load_config()["surprise_light"] is True

    session(d)
    names = {x["name"]: x["id"] for x in saved_lights.listing()}
    assert names == {"High before Surprise": saved_lights.light_id(original)}
    assert peak.raw[1] != original

    # Its own pick isn't saved again the next time round.
    session(d)
    assert len(saved_lights.listing()) == 1


def test_never_picks_the_light_already_on(tmp_path):
    original = b"\xa1\x65moods\x01"
    peak = FakePeak(original)
    d = daemon(tmp_path, peak)
    d._surprise_rng.random = lambda: 0.0  # always reach for saved lights
    asyncio.run(d._set_surprise(True))
    for _ in range(5):
        before = peak.raw[1]
        session(d)
        assert peak.raw[1] != before


def test_wont_replace_a_light_it_couldnt_save(tmp_path, monkeypatch):
    peak = FakePeak(b"\xa1\x61y\x02")
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_surprise(True))

    def full(name, raw):
        raise ValueError("You can keep up to 24 saved lights; delete one first")

    monkeypatch.setattr(saved_lights, "save", full)
    session(d)
    assert peak.cycles == []
    assert peak.raw[1] == b"\xa1\x61y\x02"


def test_aborted_preheat_changes_nothing(tmp_path):
    peak = FakePeak(b"\xa1\x61z\x03")
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_surprise(True))

    async def go():
        await d._track_session_end(IDLE, PREHEAT)
        await d._track_session_end(PREHEAT, IDLE)
        await asyncio.gather(*list(d._tasks))

    asyncio.run(go())
    assert peak.cycles == []
