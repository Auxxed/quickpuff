"""Slow trends that say how the Peak is wearing: heat-up time and battery per dab.

Both come from history QuickPuff already keeps, so they cover the months
before this was added.

- **Heat-up** uses the real preheat times from the Peak's own log. Only cold
  starts count (a chamber still warm from the last dab heats faster), and
  each is scaled to one reference temperature so changing a profile's heat
  doesn't read as wear. A heat-up that creeps up over months points at the
  atomizer or a dirty chamber.
- **Battery per dab** is the charge a dab took: from just before it heated
  to just after, for dabs QuickPuff watched from the start. Older dabs fall
  back to two post-dab readings close together with exactly one dab between,
  which also counts a little idle drain. A rising cost is the battery
  losing capacity under load.

Each trend compares the earliest sessions with the latest, and stays
"learning" until there are enough of both to say anything.
"""

from __future__ import annotations

import statistics
from bisect import bisect_right
from datetime import datetime
from itertools import pairwise
from typing import Any

# Ambient the chamber starts from, for scaling one heat-up to another temperature.
AMBIENT_C = 22.0
# A dab this soon after the last one starts with a warm chamber.
WARM_GAP_S = 15 * 60
HEATUP_BASELINE = 20
HEATUP_RECENT = 15
# Past this the change is more than session-to-session noise (about 5% here).
HEATUP_SHIFT = 0.12

# Two post-dab readings further apart than this mostly measure idle drain
# (an open link alone costs about 3% an hour).
BATTERY_MAX_GAP_S = 90 * 60
BATTERY_BASELINE = 10
BATTERY_RECENT = 10
BATTERY_SHIFT = 0.2

MONTHS_SHOWN = 6


def _c_to_f(c: float) -> int:
    return round(c * 9 / 5 + 32)


def _month(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m")


def _months(points: list[tuple[float, float]], digits: int) -> list[dict[str, Any]]:
    by_month: dict[str, list[float]] = {}
    for ts, value in points:
        by_month.setdefault(_month(ts), []).append(value)
    return [
        {"month": m, "value": round(statistics.median(v), digits), "n": len(v)}
        for m, v in sorted(by_month.items())[-MONTHS_SHOWN:]
    ]


def _verdict(points: list[tuple[float, float]], baseline_n: int, recent_n: int, shift: float, digits: int) -> dict[str, Any]:
    values = [v for _, v in points]
    out: dict[str, Any] = {
        "state": "learning",
        "samples": len(values),
        "needed": baseline_n + recent_n,
        "recent": round(statistics.median(values[-recent_n:]), digits) if values else None,
        "baseline": None,
        "change_pct": None,
        "since": None,
        "months": _months(points, digits),
    }
    if len(values) < baseline_n + recent_n:
        return out
    baseline = statistics.median(values[:baseline_n])
    recent = statistics.median(values[-recent_n:])
    change = recent / baseline - 1 if baseline else 0.0
    out.update(
        baseline=round(baseline, digits),
        change_pct=round(change * 100),
        since=points[0][0],
        state="up" if change >= shift else "down" if change <= -shift else "steady",
    )
    return out


def heatup(device_sessions: list[dict]) -> dict[str, Any]:
    """Cold-start heat-up seconds, scaled to the temperature you use now."""
    cold: list[tuple[float, float, float]] = []
    previous = None
    for s in sorted(device_sessions, key=lambda s: float(s["ts"])):
        ts = float(s["ts"])
        warm = previous is not None and ts - previous < WARM_GAP_S
        previous = ts
        try:
            preheat, temp_c = float(s["preheat_s"]), float(s["temp_c"])
        except (KeyError, TypeError, ValueError):
            continue
        if warm or preheat <= 0 or temp_c <= AMBIENT_C + 50:
            continue
        cold.append((ts, preheat, temp_c))
    if not cold:
        out = _verdict([], HEATUP_BASELINE, HEATUP_RECENT, HEATUP_SHIFT, 1)
        out["ref_temp_f"] = None
        return out
    ref_c = statistics.median(t for _, _, t in cold[-30:])
    points = [(ts, p * (ref_c - AMBIENT_C) / (t - AMBIENT_C)) for ts, p, t in cold]
    out = _verdict(points, HEATUP_BASELINE, HEATUP_RECENT, HEATUP_SHIFT, 1)
    out["ref_temp_f"] = _c_to_f(ref_c)
    return out


def battery_per_dab(events: list[dict], device_sessions: list[dict]) -> dict[str, Any]:
    """Percent of the pack each dab costs."""
    measured = [e for e in events if isinstance(e.get("battery"), (int, float)) and e.get("ts") is not None]
    points: list[tuple[float, float]] = []
    for e in measured:
        start = e.get("battery_start")
        if isinstance(start, (int, float)) and start > e["battery"]:
            points.append((float(e["ts"]), float(start - e["battery"])))
    readings = sorted((float(e["ts"]), int(e["battery"])) for e in measured if "battery_start" not in e)
    starts = sorted(float(s["ts"]) for s in device_sessions) or sorted(
        float(e["ts"]) for e in events if e.get("ts") is not None
    )
    for (t0, b0), (t1, b1) in pairwise(readings):
        drop = b0 - b1
        if drop <= 0 or t1 - t0 > BATTERY_MAX_GAP_S:
            continue  # charged in between, or long enough for idle drain to blur it
        if bisect_right(starts, t1) - bisect_right(starts, t0) != 1:
            continue
        points.append((t1, float(drop)))
    points.sort()
    return _verdict(points, BATTERY_BASELINE, BATTERY_RECENT, BATTERY_SHIFT, 1)


def trends(data: dict[str, Any]) -> dict[str, Any]:
    device = data.get("device_sessions") or []
    return {
        "heatup": heatup(device),
        "battery": battery_per_dab(data.get("events") or [], device),
    }
