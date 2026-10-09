"""Short helper commands, run with a deadline and a cap on what they print."""

from __future__ import annotations

import os
import selectors
import signal
import subprocess
import threading
import time
from typing import Any

# What a status query like `systemctl show` prints is a few hundred bytes.
DEFAULT_MAX_BYTES = 64 * 1024


def _kill_group(proc: subprocess.Popen) -> None:
    # Its own session, so its process group is its pid, and that pid can't
    # have been reused: the handle hasn't reaped it yet.
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except OSError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass


def run_bounded(
    argv: list[str],
    *,
    timeout: float,
    max_bytes: int = DEFAULT_MAX_BYTES,
    stdin_bytes: bytes | None = None,
    text: bool = True,
) -> tuple[int, Any]:
    """(exit code, stdout) of a short command, or (127, "") when it can't be
    run, outlives `timeout`, or prints more than max_bytes. stdout is text,
    stripped, unless text=False, when it is the raw bytes.

    stdin is closed, or carries stdin_bytes (written from a thread, so a
    command that prints while it reads can't deadlock), and stderr is
    discarded. The command runs in its own
    session, its output is read as it comes against one deadline for the
    whole run, and it is killed along with anything it started at the
    deadline or as soon as it passes the cap, so neither a wedged command
    nor a chatty one can hold the caller or fill its memory.
    """
    try:
        proc = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL if stdin_bytes is None else subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return 127, "" if text else b""
    if stdin_bytes is not None:
        threading.Thread(target=_feed, args=(proc.stdin, stdin_bytes), daemon=True).start()
    deadline = time.monotonic() + timeout
    chunks: list[bytes] = []
    size = 0
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while True:
                left = deadline - time.monotonic()
                if left <= 0:
                    raise TimeoutError
                if not selector.select(left):
                    continue
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    break
                size += len(chunk)
                if size > max_bytes:
                    raise OverflowError
                chunks.append(chunk)
        code = proc.wait(timeout=max(0.0, deadline - time.monotonic()))
    except (TimeoutError, OverflowError, subprocess.TimeoutExpired):
        _kill_group(proc)
        return 127, "" if text else b""
    except BaseException:
        _kill_group(proc)
        raise
    finally:
        proc.stdout.close()
    out = b"".join(chunks)
    return code, out.decode("utf-8", "replace").strip() if text else out


def _feed(pipe: Any, data: bytes) -> None:
    try:
        pipe.write(data)
    except OSError:
        pass  # the command stopped reading; its exit code says why
    finally:
        try:
            pipe.close()
        except OSError:
            pass
