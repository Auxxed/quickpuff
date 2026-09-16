"""Cleaning up after a lost link, and recording why links end."""

import asyncio
import logging
import time

from quickpuff import bluez
from quickpuff.ble import PuffcoBLE
from quickpuff.daemon import QuickPuffDaemon


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


def test_bluez_device_paths_give_back_the_address():
    assert bluez.address_from_path("/org/bluez/hci0/dev_F0_AD_4E_38_6E_3C") == "F0:AD:4E:38:6E:3C"
    assert bluez.address_from_path("/org/bluez/hci0") is None


def _daemon(tmp_path):
    d = QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d._connect_mac = "F0:AD:4E:38:6E:3C"
    return d


def test_why_a_link_ended_is_logged_with_what_the_peak_was_doing(tmp_path, caplog):
    d = _daemon(tmp_path)
    d.status.update({"operating_state": "Session", "heater_temp_f": 534})
    d._link_started = time.monotonic()
    d._on_ble_drop()                       # the state is overwritten here...
    with caplog.at_level(logging.INFO, logger="quickpuff.daemon"):
        d._on_link_ended("f0:ad:4e:38:6e:3c", "org.bluez.Reason.Timeout", "Connection timeout")
    line = next(r.getMessage() for r in caplog.records if "Bluetooth link ended" in r.getMessage())
    assert "timeout (Connection timeout)" in line
    assert "while Session, 534°F" in line  # ...but what it was doing survives


def test_other_devices_ending_their_links_are_not_logged(tmp_path, caplog):
    d = _daemon(tmp_path)
    with caplog.at_level(logging.INFO, logger="quickpuff.daemon"):
        d._on_link_ended("11:22:33:44:55:66", "org.bluez.Reason.Remote", "Connection terminated by remote user")
    assert not [r for r in caplog.records if "Bluetooth link ended" in r.getMessage()]
