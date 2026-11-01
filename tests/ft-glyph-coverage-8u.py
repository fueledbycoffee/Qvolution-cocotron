#!/usr/bin/env python3
"""Execute the production 8-bit glyph coverage span natively.
FreeType gray bitmaps hold coverage 0..255; the Onyx2D 8-bit span helpers
weight on a 0..256 scale. Full glyph ink must stay fully opaque, and partial
coverage must not lose a level to the scale mismatch.
"""
import argparse, os, re, subprocess, tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
header=(root/'Onyx2D/include/Onyx2D/O2argb8u.h').read_text()
ft=(a.source or root/'Onyx2D/O2Context_builtin_FT.m').read_text()
def block(text,start):
 begin=text.index(start);opening=text.index('{',begin);depth=1;end=opening+1
 while depth:
  depth+={'{':1,'}':-1}.get(text[end],0);end+=1
 return text[begin:end]
parts=[header[header.index('typedef struct {\n    uint8_t b;'):header.index('} O2argb8u_LE;')+len('} O2argb8u_LE;')],
 'typedef O2argb8u_LE O2argb8u;','#define COVERAGE_MULTIPLIER 256']
for name in ['static inline uint32_t inverseCoverage(','static inline uint32_t multiplyByCoverage(',
 'static inline O2argb8u O2argb8uMultiplyByCoverageNoBypass(','static inline O2argb8u O2argb8uMultiplyByCoverage(',
 'static inline O2argb8u O2argb8uMultiplyByCoverageAdd(','static inline O2argb8u O2argb8uAdd(']:parts.append(block(header,name))
parts.append(block(ft,'static void applyCoverageToSpan_lRGBA8888_PRE('))
src='#include <assert.h>\n#include <stdint.h>\n#include <stdio.h>\n#define RI_INT_MIN(a,b) ((a)<(b)?(a):(b))\n'+'\n'.join(parts)+r'''
int main(void){
 for(int g=0;g<=255;g++){
  // Opaque black ink over a transparent surface, and white ink over black.
  O2argb8u dst={0,0,0,0},src={0,0,0,255};unsigned char cov=(unsigned char)g;
  applyCoverageToSpan_lRGBA8888_PRE(&dst,&cov,&src,1);
  int ideal=g; // alpha = coverage exactly, within one level of rounding
  if(dst.a<ideal-1||dst.a>ideal){printf("FAIL coverage %d gave alpha %d\n",g,dst.a);return 1;}
  O2argb8u under={0,0,0,255},white={255,255,255,255};
  applyCoverageToSpan_lRGBA8888_PRE(&under,&cov,&white,1);
  if(under.a!=255||under.r<ideal-1||under.r>ideal){printf("FAIL coverage %d over opaque gave r=%d a=%d\n",g,under.r,under.a);return 1;}
 }
 O2argb8u full={0,0,0,0},ink={0,0,0,255};unsigned char cov=255;applyCoverageToSpan_lRGBA8888_PRE(&full,&cov,&ink,1);assert(full.a==255);
 puts("PASS 8-bit glyph coverage: 0..255 FreeType gray maps to exact alpha (full ink opaque), opaque destinations stay opaque");return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='glyph-coverage-') as folder:
 folder=Path(folder);(folder/'probe.c').write_text(src)
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-Wno-unused-function','-fsanitize=address,undefined',str(folder/'probe.c'),'-o',str(folder/'probe')],check=True)
 subprocess.run([str(folder/'probe')],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
