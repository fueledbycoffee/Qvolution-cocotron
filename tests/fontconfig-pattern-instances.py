#!/usr/bin/env python3
"""Actual own matching/loader source over private open-font config; no guest pass."""
from pathlib import Path
import argparse,subprocess,tempfile,shlex,os
repo=Path(__file__).resolve().parents[1];p=argparse.ArgumentParser();p.add_argument('--baseline',help='own-source commit with legacy face0 loader');a=p.parse_args()
def body(source,signature):
 start=source.index(signature);opening=source.index('{',start);depth=1;end=opening+1
 while depth:
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  end+=1
 return source[start:end]
source=subprocess.check_output(['git','show',a.baseline+':Onyx2D/O2Font_freetype.m'],cwd=repo,text=True) if a.baseline else (repo/'Onyx2D/O2Font_freetype.m').read_text()
pre=r'''#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef int BOOL;
#define YES 1
#define NO 0
#define nil NULL
static FT_Library library;static FcConfig *config;
static FT_Library O2FontSharedFreeTypeLibrary(void){return library;}
static FcConfig *O2FontSharedFontConfig(void){return config;}
'''
if a.baseline:
 # Adapt only NSString->UTF8 argument transport around the old actual C calls.
 # Valid existing-file guards are satisfied by inputs; no full ObjC API claim.
 method=body(source,'+ (NSString *) filenameForPattern:')
 c=method[method.index('    FcConfig *config ='):method.index('    NSString *res =')]
 c=c.replace('[pattern UTF8String]','pattern')
 initializer=body(source,'- (instancetype) initWithFontName:')
 start=initializer.index('    FT_Face face;');end=initializer.index('    if (error != 0)',start)
 load=initializer[start:end].replace('[freetypePath fileSystemRepresentation]','(const char *)filename')
 production='static FT_Face loadPattern(const char *pattern){\n'+c+load+'\nFcPatternDestroy(match);return error ? NULL : face;\n}\n'
else:
 production='\n'.join(body(source,x) for x in ['static FT_Face createFaceForMatchInLibrary(','static FT_Face createFaceForMatch(','static FT_Face createMatchingFaceWithEncodingRequirement(','static FT_Face createPatternFace('])+'\n#define loadPattern createPatternFace\n'
test=r'''
static unsigned failures;
static void expect(int c,const char *m){printf("%s: %s\n",c?"PASS":"FAIL",m);failures+=!c;}
int main(void){assert(!FT_Init_FreeType(&library));config=FcConfigCreate();assert(config);
 assert(FcConfigAppFontAddFile(config,(const FcChar8*)"/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf"));
 assert(FcConfigAppFontAddFile(config,(const FcChar8*)"/usr/share/fonts/truetype/ubuntu/Ubuntu-Italic[wdth,wght].ttf"));
 struct Case{const char *pattern,*ps;long index,width;} cases[]={
 {"Ubuntu:style=Regular","Ubuntu-Regular",0,924},
 {"Ubuntu:style=Bold","Ubuntu-Bold",327680,942},
 {"Ubuntu:style=Bold Italic","UbuntuItalic-BoldItalic",327680,931},
 {"Ubuntu:style=Condensed Bold","Ubuntu-CondensedBold",720896,721}};
 for(unsigned i=0;i<sizeof(cases)/sizeof(*cases);i++){
  FcPattern *query=FcNameParse((const FcChar8*)cases[i].pattern);assert(query&&FcConfigSubstitute(config,query,FcMatchPattern));FcDefaultSubstitute(query);FcResult result;FcPattern *match=FcFontMatch(config,query,&result);assert(match);int index;assert(FcPatternGetInteger(match,FC_INDEX,0,&index)==FcResultMatch);assert(index==cases[i].index);FcPatternDestroy(match);FcPatternDestroy(query);
  FT_Face face=loadPattern(cases[i].pattern);assert(face);const char *ps=FT_Get_Postscript_Name(face);assert(ps);unsigned g=FT_Get_Char_Index(face,'W');assert(g&&!FT_Load_Glyph(face,g,FT_LOAD_NO_SCALE|FT_LOAD_NO_HINTING));
  printf("MEASURE pattern=%s actualPS=%s index=%ld W=%ld expectedPS=%s index=%ld W=%ld\n",cases[i].pattern,ps,face->face_index,face->glyph->advance.x,cases[i].ps,cases[i].index,cases[i].width);
  expect(!strcmp(ps,cases[i].ps)&&face->face_index==cases[i].index&&face->glyph->advance.x==cases[i].width,"actual pattern loader retains matched file/index/named-instance metrics");FT_Done_Face(face);
 }
 FcConfigDestroy(config);FT_Done_FreeType(library);printf("RESULT %u failures\n",failures);return failures?1:0;}
'''
with tempfile.TemporaryDirectory(prefix='qv-pattern-instance-') as d:
 f=Path(d)/'test.c';out=Path(d)/'test';f.write_text(pre+production+test)
 flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','fontconfig','freetype2'],text=True))
 subprocess.run(['clang','-std=c11','-UNDEBUG','-fsanitize=address,undefined',str(f),'-o',str(out),*flags],check=True)
 r=subprocess.run([str(out)],env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'},timeout=20);raise SystemExit(r.returncode)
