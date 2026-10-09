"""The visualiser: finding the tempo in the desktop's audio, and the lantern
dancing to it."""

import array
import asyncio
import math

import pytest

from quickpuff import beat
from quickpuff.daemon import QuickPuffDaemon


def kicks(bpm, seconds=10.0, rate=beat.RATE):
    """A kick drum on every beat (a decaying 60 Hz thump), 16-bit mono."""
    out = array.array("h", [0]) * int(seconds * rate)
    period = 60.0 / bpm
    t = 0.0
    while t < seconds:
        start = int(t * rate)
        for i in range(int(0.12 * rate)):
            if start + i >= len(out):
                break
            out[start + i] = int(20000 * math.exp(-i / (0.03 * rate)) * math.sin(2 * math.pi * 60 * i / rate))
        t += period
    return out.tobytes()


@pytest.mark.parametrize("bpm", [90, 100, 128, 150])
def test_finds_the_tempo_of_a_kick_drum(bpm):
    tracker = beat.BeatTracker()
    data = kicks(bpm)
    for i in range(0, len(data), 1601):  # odd chunks: samples split across reads
        tracker.feed(data[i:i + 1601])
    found, confidence = tracker.tempo()
    assert abs(found - bpm) < 2.5 and confidence > 0.3


def test_silence_has_no_tempo():
    tracker = beat.BeatTracker()
    tracker.feed(bytes(beat.RATE * 2 * 10))
    assert not tracker.playing and tracker.tempo() is None


def test_dance_picks_a_style_and_the_peaks_tempo_setting():
    assert beat.dance(80)[0] == "breathe" and beat.dance(110)[0] == "spin" and beat.dance(140)[0] == "disco"
    style, tempo = beat.dance(120)
    assert math.isclose(tempo * tempo * 480, 120 / 4, rel_tol=0.01)


class LanternPeak:
    is_connected = True

    def __init__(self):
        self.lights = []

    async def get_lantern_light_raw(self):
        return b"\xa0"

    async def set_lantern_light(self, colors, *, style="fade", tempo=0.3, show=False):
        self.lights.append((list(colors), style, tempo, show))

    async def set_lantern_light_raw(self, raw, *, show=False):
        pass


class Heard:
    def __init__(self, bpm):
        self.bpm = bpm

    def tempo(self):
        return None if self.bpm is None else (self.bpm, 0.9)


def test_the_lantern_dances_while_music_plays(tmp_path, monkeypatch):
    peak = LanternPeak()
    d = QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d.device = peak
    d._keep_listening = lambda: None

    async def no_art():
        return None, ""

    d._music_palette = no_art
    asyncio.run(d._set_ambient("visualizer", True))
    d._beats = Heard(128)
    asyncio.run(d._ambient_step())
    colors, style, tempo, show = peak.lights[-1]
    assert style == "disco" and show is True and len(colors) >= 2
    assert d.status["ambient"]["source"] == "visualizer" and d.status["ambient"]["bpm"] == 128
    assert d.status["lantern"] is True
    # A wobble of a beat or two doesn't rewrite the lantern.
    d._beats = Heard(129)
    asyncio.run(d._ambient_step())
    assert len(peak.lights) == 1
    # The music stops: nothing left to follow, so the lantern's own light returns.
    d._beats = Heard(None)
    asyncio.run(d._ambient_step())
    assert d.status["ambient"] is None
