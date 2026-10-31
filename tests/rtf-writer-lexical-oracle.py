#!/usr/bin/env python3
"""Own public-format oracle, no framework reader or producer extraction."""
from pathlib import Path
import runpy,sys
parse=runpy.run_path(str(Path(__file__).with_name('rtf-readiness-oracle.py')))['parse']
suffix=' {brace}\\slash é e\u0301 \U0001d538\n\tend\r'
expected={'full.rtf':'0123456789abcdef'*256+suffix,'slice.rtf':suffix,'empty.rtf':''}
for name,text in expected.items():
 actual=parse((Path(sys.argv[1])/name).read_bytes())[0]
 assert actual==text,(name,'decoded text differs',len(actual),len(text))
 print('PASS:',name,'independent signed-Unicode/escape/group/text oracle',len(text))
