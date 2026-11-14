#!/usr/bin/python3
"""Frame series of the bar strip, for animation checks (docs/PLAN.md M3, M4).

    tests/frames.py OUT_DIR LABEL SLOW T1 T2 ... [-- COMMAND...]

Runs COMMAND (if any) inside the nested session, then grabs the bottom
24 px of HEADLESS-1 at the animation times T1, T2, ... (ms). With bar's
slow motion (`debug slow SLOW`), animation time t is reached after
t * SLOW ms of real time. Each grab starts on its own (grim -l 0 on the
strip only), so a slow grab does not delay the next one. The real start
time of every grab is recorded, and the frames are stacked into
OUT_DIR/LABEL-series.png with their nominal and measured times.

Time 0 is the start of this script, or FRAMES_T0 (seconds since the epoch,
as `date +%s.%N` prints it) for an animation that starts later on its own,
such as the roll when a note times out.
"""
import os
import subprocess
import sys
import time

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
NESTED = os.path.join(REPO, "tests", "nested.sh")

out_dir, label, slow = sys.argv[1], sys.argv[2], float(sys.argv[3])
rest = sys.argv[4:]
command = []
if "--" in rest:
    i = rest.index("--")
    rest, command = rest[:i], rest[i + 1:]
times = [float(t) for t in rest]
os.makedirs(out_dir, exist_ok=True)

t0 = time.monotonic()
if os.environ.get("FRAMES_T0"):
    t0 += float(os.environ["FRAMES_T0"]) - time.time()
if command:
    subprocess.Popen([NESTED, "run"] + command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

grabs = []
for t in times:
    due = t0 + t * slow / 1000
    wait = due - time.monotonic()
    if wait > 0:
        time.sleep(wait)
    started = time.monotonic()
    path = os.path.join(out_dir, f"{label}-{int(t):05d}.png")
    proc = subprocess.Popen([NESTED, "run", "grim", "-l", "0", "-g", "0,1176 1920x24", path])
    grabs.append((t, (started - t0) * 1000 / slow, path, proc))
for _, _, _, proc in grabs:
    proc.wait()

frames = [(t, real, Image.open(path).convert("RGB")) for t, real, path, _ in grabs]
width = max(img.width for _, _, img in frames)
gap = 22
sheet = Image.new("RGB", (width, len(frames) * (frames[0][2].height + gap)), (0, 0, 0))
draw = ImageDraw.Draw(sheet)
y = 0
for t, real, img in frames:
    draw.text((4, y + 4), f"{label}  t = {t:g} ms (grab started at {real:.0f} ms, slow x{slow:g})", fill=(220, 220, 220))
    sheet.paste(img, (0, y + gap))
    y += img.height + gap
sheet.save(os.path.join(out_dir, f"{label}-series.png"))
for t, real, path, _ in grabs:
    print(f"{t:8g} ms  grab at {real:8.1f} ms  {path}")
print(os.path.join(out_dir, f"{label}-series.png"))
