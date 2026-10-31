#!/usr/bin/env python3
"""Run actual cache/query source against native FreeType; no guest qualification.

Pass a generated sparse raw CID, dense outline fonts and optionally a bitmap font.
Only Foundation allocation/exception and Objective-C dispatch plumbing is adapted.
"""
import pathlib, re, shlex, subprocess, sys, tempfile
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'Onyx2D/O2Font_freetype.m').read_text()
helper=re.search(r'static NSInteger \*copyUnscaledAdvances\(.*?\n\}',source,re.S).group(0)
helper=re.sub(r'\[NSException raise:.*?\];','fail_error(1);',helper,flags=re.S)
body=re.search(r'- \(void\) fetchAdvances \{(.*?)\n\}',source,re.S).group(1)
query=re.search(r'BOOL O2FontGetGlyphAdvances\(.*?\n\}',(root/'Onyx2D/O2Font.m').read_text(),re.S).group(0)
query=query.replace('O2FontRef self, ','').replace('self->_','_').replace('[self fetchAdvances]','actual()')
program=r'''
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_ADVANCES_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <setjmp.h>
typedef long NSInteger;
typedef int BOOL;
typedef uint16_t O2Glyph;
#define YES 1
#define NO 0
#define MIN(a,b) ((a)<(b)?(a):(b))
#define NSLog(...) ((void)0)
#define CHECK(c,m) do {if(!(c)){fprintf(stderr,"FAIL: %s\n",m);return 1;}}while(0)
static FT_Face _face;
static NSInteger _numberOfGlyphs;
static NSInteger *_advances;
static unsigned char *_advanceIsValid;
static jmp_buf failure;
static int expecting_error,live_allocations,allocation_failure=-1,injection;
static unsigned scalar_calls,batch_calls;
static void fail_error(FT_Error e) {if(expecting_error)longjmp(failure,1);fprintf(stderr,"unexpected helper error %d\n",e);exit(1);}
static void *allocate(size_t bytes) {
 if(allocation_failure==0)return NULL;
 if(allocation_failure>0)allocation_failure--;
 void *p=malloc(bytes);if(p)live_allocations++;return p;
}
static void release(void *p) {if(p){live_allocations--;free(p);}}
#define NSZoneMalloc(zone,n) allocate(n)
#define NSZoneFree(zone,p) release(p)
static FT_Error tracked_batch(FT_Face face,FT_UInt first,FT_UInt count,FT_Int32 flags,FT_Fixed *values) {
 batch_calls++;
 if(injection==1||injection==3)return FT_Err_Invalid_Argument;
 if(injection==2)return FT_Err_Invalid_Table;
 return FT_Get_Advances(face,first,count,flags,values);
}
static FT_Error tracked_scalar(FT_Face face,FT_UInt glyph,FT_Int32 flags,FT_Fixed *value) {
 scalar_calls++;if(injection==3&&glyph==34)return FT_Err_Invalid_Table;
 return FT_Get_Advance(face,glyph,flags,value);
}
#define FT_Get_Advances tracked_batch
#define FT_Get_Advance tracked_scalar
ACTUAL_HELPER
#undef FT_Get_Advances
#undef FT_Get_Advance
static void actual(void) { ACTUAL_BODY }
ACTUAL_QUERY
static int expected_failure(int kind) {
 int before=live_allocations;
 unsigned char *valid=(unsigned char *)(uintptr_t)1;
 expecting_error=1;
 if(setjmp(failure)==0) {
  NSInteger *unexpected=copyUnscaledAdvances(_face,_numberOfGlyphs,&valid);
  release(unexpected);if(valid!=(unsigned char *)(uintptr_t)1)release(valid);
  return 0;
 }
 expecting_error=0;
 if(live_allocations!=before||valid!=(unsigned char *)(uintptr_t)1) {
  fprintf(stderr,"FAIL: error kind%d changed unpublished state/live allocations\n",kind);return 0;
 }
 return 1;
}
int main(int argc,char **argv) {
 FT_Library library;CHECK(argc>=3&&FT_Init_FreeType(&library)==0,"font arguments/native library");
 for(int f=1;f<argc;f++) {
  CHECK(FT_New_Face(library,argv[f],0,&_face)==0,"real face loads");
  _numberOfGlyphs=_face->num_glyphs;_advances=NULL;_advanceIsValid=NULL;
  CHECK(FT_IS_SCALABLE(_face)?FT_Set_Char_Size(_face,0,16*64,72,72)==0:FT_Select_Size(_face,0)==0,"real live size");
  FT_Size_Metrics before=_face->size->metrics;scalar_calls=batch_calls=0;actual();
  CHECK(_face->size->metrics.x_ppem==before.x_ppem&&_face->size->metrics.y_ppem==before.y_ppem&&_face->size->metrics.x_scale==before.x_scale&&_face->size->metrics.y_scale==before.y_scale,"cache preserves live size");
  int rawCID=FT_IS_CID_KEYED(_face)&&!FT_IS_SFNT(_face);unsigned holes=0,reachable=0;
  CHECK(rawCID?(_advanceIsValid!=NULL):(_advanceIsValid==NULL&&scalar_calls==0),"validity/fallback limited to raw CID");
  for(FT_UInt glyph=0;glyph<(FT_UInt)_numberOfGlyphs;glyph++) {
   FT_Fixed reference;FT_Error error=FT_Get_Advance(_face,glyph,FT_LOAD_NO_SCALE,&reference);
   if(error==FT_Err_Invalid_Argument&&rawCID){CHECK(!_advanceIsValid[glyph],"documented CID hole marked inaccessible");holes++;continue;}
   CHECK(error==0,"unexpected reference error");
   CHECK(!rawCID||_advanceIsValid[glyph],"reachable CID remains queryable");
   CHECK(_advances[glyph]==reference/(FT_IS_SCALABLE(_face)?1:64),"real unscaled metric retained");reachable++;
  }
  NSInteger *published=_advances;unsigned char *publishedValid=_advanceIsValid;actual();
  CHECK(_advances==published&&_advanceIsValid==publishedValid,"cache fetch idempotence");
  if(rawCID) {
   CHECK(holes==998&&reachable==3,"independently generated sparse fixture shape");
   O2Glyph glyphs[]={0,34,1000};int values[]={-7,-7,-7};
   CHECK(O2FontGetGlyphAdvances(glyphs,3,values)&&values[0]==1000&&values[1]==608&&values[2]==1000,"actual shared query returns real CID metrics");
   O2Glyph bad[][3]={{0,1,34},{0,33,1000},{0,35,1000},{0,999,1000},{0,1001,34}};
   for(unsigned b=0;b<sizeof(bad)/sizeof(*bad);b++) {
    values[0]=values[1]=values[2]=-7;
    CHECK(!O2FontGetGlyphAdvances(bad[b],3,values),"actual query rejects CID hole/bounds");
    CHECK(values[0]==-7&&values[1]==-7&&values[2]==-7,"invalid CID batch never partially writes");
   }
  }
  for(NSInteger count=255;count<=257&&count<=_numberOfGlyphs;count++) {
   unsigned char *valid=NULL;NSInteger *prefix=copyUnscaledAdvances(_face,count,&valid);
   for(NSInteger i=0;i<count;i++) {
    CHECK(!rawCID||valid[i]==_advanceIsValid[i],"batch-boundary CID validity");
    if(!valid||valid[i])CHECK(prefix[i]==_advances[i],"batch-boundary real widths");
   }release(prefix);release(valid);
  }
  injection=2;CHECK(expected_failure(2),"unexpected batch FT errors propagate with cleanup");
  injection=rawCID?3:1;CHECK(expected_failure(injection),"CID scalar error/dense argument error propagates");injection=0;
  allocation_failure=0;CHECK(expected_failure(10),"advance allocation failure cleanup");allocation_failure=-1;
  if(rawCID){allocation_failure=1;CHECK(expected_failure(11),"CID validity allocation failure cleanup");allocation_failure=-1;}
  printf("PASS: %s CID=%d reachable=%u holes=%u batch=%u scalar=%u\n",FT_Get_Postscript_Name(_face),rawCID,reachable,holes,batch_calls,scalar_calls);
  release(_advances);release(_advanceIsValid);CHECK(live_allocations==0,"all cache allocations released");FT_Done_Face(_face);
 }
 FT_Done_FreeType(library);return 0;
}
'''.replace('ACTUAL_HELPER',helper).replace('ACTUAL_BODY',body).replace('ACTUAL_QUERY',query)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','freetype2'],text=True))
with tempfile.TemporaryDirectory(prefix='font-cid-') as directory:
    path=pathlib.Path(directory);(path/'probe.c').write_text(program)
    subprocess.run(['cc','-O1','-g','-fsanitize=address,undefined',str(path/'probe.c'),*flags,'-o',str(path/'probe')],check=True)
    subprocess.run([str(path/'probe'),*sys.argv[1:]],check=True)
