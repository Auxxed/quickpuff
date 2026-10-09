"""A pretend heat cycle, for showing QuickPuff off without heating anything.

`quickpuff demo` has the daemon play one of these over the Peak's own
readings, so the bar, the panel and the overlays go through a session exactly
as they would for a real one. This module is only the maths: given the run's
settings and the seconds since it began, what would the Peak be reporting?
There is no randomness in it, so every take looks the same.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from .constants import (
    OPERATING_STATE_LABELS,
    BatteryChargeSource,
    BatteryChargeState,
    ChamberType,
    OperatingState,
)
from .heat_trace import HeatTrace
from .product_info import get_product_info
from .utils import PuffcoUtils

PREHEAT = int(OperatingState.HEAT_CYCLE_PREHEAT)
ACTIVE = int(OperatingState.HEAT_CYCLE_ACTIVE)
FADE = int(OperatingState.HEAT_CYCLE_FADE)
IDLE = int(OperatingState.IDLE)

# A chamber at room temperature, where a cold Peak starts from.
ROOM_F = 80.0
# After the fade, a few seconds of plain idle while the chamber keeps cooling,
# so a take ends on a settled Peak rather than mid-fade.
IDLE_S = 4.0
# Once the heater lets go, the chamber sheds heat toward the room on roughly
# this time constant: a clear fall without crashing to cold.
COOL_TAU_S = 25.0
# At temperature the heater hunts around the target. Two slow waves (°F,
# period in seconds) that never line up, adding to a little over ±4°F.
WOBBLE = ((3.0, 7.0), (1.2, 2.9))
# What a session costs the battery, drained as the heater works.
BATTERY_DIP = 4


@dataclass(frozen=True)
class DemoRun:
    preheat_s: float = 12.0
    session_s: float = 20.0
    cooldown_s: float = 6.0
    target_f: float = 530.0
    start_f: float = ROOM_F

    @property
    def ready_at(self) -> float:
        return self.preheat_s

    @property
    def fade_at(self) -> float:
        return self.preheat_s + self.session_s

    @property
    def idle_at(self) -> float:
        return self.fade_at + self.cooldown_s

    @property
    def length_s(self) -> float:
        """Start to finish, the idle cooling included."""
        return self.idle_at + IDLE_S


def _preheat_f(run: DemoRun, t: float) -> float:
    # Eases out: the heater climbs hard from cold, then slows as it closes on
    # the target, reaching it within ~2°F only in the last moments of preheat.
    p = min(1.0, t / run.preheat_s) if run.preheat_s > 0 else 1.0
    return run.start_f + (run.target_f - run.start_f) * (1 - (1 - p) ** 2)


def _wobble_f(u: float) -> float:
    # Zero at the moment it's ready, so the hand-off from preheat is seamless;
    # the first swing is a small overshoot.
    return sum(amp * math.sin(2 * math.pi * u / period) for amp, period in WOBBLE)


def _cooling_f(run: DemoRun, t: float) -> float:
    released = run.target_f + _wobble_f(run.session_s)
    return ROOM_F + (released - ROOM_F) * math.exp(-(t - run.fade_at) / COOL_TAU_S)


def sample(run: DemoRun, elapsed: float) -> dict[str, Any] | None:
    """What the Peak would report `elapsed` seconds in; None once it's over.

    The timer fields follow the Peak's own: seconds in the current state and
    that state's planned length, reported only through the heat cycle.
    """
    t = max(0.0, float(elapsed))
    if t >= run.length_s:
        return None
    if t < run.ready_at:
        phase, state, temp = "preheat", PREHEAT, _preheat_f(run, t)
        timer = (t, run.preheat_s)
    elif t < run.fade_at:
        u = t - run.ready_at
        phase, state, temp = "session", ACTIVE, run.target_f + _wobble_f(u)
        timer = (u, run.session_s)
    elif t < run.idle_at:
        phase, state, temp = "fade", FADE, _cooling_f(run, t)
        timer = (t - run.fade_at, run.cooldown_s)
    else:
        phase, state, temp = "idle", IDLE, _cooling_f(run, t)
        timer = None
    return {
        "phase": phase,
        "operating_state_id": state,
        "operating_state": OPERATING_STATE_LABELS[OperatingState(state)],
        "heater_temp_f": round(temp, 1),
        "state_elapsed_s": round(timer[0], 2) if timer else None,
        "state_total_s": timer[1] if timer else None,
    }


def heat_trace(run: DemoRun, elapsed: float) -> dict[str, Any] | None:
    """The panel's heat graph for the run so far, recorded by a real HeatTrace.

    Rebuilt from the start each time, a sample a second plus the moments the
    phases change, so the curve is the same however late a tick lands.
    """
    upto = min(max(0.0, float(elapsed)), run.length_s)
    moments = {float(s) for s in range(int(upto) + 1)}
    moments |= {m for m in (run.ready_at, run.fade_at, run.idle_at) if m <= upto}
    trace = HeatTrace()
    prev = IDLE
    for t in sorted(moments):
        now = sample(run, t)
        if now is None:
            break
        trace.update(prev, now["operating_state_id"], now["heater_temp_f"], t, run.target_f)
        prev = now["operating_state_id"]
    return trace.as_status()


def battery_at(run: DemoRun, start: int, elapsed: float) -> int:
    """The charge shown `elapsed` seconds in: a few percent spent while heating."""
    heating = run.preheat_s + run.session_s
    used = BATTERY_DIP * min(1.0, max(0.0, float(elapsed)) / heating) if heating > 0 else 0.0
    return max(1, int(start) - int(used + 0.5))


# With no real Peak to borrow, a demo shows this one: a stock Peak Pro Onyx
# wearing its four factory heat profiles, the third one selected.
STOCK_NAME = "QuickPuff"
STOCK_BATTERY = 87
STOCK_PROFILE = 2
STOCK_PROFILES = (
    # name (as the panel's Tips list them), °F, the colour its lights glow
    ("Low", 490, "#3b9eff"),
    ("Med", 510, "#3dd68c"),
    ("High", 530, "#ff4d4d"),
    ("Peak", 545, "#ffffff"),
)
STOCK_TIME_S = 45
STOCK_PRODUCT_CODE = 71  # Onyx


def stock_profile(index: int) -> dict[str, Any]:
    name, temp_f, color = STOCK_PROFILES[index]
    return {
        "index": index,
        "name": name,
        "temp_c": round(PuffcoUtils.f_to_c(temp_f), 1),
        "temp_f": temp_f,
        "time": STOCK_TIME_S,
        "color": color,
        "cycle": None,
        "light_id": None,
        "vapor": "smooth",
        "vapor_level": 0.0,
        "boost_temp_f": 10.0,
        "boost_time": 15.0,
    }


def stock_peak() -> dict[str, Any]:
    """The fields that make a status read as that stock Peak, connected."""
    info = get_product_info(product_code=STOCK_PRODUCT_CODE)
    product = info.to_dict() if info else {}
    if info:
        product["model_code"] = info.model_codes[0]
    return {
        "connected": True,
        "device_name": STOCK_NAME,
        "device_mac": "",
        "product": product,
        "battery": STOCK_BATTERY,
        "charge_state": "Unplugged",
        "charge_state_id": int(BatteryChargeState.DONE_DISCONNECTED),
        "charge_source": "Unplugged",
        "charge_source_id": int(BatteryChargeSource.NONE),
        "charge_eta_s": None,
        "chamber": "3D",
        "chamber_id": int(ChamberType.THREE_D),
        "dabs_remaining": 26,
        "current_profile": STOCK_PROFILE,
        "profiles": [stock_profile(i) for i in range(len(STOCK_PROFILES))],
    }
