"""Lights captured off a Peak, to put back on any profile later.

Exclusive moods (Puffcon, Plasma, ...) are only handed out by Puffco's
servers to signed-in app accounts, so QuickPuff never builds them. Instead,
once a mood is on a profile, its light is copied off the Peak byte for byte
and kept here under a name. Replaying those exact bytes is the one way to get
it back without knowing how it was made.
"""

from __future__ import annotations

import hashlib
import time
from typing import Any

import cbor2

from .codec import decode_puffco_json, first_color
from .moods import decode_cycle
from .paths import RefusedFile, data_dir, read_json_bounded, report_readable, report_unusable, write_json_atomic

MAX_SAVED = 40
MAX_NAME = 32
# A profile light is a few hundred bytes; anything far past that isn't one.
MAX_RAW = 4096
# Forty lights of up to MAX_RAW bytes each, written as hex, with room to spare.
MAX_FILE_BYTES = 1024 * 1024


def _path():
    return data_dir() / "lights.json"


def light_id(raw: bytes) -> str:
    """Stable id for a light's exact bytes, so a profile wearing a saved light
    can be recognised."""
    return hashlib.sha1(raw).hexdigest()[:12]


def describe(raw: bytes) -> dict[str, Any]:
    """Colours and style of a light, for showing it without the raw bytes."""
    try:
        decoded = decode_puffco_json(cbor2.loads(raw))
    except Exception:
        return {"style": "custom", "colors": []}
    cycle = recall_cycle(raw) or decode_cycle(decoded)
    if cycle:
        return {"style": cycle["style"], "colors": list(cycle["colors"])[:6]}
    color = first_color(decoded)
    return {"style": "solid", "colors": [color] if color else []}


def reacts_to_inhale(raw: bytes) -> bool:
    """Whether a light follows your inhale, so a light replacing it can too."""
    try:
        cycle = recall_cycle(raw) or decode_cycle(decode_puffco_json(cbor2.loads(raw)))
    except Exception:
        return False
    return bool((cycle or {}).get("inhale"))


def _well_formed(entry: Any) -> bool:
    """A saved light as save() writes it: an id, a name no longer than
    MAX_NAME, and bytes (as hex) no longer than a profile light can be."""
    if not isinstance(entry, dict):
        return False
    ident, name, raw = entry.get("id"), entry.get("name"), entry.get("raw")
    return (
        isinstance(ident, str)
        and bool(ident)
        and isinstance(name, str)
        and len(name) <= MAX_NAME
        and isinstance(raw, str)
        and 0 < len(raw) <= 2 * MAX_RAW
    )


def _load() -> list[dict[str, Any]]:
    """The saved lights, or none.

    A lights.json that is refused (a link, a FIFO, another account's,
    oversized) reads as none and is logged, and _store won't replace it.
    One that is damaged, or holds more lights than save() ever keeps, reads
    as none too and the next save replaces it.
    """
    path = _path()
    try:
        data = read_json_bounded(path, MAX_FILE_BYTES)
    except (OSError, ValueError) as exc:
        report_unusable(path, exc)
        return []
    report_readable(path)
    lights = data.get("lights") if isinstance(data, dict) else None
    kept = [x for x in lights or [] if _well_formed(x)] if isinstance(lights, list) else []
    if len(kept) > MAX_SAVED:
        report_unusable(path, ValueError(f"{path} holds more than {MAX_SAVED} saved lights"))
        return []
    return kept


def _store(lights: list[dict[str, Any]]) -> None:
    # Raises RefusedFile for a lights.json _load refused; the caller asked
    # for this change, so it hears that it didn't happen.
    write_json_atomic(_path(), {"lights": lights}, indent=2, max_bytes=MAX_FILE_BYTES)


def _clean_name(name: Any) -> str:
    text = " ".join(str(name or "").split())[:MAX_NAME]
    if not text:
        raise ValueError("A saved light needs a name")
    return text


def listing() -> list[dict[str, Any]]:
    """Saved lights without their bytes, for status and the panel."""
    return [{k: v for k, v in x.items() if k != "raw"} for x in _load()]


def get_raw(ident: str) -> bytes:
    for x in _load():
        if x["id"] == ident:
            return bytes.fromhex(x["raw"])
    raise ValueError(f"No saved light {ident!r}")


def save(name: Any, raw: bytes) -> dict[str, Any]:
    """Keep `raw` under `name`. Saving the same light again renames it."""
    if not raw or len(raw) > MAX_RAW:
        raise ValueError("That doesn't look like a profile light")
    name = _clean_name(name)
    ident = light_id(raw)
    lights = [x for x in _load() if x["id"] != ident]
    if len(lights) >= MAX_SAVED:
        raise ValueError(f"You can keep up to {MAX_SAVED} saved lights; delete one first")
    entry = {"id": ident, "name": name, "saved_at": int(time.time()), "raw": raw.hex(), **describe(raw)}
    lights.append(entry)
    _store(lights)
    return {k: v for k, v in entry.items() if k != "raw"}


def rename(ident: str, name: Any) -> None:
    name = _clean_name(name)
    lights = _load()
    for x in lights:
        if x["id"] == ident:
            x["name"] = name
            _store(lights)
            return
    raise ValueError(f"No saved light {ident!r}")


def delete(ident: str) -> None:
    lights = _load()
    kept = [x for x in lights if x["id"] != ident]
    if len(kept) == len(lights):
        raise ValueError(f"No saved light {ident!r}")
    _store(kept)


# ------------------------------------------------------------ cycle memo
# The Peak stores a cycle as a blended colour table, which CIELUV's gamut
# clamp nudges (#ff0000 reads back as #fd0d0d). QuickPuff's payloads are
# deterministic, so it remembers what it wrote, keyed by the exact bytes,
# and reads those settings back instead of re-deriving them.

MAX_MEMO = 64
# MAX_MEMO cycles of a few colours each, with room to spare.
MAX_MEMO_BYTES = 256 * 1024


def _memo_path():
    return data_dir() / "cycles.json"


def _memo() -> dict[str, Any]:
    """The remembered cycles. One that is refused reads as empty (logged)
    and isn't replaced; a damaged one reads as empty and is."""
    path = _memo_path()
    try:
        data = read_json_bounded(path, MAX_MEMO_BYTES)
    except (OSError, ValueError) as exc:
        report_unusable(path, exc)
        return {}
    report_readable(path)
    return data if isinstance(data, dict) else {}


def remember_cycle(raw: bytes, cycle: dict[str, Any]) -> None:
    memo = _memo()
    memo.pop(light_id(raw), None)
    memo[light_id(raw)] = dict(cycle)
    # Oldest first; keep the most recent.
    while len(memo) > MAX_MEMO:
        memo.pop(next(iter(memo)))
    try:
        write_json_atomic(_memo_path(), memo, max_bytes=MAX_MEMO_BYTES)
    except RefusedFile as exc:
        # Only a memo of what was written: the light is on the Peak already,
        # so a cycles.json that was refused is left alone without failing that.
        report_unusable(_memo_path(), exc)


def recall_cycle(raw: bytes) -> dict[str, Any] | None:
    found = _memo().get(light_id(raw))
    # Only the shape remember_cycle writes; anything else is re-derived.
    if isinstance(found, dict) and isinstance(found.get("style"), str) and isinstance(found.get("colors"), list):
        return dict(found)
    return None

