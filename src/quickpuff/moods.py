"""Colour-cycle lights, built the way the official Puffco app builds its moods.

Every style ports the app's own mood definition for the Peak Pro (its
"peach" projector): the formulas that turn a colour list and a tempo into the
lamp the Peak animates by itself. Once written, a cycling profile costs no
Bluetooth traffic.

- pikaled2 lamps (Fade, Spin, Disco, Split, Fill, and the older Breathe) play
  a table of colours blended by the app's `lchycle`, ported exactly below.
- migrtn1 lamps (Lava Lamp, Confetti) run a particle simulation on the Peak
  itself and need firmware AF or newer.

`decode_cycle` reads a lamp back into style, colours and tempo.
"""

from __future__ import annotations

import math
import sys
from typing import Any

from .lights import normalize_color

STEPS_PER_COLOR = 5
MAX_COLORS = 6
BLACK = "#000000"

STYLES = ("fade", "spin", "breathe", "disco", "split", "fill", "lava", "confetti")
# migrtn1 styles: the app offers them from firmware AF.
ADVANCED_STYLES = ("lava", "confetti")
# Colours each style's editor accepts in the app (Breathe from app 2.4.3).
MIN_COLORS = {"spin": 1}

_ALIASES = {
    "breathing": "breathe",
    "split_gradient": "split",
    "splitgradient": "split",
    "vertical_slideshow": "fill",
    "verticalslideshow": "fill",
    "slideshow": "fill",
    "lava_lamp": "lava",
    "lavalamp": "lava",
}

DISCO_OFFSETS = [15360, 18773, 1707, 5120, 8533, 11947, 15360, 10240, 10240, 5120, 2844, 1138, 853, 19627, 19342, 17636, 0, 0, 0, 0]
SPLIT_OFFSETS_2 = [0, 0, 0, 0, 0, 0, 7680, 25600, 15360, 7680, 12800, 12800, 17920, 17920, 12800, 12800, 15360, 15360, 15360, 15360]
SPLIT_OFFSETS_4 = [0, 0, 0, 0, 0, 0, 7680, 46080, 15360, 7680, 33280, 33280, 38400, 38400, 33280, 33280, 15360, 15360, 15360, 15360]
SPLIT_OFFSETS_6 = [0, 0, 0, 0, 0, 0, 7680, 66560, 15360, 7680, 53760, 53760, 58880, 58880, 53760, 53760, 15360, 15360, 15360, 15360]
FILL_OFFSETS = [20480, 20480, 20480, 20480, 20480, 20480, 15930, 9100, 11835, 15930, 0, 0, 6825, 6825, 0, 0, 20480, 20480, 20480, 20480]
ZERO_OFFSETS = [0] * 20

# migrtn1: which LEDs each simulated strand lights, and where strands start.
CONFETTI_PATHS = [[[6, 255]], [[13, 255]], [[12, 255]], [[9, 255]], [[8, 255]], [[8, 255]], [[15, 255]], [[11, 127], [14, 127]], [[7, 255]], [[10, 255]], [[-1, 255]], [[-1, 255]], [[10, 127], [11, 127]], [[15, 127], [14, 127]], [[-1, 255]], [[-1, 255]]]
LAVA_PATHS = [[[6, 205], [8, 26], [13, 26]], [[13, 230], [6, 26]], [[12, 230], [9, 26]], [[9, 205], [8, 26], [12, 26]], [[8, 230], [9, 26]], [[8, 230], [6, 26]], [[13, 51], [15, 102], [7, 26], [14, 77]], [[10, 51], [11, 77], [14, 77], [15, 77]], [[7, 255]], [[12, 51], [10, 102], [7, 26], [11, 77]], [[11, 102], [-1, 154]], [[10, 51], [14, 51], [-1, 154]], [[10, 102], [11, 102], [14, 51]], [[15, 102], [14, 102], [11, 51]], [[15, 51], [11, 51], [-1, 154]], [[14, 102], [-1, 154]]]
MIGRATION_SOURCES = [[0, 43], [1, 43], [2, 43], [3, 43], [4, 43], [5, 43]]


def _js_round(value: float) -> int:
    # The app rounds the JavaScript way (half up), not Python's half-even.
    return int(math.floor(value + 0.5))


def _num(value: float) -> int | float:
    # JavaScript numbers carry no int/float split; whole values encode as CBOR ints.
    return int(value) if float(value).is_integer() else float(value)


# ------------------------------------------------------------------ lchycle
# A port of the app's colour module: sRGB <-> CIE LCh(uv), and `lchycle`,
# which blends a looping colour cycle through CIELUV with a piecewise cubic.

_EPS = sys.float_info.epsilon
_KAPPA = 903.2962962962963
_EPSILON = 0.008856451679035631
_REF_U = 0.197839824821408
_REF_V = 0.46833630293241


def _max_chroma(lightness: float, hue: float) -> float:
    l = min(max(lightness, 0), 100)
    if l == 0:
        return 0.0
    h = hue * math.pi / 180
    sh, ch = math.sin(h), math.cos(h)
    sub1 = (l + 16) ** 3 / 1560896
    sub2 = sub1 if sub1 > _EPSILON else 27 * l / 24389
    m1 = [-1836216.146601413, -3205832.374331522, 10550402.85844013]
    m2 = [-14729646.91512916, 4250821.495452787, 1283157.104404885]
    best = sys.float_info.max
    for i in range(3):
        top = 11700000 * sub2
        bottom = (m1[i] * sh + m2[i] * ch) * sub2
        candidates = [l * top / bottom, l * (top - 11700000) / (bottom + 1921696 * sh)]
        best = min([best] + [c for c in candidates if c > 0])
    return min(best, 175.2)


def _from_linear(c: float) -> float:
    return 12.92 * c if c <= 0.0031306684425005883 else 1.055 * c ** 0.4166666666666667 - 0.055


def _to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.0404482362771076 else ((c + 0.055) / 1.055) ** 2.4


def _f(t: float) -> float:
    return (_KAPPA * t + 16) / 116 if t < _EPSILON else math.copysign(abs(t) ** (1 / 3), t)


def _rgb_to_lch(rgb: tuple[float, float, float]) -> list[float]:
    r, g, b = (_to_linear(c) for c in rgb)
    x = 0.412456439089691 * r + 0.357576077643907 * g + 0.180437483266397 * b
    y = 0.212672851405621 * r + 0.715152155287816 * g + 0.072174993306558 * b
    z = 0.019333895582328 * r + 0.1191920258813 * g + 0.950304078536368 * b
    denom = x + 15 * y + 3 * z
    denom = denom if denom != 0 else 1
    lightness = 116 * _f(y) - 16
    u = 13 * lightness * (4 * x / denom - _REF_U)
    v = 13 * lightness * (9 * y / denom - _REF_V)
    hue = (180 * math.atan2(v, u) / math.pi + 360) % 360
    chroma = math.sqrt(u * u + v * v)
    return [lightness, min(max(chroma, 0), _max_chroma(lightness, hue)), hue]


def _lch_to_rgb(lch: list[float]) -> list[float]:
    lightness = lch[0]
    if lightness <= 0:
        return [0.0, 0.0, 0.0]
    hue = lch[2]
    chroma = min(max(lch[1], 0), _max_chroma(lightness, hue))
    t = (lightness + 16) / 116
    y = 27 * (116 * t - 16) / 24389 if t < 0.20689655172413793 else t ** 3
    u = math.cos(hue * math.pi / 180) * chroma / (13 * lightness) + _REF_U
    v = math.sin(hue * math.pi / 180) * chroma / (13 * lightness) + _REF_V
    x = -9 * y * u / ((u - 4) * v - u * v)
    z = (9 * y - 15 * v * y - v * x) / (3 * v)
    rgb = [
        3.240454162114103 * x + -1.537138512797715 * y + -0.49853140955601 * z,
        -0.96926603050518 * x + 1.876010845446694 * y + 0.041556017530349 * z,
        0.055643430959114 * x + -0.20402591351675 * y + 1.057225188223179 * z,
    ]
    return [min(max(_from_linear(c), 0), 1) for c in rgb]


def _hex_to_triple(color: str) -> tuple[float, float, float]:
    return tuple(int(color[i : i + 2], 16) / 255 for i in (1, 3, 5))  # type: ignore[return-value]


def _triple_to_hex(rgb: list[float]) -> str:
    return "#" + "".join("%02x" % _js_round(255 * c) for c in rgb)


def _lower_bound(xs: list[float], x: float) -> int:
    lo, hi = 0, len(xs)
    while lo < hi:
        mid = (lo + hi) // 2
        if xs[mid] < x:
            lo = mid + 1
        else:
            hi = mid
    return hi


def _cubic_zero_deriv(ts: list[float], ys: list[float], xs: list[float]) -> list[float]:
    """Piecewise cubic through (ts, ys), flat at every knot (the app's
    `piecewiseCubic` with all-zero derivatives)."""
    out = [0.0] * len(xs)
    for u in range(len(ts) - 1):
        c = ts[u + 1] - ts[u]
        f = ys[u + 1] - ys[u]
        lin = (f / c) / c
        cub = (-2 * f / c) / (c * c)
        p = _lower_bound(xs, ts[u])
        d = _lower_bound(xs, ts[u + 1])
        if u == len(ts) - 2 and d < len(xs) and xs[d] == ts[u + 1]:
            d += 1
        for i in range(p, d):
            dx = xs[i] - ts[u]
            out[i] = ys[u] + dx * (dx * (lin + cub * (xs[i] - ts[u + 1])))
    return out


def lchycle(colors: list[str], n_out: int, steady: float = 0.0) -> list[str]:
    """The app's `lchycle({colors, nOut, steady, zeroDeriv: true, luv: true})`:
    `n_out` colours looping through `colors`, each held for `steady` of its
    stretch, blended through CIELUV."""
    k = len(colors)
    span = n_out / k
    if steady > 0:
        hold = min(steady, 1 - 10 * _EPS)
        points = [(colors[i // 2], (i // 2 + (hold / 2 if i % 2 else -hold / 2)) * span) for i in range(2 * k)]
    else:
        points = [(colors[i], i * span) for i in range(k)]
    points.sort(key=lambda p: p[1])
    ts = [t for _, t in points]
    luv = []
    for color, _ in points:
        lightness, chroma, hue = _rgb_to_lch(_hex_to_triple(color))
        luv.append([lightness, chroma * math.cos(hue * math.pi / 180), chroma * math.sin(hue * math.pi / 180)])
    knots = luv * 3
    knot_ts = ts + [t + n_out for t in ts] + [t + 2 * n_out for t in ts]
    xs = [n_out + i for i in range(n_out)]
    channels = [_cubic_zero_deriv(knot_ts, [p[ch] for p in knots], xs) for ch in range(3)]
    out = []
    for lightness, u, v in zip(*channels):
        lch = [lightness, math.sqrt(u * u + v * v), (180 * math.atan2(v, u) / math.pi + 360) % 360]
        out.append(_triple_to_hex(_lch_to_rgb(lch)))
    return out


# ------------------------------------------------------------------ styles


def normalize_style(style: str) -> str:
    key = str(style).strip().lower().replace(" ", "_").replace("-", "_")
    key = _ALIASES.get(key, key)
    if key not in STYLES:
        raise ValueError(f"Unknown cycle style {style!r}. Try: {', '.join(STYLES)}")
    return key


def _tempo_cpm(tempo: float) -> float:
    return tempo * tempo * 480


def _pikaled2(style: str, user: list[str], tempo: float, inhale: bool) -> dict[str, Any]:
    n = len(user)
    cpm = _tempo_cpm(tempo)
    if style == "spin":
        speed = min(_js_round(cpm * 256 / 480), 255)
    elif style in ("fade", "breathe"):
        speed = _js_round(cpm / 3)
    else:
        speed = _js_round(cpm / 3) if cpm > 0 else 64
    speed_di1 = min(speed * 2, 255)
    phase_lock = 0 if cpm > 0 else 1
    steady = 0.3 if style in ("fade", "spin", "breathe") else 0.0
    table_len = n * STEPS_PER_COLOR

    param: dict[str, Any] = {
        "bright": 255,
        "speed": speed,
        "speedDi0": _num(speed_di1 / 8),
        "speedDi1": speed_di1,
        "anim": 1,
        "plNum": 0,
        "plDenom": 0,
        "offset": list(ZERO_OFFSETS),
        "color": lchycle(user, table_len, steady),
        "colorLen": table_len,
        "diFrac": 1 if inhale else 0,
    }
    if style == "spin":
        param.update(anim=7, plNum=1, plDenom=n)
    elif style == "breathe":
        param["anim"] = 5
    elif style == "disco":
        param.update(offset=[_js_round(v * n) for v in DISCO_OFFSETS], plDenom=phase_lock)
    elif style == "split":
        offsets = SPLIT_OFFSETS_2 if n == 2 else SPLIT_OFFSETS_4 if n <= 4 else SPLIT_OFFSETS_6
        param.update(offset=list(offsets), plDenom=phase_lock)
    elif style == "fill":
        param.update(offset=list(FILL_OFFSETS), plDenom=phase_lock)
    return {"lamp": {"name": "pikaled2", "param": param}}


def _migrtn1(style: str, user: list[str], tempo: float, inhale: bool) -> dict[str, Any]:
    if style == "confetti":
        density = 6
        speed = (tempo * 0.9 + 0.1) ** 2 * 20
        param: dict[str, Any] = {
            "speed": speed,
            "speedDi0": speed * 0.25,
            "speedDi1": speed * 2,
            "minLength": 2,
            "maxLength": 4,
            "minQty": _js_round(density),
            "maxQty": _js_round(density + 4),
            "spawnFreq": 5,
            "bgBright": 1 / 2,
            "bgBrightDi0": 1 / 4,
            "bgBrightDi1": 3 / 4,
            "sigma": 3,
            "sigmaDi0": 3.5,
            "sigmaDi1": 2.5,
            "paths": CONFETTI_PATHS,
        }
    else:
        density = 2
        speed = (tempo * 0.9 + 0.1) ** 2 * 4
        param = {
            "speed": speed,
            "speedDi0": speed * 0.5,
            "speedDi1": speed * 3,
            "minLength": 4,
            "maxLength": 8,
            "minQty": _js_round(density),
            "maxQty": _js_round(density + 2),
            "spawnFreq": 0.5,
            "bgBright": 2 / 3,
            "bgBrightDi0": 1 / 3,
            "bgBrightDi1": 1,
            "sigma": 3,
            "sigmaDi0": 4,
            "sigmaDi1": 2,
            "paths": LAVA_PATHS,
        }
    param.update(
        sunlight=0.1,
        nutrDep=0,
        colors=list(user),
        diFrac=1 if inhale else 0,
        preRunTick=0.2 / param["speed"],
        preRunNTicks=30,
        sources=MIGRATION_SOURCES,
    )
    param = {k: (_num(v) if isinstance(v, float) else v) for k, v in param.items()}
    return {"lamp": {"name": "migrtn1", "param": param}}


def cycle_payload(style: str, colors: list[str], *, tempo: float = 0.5, inhale: bool = False) -> dict[str, Any]:
    """The lamp that animates `colors`, as the Puffco app would write it.

    `tempo` is 0..1 (the app's tempo slider). `inhale` is the app's Dynamic
    Inhale, which lets the lights react while you pull. Styles that need two
    colours cycle a single one against black.
    """
    style = normalize_style(style)
    user = [normalize_color(c) for c in colors][:MAX_COLORS]
    if not user:
        raise ValueError("A colour cycle needs at least one colour")
    while len(user) < MIN_COLORS.get(style, 2):
        user.append(BLACK)
    # Zero tempo would freeze the animation; that's what a solid colour is for.
    tempo = max(0.1, min(1.0, float(tempo)))
    if style in ADVANCED_STYLES:
        return _migrtn1(style, user, tempo, inhale)
    return _pikaled2(style, user, tempo, inhale)


def decode_cycle(decoded: Any) -> dict[str, Any] | None:
    """Style, colours, tempo and inhale of an animated lamp; None for a steady
    colour. A lamp this module didn't build (an exclusive mood captured from
    the app) comes back as style "custom" with whatever colours it carries."""
    if not isinstance(decoded, dict):
        return None
    lamp = decoded.get("lamp") or {}
    param = lamp.get("param") or {}
    name = lamp.get("name")
    inhale = bool(param.get("diFrac"))

    if name == "migrtn1":
        colors = [c for c in (param.get("colors") or []) if isinstance(c, str) and c.startswith("#")]
        try:
            speed = float(param.get("speed"))
            min_len = int(param.get("minLength"))
        except (TypeError, ValueError):
            return {"style": "custom", "colors": colors, "tempo": 0.5, "inhale": inhale}
        style, scale = ("confetti", 20) if min_len == 2 else ("lava", 4) if min_len == 4 else ("custom", 0)
        tempo = (math.sqrt(max(speed, 0) / scale) - 0.1) / 0.9 if scale else 0.5
        return {"style": style, "colors": colors, "tempo": round(max(0.0, min(1.0, tempo)), 2), "inhale": inhale}

    if name != "pikaled2":
        return {"style": "custom", "colors": [], "tempo": 0.5, "inhale": inhale} if lamp else None
    try:
        length = int(param.get("colorLen"))
        anim = int(param.get("anim"))
        speed = float(param.get("speed"))
    except (TypeError, ValueError):
        return None
    table = param.get("color")
    # A steady colour is the full 32-slot table ("No animation").
    if length >= 32 or length <= 0 or not isinstance(table, list):
        return None
    colors = [c for c in table[:length:STEPS_PER_COLOR] if isinstance(c, str) and c.startswith("#")]
    offsets = list(param.get("offset") or [])
    n = max(1, len(colors))
    if length % STEPS_PER_COLOR:
        style = "custom"
    elif anim == 7:
        style = "spin"
    elif anim == 5:
        style = "breathe"
    elif anim != 1:
        style = "custom"
    elif offsets == ZERO_OFFSETS or not any(offsets):
        style = "fade"
    elif offsets == [_js_round(v * n) for v in DISCO_OFFSETS]:
        style = "disco"
    elif offsets in (SPLIT_OFFSETS_2, SPLIT_OFFSETS_4, SPLIT_OFFSETS_6):
        style = "split"
    elif offsets == FILL_OFFSETS:
        style = "fill"
    else:
        style = "custom"
    # The padding black a single colour cycles against isn't one of "your" colours.
    if len(colors) == 2 and colors[1] == BLACK and style not in ("spin", "custom"):
        colors = colors[:1]
    scale = 256 if style == "spin" else 160
    tempo = 0.5 if (style in ("disco", "split", "fill") and speed == 64) else math.sqrt(max(0.0, speed) / scale)
    return {"style": style, "colors": colors, "tempo": round(min(1.0, tempo), 2), "inhale": inhale}


# ------------------------------------------------------------------ surprise
# The panel's ready-made palettes (Panel.qml `cyclePalettes`), for Surprise me.
PALETTES = {
    "Rainbow": ["#ff0000", "#ffaa00", "#f6f600", "#00e05a", "#0080ff", "#a020ff"],
    "Sunset": ["#ff2d55", "#ff6a1a", "#ffb000"],
    "Ocean": ["#0040ff", "#00b4ff", "#00ffd0"],
    "Vapor": ["#ff4fa3", "#a855f7", "#3b9eff"],
    "Fire": ["#ff1a00", "#ff5a00", "#ffae00"],
    "Forest": ["#1f8f3a", "#8fd400", "#00c090"],
}
# Breathe is the app's retired style; Surprise sticks to the current ones.
SURPRISE_STYLES = ("fade", "spin", "disco", "split", "fill", "lava", "confetti")
# How often Surprise reaches for one of your saved lights, when you have any.
SAVED_SHARE = 0.25


def surprise_pick(
    rng: Any,
    *,
    advanced: bool,
    saved_ids: list[str],
    last: str | None = None,
) -> dict[str, Any]:
    """A light for the next session: {"saved": id} for one of your saved
    lights, or {"style", "colors", "tempo", "key"} for a fresh cycle.

    `advanced` is whether the Peak runs Lava and Confetti (firmware AF+).
    `last` is the previous pick's key, so the same look never plays twice in
    a row when there's anything else to choose.
    """
    styles = [s for s in SURPRISE_STYLES if advanced or s not in ADVANCED_STYLES]
    looks: list[dict[str, Any]] = [
        {"style": s, "palette": p, "key": f"{s}/{p}"} for s in styles for p in PALETTES
    ]
    saved = [{"saved": i, "key": f"saved/{i}"} for i in saved_ids]
    pool = saved if saved and rng.random() < SAVED_SHARE else looks
    # A lone saved light that just played gives way to a fresh cycle.
    fresh = [look for look in pool if look["key"] != last] or [look for look in looks if look["key"] != last]
    look = dict(rng.choice(fresh))
    if "saved" in look:
        return look
    palette = look.pop("palette")
    look["colors"] = list(PALETTES[palette])
    # The middle of the speed slider, give or take: lively, never frantic.
    look["tempo"] = round(rng.uniform(0.35, 0.7), 2)
    return look
