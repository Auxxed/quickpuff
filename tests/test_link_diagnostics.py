"""Cleaning up after a lost link, and recording why links end."""

import asyncio
from quickpuff.ble import PuffcoBLE


class DeadClient:
    """A BleakClient whose link has already dropped."""

    def __init__(self):
        self.is_connected = False
        self.disconnect_calls = 0

    async def disconnect(self):
        self.disconnect_calls += 1


def test_a_link_that_already_dropped_is_still_disconnected_in_bleak():
    """Bleak closes its D-Bus connection in disconnect() even for a dead link,
    and that connection owns the StartNotify session. Skipping the call left the
    session open: each later link received every reply once per earlier drop."""

    async def scenario():
        ble = PuffcoBLE(device_mac="AA:BB:CC:DD:EE:FF")
        client = DeadClient()
        ble.client = client
        await ble.disconnect()
        assert client.disconnect_calls == 1
        assert ble.client is None

    asyncio.run(scenario())
