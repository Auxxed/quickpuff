"""The tempo of what's playing, from the desktop's audio.

Fed 16-bit mono samples at RATE (from `pw-record --raw` on the output's
monitor), it follows the bass's energy in 25 ms frames, turns rises in it into
an onset curve, and finds the tempo as the strongest repeat in the last eight
seconds of that curve. Pure Python, a few milliseconds of work per second of
audio; nothing is kept beyond the last eight seconds of frame energies.
"""

from __future__ import annotations

import array
import math
from collections import deque

RATE = 8000
FRAME = 200                    # 25 ms
FPS = RATE / FRAME             # 40 frames a second
WINDOW_FRAMES = int(8 * FPS)   # eight seconds
MIN_BPM, MAX_BPM = 70.0, 180.0
SILENCE_RMS = 120.0            # of 32768: below this it's not music


class BeatTracker:
    def __init__(self) -> None:
        self._low = 0.0
        self._alpha = 1 - math.exp(-2 * math.pi * 150 / RATE)   # one-pole low-pass at 150 Hz
        self._partial = array.array("h")
        self._carry = b""
        self.energy: deque[float] = deque(maxlen=WINDOW_FRAMES)
        self.onsets: deque[float] = deque(maxlen=WINDOW_FRAMES)
        self.rms: deque[float] = deque(maxlen=int(2 * FPS))

    def feed(self, data: bytes) -> None:
        data = self._carry + data
        whole = len(data) // 2 * 2
        self._carry = data[whole:]
        samples = array.array("h")
        samples.frombytes(data[:whole])
        self._partial.extend(samples)
        while len(self._partial) >= FRAME:
            frame, self._partial = self._partial[:FRAME], self._partial[FRAME:]
            self._frame(frame)

    def _frame(self, frame: array.array) -> None:
        low, a = self._low, self._alpha
        bass = 0.0
        loud = 0.0
        for x in frame:
            low += a * (x - low)
            bass += low * low
            loud += x * x
        self._low = low
        self.rms.append(math.sqrt(loud / FRAME))
        level = math.log1p(bass / FRAME)
        last = self.energy[-1] if self.energy else level
        self.energy.append(level)
        self.onsets.append(max(0.0, level - last))

    @property
    def playing(self) -> bool:
        """Music (not silence) over the last second or two."""
        return len(self.rms) >= FPS and sum(self.rms) / len(self.rms) > SILENCE_RMS

    def tempo(self) -> tuple[float, float] | None:
        """(beats per minute, confidence 0-1) from the last eight seconds, or
        None without enough music to tell."""
        if not self.playing or len(self.onsets) < WINDOW_FRAMES * 0.75:
            return None
        curve = list(self.onsets)
        mean = sum(curve) / len(curve)
        curve = [c - mean for c in curve]
        power = sum(c * c for c in curve)
        if power <= 1e-9:
            return None
        lo, hi = int(FPS * 60 / MAX_BPM), int(math.ceil(FPS * 60 / MIN_BPM))
        scores = {}
        for lag in range(lo, hi + 1):
            scores[lag] = sum(curve[i] * curve[i + lag] for i in range(len(curve) - lag)) / power
        best = max(scores, key=scores.get)
        # Refine between frames, then prefer the tempo a listener would tap.
        left, mid, right = scores.get(best - 1, 0.0), scores[best], scores.get(best + 1, 0.0)
        bend = (left - right) / (2 * (left - 2 * mid + right)) if (left - 2 * mid + right) else 0.0
        bpm = 60 * FPS / (best + max(-0.5, min(0.5, bend)))
        while bpm < 85:
            bpm *= 2
        while bpm > 160:
            bpm /= 2
        return round(bpm, 1), max(0.0, min(1.0, mid))


# How the lantern dances: a style for the tempo, and the Peak's own tempo
# setting (cycles a minute = tempo² × 480) at one colour cycle per bar.
def dance(bpm: float, beats_per_cycle: float = 4.0) -> tuple[str, float]:
    style = "breathe" if bpm < 95 else "spin" if bpm < 125 else "disco"
    cycles_per_minute = bpm / beats_per_cycle
    return style, round(max(0.1, min(1.0, math.sqrt(cycles_per_minute / 480))), 3)
