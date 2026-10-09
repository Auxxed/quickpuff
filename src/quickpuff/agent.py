"""BlueZ Just Works pairing agent.

GNOME/blueman cancel unsolicited Pair() requests from a systemd service
(AuthenticationCanceled). This agent auto-accepts LE Just Works so the
Peak can bond after the Lorax VERSION_CHAR read.

It says yes for the Peak being connected and for nothing else. While it is
registered it is the system's default agent, so every pairing and every
service authorization BlueZ can't settle by itself comes here; accepting
those for any device would let anything in range pair without a prompt
(a keyboard that types, say). Everything but the Peak is rejected, and so
is AuthorizeService for every device: QuickPuff only ever acts as a GATT
client, which never needs it, and the Peak is marked trusted before the
link comes up anyway.
"""

from __future__ import annotations

import logging
import re

from dbus_fast import BusType, DBusError
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, method

log = logging.getLogger("puffcoble.agent")

AGENT_PATH = "/puffco/agent"
BLUEZ = "org.bluez"
AGENT_MANAGER = "org.bluez.AgentManager1"
REJECTED = "org.bluez.Error.Rejected"

# A Bluetooth device address as BlueZ prints it.
ADDRESS = re.compile(r"[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}")


def device_path_name(address: str) -> str:
    """The last part of a device's BlueZ object path: AA:BB:CC:DD:EE:FF is
    /org/bluez/hciN/dev_AA_BB_CC_DD_EE_FF, whichever adapter it is on."""
    text = address.strip() if isinstance(address, str) else ""
    if not ADDRESS.fullmatch(text):
        raise ValueError(f"Not a Bluetooth address: {address!r}")
    return "dev_" + text.upper().replace(":", "_")


class JustWorksAgent(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.Agent1")
        # Last path parts of the devices this agent may say yes for. Empty
        # until connect() names the Peak, and until then it refuses everyone.
        self._allowed: frozenset[str] = frozenset()

    def allow(self, address: str) -> None:
        """Say yes for this Peak, and only this one, from now on."""
        self._allowed = frozenset({device_path_name(address)})

    def _check(self, device: str) -> None:
        """Raise Rejected unless `device` is the Peak this agent is for.

        The whole last component of the object path has to match, so
        dev_AA_BB_CC_DD_EE_FF doesn't also let in a longer path that merely
        ends the same way."""
        name = str(device).rsplit("/", 1)[-1]
        if name not in self._allowed:
            log.warning("agent: refused %s, which is not the Peak being connected", device)
            raise DBusError(REJECTED, "not the Peak")

    @method()
    def Release(self):
        log.debug("agent Release")

    @method()
    def Cancel(self):
        log.debug("agent Cancel")

    @method()
    def RequestPinCode(self, device: "o") -> "s":
        self._check(device)
        log.info("agent PIN requested for %s", device)
        return "000000"

    @method()
    def DisplayPinCode(self, device: "o", pincode: "s"):
        self._check(device)
        log.info("agent display PIN %s for %s", pincode, device)

    @method()
    def RequestPasskey(self, device: "o") -> "u":
        self._check(device)
        log.info("agent passkey requested for %s", device)
        return 0

    @method()
    def DisplayPasskey(self, device: "o", passkey: "u", entered: "q"):
        self._check(device)
        log.info("agent display passkey %s for %s", passkey, device)

    @method()
    def RequestConfirmation(self, device: "o", passkey: "u"):
        self._check(device)
        log.info("agent confirming passkey %s for %s", passkey, device)

    @method()
    def RequestAuthorization(self, device: "o"):
        self._check(device)
        log.info("agent authorizing %s", device)

    @method()
    def AuthorizeService(self, device: "o", uuid: "s"):
        # A GATT client never needs a service authorized, and the Peak is
        # trusted before the link comes up, so this is never the Peak asking.
        log.warning("agent: refused service %s for %s", uuid, device)
        raise DBusError(REJECTED, "QuickPuff authorizes no services")


class PairingAgent:
    def __init__(self):
        self._bus: MessageBus | None = None
        self._registered = False
        self._agent = JustWorksAgent()

    def allow(self, address: str) -> None:
        """The Peak this connect is for: the only device the agent accepts."""
        self._agent.allow(address)

    async def start(self) -> None:
        if self._registered:
            return
        self._bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
        self._bus.export(AGENT_PATH, self._agent)
        introspect = await self._bus.introspect(BLUEZ, "/org/bluez")
        obj = self._bus.get_proxy_object(BLUEZ, "/org/bluez", introspect)
        manager = obj.get_interface(AGENT_MANAGER)
        try:
            await manager.call_register_agent(AGENT_PATH, "NoInputNoOutput")
        except Exception as exc:
            log.debug("RegisterAgent: %s", exc)
            try:
                await manager.call_unregister_agent(AGENT_PATH)
            except Exception:
                pass
            await manager.call_register_agent(AGENT_PATH, "NoInputNoOutput")
        try:
            await manager.call_request_default_agent(AGENT_PATH)
            log.info("Registered default NoInputNoOutput (Just Works) Bluetooth agent")
        except Exception as exc:
            log.warning("Could not become default Bluetooth agent: %s", exc)
        self._registered = True

    async def stop(self) -> None:
        if not self._bus:
            return
        try:
            introspect = await self._bus.introspect(BLUEZ, "/org/bluez")
            obj = self._bus.get_proxy_object(BLUEZ, "/org/bluez", introspect)
            manager = obj.get_interface(AGENT_MANAGER)
            await manager.call_unregister_agent(AGENT_PATH)
        except Exception:
            pass
        try:
            self._bus.disconnect()
        except Exception:
            pass
        self._bus = None
        self._registered = False

    async def __aenter__(self) -> "PairingAgent":
        await self.start()
        return self

    async def __aexit__(self, *_exc) -> None:
        await self.stop()
