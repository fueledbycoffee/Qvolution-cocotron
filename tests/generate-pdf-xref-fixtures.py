#!/usr/bin/env python3
"""Original minimal PDF1.5 fixtures; no input/vendor PDFs or external tools."""
from pathlib import Path
import sys,zlib,runpy
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
helpers=runpy.run_path(str(Path(__file__).with_name('generate-pdf-predictor-fixtures.py')))
png=helpers['png'];vectors=helpers['generate'](out)
RED=b'1 0 0 rg 0 0 32 32 re f\n';GREEN=b'0 1 0 rg 0 0 32 32 re f\n'
BODIES={1:b'<< /Type /Catalog /Pages 2 0 R >>',2:b'<< /Type /Pages /Count 1 /Kids [3 0 R] >>',3:b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 32 32] /Contents 4 0 R /Resources << >> >>'}
def obj(pdf,n,body,offsets):
 offsets[n]=len(pdf);pdf.extend(f'{n} 0 obj\n'.encode()+body+b'\nendobj\n')
def stream(data,extra=b''):
 return b'<< /Length '+str(len(data)).encode()+b' '+extra+b' >>\nstream\n'+data+b'\nendstream'
def xref(pdf,offsets,records,number,size,w=(1,4,2),index=None,extra=b'',compress=True,predictor=None,truncate=False):
 at=len(pdf);offsets[number]=at;records[number]=(1,at,0)
 order=list(range(size)) if index is None else [n for start,count in zip(index[::2],index[1::2]) for n in range(start,start+count)]
 rows=[b''.join(v.to_bytes(width,'big') for v,width in zip(records.get(n,(0,0,65535)),w) if width) for n in order]
 if truncate:rows=rows[:-1]
 data=b''.join(rows);params=b''
 if predictor:
  data=png(rows,predictor);params=f' /DecodeParms << /Predictor {12 if predictor=="up" else 15} /Columns {sum(w)} >>'.encode()
 if compress:data=zlib.compress(data);params=b'/Filter /FlateDecode '+params
 ix=b'' if index is None else b' /Index ['+b' '.join(str(n).encode() for n in index)+b']'
 dictionary=f'/Type /XRef /Size {size} /W [{w[0]} {w[1]} {w[2]}] /Root 1 0 R'.encode()+ix+params+extra
 obj(pdf,number,stream(data,dictionary),offsets);pdf.extend(b'startxref\n'+str(at).encode()+b'\n%%EOF\n');return at

def make(name,compressed=False,w=(1,4,2),index=None,predictor=None,filtering=True,truncate=False,bad_object=None):
 pdf=bytearray(b'%PDF-1.5\n');offsets={};records={}
 if compressed:
  pieces=[];header=bytearray();cursor=0
  for n in [1,2,3]:
   header.extend(f'{n} {cursor} '.encode())
   body=BODIES[n]
   if bad_object=='self-ref' and n==1:body=b'1 0 R'
   if bad_object=='mutual-ref' and n in [1,2]:body=f'{3-n} 0 R'.encode()
   pieces.append(body+b' ');cursor+=len(pieces[-1])
  data=bytes(header)+b''.join(pieces)
  first=len(data)+1 if bad_object=='first' else len(header)
  count=9 if bad_object=='count' else 3
  obj(pdf,5,stream(zlib.compress(data),f'/Type /ObjStm /N {count} /First {first} /Filter /FlateDecode'.encode()),offsets)
  for i,n in enumerate([1,2,3]):records[n]=(2,5,9 if bad_object=='index' and n==1 else i)
 else:
  for n,body in BODIES.items():obj(pdf,n,body,offsets)
 obj(pdf,4,stream(RED),offsets)
 for n,at in offsets.items():records[n]=(1,at,0)
 xref(pdf,offsets,records,6 if compressed else 5,7 if compressed else 6,w,index,compress=filtering,predictor=predictor,truncate=truncate)
 (out/name).write_bytes(pdf)
make('flate.pdf');make('raw.pdf',filtering=False);make('object-stream.pdf',compressed=True)
make('default-width.pdf',w=(0,4,0),index=[1,5]);make('index.pdf',index=[1,3,4,2])
make('png-up.pdf',predictor='up');make('png-all.pdf',predictor='all')
make('truncated.pdf',truncate=True)
# Incremental xref stream points into a traditional previous section.
for name,free in [('incremental.pdf',False),('free-newest.pdf',True)]:
 pdf=bytearray(b'%PDF-1.5\n');offsets={}
 for n,body in BODIES.items():obj(pdf,n,body,offsets)
 obj(pdf,4,stream(RED),offsets);prev=len(pdf);pdf.extend(b'xref\n0 5\n0000000000 65535 f \n')
 for n in range(1,5):pdf.extend(f'{offsets[n]:010d} 00000 n \n'.encode())
 pdf.extend(b'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n'+str(prev).encode()+b'\n%%EOF\n')
 if not free:obj(pdf,4,stream(GREEN),offsets)
 records={4:(0,0,1) if free else (1,offsets[4],0)}
 xref(pdf,offsets,records,5,6,index=[4,2],extra=f' /Prev {prev}'.encode())
 (out/name).write_bytes(pdf)
# The stream length remains correct; malformed structural fields are explicit.
base=(out/'raw.pdf').read_bytes()
(out/'bad-width.pdf').write_bytes(base.replace(b'/W [1 4 2]',b'/W [1 9 2]'))
(out/'bad-index.pdf').write_bytes(base.replace(b'/Size 6',b'/Size 6 /Index [0 7]'))
# Repeated Prev must terminate; startxref location itself stays unchanged.
raw=(out/'raw.pdf').read_bytes();at=int(raw.split(b'startxref\n')[-1].splitlines()[0])
(out/'prev-cycle.pdf').write_bytes(raw.replace(b'/Root 1 0 R',b'/Root 1 0 R /Prev '+str(at).encode()))
for kind in ['self-ref','mutual-ref','first','count','index']:
 make('bad-object-'+kind+'.pdf',compressed=True,bad_object=kind)
# Supplemental xref stream searched before the old traditional section.
pdf=bytearray(b'%PDF-1.5\n');offsets={}
for n,body in BODIES.items():obj(pdf,n,body,offsets)
obj(pdf,4,stream(RED),offsets);prev=len(pdf);pdf.extend(b'xref\n0 5\n0000000000 65535 f \n')
for n in range(1,5):pdf.extend(f'{offsets[n]:010d} 00000 n \n'.encode())
pdf.extend(b'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n'+str(prev).encode()+b'\n%%EOF\n')
obj(pdf,4,stream(GREEN),offsets);supplement=xref(pdf,offsets,{4:(1,offsets[4],0)},5,6,index=[4,2])
latest=len(pdf);pdf.extend(b'xref\n5 1\n'+f'{supplement:010d} 00000 n \n'.encode()+f'trailer\n<< /Size 6 /Root 1 0 R /Prev {prev} /XRefStm {supplement} >>\nstartxref\n{latest}\n%%EOF\n'.encode())
(out/'hybrid.pdf').write_bytes(pdf)
# Final ObjStm tokens need no whitespace after their last byte.
for kind,body in [('integer',b'32'),('real',b'32.0'),('name',b'/Named'),('boolean',b'true'),('null',b'null')]:
 pdf=bytearray(b'%PDF-1.5\n');offsets={};records={}
 obj(pdf,1,BODIES[1][:-2]+b'/Probe 7 0 R >>',offsets)
 obj(pdf,2,BODIES[2],offsets)
 page=BODIES[3].replace(b'[0 0 32 32]',b'[0 0 7 0 R 7 0 R]') if kind in ['integer','real'] else BODIES[3]
 obj(pdf,3,page,offsets);obj(pdf,4,stream(RED),offsets)
 obj(pdf,5,stream(zlib.compress(b'7 0 '+body),b'/Type /ObjStm /N 1 /First 4 /Filter /FlateDecode'),offsets)
 records={n:(1,at,0) for n,at in offsets.items()};records[7]=(2,5,0)
 xref(pdf,offsets,records,6,8);(out/('eof-'+kind+'.pdf')).write_bytes(pdf)
pdf=bytearray(b'%PDF-1.5\n');offsets={}
for n in [2,3]:obj(pdf,n,BODIES[n],offsets)
obj(pdf,4,stream(RED),offsets)
obj(pdf,5,stream(zlib.compress(b'1 0'+BODIES[1]),b'/Type /ObjStm /N 1 /First 3 /Filter /FlateDecode'),offsets)
records={n:(1,at,0) for n,at in offsets.items()};records[1]=(2,5,0)
xref(pdf,offsets,records,6,7);(out/'compact-header.pdf').write_bytes(pdf)

pdf=bytearray(b'%PDF-1.5\n');offsets={}
xref(pdf,offsets,{},5,2147483650,index=[2147483648,1])
(out/'bad-map-key.pdf').write_bytes(pdf)
print('Original fixtures ready:',len(list(out.glob('*.pdf'))),'PDFs and',len(vectors),'predictor cases')
