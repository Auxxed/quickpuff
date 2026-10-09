"""XDG paths and saved settings.

Every file QuickPuff keeps is read and written here. A read opens the file
once without following a symlink or waiting on a FIFO, checks that
descriptor, and reads a bounded amount from it. A write goes through a fresh
private temporary that is renamed into place. A file that is there but isn't
a plain file this user owns within its size limit (a link, a FIFO, another
account's file, something too big) is refused: readers do without it, and
writers leave it exactly as found rather than replace it with defaults.
"""

from __future__ import annotations

import errno
import json
import logging
import math
import os
import re
import secrets
import stat
from pathlib import Path
from typing import Any

from .constants import READY_ANIMATIONS, SHOWTIME_MODES

log = logging.getLogger("quickpuff.paths")

SOCKET_NAME = "quickpuff.sock"

# Settings are a few KiB; anything far past that isn't a QuickPuff config.
MAX_CONFIG_BYTES = 256 * 1024

DEFAULTS: dict[str, Any] = {
    "device_mac": "",
    "device_name": "",
    "adapter": "",  # "" auto-detects; set "hci1" to pin a specific radio
    "auto_connect": True,
    # Two computers can't share a Peak: let go of it when this seat is locked
    # or switched away, and take it back when someone returns.
    "handoff": True,
    "units": "F",
    # What plays on screen when the Peak reaches temperature (the bar widget's
    # overlay): see READY_ANIMATIONS.
    "ready_animation": "rocket",
    # The heat-up overlay while the Peak preheats: see SHOWTIME_MODES.
    "showtime": "corner",
    # The overlays' sounds, and how loud (0-100).
    "sounds": True,
    "sound_volume": 70,
    # Which monitor the overlays play on: "focused" follows you around, or
    # a monitor name such as "DP-2" pins them there.
    "overlay_screen": "focused",
    "notify_ready": True,
    "notify_low_battery": True,
    "qtip_reminder": True,
    "daily_limit": 0,
    "weekly_recap": True,
    "battery_rated_mah": 1700,
    "battery_saver": False,
    "clean_every": 30,
    "clean_at_total": None,
    "clean_notified": False,
}


class RuntimeDirMissing(RuntimeError):
    """No usable XDG_RUNTIME_DIR, so nowhere private for the socket."""


class RefusedFile(OSError):
    """A file QuickPuff keeps that it would not read or would not replace.

    Something other than a plain file this user owns is at the path (a
    symlink, a FIFO, another account's file), or it is bigger than QuickPuff
    ever writes, or it can't be opened. It is left exactly as it was found.
    """


RUNTIME_DIR_HELP = (
    "XDG_RUNTIME_DIR isn't set, so QuickPuff has no private directory for its socket "
    "(and won't fall back to /tmp, where another account could get there first). "
    "Run it from your desktop session, where systemd-logind sets XDG_RUNTIME_DIR "
    "(usually /run/user/$UID)."
)


def runtime_dir() -> Path:
    """$XDG_RUNTIME_DIR: made by logind, private to this user, gone at logout.

    There is deliberately no fallback. A guessable directory under /tmp is
    somewhere another account can create first, so without a runtime
    directory QuickPuff refuses rather than put its socket there.
    """
    raw = os.environ.get("XDG_RUNTIME_DIR", "")
    # The XDG spec has a relative path ignored, the same as unset.
    if not raw or not os.path.isabs(raw):
        raise RuntimeDirMissing(RUNTIME_DIR_HELP)
    return Path(raw)


def config_dir() -> Path:
    raw = os.environ.get("XDG_CONFIG_HOME")
    base = Path(raw) if raw else Path.home() / ".config"
    return base / "quickpuff"


def data_dir() -> Path:
    raw = os.environ.get("XDG_DATA_HOME")
    base = Path(raw) if raw else Path.home() / ".local" / "share"
    return base / "quickpuff"


def socket_path() -> Path:
    override = os.environ.get("QUICKPUFF_SOCKET")
    if override:
        return Path(override)
    return runtime_dir() / SOCKET_NAME


def config_path() -> Path:
    return config_dir() / "config.json"


def log_path() -> Path:
    return runtime_dir() / "quickpuff-daemon.log"


def device_file_stem(serial: str) -> str:
    """A Peak's serial as a file name. The serial comes from the Peak, so
    anything but letters, digits, `_`, `.` and `-` becomes `_`, a leading dot
    (a hidden file, or `..`) is dropped, and it is capped well inside a file
    name's limit."""
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", str(serial)).lstrip(".")[:64]
    return safe or "peak"


# ---- reading -----------------------------------------------------------------


def _open_problem(exc: OSError) -> str:
    if exc.errno == errno.ELOOP:
        return "is a symlink (QuickPuff doesn't follow links for its own files)"
    if exc.errno == errno.ENXIO:
        return "is a socket or device, not a file"
    return f"can't be opened ({exc.strerror or exc})"


def _file_problem(info: os.stat_result, max_bytes: int) -> str | None:
    if not stat.S_ISREG(info.st_mode):
        return "is not a regular file"
    if info.st_uid != os.geteuid():
        return f"belongs to another user (uid {info.st_uid})"
    if info.st_size > max_bytes:
        return f"is {info.st_size} bytes, over the {max_bytes} QuickPuff allows"
    return None


def read_bytes_bounded(path: Path, max_bytes: int) -> bytes | None:
    """The contents of a file QuickPuff keeps, or None when there is none.

    The file is opened once, without following a symlink and without waiting
    on a FIFO, checked on that descriptor (a regular file this user owns, no
    bigger than max_bytes) and read from the same descriptor, so nothing can
    be swapped in between the check and the read. At most max_bytes + 1 bytes
    are read, and a file over the limit is refused rather than cut short.
    Anything but "there is no such file" raises RefusedFile.
    """
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise RefusedFile(f"{path} {_open_problem(exc)}") from exc
    try:
        problem = _file_problem(os.fstat(fd), max_bytes)
        if problem:
            raise RefusedFile(f"{path} {problem}")
        # O_NONBLOCK was only for the open; a regular file reads normally.
        os.set_blocking(fd, True)
        chunks: list[bytes] = []
        left = max_bytes + 1
        while left > 0:
            chunk = os.read(fd, min(left, 1 << 20))
            if not chunk:
                break
            chunks.append(chunk)
            left -= len(chunk)
    except RefusedFile:
        raise
    except OSError as exc:
        raise RefusedFile(f"{path} can't be read ({exc.strerror or exc})") from exc
    finally:
        os.close(fd)
    data = b"".join(chunks)
    if len(data) > max_bytes:
        raise RefusedFile(f"{path} grew past the {max_bytes} bytes QuickPuff allows")
    return data


def read_json_bounded(path: Path, max_bytes: int) -> Any:
    """A JSON file QuickPuff keeps, through read_bytes_bounded.

    None when it isn't there; RefusedFile when it is refused (see
    read_bytes_bounded); ValueError when it is QuickPuff's own file but not
    valid JSON, which the callers treat as damaged and start afresh from, as
    they always have.
    """
    raw = read_bytes_bounded(path, max_bytes)
    if raw is None:
        return None
    try:
        return loads_json(raw.decode("utf-8"))
    except ValueError as exc:
        # Bad UTF-8, bad JSON, or nested deeper than anything QuickPuff writes.
        raise ValueError(f"{path} isn't valid JSON ({exc})") from exc


# Deeper than any file, request or reply QuickPuff writes (those are a few
# levels), and far inside what any Python can parse.
MAX_JSON_DEPTH = 64


def loads_json(text: str, max_depth: int = MAX_JSON_DEPTH) -> Any:
    """json.loads, with nesting capped at max_depth: ValueError past it.

    The cap is checked here rather than left to the parser, which gives up at
    a depth that depends on the Python version and the stack size, so a
    deeply nested document can parse on one machine and fail on another. The
    walk is iterative, so the check itself can't run out of stack.
    """
    try:
        value = json.loads(text)
    except RecursionError as exc:
        raise ValueError("nested too deep to parse") from exc
    pending = [(value, 1)] if isinstance(value, (dict, list)) else []
    while pending:
        item, depth = pending.pop()
        if depth > max_depth:
            raise ValueError(f"nested more than {max_depth} levels deep")
        children = item.values() if isinstance(item, dict) else item
        pending.extend((child, depth + 1) for child in children if isinstance(child, (dict, list)))
    return value


# Files already reported, so a poll that reads one every second says so once
# rather than every time. Cleared once the file reads fine again.
_reported: set[str] = set()


def report_unusable(path: Path, exc: Exception) -> None:
    """Log a file a reader had to do without, once per incident."""
    key = str(path)
    if key in _reported:
        log.debug("still doing without %s: %s", path, exc)
        return
    _reported.add(key)
    if isinstance(exc, RefusedFile):
        log.warning("%s. Left as it is, and not saved over until it's fixed or removed.", exc)
    else:
        log.warning("%s. Starting afresh; the next save replaces it.", exc)


def report_readable(path: Path) -> None:
    _reported.discard(str(path))


# ---- writing -----------------------------------------------------------------


def open_private_dir(path: Path) -> int:
    """A descriptor for one of QuickPuff's own directories, made if missing.

    A missing directory is created 0700. The directory is then opened once
    and checked on that descriptor (a directory this user owns), tightened
    to 0700 if it was wider, and what follows works relative to it, so the
    directory that was checked is the one written to. A directory reached
    through a symlink is allowed (dotfile managers link ~/.config/quickpuff);
    the checks apply to wherever it leads.
    """
    try:
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    except OSError as exc:
        raise RefusedFile(f"{path} can't be used as a directory ({exc.strerror or exc})") from exc
    try:
        info = os.fstat(fd)
        if info.st_uid != os.geteuid():
            raise RefusedFile(f"{path} belongs to another user (uid {info.st_uid})")
        if stat.S_IMODE(info.st_mode) & 0o077:
            os.fchmod(fd, 0o700)
    except BaseException:
        os.close(fd)
        raise
    return fd


def _refuse_unless_replaceable(dir_fd: int, path: Path, max_bytes: int | None) -> None:
    """Saving only ever replaces a file its reader would have read: a plain
    file this user owns, within max_bytes. A symlink, a FIFO, a socket,
    another account's file or an oversized one at the destination is left
    alone; it isn't QuickPuff's to delete, and a reader that refused it fell
    back to defaults that must not be written over it."""
    try:
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dir_fd)
    except FileNotFoundError:
        return
    except OSError as exc:
        raise RefusedFile(f"not saving over {path}: it {_open_problem(exc)}") from exc
    try:
        info = os.fstat(fd)
    finally:
        os.close(fd)
    problem = _file_problem(info, max_bytes if max_bytes is not None else info.st_size)
    if problem:
        raise RefusedFile(f"not saving over {path}: it {problem}")


def write_json_atomic(path: Path, data: Any, *, indent: int | None = None, max_bytes: int | None = None) -> None:
    """Write JSON through a fresh private temporary and rename it into place.

    The daemon and the CLI both write these files, and a crash or a full
    disk part-way through a plain write leaves a truncated file that the
    next load refuses. So the temporary is created exclusively, with a
    random name and mode 0600 from the start, in the destination directory
    (held open, see open_private_dir); written and fsynced through its own
    descriptor; renamed over the destination; and the directory fsynced so
    the rename survives a crash too. rename() replaces a symlink rather than
    writing through it, and whatever is at the destination is only replaced
    if its reader would have read it (see _refuse_unless_replaceable). Pass
    the reader's max_bytes: nothing bigger is written, or replaced.
    """
    blob = (json.dumps(data, indent=indent) + "\n").encode("utf-8")
    if max_bytes is not None and len(blob) > max_bytes:
        raise RefusedFile(f"not saving {path}: {len(blob)} bytes is over the {max_bytes} QuickPuff allows")
    dir_fd = open_private_dir(path.parent)
    try:
        _refuse_unless_replaceable(dir_fd, path, max_bytes)
        tmp = f".{path.name}.{secrets.token_hex(8)}.tmp"
        fd = os.open(
            tmp,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
            dir_fd=dir_fd,
        )
        try:
            try:
                # The umask can only take bits away; this makes sure of 0600.
                os.fchmod(fd, 0o600)
                view = memoryview(blob)
                while view:
                    written = os.write(fd, view)
                    if written <= 0:
                        raise OSError(errno.EIO, "short write", str(path))
                    view = view[written:]
                os.fsync(fd)
            finally:
                os.close(fd)
            os.replace(tmp, path.name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        except BaseException:
            try:
                os.unlink(tmp, dir_fd=dir_fd)
            except OSError:
                pass
            raise
        try:
            os.fsync(dir_fd)
        except OSError as exc:
            # A few filesystems can't sync a directory; nothing more to do there.
            if exc.errno not in (errno.EINVAL, errno.EOPNOTSUPP):
                raise
    finally:
        os.close(dir_fd)


# ---- settings ----------------------------------------------------------------

# Settings earlier versions wrote that nothing reads any more.
RETIRED_KEYS = ("last_fact", "poll_interval")


def load_config() -> dict[str, Any]:
    """Saved settings over the defaults.

    A config.json that is refused (a link, a FIFO, another account's,
    oversized) reads as the defaults and is logged, and save_config won't
    replace it. One that is damaged reads as the defaults too, as it always
    has, and the next save replaces it.
    """
    path = config_path()
    data = dict(DEFAULTS)
    try:
        loaded = read_json_bounded(path, MAX_CONFIG_BYTES)
    except (OSError, ValueError) as exc:
        report_unusable(path, exc)
        loaded = None
    else:
        report_readable(path)
    if isinstance(loaded, dict):
        data.update(loaded)
    for key in RETIRED_KEYS:
        data.pop(key, None)
    return data


def save_config(data: dict[str, Any]) -> None:
    """Save settings. Raises RefusedFile, saving nothing, when the config.json
    already there is one load_config refused: the settings in it would be
    lost for the defaults it fell back to."""
    merged = dict(DEFAULTS)
    merged.update(data)
    for key in RETIRED_KEYS:
        merged.pop(key, None)
    write_json_atomic(config_path(), merged, indent=2, max_bytes=MAX_CONFIG_BYTES)


def switched_on(value: Any) -> bool:
    # A hand-edited config can say "false", which bool() calls true.
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "on", "yes"}
    return bool(value)


def clamp_volume(value: Any) -> int:
    """A sound volume, 0-100. Anything that isn't a finite number (a bool, a
    word, NaN, infinity) reads as the default."""
    if isinstance(value, bool):
        return int(DEFAULTS["sound_volume"])
    try:
        number = float(value)
    except (TypeError, ValueError):
        return int(DEFAULTS["sound_volume"])
    if not math.isfinite(number):
        return int(DEFAULTS["sound_volume"])
    return max(0, min(100, int(round(number))))


# Output names as Hyprland reports them: DP-2, HDMI-A-1, eDP-1.
MONITOR_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,31}")


def overlay_screen_setting(value: Any) -> str:
    """"focused", or a monitor name; anything else reads as "focused"."""
    if not isinstance(value, str):
        return "focused"
    name = value.strip()
    if name.lower() == "focused" or not MONITOR_NAME.fullmatch(name):
        return "focused"
    return name


def ui_settings(cfg: dict[str, Any] | None = None) -> dict[str, Any]:
    """The overlay and display settings the bar widget and panel need.

    Handed to the shell in `status` and `quickpuff waybar`, so it never
    opens config.json itself. Each value is checked against what it may be,
    and one that isn't reads as its default:

      ready_animation  one of READY_ANIMATIONS            (default "rocket")
      showtime         "off", "corner" or "stage"         (default "corner")
      sounds           true or false                      (default true)
      sound_volume     whole number 0-100                 (default 70)
      overlay_screen   "focused" or a monitor name        (default "focused")
      units            "F" or "C"                         (default "F")
    """
    if cfg is None:
        cfg = load_config()
    animation = cfg.get("ready_animation")
    showtime = cfg.get("showtime")
    units = cfg.get("units")
    return {
        "ready_animation": animation if animation in READY_ANIMATIONS else DEFAULTS["ready_animation"],
        "showtime": showtime if showtime in SHOWTIME_MODES else DEFAULTS["showtime"],
        "sounds": switched_on(cfg.get("sounds", DEFAULTS["sounds"])),
        "sound_volume": clamp_volume(cfg.get("sound_volume", DEFAULTS["sound_volume"])),
        "overlay_screen": overlay_screen_setting(cfg.get("overlay_screen")),
        "units": "C" if isinstance(units, str) and units.strip().upper() == "C" else "F",
    }
