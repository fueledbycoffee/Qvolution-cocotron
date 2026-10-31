#!/usr/bin/env python3
"""Actual C helper bodies + real Fontconfig/FreeType; no CTFont/runtime mock pass."""
from pathlib import Path
import subprocess,shlex,tempfile
repo=Path(__file__).resolve().parents[1]
s=(repo/'Onyx2D/O2Font_freetype.m').read_text()+(repo/'Onyx2D/O2UIFontPolicy.h').read_text()
def body(name):
 start=s.index(('BOOL ' if name=='O2FontGetFaceStyleFlags' else 'static int ' if name=='O2UIFontPatternHasFamily' else 'static FT_Face ')+name+'(');opening=s.index('{',start);depth=1;end=opening+1
 while depth:
  if s[end]=='{':depth+=1
  elif s[end]=='}':depth-=1
  end+=1
 return s[start:end]
pre='''#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_MULTIPLE_MASTERS_H
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef int BOOL;
#define YES 1
#define NO 0
static FT_Library library;
static FcConfig *config;
static const char *uiFontFamily="sans-serif", *fixedFontFamily="monospace";
static FT_Library O2FontSharedFreeTypeLibrary(void){return library;}
static FcConfig *O2FontSharedFontConfig(void){return config;}
'''
test=r'''
int main(void){
 assert(FT_Init_FreeType(&library)==0);config=FcConfigCreate();assert(config);
 assert(FcConfigAppFontAddDir(config,(const FcChar8*)"/usr/share/fonts/truetype/dejavu"));
 assert(FcConfigAppFontAddFile(config,(const FcChar8*)"/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf"));
 assert(FcConfigAppFontAddFile(config,(const FcChar8*)"/usr/share/fonts/truetype/ubuntu/Ubuntu-Italic[wdth,wght].ttf"));
 const char *languages[]={NULL,"en","fr","ja"};
 for(int mono=0;mono<2;mono++)for(int bold=0;bold<2;bold++)for(unsigned l=0;l<4;l++){
  fprintf(stderr,"PHASE selection mono=%d bold=%d language=%u\n",mono,bold,l);FT_Face face=createUserInterfaceFace(mono,bold,languages[l]);assert(face);
  assert(face->units_per_EM>0&&face->num_glyphs>0&&face->family_name&&face->family_name[0]);
  FT_Long actualStyle;assert(O2FontGetFaceStyleFlags(face,&actualStyle));
  assert(!mono||FT_IS_FIXED_WIDTH(face));assert(!bold||(actualStyle&FT_STYLE_FLAG_BOLD));
  assert(FT_Set_Char_Size(face,0,17*64,72,72)==0);FT_Pos advance[3];const unsigned cp[]={'A','i','W'};
  for(int i=0;i<3;i++){unsigned glyph=FT_Get_Char_Index(face,cp[i]);assert(glyph&&FT_Load_Glyph(face,glyph,FT_LOAD_DEFAULT)==0);advance[i]=face->glyph->advance.x;assert(advance[i]>0);}
  assert(!mono||advance[1]==advance[2]);FT_Done_Face(face);
 }
 uiFontFamily="DejaVu Sans";fixedFontFamily="DejaVu Sans Mono";
 for(int mono=0;mono<2;mono++)for(int bold=0;bold<2;bold++){
  FT_Face exact=createUserInterfaceFace(mono,bold,NULL);assert(exact);
  assert(!strcmp(exact->family_name,mono?"DejaVu Sans Mono":"DejaVu Sans"));FT_Done_Face(exact);
 }
 // The common actual loader also receives the unchanged coverage caller's typed charset.
 FcPattern *pattern=FcPatternCreate();FcCharSet *set=FcCharSetCreate();assert(pattern&&set);
 assert(FcCharSetAddChar(set,'A')&&FcCharSetAddChar(set,0x03a9)&&FcPatternAddCharSet(pattern,FC_CHARSET,set));
 FT_Face covered=createMatchingFace(pattern);assert(covered&&FT_Get_Char_Index(covered,'A')&&FT_Get_Char_Index(covered,0x03a9));
 FT_Done_Face(covered);FcCharSetDestroy(set);FcPatternDestroy(pattern);
 FcConfigDestroy(config);config=FcConfigCreate();assert(config);
 assert(!createUserInterfaceFace(0,0,NULL)&&!createUserInterfaceFace(1,1,"en"));
 FcConfigDestroy(config);FT_Done_FreeType(library);
 puts("PASS actual UI-selection/shared-loader source with real Fontconfig/FT traits, languages and glyphs; no CTFont or app qualification");
}
'''
with tempfile.TemporaryDirectory(prefix='qv-ui-face-') as d:
 f=Path(d)/'test.c';out=Path(d)/'test';f.write_text(pre+body('O2FontGetFaceStyleFlags')+'\n'+body('createFaceForMatchInLibrary')+'\n'+body('createFaceForMatch')+'\n'+body('createMatchingFaceWithEncodingRequirement')+'\n'+body('createMatchingFace')+'\n'+body('O2UIFontPatternHasFamily')+'\n'+body('createUserInterfaceFace')+test)
 flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','fontconfig','freetype2'],text=True))
 subprocess.run(['clang','-std=c11','-UNDEBUG','-fsanitize=address,undefined',str(f),'-o',str(out),*flags],check=True)
 import os
 subprocess.run([str(out)],check=True,timeout=20,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'})
