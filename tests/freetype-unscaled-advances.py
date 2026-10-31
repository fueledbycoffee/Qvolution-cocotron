#!/usr/bin/env python3
"""Run the actual cache-fill body with native FreeType; provide font file paths.

Only Foundation allocation/exception plumbing is substituted. Guest coverage is
freetype-unscaled-advances.m; this host probe adds reproducible native timings.
"""
import pathlib, re, shlex, subprocess, sys, tempfile
source = pathlib.Path(__file__).resolve().parents[1] / 'Onyx2D/O2Font_freetype.m'
text = source.read_text()
body = re.search(r'- \(void\) fetchAdvances \{(.*?)\n\}', text, re.S).group(1)
helper = re.search(r'static NSInteger \*copyUnscaledAdvances\(.*?\n\}', text, re.S).group(0)
# Only exception transport changes: actual bounds, allocations, batching, units and publication remain source-derived.
helper = re.sub(r'\[NSException raise:.*?\];', 'fail_error(1);', helper, flags=re.S)
program = r'''
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_ADVANCES_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <setjmp.h>
typedef long NSInteger;
typedef double O2Float;
typedef uint16_t O2Glyph;
#define MIN(a,b) ((a)<(b)?(a):(b))
#define NSZoneMalloc(zone,n) malloc(n)
#define NSZoneFree(zone,p) free(p)
static FT_Face _face;
static long _numberOfGlyphs;
static double _unitsPerEm;
static NSInteger *_advances;
static jmp_buf failure;
static int expecting_error;
static void fail_error(FT_Error e) { if(expecting_error)longjmp(failure,1);fprintf(stderr,"FreeType error %d\n",e); exit(1); }
ACTUAL_HELPER
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static void actual(void) { ACTUAL_BODY }
int main(int argc,char **argv) {
 FT_Library library; if(argc<2||FT_Init_FreeType(&library)) return 1;
 expecting_error=1;if(setjmp(failure)==0){copyUnscaledAdvances(NULL,0);return 1;}expecting_error=0;
 puts("PASS: actual helper rejects null/zero cache");
 for(int f=1;f<argc;f++) {
  if(FT_New_Face(library,argv[f],0,&_face))return 1;
  _numberOfGlyphs=_face->num_glyphs;_unitsPerEm=_face->units_per_EM;_advances=NULL;
  if(FT_IS_SCALABLE(_face) ? FT_Set_Char_Size(_face,0,16*64,72,72) : FT_Select_Size(_face,0))return 1;
  FT_Size_Metrics before=_face->size->metrics;double start=now();actual();double fill=now()-start;
  if(_face->size->metrics.y_ppem!=before.y_ppem || _face->size->metrics.x_ppem!=before.x_ppem || _face->size->metrics.x_scale!=before.x_scale || _face->size->metrics.y_scale!=before.y_scale) {
   fprintf(stderr,"FAIL: %s advance cache changed live face size (16 -> %u), fill %.6fs\n",_face->family_name,_face->size->metrics.y_ppem,fill);return 1;
  }
  start=now();
  for(FT_UInt glyph=0;glyph<_numberOfGlyphs;glyph++) {
   if(FT_Load_Glyph(_face,glyph,FT_LOAD_NO_SCALE)||_advances[glyph]!=_face->glyph->advance.x/(FT_IS_SCALABLE(_face)?1:64)) {
    fprintf(stderr,"FAIL: unscaled advance mismatch at glyph %u\n",glyph);return 1;
   }
  }
  double reference=now()-start;
  expecting_error=1;if(setjmp(failure)==0){copyUnscaledAdvances(_face,0);return 1;}expecting_error=0;
  for(NSInteger count=255;count<=257;count++)if(count<=_numberOfGlyphs){
   NSInteger *prefix=copyUnscaledAdvances(_face,count);
   for(NSInteger index=0;index<count;index++)if(prefix[index]!=_advances[index])return 1;
   free(prefix);
  }
  NSInteger *published=_advances;actual();if(published!=_advances){fputs("FAIL: fetch is not idempotent\n",stderr);return 1;}
  // Exercise the actual FT failure path just past the final glyph, across the final batch boundary.
  expecting_error=1;if(setjmp(failure)==0){copyUnscaledAdvances(_face,_numberOfGlyphs+1);return 1;}expecting_error=0;
  printf("PASS: %s glyphs=%ld fill=%.6fs outline_reference=%.6fs live_ppem=%u\n",_face->family_name,_numberOfGlyphs,fill,reference,_face->size->metrics.y_ppem);
  free(_advances);FT_Done_Face(_face);
 }
 FT_Done_FreeType(library); return 0;
}
'''.replace('ACTUAL_BODY', body).replace('ACTUAL_HELPER', helper)
flags = shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','freetype2'], text=True))
with tempfile.TemporaryDirectory(prefix='font-advances-') as directory:
    path = pathlib.Path(directory)
    (path/'probe.c').write_text(program)
    subprocess.run(['cc','-O2',str(path/'probe.c'),*flags,'-o',str(path/'probe')],check=True)
    subprocess.run([str(path/'probe'),*sys.argv[1:]],check=True)
