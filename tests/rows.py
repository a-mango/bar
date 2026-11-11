#!/usr/bin/python3
"""Row summary of a screenshot region, for layer and handoff checks.

    tests/rows.py IMAGE [FIRST_ROW [LAST_ROW]]

Prints one line per run of identical rows: the physical row range, the
number of distinct colors in a row and the most common one. With a strip
drawn over the bar, the bar's rows collapse into one single-color run.
"""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
width, height = img.size
first = int(sys.argv[2]) if len(sys.argv) > 2 else 0
last = int(sys.argv[3]) if len(sys.argv) > 3 else height - 1
print(f"{sys.argv[1]}: {width}x{height}, rows {first}..{last}")

run = None  # (start, key)
for y in range(first, last + 2):
    key = None
    if y <= last:
        colors = img.crop((0, y, width, y + 1)).getcolors(width)
        count, color = max(colors)
        key = (len(colors), "#%02x%02x%02x" % color, count)
    if run and run[1] != key:
        n, color, count = run[1]
        print(f"  rows {run[0]:4d}..{y - 1:4d}: {n:3d} color(s), most common {color} on {count} of {width} px")
        run = None
    if key and not run:
        run = (y, key)
