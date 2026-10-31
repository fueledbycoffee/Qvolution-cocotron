#!/usr/bin/env python3
"""Original SFNT name-table variants derived only from an explicit open DejaVu font.

No proprietary font input. Preserve glyph tables, update table/file checksums,
and mutate only full-name record metadata/payload within its existing bounds.
"""
import argparse,json,struct
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('dejavu_bold_oblique',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
source=a.dejavu_bold_oblique.read_bytes();u16=lambda b,o:struct.unpack_from('>H',b,o)[0]
def checksum(b):
 b=bytes(b)+bytes((-len(b))%4);return sum(struct.unpack('>'+str(len(b)//4)+'I',b))&0xffffffff
n=u16(source,4);tables={}
for i in range(n):
 off=12+16*i;tag,check,start,length=struct.unpack_from('>4sIII',source,off);assert start+length<=len(source);tables[tag]=(off,start,length)
_,start,length=tables[b'name'];fmt,count,storage=struct.unpack_from('>HHH',source,start);assert fmt==0 and storage>=6+12*count
records=[start+6+12*i for i in range(count) if u16(source,start+6+12*i+6)==4];assert records
assert all(u16(source,r+8)>=17 and storage+u16(source,r+10)+u16(source,r+8)<=length for r in records)
a.output.mkdir(parents=True,exist_ok=True)
for mode in ['missing','odd-utf16','bad-surrogate','unsupported','empty','unicode-unknown','unicode-variation','unicode','macroman','english-preference']:
 b=bytearray(source)
 for r in records:
  if mode=='missing':struct.pack_into('>H',b,r+6,0);continue
  if mode=='macroman':platform,encoding,language=1,0,0;payload='Fixture Mac Romé'.encode('mac_roman')
  elif mode=='english-preference':
   if u16(source,r)==1:platform,encoding,language=1,0,0;payload=b'Fallback Locale'
   else:platform,encoding,language=3,1,0x409;payload='English Preferred'.encode('utf-16-be')
  else:
   platform,encoding,language=3,1,0x409
   payload={'odd-utf16':b'\0','bad-surrogate':b'\xd8\0','unsupported':b'\0X','empty':b'','unicode-unknown':b'\0X','unicode-variation':b'\0X','unicode':'\U0001d11e Full'.encode('utf-16-be')}.get(mode)
   if mode=='unsupported':encoding=2
   if mode=='unicode':platform,encoding,language=0,4,0
   if mode=='unicode-unknown':platform,encoding,language=0,65535,0
   if mode=='unicode-variation':platform,encoding,language=0,5,0
  assert len(payload)<=u16(source,r+8)
  struct.pack_into('>HHHHH',b,r,platform,encoding,language,4,len(payload))
  at=start+storage+u16(source,r+10);b[at:at+len(payload)]=payload
 directory,_,_=tables[b'name'];struct.pack_into('>I',b,directory+4,checksum(b[start:start+length]))
 _,head,_=tables[b'head'];struct.pack_into('>I',b,head+8,0);struct.pack_into('>I',b,head+8,(0xb1b0afba-checksum(b))&0xffffffff)
 assert checksum(b)==0xb1b0afba
 (a.output/(mode+'.ttf')).write_bytes(b)
print(json.dumps({'variants':10,'input':'explicit open DejaVu Sans Bold Oblique','expected_full':{'unicode':'\U0001d11e Full','macroman':'Fixture Mac Romé','english-preference':'English Preferred'},'invalid_full':['missing','odd-utf16','bad-surrogate','unsupported','empty','unicode-unknown','unicode-variation']}))
