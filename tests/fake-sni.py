#!/usr/bin/python3
"""Fake tray item for the nested session (spike S9, matrix case B5).

It registers one StatusNotifierItem with a small com.canonical.dbusmenu
menu on the private bus and logs every call it receives to
.test/logs/fake-sni.log. Real applets act on the real system, so activation
and menu-click tests use this item instead.

    tests/nested.sh run tests/fake-sni.py

FAKE_SNI_STATUS sets the first status (Active by default), FAKE_SNI_PIDFILE
a file to write the process id to. SIGUSR1 sets
the status to NeedsAttention, SIGUSR2 to Active, SIGHUP to Passive.
All texts are fictional.
"""
import asyncio
import os
import signal as signals
import sys
import time

from dbus_next import PropertyAccess, Variant
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, dbus_property, method, signal

if "BAR_TEST_DIR" not in os.environ:
    sys.exit("fake-sni: run me inside the nested session (tests/nested.sh run tests/fake-sni.py)")

LOG = open(os.path.join(os.environ["BAR_TEST_DIR"], "logs", "fake-sni.log"), "a", buffering=1)


def log(*parts):
    line = time.strftime("%H:%M:%S ") + f"[{os.getpid()}] " + " ".join(str(part) for part in parts)
    print(line, flush=True)
    LOG.write(line + "\n")


# id -> properties. Id 0 is the root.
MENU = {
    1: {"label": Variant("s", "Open demo window")},
    2: {"label": Variant("s", "Sync demo data")},
    3: {"type": Variant("s", "separator")},
    4: {"label": Variant("s", "Quit demo applet")},
}


def icon_pixmap():
    """One 16x16 ARGB32 pixmap in network byte order: a filled square with a border."""
    data = bytearray()
    for y in range(16):
        for x in range(16):
            edge = x in (0, 15) or y in (0, 15)
            data += bytes((255, 40, 40, 40)) if edge else bytes((255, 161, 181, 108))
    return [[16, 16, bytes(data)]]


class Item(ServiceInterface):
    def __init__(self):
        super().__init__("org.kde.StatusNotifierItem")
        self.status = os.environ.get("FAKE_SNI_STATUS", "Active")

    @dbus_property(access=PropertyAccess.READ)
    def Category(self) -> "s":
        return "ApplicationStatus"

    @dbus_property(access=PropertyAccess.READ)
    def Id(self) -> "s":
        return "fake-sni"

    @dbus_property(access=PropertyAccess.READ)
    def Title(self) -> "s":
        return "Fake tray item"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return self.status

    @dbus_property(access=PropertyAccess.READ)
    def WindowId(self) -> "i":
        return 0

    @dbus_property(access=PropertyAccess.READ)
    def IconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def IconPixmap(self) -> "a(iiay)":
        return icon_pixmap()

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def AttentionMovieName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def ToolTip(self) -> "(sa(iiay)ss)":
        return ["", [], "Fake tray item", "A fictional applet for tests"]

    @dbus_property(access=PropertyAccess.READ)
    def ItemIsMenu(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Menu(self) -> "o":
        return "/MenuBar"

    @dbus_property(access=PropertyAccess.READ)
    def IconThemePath(self) -> "s":
        return ""

    @method()
    def Activate(self, x: "i", y: "i"):
        log("Activate", x, y)

    @method()
    def SecondaryActivate(self, x: "i", y: "i"):
        log("SecondaryActivate", x, y)

    @method()
    def ContextMenu(self, x: "i", y: "i"):
        log("ContextMenu", x, y)

    @method()
    def Scroll(self, delta: "i", orientation: "s"):
        log("Scroll", delta, orientation)

    @signal()
    def NewStatus(self) -> "s":
        return self.status

    def set_status(self, status):
        self.status = status
        log("status", status)
        self.NewStatus()


class Menu(ServiceInterface):
    def __init__(self):
        super().__init__("com.canonical.dbusmenu")

    @dbus_property(access=PropertyAccess.READ)
    def Version(self) -> "u":
        return 3

    @dbus_property(access=PropertyAccess.READ)
    def TextDirection(self) -> "s":
        return "ltr"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return "normal"

    @dbus_property(access=PropertyAccess.READ)
    def IconThemePath(self) -> "as":
        return []

    @method()
    def GetLayout(self, parent: "i", depth: "i", names: "as") -> "u(ia{sv}av)":
        log("GetLayout", parent, depth)
        if parent == 0:
            children = [Variant("(ia{sv}av)", [item, props, []]) for item, props in MENU.items()]
            return [1, [0, {"children-display": Variant("s", "submenu")}, children]]
        return [1, [parent, MENU.get(parent, {}), []]]

    @method()
    def GetGroupProperties(self, ids: "ai", names: "as") -> "a(ia{sv})":
        log("GetGroupProperties", ids)
        return [[item, MENU[item]] for item in (ids or MENU) if item in MENU]

    @method()
    def GetProperty(self, item: "i", name: "s") -> "v":
        log("GetProperty", item, name)
        return MENU.get(item, {}).get(name, Variant("s", ""))

    @method()
    def Event(self, item: "i", event: "s", data: "v", timestamp: "u"):
        label = MENU.get(item, {}).get("label")
        log("Event", item, event, repr(label.value) if label else "")

    @method()
    def EventGroup(self, events: "a(isvu)") -> "ai":
        for item, event, _data, _timestamp in events:
            label = MENU.get(item, {}).get("label")
            log("Event", item, event, repr(label.value) if label else "")
        return []

    @method()
    def AboutToShow(self, item: "i") -> "b":
        log("AboutToShow", item)
        return False

    @method()
    def AboutToShowGroup(self, ids: "ai") -> "aiai":
        log("AboutToShowGroup", ids)
        return [[], []]

    @signal()
    def LayoutUpdated(self) -> "ui":
        return [1, 0]


async def main():
    if os.environ.get("FAKE_SNI_PIDFILE"):
        with open(os.environ["FAKE_SNI_PIDFILE"], "w") as pidfile:
            print(os.getpid(), file=pidfile)
    bus = await MessageBus().connect()
    item = Item()
    bus.export("/StatusNotifierItem", item)
    bus.export("/MenuBar", Menu())
    name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
    await bus.request_name(name)

    introspection = await bus.introspect("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
    watcher = bus.get_proxy_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", introspection)
    await watcher.get_interface("org.kde.StatusNotifierWatcher").call_register_status_notifier_item(name)
    log("registered", name)

    loop = asyncio.get_running_loop()
    loop.add_signal_handler(signals.SIGUSR1, item.set_status, "NeedsAttention")
    loop.add_signal_handler(signals.SIGUSR2, item.set_status, "Active")
    loop.add_signal_handler(signals.SIGHUP, item.set_status, "Passive")
    await bus.wait_for_disconnect()


asyncio.run(main())
