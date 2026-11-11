#!/usr/bin/python3
"""Exact pixel comparison of two screenshots (handoff checks, case N16).

    tests/pixdiff.py A.png B.png [WxH+X+Y]

Prints the number of differing pixels, the largest channel difference and
the bounding box of the differences. Exits 0 only if the images (or the
given region of both) are identical.
"""
import re
import sys

from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
if len(sys.argv) > 3:
    w, h, x, y = map(int, re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", sys.argv[3]).groups())
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
