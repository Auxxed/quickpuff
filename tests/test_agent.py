"""The pairing agent says yes for the Peak being connected and nothing else.

While registered it is the system's default Bluetooth agent, so before this
every device in range could pair, and have any service authorized, without a
prompt. No D-Bus here: the methods are called directly.
"""

import asyncio

import pytest
from dbus_fast import DBusError

from quickpuff import agent as agent_module
from quickpuff.agent import JustWorksAgent, PairingAgent, device_path_name

PEAK = "AA:BB:CC:11:22:33"
PEAK_PATH = "/org/bluez/hci0/dev_AA_BB_CC_11_22_33"
STRANGER_PATH = "/org/bluez/hci0/dev_DE_AD_BE_EF_00_01"


def call(agent, name, *args):
    """The method body itself: dbus_fast's wrapper drops return values."""
    return getattr(type(agent), name).__wrapped__(agent, *args)


def rejected(fn, *args):
    with pytest.raises(DBusError) as info:
        fn(*args)
    assert info.value.type == "org.bluez.Error.Rejected"
    return True


@pytest.fixture
def peak_agent():
    agent = JustWorksAgent()
    agent.allow(PEAK)
    return agent


def test_address_becomes_the_bluez_object_name():
    assert device_path_name("aa:bb:cc:11:22:33") == "dev_AA_BB_CC_11_22_33"
    assert device_path_name(" AA:BB:CC:11:22:33 ") == "dev_AA_BB_CC_11_22_33"


@pytest.mark.parametrize(
    "bad",
    ["", "AA:BB:CC:11:22", "AA:BB:CC:11:22:33:44", "AA-BB-CC-11-22-33", "GG:BB:CC:11:22:33", "../x", None, 7],
)
def test_anything_but_an_address_is_refused(bad):
    with pytest.raises(ValueError):
        JustWorksAgent().allow(bad)


def test_the_peak_is_accepted_on_any_adapter(peak_agent):
    for path in (PEAK_PATH, "/org/bluez/hci1/dev_AA_BB_CC_11_22_33"):
        assert call(peak_agent, "RequestPinCode", path) == "000000"
        assert call(peak_agent, "RequestPasskey", path) == 0
        call(peak_agent, "RequestConfirmation", path, 123456)
        call(peak_agent, "RequestAuthorization", path)
        call(peak_agent, "DisplayPasskey", path, 123456, 0)
        call(peak_agent, "DisplayPinCode", path, "1234")


@pytest.mark.parametrize(
    "name,extra",
    [
        ("RequestPinCode", ()),
        ("RequestPasskey", ()),
        ("RequestConfirmation", (123456,)),
        ("RequestAuthorization", ()),
        ("DisplayPasskey", (123456, 0)),
        ("DisplayPinCode", ("1234",)),
    ],
)
def test_every_other_device_is_rejected(peak_agent, name, extra):
    method = getattr(peak_agent, name)  # through dbus_fast's own wrapper too
    assert rejected(method, STRANGER_PATH, *extra)
    # Only the whole last component counts, not a path that merely ends the same.
    assert rejected(method, "/org/bluez/hci0/xdev_AA_BB_CC_11_22_33", *extra)
    assert rejected(method, PEAK_PATH + "/extra", *extra)


def test_with_no_peak_named_yet_everything_is_rejected():
    agent = JustWorksAgent()
    assert rejected(agent.RequestAuthorization, PEAK_PATH)
    assert rejected(agent.RequestConfirmation, PEAK_PATH, 1)


def test_authorize_service_is_rejected_even_for_the_peak(peak_agent):
    hid = "00001124-0000-1000-8000-00805f9b34fb"
    assert rejected(peak_agent.AuthorizeService, PEAK_PATH, hid)
    assert rejected(peak_agent.AuthorizeService, STRANGER_PATH, hid)


def test_allowing_another_peak_forgets_the_first(peak_agent):
    peak_agent.allow("11:22:33:44:55:66")
    assert rejected(peak_agent.RequestAuthorization, PEAK_PATH)
    call(peak_agent, "RequestAuthorization", "/org/bluez/hci0/dev_11_22_33_44_55_66")


def test_pairing_agent_hands_the_address_to_the_exported_agent():
    pairing = PairingAgent()
    pairing.allow(PEAK)
    call(pairing._agent, "RequestAuthorization", PEAK_PATH)
    assert rejected(pairing._agent.RequestAuthorization, STRANGER_PATH)


# ---- how connect() uses it ------------------------------------------------------------


class FakeAgent:
    instances = []

    def __init__(self):
        self.events = []
        FakeAgent.instances.append(self)

    async def start(self):
        self.events.append("start")

    def allow(self, address):
        self.events.append(("allow", address))

    async def stop(self):
        self.events.append("stop")


class FakeClient:
    is_connected = True

    async def disconnect(self):
        pass


def connect_with(monkeypatch, bonded):
    from quickpuff.ble import PuffcoBLE

    FakeAgent.instances.clear()
    monkeypatch.setattr(agent_module, "PairingAgent", FakeAgent)
    ble = PuffcoBLE(device_mac=PEAK)

    async def gatt(address):
        FakeAgent.instances[-1].events.append(("gatt", address))
        return FakeClient()

    async def handshake(client):
        return bonded

    monkeypatch.setattr(ble, "_gatt_connect", gatt)
    monkeypatch.setattr(ble, "_lorax_handshake", handshake)
    asyncio.run(ble.connect())
    return ble, FakeAgent.instances[-1].events


def test_connect_names_the_peak_before_connecting_and_lets_go_once_bonded(monkeypatch):
    ble, events = connect_with(monkeypatch, bonded=True)
    assert events == ["start", ("allow", PEAK), ("gatt", PEAK), "stop"]
    assert ble._pairing_agent is None


def test_a_peak_that_did_not_bond_keeps_the_restricted_agent_until_disconnect(monkeypatch):
    ble, events = connect_with(monkeypatch, bonded=False)
    assert events == ["start", ("allow", PEAK), ("gatt", PEAK)]
    assert ble._pairing_agent is not None
    ble.client = None
    asyncio.run(ble.disconnect())
    assert events[-1] == "stop"
