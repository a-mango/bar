#!/usr/bin/python3
"""Frame series: commands and screenshots on a fixed schedule, each
screenshot stamped with the time of the frame it shows. Run it inside the
nested session only:

    tests/nested.sh run tests/frames.py OUT_DIR [--region "X,Y WxH"] EVENT...

EVENT is "<ms> shot" or "<ms> run <command line>", in ms after the start.
Commands start on time in the background. The region is in logical px of
HEADLESS-1 (default: the overlay window, "0,1104 1920x96").

Why not grim: grim 1.5 uses ext-image-copy-capture, which reads back the
whole 3840x2400 output for every shot, even with -g. That blocks the
compositor for about 80 ms per shot, delays the next shots and stalls
Quickshell, so the series would show a slowed-down animation. This tool
keeps one Wayland connection and uses wlr-screencopy's
capture_output_region, which copies only the region (shm buffer). It speaks
the wire protocol directly, like tests/vpointer.py.

Frame time: the `ready` event carries the time of the output frame that
was copied, in CLOCK_MONOTONIC (the clock of time.monotonic()). The tool
checks that it lies between the request and the event, else it falls back
to the request time and marks the shot "clock": "request".

Writes, in OUT_DIR:
    t<ms>.png       one file per shot, named after the requested time
    frames.json     the schedule with actual times and the commands' output
    sheet.png       the shots stacked top to bottom, each with its times
Prints frames.json to stdout.
"""
import json
import mmap
import os
import select
import shlex
import socket
import struct
import subprocess
import sys
import threading
import time

from PIL import Image, ImageDraw, ImageFont

if "BAR_TEST_DIR" not in os.environ:
    sys.exit("frames: run me inside the nested session (tests/nested.sh run tests/frames.py ...)")

OUTPUT = "HEADLESS-1"
# wl_shm formats: memory byte order for PIL's raw decoder.
FORMATS = {0: "BGRX", 1: "BGRX", 0x34324258: "RGBX", 0x34324241: "RGBX"}


# ---- Wayland wire protocol ------------------------------------------------

def string(text):
    data = text.encode() + b"\0"
    return struct.pack("<I", len(data)) + data + b"\0" * (-len(data) % 4)


def unstring(payload, offset=0):
    length = struct.unpack_from("<I", payload, offset)[0]
    text = payload[offset + 4:offset + 4 + length - 1].decode()
    return text, offset + 4 + length + (-length % 4)


class Wayland:
    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"]))
        self.buf = b""
        self.next_id = 2
        self.handlers = {}

    def new_id(self, handler=None):
        oid = self.next_id
        self.next_id += 1
        if handler:
            self.handlers[oid] = handler
        return oid

    def request(self, obj, opcode, payload=b"", fd=None):
        msg = struct.pack("<IHH", obj, opcode, 8 + len(payload)) + payload
        if fd is None:
            self.sock.sendall(msg)
        else:
            socket.send_fds(self.sock, [msg], [fd])

    def dispatch(self, timeout):
        """Handles every message that arrives within `timeout` seconds."""
        if not select.select([self.sock], [], [], max(0, timeout))[0]:
            return
        data = self.sock.recv(65536)
        if not data:
            sys.exit("frames: the compositor closed the connection")
        self.buf += data
        while len(self.buf) >= 8:
            obj, opcode, size = struct.unpack_from("<IHH", self.buf)
            if len(self.buf) < size:
                break
            payload, self.buf = self.buf[8:size], self.buf[size:]
            if obj == 1 and opcode == 0:
                oid, code = struct.unpack_from("<II", payload)
                sys.exit(f"frames: protocol error on object {oid}, code {code}: {unstring(payload, 8)[0]}")
            handler = self.handlers.get(obj)
            if handler:
                handler(opcode, payload)

    def roundtrip(self):
        done = []
        callback = self.new_id(lambda opcode, payload: done.append(True))
        self.request(1, 0, struct.pack("<I", callback))  # wl_display.sync
        while not done:
            self.dispatch(1.0)


class Screencopy:
    """Region captures of one output through zwlr_screencopy_manager_v1."""

    def __init__(self, wl, output_name):
        self.wl = wl
        globals_ = []

        def on_global(opcode, payload):  # wl_registry.global(name, interface, version)
            interface, end = unstring(payload, 4)
            globals_.append((struct.unpack_from("<I", payload)[0], interface, struct.unpack_from("<I", payload, end)[0]))

        registry = wl.new_id(on_global)
        wl.request(1, 1, struct.pack("<I", registry))  # wl_display.get_registry
        wl.roundtrip()

        def bind(name, interface, version, handler=None):
            oid = wl.new_id(handler)
            wl.request(registry, 0, struct.pack("<I", name) + string(interface) + struct.pack("<II", version, oid))
            return oid

        def output_handler(names):
            def on_output(opcode, payload):
                if opcode == 4:  # wl_output.name (v4)
                    names.append(unstring(payload)[0])
            return on_output

        self.manager, outputs = None, []
        for name, interface, version in globals_:
            if interface == "wl_shm":
                self.shm = bind(name, interface, 1)
            elif interface == "zwlr_screencopy_manager_v1" and version >= 3:
                self.manager = bind(name, interface, 3)
            elif interface == "wl_output" and version >= 4:
                names = []
                outputs.append((bind(name, interface, 4, output_handler(names)), names))
        if self.manager is None:
            sys.exit("frames: the compositor has no zwlr_screencopy_manager_v1 version 3")
        wl.roundtrip()
        matches = [oid for oid, names in outputs if output_name in names]
        if not matches:
            sys.exit(f"frames: no output named {output_name}")
        self.output = matches[0]
        self.pending = 0

    def capture(self, shot, region, t0):
        """Starts a capture. `shot` gets file, request_ms, frame_ms, clock."""
        (x, y), (w, h) = (map(int, part.replace("x", ",").split(",")) for part in region.split())
        state = {"shm": None}
        requested = time.monotonic()
        shot["request_ms"] = ms(requested, t0)

        def on_frame(opcode, payload):
            if opcode == 0:  # buffer(format, width, height, stride): an shm option
                state["shm"] = struct.unpack_from("<IIII", payload)
            elif opcode == 1:  # flags
                state["flags"] = struct.unpack_from("<I", payload)[0]
            elif opcode == 6:  # buffer_done: every buffer option is known
                self.copy(frame, state)
            elif opcode == 2:  # ready(tv_sec_hi, tv_sec_lo, tv_nsec)
                hi, lo, nsec = struct.unpack_from("<III", payload)
                stamp, now = (hi << 32) + lo + nsec / 1e9, time.monotonic()
                if requested <= stamp <= now:
                    shot["frame_ms"], shot["clock"] = ms(stamp, t0), "frame"
                else:
                    shot["frame_ms"], shot["clock"] = shot["request_ms"], "request"
                self.save(shot, state)
                self.wl.request(frame, 1)  # destroy
                self.pending -= 1
            elif opcode == 3:  # failed
                shot["error"] = "capture failed"
                self.wl.request(frame, 1)
                self.pending -= 1

        frame = self.wl.new_id(on_frame)
        self.pending += 1
        # capture_output_region(frame, overlay_cursor, output, x, y, width, height)
        self.wl.request(self.manager, 1, struct.pack("<IiIiiii", frame, 0, self.output, x, y, w, h))

    def copy(self, frame, state):
        fmt, width, height, stride = state["shm"]
        if fmt not in FORMATS:
            sys.exit(f"frames: unsupported shm format {fmt:#x}")
        size = stride * height
        fd = os.memfd_create("frame", os.MFD_CLOEXEC)
        os.ftruncate(fd, size)
        state["map"] = mmap.mmap(fd, size)
        pool, buffer = self.wl.new_id(), self.wl.new_id()
        self.wl.request(self.shm, 0, struct.pack("<Ii", pool, size), fd=fd)  # wl_shm.create_pool(id, fd, size)
        os.close(fd)
        self.wl.request(pool, 0, struct.pack("<Iiiiii", buffer, 0, width, height, stride, fmt))  # create_buffer
        self.wl.request(pool, 1)  # wl_shm_pool.destroy (the buffer keeps the memory)
        state["buffer"] = buffer
        self.wl.request(frame, 0, struct.pack("<I", buffer))  # zwlr_screencopy_frame_v1.copy

    def save(self, shot, state):
        fmt, width, height, stride = state["shm"]
        img = Image.frombytes("RGB", (width, height), bytes(state["map"]), "raw", FORMATS[fmt], stride, 1).convert("RGB")
        if state.get("flags", 0) & 1:  # y_invert
            img = img.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        img.save(shot["file"])
        state["map"].close()
        self.wl.request(state["buffer"], 0)  # wl_buffer.destroy


# ---- schedule ---------------------------------------------------------------

def usage():
    sys.exit(__doc__)


def parse(argv):
    if len(argv) < 2:
        usage()
    out, region, events = argv[1], "0,1104 1920x96", []
    rest = argv[2:]
    while rest:
        arg = rest.pop(0)
        if arg == "--region":
            region = rest.pop(0)
            continue
        at, _, what = arg.partition(" ")
        kind, _, cmd = what.strip().partition(" ")
        if kind not in ("shot", "run") or (kind == "run" and not cmd):
            usage()
        events.append({"at": int(at), "kind": kind, "cmd": cmd})
    events.sort(key=lambda e: e["at"])
    return out, region, events


def ms(t, t0):
    return round((t - t0) * 1000, 1)


def run(event, t0):
    """Starts a command and returns the thread that waits for it."""
    spawn = time.monotonic()
    proc = subprocess.Popen(shlex.split(event["cmd"]), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    event["spawn_ms"] = ms(spawn, t0)

    def wait():
        stdout, stderr = proc.communicate()
        event["exit_ms"] = ms(time.monotonic(), t0)
        event["status"] = proc.returncode
        event["stdout"] = stdout.strip()
        if stderr.strip():
            event["stderr"] = stderr.strip()

    thread = threading.Thread(target=wait)
    thread.start()
    return thread


def font(size):
    try:
        path = subprocess.run(["fc-match", "-f", "%{file}", "monospace"], capture_output=True, text=True).stdout
        return ImageFont.truetype(path, size)
    except (OSError, ValueError):
        return ImageFont.load_default()


def sheet(out, shots):
    frames = [(s, Image.open(s["file"]).convert("RGB")) for s in shots if "frame_ms" in s]
    if not frames:
        return
    label_h, gap = 44, 8
    width = max(img.width for _, img in frames)
    height = sum(label_h + img.height + gap for _, img in frames)
    canvas = Image.new("RGB", (width, height), (96, 96, 96))
    draw, face, y = ImageDraw.Draw(canvas), font(28), 0
    for s, img in frames:
        text = "requested %d ms   frame at %.1f ms" % (s["at"], s["frame_ms"])
        draw.text((12, y + 6), text, fill=(255, 255, 255), font=face)
        canvas.paste(img, (0, y + label_h))
        y += label_h + img.height + gap
    canvas.save(os.path.join(out, "sheet.png"))


def main():
    out, region, events = parse(sys.argv)
    os.makedirs(out, exist_ok=True)
    wl = Wayland()
    copier = Screencopy(wl, OUTPUT)
    threads = []
    t0 = time.monotonic()
    queue = list(events)
    while queue or copier.pending:
        if queue:
            wait = t0 + queue[0]["at"] / 1000 - time.monotonic()
            if wait > 0:
                wl.dispatch(min(wait, 0.05))
                continue
            event = queue.pop(0)
            if event["kind"] == "shot":
                event["file"] = os.path.join(out, "t%04d.png" % event["at"])
                copier.capture(event, region, t0)
            else:
                threads.append(run(event, t0))
        else:
            wl.dispatch(1.0)
    for thread in threads:
        thread.join()

    shots = [e for e in events if e["kind"] == "shot"]
    sheet(out, shots)
    result = {"region": region, "shots": shots, "runs": [e for e in events if e["kind"] == "run"]}
    with open(os.path.join(out, "frames.json"), "w") as f:
        json.dump(result, f, indent=1)
    json.dump(result, sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    main()
