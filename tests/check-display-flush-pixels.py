#!/usr/bin/env python3
"""Independent own-input pixel oracle; reads only explicitly supplied fixture PNGs."""
import argparse
from pathlib import Path
from PIL import Image
parser=argparse.ArgumentParser()
parser.add_argument('png',type=Path)
parser.add_argument('--negative',action='store_true',help='corrupt one own-input pixel in memory; expected failure')
args=parser.parse_args()
image=Image.open(args.png).convert('RGBA')
def points(color):
 return [(x,y) for y in range(image.height) for x in range(image.width) if image.getpixel((x,y))==color]
def box(found):
 assert found,'missing expected own-input color'
 return min(x for x,y in found),min(y for x,y in found),max(x for x,y in found)+1,max(y for x,y in found)+1
green=(0,255,0,255);blue=(0,0,255,255)
g=box(points(green));b=box(points(blue))
if args.negative:
 image.putpixel(((g[0]+g[2])//2,(g[1]+g[3])//2),(0,0,0,0))
for color,rect in [(green,g),(blue,b)]:
 assert all(image.getpixel((x,y))==color for y in range(rect[1],rect[3]) for x in range(rect[0],rect[2])),'own solid rectangle pixel mismatch'
gw,gh=g[2]-g[0],g[3]-g[1];bw,bh=b[2]-b[0],b[3]-b[1]
scale=(gw/13+gh/11+bw/19+bh/7)/4
assert scale>0 and all(abs(actual-logical*scale)<=1.5 for actual,logical in [(gw,13),(gh,11),(bw,19),(bh,7)]),'asymmetric input dimensions/scale mismatch'
assert g[0]<b[0] and g[1]>b[1],'own input orientation mismatch: green bottom-left, blue top-right'
assert len(points((255,0,0,255)))>(gw*gh+bw*bh)*4,'missing predominant own red field'
print(f'PASS own client pixels {image.width}x{image.height}, green={g}, blue={b}, scale≈{scale:.3f}; not native compositor visibility')
