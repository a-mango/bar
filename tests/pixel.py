#!/usr/bin/python3
"""Colors and boxes in a screenshot of HEADLESS-1 (scale 2), in logical px.
PX_SCALE=1 reads a screenshot of the scale 1 second output (tests/scene.sh
focus-other) instead.

    tests/pixel.py IMAGE color X Y          the color at (X, Y), as #rrggbb
    tests/pixel.py IMAGE run X Y            the run of that color along row Y
                                            that contains X, as "start end"
    tests/pixel.py IMAGE ink X0 Y0 X1 Y1    number of distinct colors in the box
    tests/pixel.py IMAGE count COLOR X0 Y0 X1 Y1   pixels of that #rrggbb color
                                            in the box
    tests/pixel.py IMAGE diff OTHER X0 Y0 X1 Y1   pixels that differ in the box
    tests/pixel.py IMAGE bbox OTHER         bounding box of the differences,
                                            as "x0 y0 x1 y1"
"""
import os
import sys

from PIL import Image, ImageChops

img = Image.open(sys.argv[1]).convert("RGB")
op, args = sys.argv[2], sys.argv[3:]


SCALE = int(os.environ.get("PX_SCALE", "2"))


def phys(v):
    return int(round(float(v) * SCALE))


def hexcolor(c):
    return "#%02x%02x%02x" % c


if op == "color":
    print(hexcolor(img.getpixel((phys(args[0]) + SCALE // 2, phys(args[1]) + SCALE // 2))))
elif op == "run":
    x, y = phys(args[0]) + SCALE // 2, phys(args[1]) + SCALE // 2
    c = img.getpixel((x, y))
    a = x
    while a > 0 and img.getpixel((a - 1, y)) == c:
        a -= 1
    b = x
    while b < img.width - 1 and img.getpixel((b + 1, y)) == c:
        b += 1
    print(f"{a / SCALE:g} {(b + 1) / SCALE:g}")
elif op == "ink":
    box = tuple(phys(v) for v in args)
    print(len(img.crop(box).getcolors(1 << 20)))
elif op == "count":
    color = tuple(int(args[0][i:i + 2], 16) for i in (1, 3, 5))
    box = tuple(phys(v) for v in args[1:])
    print(sum(n for n, c in img.crop(box).getcolors(1 << 20) if c == color))
elif op in ("diff", "bbox"):
    other = Image.open(args[0]).convert("RGB")
    if op == "diff":
        box = tuple(phys(v) for v in args[1:])
        d = ImageChops.difference(img.crop(box), other.crop(box))
    else:
        d = ImageChops.difference(img, other)
    mask = d.convert("L").point(lambda v: 255 if v else 0)
    if op == "diff":
        print(mask.histogram()[255])
    else:
        b = mask.getbbox()
        print(" ".join(f"{v / SCALE:g}" for v in b) if b else "none")
else:
    sys.exit(__doc__)
