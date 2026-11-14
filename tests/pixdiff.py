#!/usr/bin/python3
"""Exact pixel comparison of two screenshots (handoff checks, case N16).

    tests/pixdiff.py A.png B.png [WxH+X+Y] [--ignore WxH+X+Y]...

Prints the number of differing pixels, the largest channel difference and
the bounding box of the differences. Exits 0 only if the images (or the
given region of both) are identical. Each --ignore rectangle is blanked in
both images first (the clock digits, which change with the minute).
Geometries are in physical pixels.
"""
import re
import sys

from PIL import Image, ImageChops, ImageDraw


def geometry(text):
    return tuple(map(int, re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", text).groups()))


args = sys.argv[1:]
ignore = []
while "--ignore" in args:
    i = args.index("--ignore")
    ignore.append(geometry(args[i + 1]))
    del args[i:i + 2]

a = Image.open(args[0]).convert("RGB")
b = Image.open(args[1]).convert("RGB")
for img in (a, b):
    draw = ImageDraw.Draw(img)
    for w, h, x, y in ignore:
        draw.rectangle((x, y, x + w - 1, y + h - 1), fill=(0, 0, 0))
if len(args) > 2:
    w, h, x, y = geometry(args[2])
    a, b = a.crop((x, y, x + w, y + h)), b.crop((x, y, x + w, y + h))
if a.size != b.size:
    sys.exit(f"sizes differ: {a.size} and {b.size}")

diff = ImageChops.difference(a, b)
box = diff.getbbox()
if box is None:
    print(f"identical: 0 of {a.width * a.height} pixels differ")
    sys.exit(0)
changed = None  # 255 where any channel differs
for band in diff.split():
    mask = band.point(lambda v: 255 if v else 0)
    changed = mask if changed is None else ImageChops.lighter(changed, mask)
count = changed.histogram()[255]
peak = max(high for _, high in diff.getextrema())
print(f"different: {count} of {a.width * a.height} pixels differ, largest channel difference {peak}/255, bounding box {box}")
sys.exit(1)
