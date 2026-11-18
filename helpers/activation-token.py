#!/usr/bin/python3
"""Sends an xdg-activation token for a notification (docs/SPEC.md section 5).

    helpers/activation-token.py <notification id>

Notification spec 1.2: before ActionInvoked, the server may emit
ActivationToken(id, token), so that the sender can raise its window. sway
marks a window urgent when it activates with a valid token, and ignores the
token a sender requests on its own from an unfocused window. Quickshell's
notification server sends none, and QML can neither ask the compositor for a
token nor emit a D-Bus signal, so bar runs this before it invokes an action.

The token is requested without serial, seat or surface (wlroots accepts it
and sway then only marks the window urgent), through the Wayland wire
protocol directly (stdlib only, as tests/vpointer.py). The signal goes out
through `gdbus emit` from this process's own connection: clients that match
ActivationToken by sender (GLib) ignore it, kitty does not. The token stays
valid after this process exits.

Exits 0 once the signal is sent, 1 on any failure (bar invokes the action
either way).
"""
import os
import re
import socket
import struct
import subprocess
import sys


def fail(msg):
    print(f"activation-token: {msg}", file=sys.stderr)
    sys.exit(1)


def string(text):
    data = text.encode() + b"\0"
    return struct.pack("<I", len(data)) + data + b"\0" * (-len(data) % 4)


def read_string(data, off):
    (n,) = struct.unpack_from("<I", data, off)
    return data[off + 4:off + 4 + n - 1].decode(), off + 4 + n + (-n % 4)


def token():
    name = os.environ.get("WAYLAND_DISPLAY")
    if not name:
        fail("no WAYLAND_DISPLAY")
    path = name if name.startswith("/") else os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""), name)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(0.3)
    sock.connect(path)

    def request(obj, opcode, payload=b""):
        sock.sendall(struct.pack("<IHH", obj, opcode, 8 + len(payload)) + payload)

    DISPLAY, REGISTRY, CALLBACK, ACTIVATION, TOKEN = 1, 2, 3, 4, 5
    request(DISPLAY, 1, struct.pack("<I", REGISTRY))  # wl_display.get_registry
    request(DISPLAY, 0, struct.pack("<I", CALLBACK))  # wl_display.sync
    buf, bound = b"", False
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            fail("the compositor closed the connection")
        buf += chunk
        while len(buf) >= 8:
            obj, opcode, size = struct.unpack_from("<IHH", buf)
            if len(buf) < size:
                break
            body, buf = buf[8:size], buf[size:]
            if obj == DISPLAY and opcode == 0:  # wl_display.error
                msg, _ = read_string(body, 8)
                fail(f"protocol error: {msg}")
            elif obj == REGISTRY and opcode == 0 and not bound:  # wl_registry.global
                (gname,) = struct.unpack_from("<I", body)
                iface, _ = read_string(body, 4)
                if iface == "xdg_activation_v1":
                    request(REGISTRY, 0, struct.pack("<I", gname) + string(iface) + struct.pack("<II", 1, ACTIVATION))
                    bound = True
            elif obj == CALLBACK and opcode == 0:  # wl_callback.done: every global announced
                if not bound:
                    fail("the compositor has no xdg_activation_v1")
                request(ACTIVATION, 1, struct.pack("<I", TOKEN))  # get_activation_token
                request(TOKEN, 3)  # xdg_activation_token_v1.commit
            elif obj == TOKEN and opcode == 0:  # xdg_activation_token_v1.done
                value, _ = read_string(body, 0)
                request(TOKEN, 4)  # destroy
                return value


if len(sys.argv) != 2 or not sys.argv[1].isdigit():
    fail("usage: activation-token.py <notification id>")
try:
    value = token()
except OSError as e:
    fail(f"wayland: {e}")
if not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
    fail(f"unexpected token {value!r}")
r = subprocess.run(["gdbus", "emit", "--session", "--object-path", "/org/freedesktop/Notifications",
                    "--signal", "org.freedesktop.Notifications.ActivationToken",
                    f"uint32 {sys.argv[1]}", f"'{value}'"], capture_output=True, text=True, timeout=1)
if r.returncode != 0:
    fail(f"gdbus: {r.stderr.strip()}")
