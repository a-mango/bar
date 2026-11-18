#!/usr/bin/python3
"""Wheel and touchpad scrolling for the nested session.

`swaymsg seat seat0 cursor press button4` reaches clients as an
axis_value120 of 1 instead of 120 (a twelfth of a degree), so a handler that
counts notches never sees one. This script creates a short-lived pointer
through the wlr-virtual-pointer protocol, like tests/vpointer.py, scrolls at
the current cursor position and exits:

    tests/nested.sh run tests/wheel.py notch <n>        n wheel notches (negative: up)
    tests/nested.sh run tests/wheel.py finger <px> <k>  a touchpad swipe: k frames of px each

It speaks the Wayland wire protocol directly and refuses to run outside the
nested session.
"""
import os
import socket
import struct
import sys
import time

if "BAR_TEST_DIR" not in os.environ:
    sys.exit("wheel: run me inside the nested session (tests/nested.sh run tests/wheel.py ...)")

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


def fixed(v):
    return int(round(v * 256))


def ms():
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


DISPLAY, REGISTRY, CALLBACK, MANAGER, POINTER, CALLBACK2 = 1, 2, 3, 4, 5, 6
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
    sys.exit("wheel: the compositor has no zwlr_virtual_pointer_manager_v1")

request(REGISTRY, 0, struct.pack("<I", manager) + string("zwlr_virtual_pointer_manager_v1") + struct.pack("<II", 1, MANAGER))
request(MANAGER, 0, struct.pack("<II", 0, POINTER))  # create_virtual_pointer(seat = null)

VERTICAL, WHEEL, FINGER = 0, 0, 1
mode = sys.argv[1] if len(sys.argv) > 1 else ""
if mode == "notch":
    n = int(sys.argv[2])
    for _ in range(abs(n)):
        step = 1 if n > 0 else -1
        request(POINTER, 5, struct.pack("<I", WHEEL))  # axis_source
        # axis_discrete(time, axis, value, discrete): wlroots sends value120 = discrete * 120
        request(POINTER, 7, struct.pack("<IIii", ms(), VERTICAL, fixed(15 * step), step))
        request(POINTER, 4)  # frame
        time.sleep(0.05)
elif mode == "finger":
    px, frames = float(sys.argv[2]), int(sys.argv[3])
    for _ in range(frames):
        request(POINTER, 5, struct.pack("<I", FINGER))
        request(POINTER, 3, struct.pack("<IIi", ms(), VERTICAL, fixed(px)))  # axis
        request(POINTER, 4)
        time.sleep(0.016)
    request(POINTER, 5, struct.pack("<I", FINGER))
    request(POINTER, 6, struct.pack("<II", ms(), VERTICAL))  # axis_stop
    request(POINTER, 4)
else:
    sys.exit(__doc__)

request(POINTER, 8)  # destroy
request(DISPLAY, 0, struct.pack("<I", CALLBACK2))  # sync: the compositor has read everything
for obj, opcode, payload in events():
    if obj == CALLBACK2:
        break
