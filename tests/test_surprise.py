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

    def __init__(self, raw: bytes, api: str = "AW", led_api: int = 3, profile: int = 1):
        self.raw = {profile: raw}
        self.api = PuffcoUtils.revision_string_to_number(api)
        self.led_api = led_api
        self.profile = profile
        self.cycles = []
        self.inhale = []

    async def get_current_profile(self):
        return self.profile

    async def get_profile_colour_raw(self, index=None):
        return self.raw[index]

    async def get_api_version(self):
        return self.api

    async def get_led_api(self):
        return self.led_api

    async def set_profile_cycle(self, index, style, colors, tempo, *, inhale=False):
        self.cycles.append((index, style, colors, tempo))
        self.inhale.append(inhale)
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


def test_old_single_colour_firmware_is_left_alone(tmp_path):
    # LED API 2 takes one colour per profile: no cycle, no saved light, and
    # nothing saved to My lights for a change that can't happen.
    peak = FakePeak(b"\xff\x00\x00\x00\x00\x00\x00\x00", api="AE", led_api=2)
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_surprise(True))
    session(d)
    assert peak.cycles == []
    assert saved_lights.listing() == []


def test_custom_temperatures_have_no_light_to_change(tmp_path):
    peak = FakePeak(b"\xa1\x61x\x01", profile=-1)
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_surprise(True))
    session(d)
    assert peak.cycles == []
    assert saved_lights.listing() == []


class DroppingPeak(FakePeak):
    async def get_api_version(self):
        self.is_connected = False
        raise RuntimeError("Client not connected")


def test_a_link_dropping_mid_way_is_logged_not_raised(tmp_path, caplog):
    peak = DroppingPeak(b"\xa1\x61x\x01")
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_surprise(True))
    tasks = []

    async def go():
        await d._track_session_end(PREHEAT, ACTIVE)
        await d._track_session_end(ACTIVE, IDLE)
        tasks.extend(d._tasks)
        await asyncio.gather(*tasks, return_exceptions=True)

    asyncio.run(go())
    assert all(t.exception() is None for t in tasks)
    assert peak.cycles == []
    assert "couldn't change the light" in caplog.text
    # The light was saved before the drop, so it's still safe.
    assert len(saved_lights.listing()) == 1


class GarbledPeak(FakePeak):
    async def get_profile_colour_raw(self, index=None):
        raise cbor2.CBORDecodeError("premature end of stream")


def test_a_light_that_wont_decode_is_logged_not_raised(tmp_path, caplog):
    peak = GarbledPeak(b"")
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_surprise(True))
    session(d)
    assert peak.cycles == []
    assert "couldn't change the light" in caplog.text


def inhale_light():
    raw = cbor2.dumps({"inhale": True})
    saved_lights.remember_cycle(raw, {"style": "fade", "colors": ["#ff0000"], "tempo": 0.5, "inhale": True})
    return raw


def test_a_light_that_followed_your_inhale_still_does(tmp_path):
    peak = FakePeak(inhale_light(), api="AW")
    d = daemon(tmp_path, peak)
    d._surprise_rng.random = lambda: 1.0  # always a fresh cycle
    asyncio.run(d._set_surprise(True))
    session(d)
    assert peak.inhale == [True]
    assert d.status["profiles"][0]["cycle"]["inhale"] is True


def test_inhale_stays_off_before_ag_firmware(tmp_path):
    peak = FakePeak(inhale_light(), api="AF")
    d = daemon(tmp_path, peak)
    d._surprise_rng.random = lambda: 1.0
    asyncio.run(d._set_surprise(True))
    session(d)
    assert peak.inhale == [False]
    assert d.status["profiles"][0]["cycle"]["inhale"] is False


def test_a_plain_light_gets_a_plain_cycle(tmp_path):
    peak = FakePeak(b"\xa1\x61x\x01")
    d = daemon(tmp_path, peak)
    d._surprise_rng.random = lambda: 1.0
    asyncio.run(d._set_surprise(True))
    session(d)
    assert peak.inhale == [False]


def test_a_saved_pick_shows_its_own_colours_straight_away(tmp_path):
    mine = cbor2.dumps({"saved": 1})
    saved_lights.remember_cycle(mine, {"style": "spin", "colors": ["#00ff00", "#0000ff"], "tempo": 0.5, "inhale": False})
    entry = saved_lights.save("Mine", mine)
    peak = FakePeak(b"\xa1\x61x\x01")
    d = daemon(tmp_path, peak)
    d.status["profiles"][0].update(color="#ff0000", cycle=None)
    d._surprise_rng.random = lambda: 0.0  # always reach for saved lights
    asyncio.run(d._set_surprise(True))
    session(d)
    profile = d.status["profiles"][0]
    assert peak.raw[1] == mine
    assert profile["light_id"] == entry["id"]
    assert profile["color"] == "#00ff00"
    assert profile["cycle"]["style"] == "spin"
