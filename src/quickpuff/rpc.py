"""Newline-delimited JSON client for the QuickPuff daemon."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Any

from .paths import loads_json, socket_path


class DaemonNotRunning(RuntimeError):
    pass


async def rpc(
    cmd: str,
    args: dict | None = None,
    timeout: float = 30.0,
    path: Path | None = None,
) -> Any:
    sock = path or socket_path()
    if not sock.exists():
        raise DaemonNotRunning(f"QuickPuff daemon is not running ({sock})")
    try:
        reader, writer = await asyncio.open_unix_connection(str(sock))
    except (FileNotFoundError, ConnectionRefusedError) as exc:
        # Gone since the check, or a socket left behind by a daemon that was killed.
        raise DaemonNotRunning(f"QuickPuff daemon is not running ({sock})") from exc
    try:
        writer.write((json.dumps({"id": 1, "cmd": cmd, "args": args or {}}) + "\n").encode())
        await writer.drain()
        while True:
            line = await asyncio.wait_for(reader.readline(), timeout=timeout)
            if not line:
                raise RuntimeError("Daemon closed the connection")
            try:
                msg = loads_json(line.decode())
            except ValueError as exc:
                raise RuntimeError(f"The daemon sent something that isn't JSON ({exc})") from exc
            if not isinstance(msg, dict):
                raise RuntimeError("The daemon sent something that isn't a reply")
            if msg.get("event"):
                continue
            if not msg.get("ok"):
                raise RuntimeError(msg.get("error") or "command failed")
            return msg.get("result")
    except ConnectionError as exc:
        # Turned away (another user's daemon, or too many clients), or it
        # went away mid-reply.
        raise RuntimeError("Daemon closed the connection") from exc
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
