"""Newline-delimited JSON client for the QuickPuff daemon."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Any

from .paths import socket_path


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
    reader, writer = await asyncio.open_unix_connection(str(sock))
    try:
        writer.write((json.dumps({"id": 1, "cmd": cmd, "args": args or {}}) + "\n").encode())
        await writer.drain()
        while True:
            line = await asyncio.wait_for(reader.readline(), timeout=timeout)
            if not line:
                raise RuntimeError("Daemon closed the connection")
            msg = json.loads(line.decode())
            if msg.get("event"):
                continue
            if not msg.get("ok"):
                raise RuntimeError(msg.get("error") or "command failed")
            return msg.get("result")
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
