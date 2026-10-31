#!/usr/bin/env python3
"""Original invalid-UTF8 full-name vector from an explicit open URW Type1 font."""
from pathlib import Path
import argparse,struct
p=argparse.ArgumentParser();p.add_argument('nimbus_sans_regular',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
b=bytearray(a.nimbus_sans_regular.read_bytes());assert b[:2]==b'\x80\x01'
length=struct.unpack_from('<I',b,2)[0];assert 6+length<=len(b)
marker=b'/FullName (Nimbus Sans)';at=b.find(marker,6,6+length);assert at>=0
# Same-length modification in the clear FontInfo string; no encrypted glyph data changes.
b[at+len(b'/FullName (')]=0xff
a.output.write_bytes(b)
print('Wrote original open Type1 invalid-UTF8 FontInfo.full_name vector')
