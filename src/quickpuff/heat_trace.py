"""The chamber's temperature over one heat cycle, for the panel's heat graph.

The daemon polls every 0.7 s while the Peak heats, panel open or not, so it
records the curve itself; opening the panel mid-session still shows the whole
climb. A trace starts when a cycle does and stays readable after it ends, as
"last session", until the next one begins.
"""

from __future__ import annotations

from typing import Any

from .constants import OperatingState

PREHEAT = int(OperatingState.HEAT_CYCLE_PREHEAT)
ACTIVE = int(OperatingState.HEAT_CYCLE_ACTIVE)
FADE = int(OperatingState.HEAT_CYCLE_FADE)
CYCLE = {PREHEAT, ACTIVE, FADE}

# One point a second is plenty for a curve a few hundred pixels wide.
STEP_S = 1.0
# Past this many points, every other one is dropped (a long session stays whole).
MAX_POINTS = 360


class HeatTrace:
    def __init__(self) -> None:
        self.points: list[list[float]] = []
        self.started: float | None = None
        self.ready_at: float | None = None
        self.fade_at: float | None = None
        self.target_f: float | None = None
        self.active = False

    def update(self, prev_state: Any, new_state: Any, temp_f: Any, now: float, target_f: Any = None) -> None:
        in_cycle = new_state in CYCLE
        if in_cycle and (not self.active or prev_state not in CYCLE):
            self._start(now, target_f)
        if not self.active:
            return
        if not in_cycle:
            # The cycle is over; keep the curve as the last session.
            self.active = False
            return
        elapsed = now - self.started if self.started is not None else 0.0
        if new_state == ACTIVE and self.ready_at is None:
            self.ready_at = round(elapsed, 1)
        if new_state == FADE and self.fade_at is None:
            self.fade_at = round(elapsed, 1)
        try:
            temp = float(temp_f)
        except (TypeError, ValueError):
            return
        if self.points and elapsed - self.points[-1][0] < STEP_S:
            return
        self.points.append([round(elapsed, 1), round(temp, 1)])
        if len(self.points) > MAX_POINTS:
            self.points = self.points[::2]

    def _start(self, now: float, target_f: Any) -> None:
        self.points = []
        self.started = now
        self.ready_at = None
        self.fade_at = None
        self.active = True
        try:
            self.target_f = float(target_f) if target_f is not None else None
        except (TypeError, ValueError):
            self.target_f = None

    def as_status(self) -> dict[str, Any] | None:
        if not self.points:
            return None
        return {
            "points": [list(p) for p in self.points],
            "target_f": self.target_f,
            "ready_at": self.ready_at,
            "fade_at": self.fade_at,
            "active": self.active,
        }
