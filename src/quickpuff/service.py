"""Start the QuickPuff daemon if it is not already listening."""

from __future__ import annotations

import os
import socket
import stat
import subprocess
import sys
import time
from pathlib import Path

from .paths import RefusedFile, log_path, open_private_dir, runtime_dir, socket_path
from .proc import run_bounded

SYSTEMCTL = "/usr/bin/systemctl"
UNIT = "quickpuff-daemon.service"
# systemd is already starting, running or restarting it: wait rather than act.
UNIT_BUSY = frozenset({"active", "activating", "deactivating", "reloading"})


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def python_executable() -> str:
    venv = project_root() / ".venv" / "bin" / "python"
    if venv.exists():
        return str(venv)
    return sys.executable


def daemon_running() -> bool:
    """Probe the socket rather than trusting the file.

    A daemon killed with SIGKILL leaves its socket file behind. Taking
    that file as proof of life meant we never respawned, and every call
    failed with 'connection refused' until it was deleted by hand.
    """
    sock = socket_path()
    if not sock.exists():
        return False
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    probe.settimeout(0.5)
    try:
        probe.connect(str(sock))
        return True
    except OSError:
        return False
    finally:
        probe.close()


def unit_state() -> dict[str, str]:
    """What systemd says about the user unit: LoadState ("loaded" once
    install.sh has put it in place), ActiveState and UnitFileState. Empty
    when systemd can't be asked."""
    code, out = run_bounded(
        [SYSTEMCTL, "--user", "show", "-p", "LoadState", "-p", "ActiveState", "-p", "UnitFileState", UNIT],
        timeout=2,
    )
    if code != 0:
        return {}
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def systemd_owns_daemon(props: dict[str, str] | None = None) -> bool:
    """True when the user unit is enabled or in the middle of a restart.

    Spawning a second process in that window steals the Unix socket and
    the Peak's one BLE write handle, which is how Connect hangs after a
    `systemctl restart`.
    """
    if props is None:
        props = unit_state()
    return props.get("ActiveState", "") in UNIT_BUSY or props.get("UnitFileState", "") == "enabled"


def open_daemon_log() -> int:
    """The daemon's log, opened for appending, as a descriptor to hand it.

    Opened once, relative to the private runtime directory: never through a
    symlink, never waiting on a FIFO, created 0600, and checked on the
    descriptor (a regular file this user owns) before the daemon writes a
    byte to it.
    """
    path = log_path()
    dir_fd = open_private_dir(runtime_dir())
    try:
        fd = os.open(
            path.name,
            os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
            0o600,
            dir_fd=dir_fd,
        )
    except OSError as exc:
        raise RefusedFile(f"{path} can't be opened for the daemon's log ({exc.strerror or exc})") from exc
    finally:
        os.close(dir_fd)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
            raise RefusedFile(f"{path} isn't a plain file this user owns; not logging to it")
        if stat.S_IMODE(info.st_mode) & 0o077:
            os.fchmod(fd, 0o600)
        # O_NONBLOCK was only for the open; the daemon writes normally.
        os.set_blocking(fd, True)
    except BaseException:
        os.close(fd)
        raise
    return fd


def _wait_for_daemon(timeout: float) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if daemon_running():
            return True
        time.sleep(0.1)
    return False


def ensure_daemon(timeout: float = 8.0) -> None:
    """Make sure a daemon is listening, starting one if need be.

    With the user unit installed, systemd is what starts it (`systemctl
    --user start`), so the daemon is one systemd stops again, uninstall
    included. Only a development checkout with no unit installed runs it
    as a detached process of its own. The bar widget and panel never get
    here: they pass --no-start, so they can't restart a daemon someone
    stopped on purpose.
    """
    if daemon_running():
        return
    props = unit_state()
    if props.get("LoadState") == "masked":
        raise RuntimeError(f"{UNIT} is masked. Unmask it first: systemctl --user unmask {UNIT}")
    if props.get("LoadState") == "loaded" or systemd_owns_daemon(props):
        if props.get("ActiveState", "") not in UNIT_BUSY:
            code, _out = run_bounded([SYSTEMCTL, "--user", "start", UNIT], timeout=timeout)
            if code != 0:
                raise RuntimeError(f"Couldn't start {UNIT}. See: journalctl --user -u {UNIT}")
        if _wait_for_daemon(timeout):
            return
        raise RuntimeError(
            f"QuickPuff systemd daemon did not come back. See: journalctl --user -u {UNIT}"
        )
    log = log_path()
    env = os.environ.copy()
    src = str(project_root() / "src")
    existing = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = src if not existing else f"{src}:{existing}"
    handle = open_daemon_log()
    # The child dups this on spawn, so the parent must not hold it open.
    try:
        subprocess.Popen(
            [python_executable(), "-m", "quickpuff.daemon"],
            cwd=str(project_root()),
            stdin=subprocess.DEVNULL,
            stdout=handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env=env,
        )
    finally:
        os.close(handle)
    if _wait_for_daemon(timeout):
        return
    raise RuntimeError(
        f"QuickPuff daemon did not start. Check {log}"
    )
