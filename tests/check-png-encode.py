#!/usr/bin/env python3
"""Independent Pillow + IHDR oracle for original public PNG boundary vectors."""
from pathlib import Path
import argparse,struct,tempfile
from PIL import Image
NAMES=('rgba-straight','rgba-premul','argb-straight','argb-premul','bgra-straight','bgra-premul','abgr-straight','abgr-premul','rgb','rgbx','xrgb','bgrx','xbgr')
def expected(name):
 out=[]
 for y in range(2):
  for x,a in enumerate((0,1,64,128,254,255)):
   channels=[31+x*29,193-y*67-x*11,17+y*109+x*7]
   if name.endswith('premul'):
    channels=[min(255,(((v*a+127)//255)*255+a//2)//a) if a else 0 for v in channels]
   out.append(tuple(channels+[a if name.endswith(('straight','premul')) else 255]))
 return out
def check(directory):
 failures=[]
 for name in NAMES:
  try:
   p=directory/(name+'.png'); data=p.read_bytes()
   assert data[:8]==b'\x89PNG\r\n\x1a\n' and data[12:16]==b'IHDR','signature/IHDR'
   w,h,depth,color=struct.unpack('>IIBB',data[16:26]);assert (w,h,depth)==(6,2,8),'dimensions/depth'
   assert color==(6 if name.endswith(('straight','premul')) else 2),'truecolor alpha contract'
   with Image.open(p) as im:
    im.load();actual=list(im.convert('RGBA').getdata())
   assert actual==expected(name),'independent straight RGBA pixels'
  except Exception as e:failures.append(f'{name}: {e}')
 return failures
def selftest():
 with tempfile.TemporaryDirectory() as d:
  p=Path(d)
  for n in NAMES:
   im=Image.new('RGBA',(6,2));im.putdata(expected(n));im.convert('RGBA' if n.endswith(('straight','premul')) else 'RGB').save(p/(n+'.png'))
  assert not check(p)
  im=Image.open(p/'rgba-premul.png').convert('RGBA');im.putpixel((3,1),(1,2,3,128));im.save(p/'rgba-premul.png')
  assert len(check(p))==1
 print('PASS independent oracle selftest + actual one-pixel negative')
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('directory',nargs='?',type=Path);ap.add_argument('--selftest',action='store_true');a=ap.parse_args()
 if a.selftest:selftest()
 else:
  ap.error('explicit directory required') if a.directory is None else None
  errors=check(a.directory)
  for error in errors:print('FAIL',error)
  emitted=sum((a.directory/(name+'.png')).is_file() for name in NAMES)
  print(f'{len(NAMES)-len(errors)}/{emitted} emitted PNG files match; {len(NAMES)-emitted} cases not emitted (13 requested)')
  raise SystemExit(bool(errors))
