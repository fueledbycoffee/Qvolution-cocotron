#!/usr/bin/env python3
"""Generate original Flate/PNG/TIFF byte vectors without input files."""
from pathlib import Path
import json,sys,zlib
def paeth(a,b,c):
 p=a+b-c;d=[abs(p-a),abs(p-b),abs(p-c)];return [a,b,c][d.index(min(d))]
def png(rows,mode):
 result=bytearray();prev=bytes(len(rows[0]))
 for j,row in enumerate(rows):
  f=2 if mode=='up' else j%5;result.append(f)
  for k,v in enumerate(row):
   a=row[k-1] if k else 0;b=prev[k];c=prev[k-1] if k else 0
   predictor=[0,a,b,(a+b)//2,paeth(a,b,c)][f];result.append((v-predictor)&255)
  prev=row
 return bytes(result)

def generate(out):
 out=Path(out);out.mkdir(parents=True,exist_ok=True)
 # Original predictor vectors, independent of PDF object lookup.
 vectors=[]
 for mode in ['up','all']:
  rows=[bytes([1,20,50,80,110,140]),bytes([9,30,70,100,150,200]),bytes([20,40,80,140,190,250]),bytes([3,20,60,120,180,240]),bytes([4,25,65,125,185,245])]
  encoded=png(rows,mode);name='predictor-'+mode
  (out/(name+'.flate')).write_bytes(zlib.compress(encoded));(out/(name+'.raw')).write_bytes(b''.join(rows));vectors.append(dict(name=name,predictor=12 if mode=='up' else 15,colors=1,bits=8,columns=6))
 # PNG Sub with RGB byte-stride3 (not adjacent bytes).
 rows=[bytes([20,40,60,70,90,110]),bytes([5,10,15,35,40,45])];encoded=b''.join(b'\x01'+row[:3]+bytes((row[i]-row[i-3])%256 for i in range(3,6)) for row in rows)
 name='predictor-rgb';(out/(name+'.flate')).write_bytes(zlib.compress(encoded));(out/(name+'.raw')).write_bytes(b''.join(rows));vectors.append(dict(name=name,predictor=11,colors=3,bits=8,columns=2))
 # TIFF horizontal differences, packed samples at every supported component depth.
 for bits in [1,2,4,8,16]:
  mask=(1<<bits)-1;values=[mask,0,1,mask//2];encoded=[values[0]]+[(b-a)&mask for a,b in zip(values,values[1:])]
  def pack(values):
   value=0
   for v in values:value=(value<<bits)|v
   bitcount=len(values)*bits;return (value << ((-bitcount)%8)).to_bytes((bitcount+7)//8,'big')
  name=f'predictor-tiff-{bits}';(out/(name+'.flate')).write_bytes(zlib.compress(pack(encoded)));(out/(name+'.raw')).write_bytes(pack(values));vectors.append(dict(name=name,predictor=2,colors=1,bits=bits,columns=4))
 (out/'predictors.json').write_text(json.dumps(vectors))

 # Malformed predictor framing/tags/dimensions must not produce fabricated pixels.
 for name,encoded,changes in [
  ('bad-png-tag',b'\x07\x01\x02\x03',{}),
  ('bad-png-length',b'\x02\x01\x02',{}),
  ('bad-png-colors',b'\x02\x01\x02\x03',{'colors':0}),
  ('bad-png-bits',b'\x02\x01\x02\x03',{'bits':3}),
  ('bad-png-predictor',b'\x02\x01\x02\x03',{'predictor':9}),
  ('bad-tiff-length',b'\x01',{'predictor':2,'columns':3,'bits':16}),
 ]:
  (out/(name+'.flate')).write_bytes(zlib.compress(encoded))
  v=dict(name=name,predictor=12,colors=1,bits=8,columns=3,invalid=True);v.update(changes);vectors.append(v)
 (out/'predictors.json').write_text(json.dumps(vectors))
 return vectors

if __name__=='__main__':
 print('Generated',len(generate(sys.argv[1])),'original predictor vectors')
