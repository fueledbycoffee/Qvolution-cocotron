#!/usr/bin/env python3
"""Original PNG inputs; stdlib encoder and independent Pillow decode oracle."""
import pathlib, struct, sys, zlib
from PIL import Image
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
rgba = [(200, 100, 50, 128), (12, 32, 60, 64), (255, 3, 128, 0), (17, 201, 43, 255), (128, 230, 40, 1)]
cases = [('rgba', 6, bytes(sum((list(p) for p in rgba), [])), b'', rgba),
         ('rgb', 2, bytes(sum((list(p[:3]) for p in rgba), [])), b'', [(*p[:3], 255) for p in rgba]),
         ('gray-alpha', 4, bytes(sum(([p[0], p[3]] for p in rgba), [])), b'', [(p[0],)*3+(p[3],) for p in rgba]),
         ('palette', 3, bytes(range(5)), chunk(b'PLTE', bytes(sum((list(p[:3]) for p in rgba), []))) + chunk(b'tRNS', bytes(p[3] for p in rgba)), rgba)]
for name, color, row, extras, pixels in cases:
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 5, 2, 8, color, 0, 0, 0)) + extras
    data += chunk(b'IDAT', zlib.compress((b'\0' + row)*2)) + chunk(b'IEND', b'')
    path = out/(name+'.png'); path.write_bytes(data)
    im = Image.open(path).convert('RGBA')
    expected = pixels*2
    assert im.tobytes() == bytes(v for pixel in expected for v in pixel)
    # Pillow's own RGBa conversion and alpha compositor are independent oracles.
    premul = bytes(im.convert('RGBa').tobytes())
    math_pre = bytes(v for p in expected for v in (*( (c*p[3]+127)//255 for c in p[:3]), p[3]))
    assert premul == math_pre
    white = Image.alpha_composite(Image.new('RGBA', im.size, (255,)*4), im).tobytes()
    math_white = bytes(v for p in expected for v in (*((c*p[3]+255*(255-p[3])+127)//255 for c in p[:3]), 255))
    assert white == math_white
    (out/(name+'.straight')).write_bytes(im.tobytes())
    (out/(name+'.premul')).write_bytes(premul)
    (out/(name+'.white')).write_bytes(white)
print('PASS: 4 original PNG cases, Pillow straight/premultiplied/white-composite expectations')
