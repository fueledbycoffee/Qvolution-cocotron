#!/usr/bin/env python3
"""Run the actual cache-fill body with native FreeType; provide font file paths.

Only Foundation allocation/exception plumbing is substituted. Guest coverage is
freetype-unscaled-advances.m; this host probe adds reproducible native timings.
"""
import pathlib, re, shlex, subprocess, sys, tempfile
source = pathlib.Path(__file__).resolve().parents[1] / 'Onyx2D/O2Font_freetype.m'
body = re.search(r'- \(void\) fetchAdvances \{(.*?)\n\}', source.read_text(), re.S).group(1)
body = re.sub(r'\[NSException raise: NSInternalInconsistencyException\s+format: @"FreeType advance lookup failed: %d", error\];', 'fail_error(error);', body)
program = r'''
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_ADVANCES_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
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
static void fail_error(FT_Error e) { fprintf(stderr,"FreeType error %d\n",e); exit(1); }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static void actual(void) { ACTUAL_BODY }
int main(int argc,char **argv) {
 FT_Library library; if(argc<2||FT_Init_FreeType(&library)) return 1;
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
  printf("PASS: %s glyphs=%ld fill=%.6fs outline_reference=%.6fs live_ppem=%u\n",_face->family_name,_numberOfGlyphs,fill,reference,_face->size->metrics.y_ppem);
  free(_advances);FT_Done_Face(_face);
 }
 FT_Done_FreeType(library); return 0;
}
'''.replace('ACTUAL_BODY', body)
flags = shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','freetype2'], text=True))
with tempfile.TemporaryDirectory(prefix='font-advances-') as directory:
    path = pathlib.Path(directory)
    (path/'probe.c').write_text(program)
    subprocess.run(['cc','-O2',str(path/'probe.c'),*flags,'-o',str(path/'probe')],check=True)
    subprocess.run([str(path/'probe'),*sys.argv[1:]],check=True)
