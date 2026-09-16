"""A Lorax command waiting for the transport lock when the link drops."""

import asyncio

import pytest

from quickpuff.ble import PuffcoBLE


class _Client:
    def __init__(self):
        self.is_connected = True


def _peak():
    ble = PuffcoBLE(device_mac="AA:BB:CC:DD:EE:FF")
    ble.client = _Client()
    ble._write_fd = 99

    async def _noop():
        return None

    ble._ensure_notify = _noop
    ble._acquire_command_write = _noop
    return ble


def test_a_drop_while_queued_reports_a_disconnect_not_a_type_error():
    """The usage sync is nearly always queued behind the poll. If the link
    drops meanwhile, the fd is gone by the time its turn comes; writing to it
    raised "'NoneType' object cannot be interpreted as an integer"."""

    async def scenario():
        ble = _peak()
        await ble._lock.acquire()           # the poll holds the transport
        queued = asyncio.create_task(ble.run_command(1, b""))
        await asyncio.sleep(0)              # the sync is now waiting its turn
        ble._on_disconnected(ble.client)    # the link drops
        ble.client.is_connected = False
        ble._lock.release()
        with pytest.raises(RuntimeError, match="Client not connected"):
            await queued

    asyncio.run(scenario())


def test_a_drop_does_not_leave_the_sequence_waiting_on_a_reply():
    async def scenario():
        ble = _peak()
        ble._write_fd = None
        with pytest.raises(RuntimeError, match="Client not connected"):
            await ble.run_command(1, b"")
        assert ble._pending == {}

    asyncio.run(scenario())
