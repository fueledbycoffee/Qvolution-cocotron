#!/usr/bin/env python3
import sys
from pathlib import Path
from PIL import Image
p=Path(sys.argv[1])
data=p.read_bytes()
assert data[:8]==b'\x89PNG\r\n\x1a\n' and data[12:16]==b'IHDR', 'signature/IHDR'
assert int.from_bytes(data[16:20],'big')==3 and int.from_bytes(data[20:24],'big')==2, 'dimensions'
assert data[24:26]==bytes((8,2)), '8-bit RGB IHDR'
im=Image.open(p); im.load()
assert list(im.convert('RGB').getdata())==[(255,0,0),(0,255,0),(0,0,255),(17,34,51),(128,64,32),(9,199,240)], 'pixel mismatch'
print('PASS independent RGB24 PNG dimensions, type and six exact pixels')
