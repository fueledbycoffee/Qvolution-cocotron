#!/usr/bin/env python3
"""Actual own trait source + real open FreeType faces; no guest/AppKit pass."""
from pathlib import Path
import argparse,subprocess,tempfile,shlex,os
repo=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--baseline',help='own-source commit with old CT trait body');p.add_argument('--vector',type=Path,help='original make-variable-style-vector.py output');args=p.parse_args()
def body(source,signature):
 start=source.index(signature);opening=source.index('{',start);depth=1;end=opening+1
 while depth:
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  end+=1
 return source[start:end]
pre=r'''#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_MULTIPLE_MASTERS_H
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
typedef int BOOL;
#define YES 1
#define NO 0
'''
if args.baseline:
 source=subprocess.check_output(['git','show',args.baseline+':CoreText/CTFont.m'],cwd=repo,text=True)
 production='''typedef FT_Face CTFontRef;typedef unsigned CTFontSymbolicTraits;
#define kCTFontTraitItalic 1
#define kCTFontTraitBold 2
#define kCTFontTraitMonoSpace 1024
static FT_Face fontTraitFace(CTFontRef face){return face;}
'''+body(source,'CTFontSymbolicTraits CTFontGetSymbolicTraits(')+'''
static BOOL readFlags(FT_Face face,FT_Long *flags){if(!face||!flags)return NO;*flags=CTFontGetSymbolicTraits(face)&3;return YES;}
'''
else:
 source=(repo/'Onyx2D/O2Font_freetype.m').read_text()
 production=r'''#define TEST_NEW_HELPER 1
static int failAllocation,failMM,failCoordinates,mmCopies,mmReleases;
static void *probeMalloc(size_t n){return failAllocation?NULL:malloc(n);}
static FT_Error probeMM(FT_Face face,FT_MM_Var **variation){if(failMM)return FT_Err_Invalid_Argument;FT_Error error=FT_Get_MM_Var(face,variation);if(!error)mmCopies++;return error;}
static FT_Error probeCoordinates(FT_Face face,FT_UInt count,FT_Fixed *values){return failCoordinates?FT_Err_Invalid_Argument:FT_Get_Var_Design_Coordinates(face,count,values);}
static FT_Error probeDoneMM(FT_Library library,FT_MM_Var *variation){mmReleases++;return FT_Done_MM_Var(library,variation);}
#define malloc probeMalloc
#define FT_Get_MM_Var probeMM
#define FT_Get_Var_Design_Coordinates probeCoordinates
#define FT_Done_MM_Var probeDoneMM
'''+body(source,'BOOL O2FontGetFaceStyleFlags(')+r'''
#undef malloc
#undef FT_Get_MM_Var
#undef FT_Get_Var_Design_Coordinates
#undef FT_Done_MM_Var
#define readFlags O2FontGetFaceStyleFlags
''' 
test=r'''
static unsigned failures;
static void expect(int c,const char *m){printf("%s: %s\n",c?"PASS":"FAIL",m);failures+=!c;}
int main(int argc,char **argv){FT_Library library;assert(!FT_Init_FreeType(&library));
 struct Case{const char *path,*ps;long index,flags;} cases[]={
 {"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf","DejaVuSans",0,0},
 {"/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf","DejaVuSans-Bold",0,FT_STYLE_FLAG_BOLD},
 {"/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf","DejaVuSans-Oblique",0,FT_STYLE_FLAG_ITALIC},
 {"/usr/share/fonts/truetype/dejavu/DejaVuSans-BoldOblique.ttf","DejaVuSans-BoldOblique",0,FT_STYLE_FLAG_BOLD|FT_STYLE_FLAG_ITALIC},
 {"/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf","Ubuntu-Regular",0,0},
 {"/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf","Ubuntu-Medium",262144,0},
 {"/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf","Ubuntu-Bold",327680,FT_STYLE_FLAG_BOLD},
 {"/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf","Ubuntu-CondensedBold",720896,FT_STYLE_FLAG_BOLD},
 {"/usr/share/fonts/truetype/ubuntu/Ubuntu-Italic[wdth,wght].ttf","UbuntuItalic-BoldItalic",327680,FT_STYLE_FLAG_BOLD|FT_STYLE_FLAG_ITALIC}};
 for(unsigned i=0;i<sizeof(cases)/sizeof(*cases);i++){
  FT_Face face;assert(!FT_New_Face(library,cases[i].path,cases[i].index,&face));assert(!strcmp(FT_Get_Postscript_Name(face),cases[i].ps));
  FT_Long raw=face->style_flags,got=-1;assert(readFlags(face,&got));printf("MEASURE PS=%s index=%ld raw=%ld actual=%ld expected=%ld\n",cases[i].ps,cases[i].index,raw,got,cases[i].flags);expect(got==cases[i].flags,"actual static/named variable basic style");
  assert(face->style_flags==raw);assert(!readFlags(face,NULL));
#ifdef TEST_NEW_HELPER
  if(i==4){
   FT_Long sentinel=19;int beforeCopies=mmCopies,beforeReleases=mmReleases;
   failAllocation=1;assert(!readFlags(face,&sentinel)&&sentinel==19);failAllocation=0;
   assert(mmCopies==beforeCopies+1&&mmReleases==beforeReleases+1);
   beforeCopies=mmCopies;beforeReleases=mmReleases;failCoordinates=1;assert(!readFlags(face,&sentinel)&&sentinel==19);failCoordinates=0;
   assert(mmCopies==beforeCopies+1&&mmReleases==beforeReleases+1);
   beforeCopies=mmCopies;beforeReleases=mmReleases;failMM=1;assert(!readFlags(face,&sentinel)&&sentinel==19);failMM=0;
   assert(mmCopies==beforeCopies&&mmReleases==beforeReleases);
  }
#endif
  FT_Long again=-1;assert(readFlags(face,&again)&&again==got);FT_Done_Face(face);
 }
 FT_Long canary=17;assert(!readFlags(NULL,&canary)&&canary==17);
 // Struct-level guard: non-SFNT AdobeMM must keep raw flags without interpreting
 // arbitrary whole-number MM coordinates on the OpenType registered-axis scale.
 FT_FaceRec mm={0};FT_GlyphSlotRec slot={0};mm.glyph=&slot;mm.face_flags=FT_FACE_FLAG_MULTIPLE_MASTERS;mm.style_flags=FT_STYLE_FLAG_BOLD;
 FT_Long mmFlags=0;assert(readFlags(&mm,&mmFlags)&&mmFlags==FT_STYLE_FLAG_BOLD);
 if(argc>1){
  FT_Face vector;assert(!FT_New_Face(library,argv[1],0,&vector)&&FT_IS_SFNT(vector)&&FT_HAS_MULTIPLE_MASTERS(vector));
  struct AxisCase{FT_Fixed weight,ital,slant;FT_Long flags;} axes[]={
   {400L*65536L,0,0,0},{699L*65536L,0,0,0},{700L*65536L,0,0,FT_STYLE_FLAG_BOLD},
   {400L*65536L,65536L,0,FT_STYLE_FLAG_ITALIC},{400L*65536L,0,-10L*65536L,FT_STYLE_FLAG_ITALIC},
   {700L*65536L,65536L,0,FT_STYLE_FLAG_BOLD|FT_STYLE_FLAG_ITALIC},
   {400L*65536L,0,10L*65536L,FT_STYLE_FLAG_ITALIC},{400L*65536L,0,0,0}};
  for(unsigned i=0;i<sizeof(axes)/sizeof(*axes);i++){
   FT_Fixed coordinates[]={axes[i].weight,axes[i].ital,axes[i].slant};assert(!FT_Set_Var_Design_Coordinates(vector,3,coordinates));FT_Long got=-1;assert(readFlags(vector,&got));expect(got==axes[i].flags,"actual original SFNT current wght/ital/slnt coordinates follow explicit classification policy");
  }
  FT_Done_Face(vector);
 }
 FT_Done_FreeType(library);printf("RESULT %u failures\n",failures);return failures?1:0;}
'''
with tempfile.TemporaryDirectory(prefix='qv-variable-traits-') as d:
 f=Path(d)/'test.c';out=Path(d)/'test';f.write_text(pre+production+test)
 flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','freetype2'],text=True))
 subprocess.run(['clang','-std=c11','-UNDEBUG','-Wall','-Wextra','-fsanitize=address,undefined',str(f),'-o',str(out),*flags],check=True)
 r=subprocess.run([str(out),*([str(args.vector)] if args.vector else [])],env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'},timeout=20);raise SystemExit(r.returncode)
