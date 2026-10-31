#!/usr/bin/env python3
"""Independent host decoder for ORIGINAL generated fixture PNGs only."""
import pathlib, sys
from PIL import Image
root = pathlib.Path(sys.argv[1])
files = sorted(root.glob("*/cpu-client-*.png"))
assert len(files) == 9, len(files)
alpha = opaque = 0
source = [(0, 0, 255, 255), (32, 64, 96, 128), (255, 0, 0, 255), (0, 0, 0, 0)]
for path in files:
    with Image.open(path) as image:
        assert image.size == (2, 2)
        pixels = list(image.convert("RGBA").getdata())
    is_opaque = path.name.endswith("-s120.png")
    expected = []
    for b, g, r, a in source:
        expected.append((r, g, b, 255) if is_opaque else
            tuple(min(255, (c * 255 + a // 2) // a) if a else 0 for c in (r, g, b)) + (a,))
    assert pixels == expected, (path.name, pixels, expected)
    if is_opaque: opaque += 1
    else:
        alpha += 1
        for pixel, (b, g, r, a) in zip(pixels, source):
            assert tuple((c*a+127)//255 for c in pixel[:3]) == (r,g,b)
assert alpha == 8 and opaque == 1
print("PASS: independent PNG dimensions/orientation/RGBA and exact premultiplied reconstruction;8alpha+1opaque")
