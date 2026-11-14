#!/usr/bin/python3
"""Virtual pointer for the nested session.

A headless sway has no input device, so seat0 has no pointer capability and
`swaymsg seat seat0 cursor ...` reaches no client (spike S4). This script
creates a pointer through the wlr-virtual-pointer protocol and keeps it
alive until the compositor exits. While it runs, the `seat seat0 cursor set/press/
release` commands synthesize real pointer events.

It speaks the Wayland wire protocol directly (no pywayland on this system)
and refuses to run outside the nested session:

    tests/nested.sh run tests/vpointer.py

tests/nested.sh starts it with every session.
"""
import os
import socket
import struct
import sys

if "BAR_TEST_DIR" not in os.environ:
    sys.exit("vpointer: run me inside the nested session (tests/nested.sh run tests/vpointer.py)")

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"]))


def string(text):
    data = text.encode() + b"\0"
    return struct.pack("<I", len(data)) + data + b"\0" * (-len(data) % 4)


def request(obj, opcode, payload=b""):
    sock.sendall(struct.pack("<IHH", obj, opcode, 8 + len(payload)) + payload)


def events():
    buf = b""
    while True:
        while len(buf) < 8:
            buf += sock.recv(4096)
        obj, opcode, size = struct.unpack("<IHH", buf[:8])
        while len(buf) < size:
            buf += sock.recv(4096)
        yield obj, opcode, buf[8:size]
        buf = buf[size:]


DISPLAY, REGISTRY, CALLBACK, MANAGER, POINTER = 1, 2, 3, 4, 5
request(DISPLAY, 1, struct.pack("<I", REGISTRY))  # wl_display.get_registry
request(DISPLAY, 0, struct.pack("<I", CALLBACK))  # wl_display.sync

manager = None
for obj, opcode, payload in events():
    if obj == REGISTRY and opcode == 0:  # wl_registry.global
        name, length = struct.unpack("<II", payload[:8])
        if payload[8:8 + length - 1].decode() == "zwlr_virtual_pointer_manager_v1":
            manager = name
    elif obj == CALLBACK:
        break
if manager is None:
    sys.exit("vpointer: the compositor has no zwlr_virtual_pointer_manager_v1")

# wl_registry.bind(name, interface, version, new_id)
request(REGISTRY, 0, struct.pack("<I", manager) + string("zwlr_virtual_pointer_manager_v1") + struct.pack("<II", 1, MANAGER))
# zwlr_virtual_pointer_manager_v1.create_virtual_pointer(seat = null, new_id)
request(MANAGER, 0, struct.pack("<II", 0, POINTER))
print("vpointer: virtual pointer created", flush=True)
while sock.recv(4096):  # returns b"" when the compositor goes away
    pass
