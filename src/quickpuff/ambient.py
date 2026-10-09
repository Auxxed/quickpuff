"""Lantern colours from the desktop: the Omarchy theme, or the album art of
what's playing.

Both end up as a short palette of LED-friendly colours (bright, saturated,
distinct in hue) that the daemon puts on the Peak's lantern. Nothing here
writes to the Peak.

The theme palette comes from the theme's colors.toml, read with the same
bounded, no-symlink read as QuickPuff's own files. Album art comes from the
media player over MPRIS: a file the player wrote locally, or an image on one
of a few known cover-art hosts, fetched over HTTPS with no redirects and a
size cap. It's decoded to a tiny thumbnail by ffmpeg (run bounded, fed through
stdin) and never stored.
"""

from __future__ import annotations

import math
import os
import ssl
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from . import moods
from .paths import RefusedFile, read_bytes_bounded
from .proc import run_bounded

FFMPEG = "/usr/bin/ffmpeg"
THEME_MAX_BYTES = 64 * 1024
ART_MAX_BYTES = 4 * 1024 * 1024
ART_TIMEOUT_S = 6.0
THUMB = 24
MAX_COLORS = 3
# Cover art from players that only hand out a web address (Spotify, YouTube
# in a browser, Apple Music, Tidal, Deezer, SoundCloud). Anything else is
# left alone.
ART_HOSTS = (
    "i.scdn.co", "mosaic.scdn.co", "i.ytimg.com", "lh3.googleusercontent.com", "yt3.ggpht.com",
    "resources.tidal.com", "e-cdns-images.dzcdn.net", "cdn-images.dzcdn.net", "i1.sndcdn.com",
    "coverartarchive.org",
)
ART_HOST_SUFFIXES = (".mzstatic.com",)
# Theme keys worth glowing, after the accent, in order of preference.
THEME_KEYS = ("bright_blue", "blue", "bright_magenta", "magenta", "bright_cyan", "cyan", "green", "bright_green",
              "red", "bright_red", "yellow", "orange")


def theme_dir() -> Path:
    state = os.environ.get("XDG_STATE_HOME") or ""
    base = Path(state) if state.startswith("/") else Path.home() / ".local/state"
    return base / "omarchy/current/theme"


def _lch(hex_color: str) -> list[float]:
    return moods._rgb_to_lch(moods._hex_to_triple(hex_color))


def _hex(lch: list[float]) -> str:
    return moods._triple_to_hex(moods._lch_to_rgb(lch))


def led_color(hex_color: str) -> str:
    """The same hue, as bright and saturated as an LED shows well."""
    lightness, chroma, hue = _lch(hex_color)
    lightness = min(max(lightness, 58.0), 72.0)
    chroma = max(chroma, 0.0) * 1.6
    return _hex([lightness, min(chroma, moods._max_chroma(lightness, hue) * 0.97), hue])


def _hue_gap(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return min(d, 360 - d)


def _distinct(candidates: list[tuple[float, str]], min_chroma: float, min_gap: float) -> list[str]:
    """The most vivid candidates whose hues stand apart, up to MAX_COLORS."""
    chosen: list[tuple[float, str]] = []
    for _, color in candidates:
        lightness, chroma, hue = _lch(color)
        if chroma < min_chroma or any(_hue_gap(hue, h) < min_gap for h, _ in chosen):
            continue
        chosen.append((hue, color))
        if len(chosen) == MAX_COLORS:
            break
    return [led_color(c) for _, c in chosen]


def parse_theme(text: str) -> dict[str, str]:
    """The `key = "#rrggbb"` lines of a colors.toml."""
    colors = {}
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        value = value.strip().strip('"').strip("'")
        if sep and len(value) == 7 and value.startswith("#"):
            try:
                int(value[1:], 16)
            except ValueError:
                continue
            colors[key.strip()] = value.lower()
    return colors


def theme_palette(directory: Path | None = None) -> list[str] | None:
    """The current Omarchy theme's accent, plus up to two more of its colours
    that stand apart from it, ready for the lantern. None without a theme."""
    try:
        raw = read_bytes_bounded((directory or theme_dir()) / "colors.toml", THEME_MAX_BYTES)
    except RefusedFile:
        return None
    if raw is None:
        return None
    colors = parse_theme(raw.decode("utf-8", "replace"))
    ordered = ([colors["accent"]] if "accent" in colors else []) + [colors[k] for k in THEME_KEYS if k in colors]
    palette = _distinct([(0.0, c) for c in ordered], min_chroma=18.0, min_gap=40.0)
    return palette or None


def art_palette(pixels: bytes) -> list[str] | None:
    """Up to three vivid, distinct colours from an RGB thumbnail, the most
    present first. None when the art is all greys."""
    bins: dict[int, list[tuple[float, float, float, float]]] = {}
    for i in range(0, len(pixels) - 2, 3):
        r, g, b = pixels[i], pixels[i + 1], pixels[i + 2]
        lightness, chroma, hue = moods._rgb_to_lch((r / 255, g / 255, b / 255))
        if chroma < 20 or not 12 < lightness < 96:
            continue
        bins.setdefault(int(hue // 20), []).append((chroma, lightness, chroma, hue))
    ranked = []
    for members in bins.values():
        weight = sum(m[0] for m in members)
        # The bin's colour: its members' mean, hue averaged on the circle.
        x = sum(m[2] * math.cos(math.radians(m[3])) for m in members)
        y = sum(m[2] * math.sin(math.radians(m[3])) for m in members)
        hue = (math.degrees(math.atan2(y, x)) + 360) % 360
        lightness = sum(m[1] for m in members) / len(members)
        chroma = sum(m[2] for m in members) / len(members)
        ranked.append((weight, _hex([lightness, chroma, hue])))
    ranked.sort(reverse=True)
    palette = _distinct(ranked, min_chroma=15.0, min_gap=35.0)
    return palette or None


def _art_host_ok(host: str) -> bool:
    host = host.lower()
    return host in ART_HOSTS or any(host.endswith(s) for s in ART_HOST_SUFFIXES)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args: Any, **kwargs: Any) -> None:  # noqa: D401
        return None


def fetch_art(url: str) -> bytes | None:
    """The bytes of a player's cover art: a local file it wrote, or an image on
    a known cover-art host over HTTPS. None for anything else, anything over
    ART_MAX_BYTES, or a failure. Blocking: run it off the event loop."""
    try:
        parts = urllib.parse.urlsplit(url)
    except ValueError:
        return None
    if parts.scheme == "file":
        path = urllib.parse.unquote(parts.path)
        if parts.netloc not in ("", "localhost") or not path.startswith("/"):
            return None
        try:
            return read_bytes_bounded(Path(path), ART_MAX_BYTES)
        except RefusedFile:
            return None
    if parts.scheme != "https" or parts.username or parts.password or parts.port not in (None, 443):
        return None
    if not parts.hostname or not _art_host_ok(parts.hostname):
        return None
    opener = urllib.request.build_opener(_NoRedirect, urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    request = urllib.request.Request(url, headers={"User-Agent": "QuickPuff"})
    try:
        with opener.open(request, timeout=ART_TIMEOUT_S) as resp:
            if resp.status != 200:
                return None
            data = resp.read(ART_MAX_BYTES + 1)
    except (OSError, ValueError):
        return None
    return data if 0 < len(data) <= ART_MAX_BYTES else None


def thumbnail(image: bytes) -> bytes | None:
    """A THUMB x THUMB RGB thumbnail of an image, decoded by ffmpeg."""
    code, out = run_bounded(
        [FFMPEG, "-v", "error", "-i", "pipe:0", "-frames:v", "1", "-vf", f"scale={THUMB}:{THUMB}:flags=area",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        timeout=8.0, max_bytes=THUMB * THUMB * 3 + 16, stdin_bytes=image, text=False,
    )
    return out if code == 0 and len(out) == THUMB * THUMB * 3 else None


# ------------------------------------------------------------------ MPRIS

MPRIS_PREFIX = "org.mpris.MediaPlayer2."
TRACK_MAX = 120


async def now_playing(bus: Any) -> dict[str, str] | None:
    """The first media player that's playing: its art address and track, from
    MPRIS on the session bus. None when nothing plays."""
    from dbus_fast import Message

    reply = await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                                   interface="org.freedesktop.DBus", member="ListNames"))
    names = sorted(n for n in (reply.body[0] if reply.body else []) if isinstance(n, str) and n.startswith(MPRIS_PREFIX))
    for name in names[:16]:
        try:
            reply = await bus.call(Message(destination=name, path="/org/mpris/MediaPlayer2",
                                           interface="org.freedesktop.DBus.Properties", member="GetAll",
                                           signature="s", body=["org.mpris.MediaPlayer2.Player"]))
            props = reply.body[0] if reply.body else {}
        except Exception:
            continue
        if not isinstance(props, dict):
            continue
        status = getattr(props.get("PlaybackStatus"), "value", None)
        if status != "Playing":
            continue
        meta = getattr(props.get("Metadata"), "value", None) or {}
        art = getattr(meta.get("mpris:artUrl"), "value", None)
        title = getattr(meta.get("xesam:title"), "value", None)
        artists = getattr(meta.get("xesam:artist"), "value", None)
        artist = ", ".join(a for a in artists if isinstance(a, str)) if isinstance(artists, list) else ""
        track = " — ".join(x for x in (artist, title if isinstance(title, str) else "") if x)
        return {"art": art if isinstance(art, str) else "", "track": track[:TRACK_MAX]}
    return None
