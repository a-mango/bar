#!/usr/bin/python3
"""Stacks review clips (tests/clip.sh) top to bottom, aligned on the first
frame that shows the note's leading edge, for an A/B look at the same
moment of each variant:

    tests/clip-ab.py OUT.mp4 CLIP.mp4 CLIP.mp4 [...]

Runs on the host (it only reads files). The edge is a column of one of
the EDGES colors over the strip's height: dark base0D (the line with the
halo, up to v1.1) or white (dark base07, Theme.onCritical).
"""
import subprocess
import sys

from PIL import Image

EDGES = [(0x7C, 0xAF, 0xC2), (0xF8, 0xF8, 0xF8)]
W, H = 3840, 192
ROWS = (152, 170, 188)  # the strip, below the progress line
SPAN = range(400, 3700, 2)  # between the workspaces (white focused button) and the tray


def is_edge(im, x):
    px = [im.getpixel((x, y)) for y in ROWS]
    return px[0] == px[1] == px[2] and px[0] in EDGES


def first_edge(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-t", "4", "-vsync", "0",
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         check=True, capture_output=True).stdout
    times = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-read_intervals", "%+4",
                            "-show_entries", "frame=pts_time", "-of", "csv=p=0", path],
                           check=True, capture_output=True, text=True).stdout.split()
    n = len(raw) // (W * H * 3)
    for i in range(n):
        im = Image.frombytes("RGB", (W, H), raw[i * W * H * 3:(i + 1) * W * H * 3])
        if any(is_edge(im, x) for x in SPAN):
            return float(times[i].split(",")[0])  # newer ffprobe appends ","
    raise SystemExit(f"clip-ab: no edge in the first 4 s of {path}")


out, clips = sys.argv[1], sys.argv[2:]
starts = [first_edge(c) for c in clips]
print("edge first seen (s):", " ".join(f"{s:.3f}" for s in starts), file=sys.stderr)
args = ["ffmpeg", "-v", "error", "-y"]
for c, s in zip(clips, starts):
    args += ["-ss", f"{max(0.0, s - 1.0):.3f}", "-i", c]
inputs = "".join(f"[{i}]" for i in range(len(clips)))
args += ["-filter_complex", f"{inputs}vstack=inputs={len(clips)}", "-c:v", "libx264rgb", "-crf", "0",
         "-preset", "ultrafast", out]
subprocess.run(args, check=True)
print(f"clip-ab: {out}", file=sys.stderr)
