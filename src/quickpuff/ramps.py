"""Heat ramps: a session that changes temperature as it goes.

A ramp is a few steps, each "this many seconds after Ready, go to the
profile's temperature plus (or minus) this much". The daemon plays them while
the session runs: start low for flavour and climb for clouds, or swell and
ease off. Nothing here talks to the Peak.

Two ways to move the heater mid-session, picked per Peak by `quickpuff ramp
probe` (which runs one short test cycle):

- "live": write a new target to the running heat cycle (/p/app/thc/temp).
  Steps can go up or down.
- "boost": the Peak's own Boost, sized to the step. Up only, by at most
  36 °F at a time, and it is what every Peak accepts mid-session, so it's the
  default until a probe shows live targets work.
"""

from __future__ import annotations

from typing import Any

MIN_TEMP_F, MAX_TEMP_F = 400.0, 620.0
MAX_BOOST_STEP_F = 36.0
MAX_STEPS = 8
MAX_STEP_AT_S = 120.0
METHODS = ("live", "boost")

# Offsets (°F) from the profile's own temperature, seconds after Ready.
PRESETS: dict[str, dict[str, Any]] = {
    "rise": {"label": "Rise", "line": "Starts at your temperature, climbs 20 then 40 °F", "steps": [(15, 20), (30, 40)]},
    "cloud": {"label": "Cloud climb", "line": "Up 15, then 30, then 45 °F: big finish", "steps": [(10, 15), (20, 30), (30, 45)]},
    "wave": {"label": "Wave", "line": "Swells 30 °F and eases back, twice", "steps": [(10, 30), (20, 0), (30, 30), (40, 0)]},
    "low": {"label": "Low & slow", "line": "Drops 40 °F for flavour, comes back up by the end", "steps": [(0, -40), (20, -20), (35, 0)]},
}


def preset_names() -> list[str]:
    return list(PRESETS)


def parse_steps(spec: list[str]) -> list[tuple[float, float]]:
    """Custom steps from the command line: "15:+20" (seconds:offset °F)."""
    steps = []
    for item in spec:
        at, sep, offset = str(item).partition(":")
        if not sep:
            raise ValueError(f"Step {item!r}: write it as seconds:offset, like 15:+20")
        steps.append((float(at), float(offset)))
    return normalize(steps)


def normalize(steps: list[Any]) -> list[tuple[float, float]]:
    """Steps in time order, each within bounds, at most MAX_STEPS. Raises
    ValueError for anything that isn't a list of (seconds, offset) pairs."""
    out = []
    for step in steps:
        if not isinstance(step, (list, tuple)) or len(step) != 2:
            raise ValueError("A ramp step is a pair: seconds after Ready, offset in °F")
        at, offset = float(step[0]), float(step[1])
        if not (0 <= at <= MAX_STEP_AT_S and -150 <= offset <= 150):
            raise ValueError(f"Step {at:g}s {offset:+g}°F is out of range (0–{MAX_STEP_AT_S:g} s, ±150 °F)")
        out.append((round(at, 1), round(offset, 1)))
    if not out:
        raise ValueError("A ramp needs at least one step")
    if len(out) > MAX_STEPS:
        raise ValueError(f"A ramp has at most {MAX_STEPS} steps")
    return sorted(out)


def steps_for(choice: Any) -> list[tuple[float, float]] | None:
    """A stored ramp (a preset name or custom steps) as steps, or None."""
    if isinstance(choice, str):
        preset = PRESETS.get(choice)
        return None if preset is None else normalize(preset["steps"])
    if isinstance(choice, list):
        try:
            return normalize(choice)
        except (TypeError, ValueError):
            return None
    return None


def plan(steps: list[tuple[float, float]], base_f: float, method: str, session_s: float | None = None) -> list[dict[str, Any]]:
    """What to do and when: one action per step that changes something.

    Each action is {"at": s, "target_f": °F, "boost_f": °F (boost only)},
    targets clamped to the Peak's range. With "boost", a step can only add to
    the base temperature (a boost doesn't stack on a boost: each one is sized
    from the base), downward steps are dropped, and each boost lasts until
    the next step or the end of the session. Steps past the session's end
    are dropped."""
    if method not in METHODS:
        raise ValueError(f"Unknown ramp method {method!r}")
    actions: list[dict[str, Any]] = []
    current = base_f
    for i, (at, offset) in enumerate(steps):
        if session_s is not None and at >= session_s:
            break
        target = min(MAX_TEMP_F, max(MIN_TEMP_F, base_f + offset))
        if method == "boost":
            target = min(target, base_f + MAX_BOOST_STEP_F)
            if target <= base_f + 0.5:
                if current > base_f:
                    # Back to base: a boost simply runs out; nothing to send.
                    current = base_f
                continue
            nxt = steps[i + 1][0] if i + 1 < len(steps) else (session_s or at + 30)
            actions.append({"at": at, "target_f": round(target, 1), "boost_f": round(target - base_f, 1),
                            "boost_s": round(max(1.0, min(60.0, nxt - at)), 1)})
        elif abs(target - current) >= 0.5:
            actions.append({"at": at, "target_f": round(target, 1)})
        current = target
    return actions


def describe(choice: Any) -> dict[str, Any] | None:
    """For the status and panel: the ramp's name, a line about it, its steps."""
    steps = steps_for(choice)
    if steps is None:
        return None
    if isinstance(choice, str):
        preset = PRESETS[choice]
        return {"key": choice, "label": preset["label"], "line": preset["line"], "steps": [list(s) for s in steps]}
    line = ", ".join(f"{at:g}s {off:+g}°F" for at, off in steps)
    return {"key": "custom", "label": "Custom", "line": line, "steps": [list(s) for s in steps]}
