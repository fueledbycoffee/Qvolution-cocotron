#!/usr/bin/env python3
"""Native production routing/loader bodies, real open fonts; not an ObjC runtime pass."""
from pathlib import Path
import argparse, json, os, shlex, subprocess
p = argparse.ArgumentParser()
p.add_argument('--revision')
p.add_argument('--output', required=True)
a = p.parse_args()
repo = Path(__file__).resolve().parents[1]
out = Path(a.output).resolve(); out.mkdir(parents=True, exist_ok=True)
def read(path):
    return subprocess.check_output(['git', '-C', str(repo), 'show', a.revision+':'+path], text=True) if a.revision else (repo/path).read_text()
def body(source, signature):
    start = source.index(signature); opening = source.index('{', start); end = opening+1; depth = 1
    while depth:
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        end += 1
    return source[start:end]
x = read('AppKit/X11.backend/X11Display.m'); ft = read('Onyx2D/O2Font_freetype.m')
# Only NSString transport/ownership is adapted; Fontconfig calls remain literal.
routing = body(x, 'static NSString *matchedFamily(').replace('NSString *', 'const char *').replace('[family UTF8String]', 'family').replace('[NSString stringWithUTF8String: (const char *) matched]', 'strdup((const char *) matched)').replace('return family;', 'return strdup(family);')
pre = r'''
#define _POSIX_C_SOURCE 200809L
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_MULTIPLE_MASTERS_H
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
typedef int BOOL;
typedef unsigned NSFontTraitMask;
#define YES 1
#define NO 0
#define nil NULL
#define NSItalicFontMask 1
#define NSBoldFontMask 2
#define NSNarrowFontMask 16
#define NSExpandedFontMask 32
static FT_Library library;
static FcConfig *config;
static FT_Library O2FontSharedFreeTypeLibrary(void){return library;}
static FcConfig *O2FontSharedFontConfig(void){return config;}
'''
production = '\n'.join(body(ft, s) for s in ['BOOL O2FontGetFaceStyleFlags(', 'static FT_Face createFaceForMatchInLibrary(', 'static FT_Face createFaceForMatch(', 'static int createExactPostScriptFace('])
production += '\n' + '\n'.join(body(x, s) for s in ['static NSFontTraitMask fontTraitsOfPattern(', 'static int fontPatternDistance(', 'static int compareFontPatterns(']) + '\n' + routing
main = r'''
static unsigned failures;
static void check(int good,const char *what){printf("%s %s\n",good?"PASS":"FAIL",what);failures+=!good;}
static FT_Face catalogFace(const char *requested,unsigned traits){
 const char *family=matchedFamily(config,requested);assert(family);
 printf("ROUTE requested=%s resolved=%s\n",requested,family);
 check(!strcmp(family,requested),"explicit installed family retained");
 FcPattern *q=FcPatternCreate();assert(q&&FcPatternAddString(q,FC_FAMILY,(const FcChar8*)family));
 FcObjectSet *o=FcObjectSetBuild(FC_FAMILY,FC_STYLE,FC_SLANT,FC_WIDTH,FC_WEIGHT,FC_FILE,FC_INDEX,NULL);
 FcFontSet *set=FcFontList(config,q,o);assert(set&&set->nfont);qsort(set->fonts,set->nfont,sizeof(FcPattern*),compareFontPatterns);
 FT_Face selected=NULL;
 for(int i=0;i<set->nfont;i++){
  FT_Face face=createFaceForMatch(set->fonts[i],NO);assert(face);FT_Long flags;assert(O2FontGetFaceStyleFlags(face,&flags));
  unsigned t=fontTraitsOfPattern(set->fonts[i])&~(NSBoldFontMask|NSItalicFontMask);
  if(flags&FT_STYLE_FLAG_BOLD)t|=NSBoldFontMask;if(flags&FT_STYLE_FLAG_ITALIC)t|=NSItalicFontMask;
  if((t&3)==traits){const char *ps=FT_Get_Postscript_Name(face);assert(ps);assert(createExactPostScriptFace(ps,&selected)==1);FT_Done_Face(face);break;}
  FT_Done_Face(face);
 }
 free((void*)family);FcFontSetDestroy(set);FcPatternDestroy(q);FcObjectSetDestroy(o);return selected;
}
int main(void){
 assert(!FT_Init_FreeType(&library));
 const char *files[]={"/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf","/usr/share/fonts/truetype/ubuntu/Ubuntu-Italic[wdth,wght].ttf"};
 const char *names[]={"Ubuntu-Regular","Ubuntu-Bold","Ubuntu-Italic","UbuntuItalic-BoldItalic","Ubuntu-Medium","Ubuntu-Light"};
 const long indices[]={0,327680,0,327680,262144,131072};
 const unsigned traits[]={0,NSBoldFontMask,NSItalicFontMask,NSBoldFontMask|NSItalicFontMask};
 for(int substituted=0;substituted<2;substituted++){
  config=FcConfigCreate();assert(config);
  for(int i=0;i<2;i++)assert(FcConfigAppFontAddFile(config,(const FcChar8*)files[i]));
  assert(FcConfigAppFontAddDir(config,(const FcChar8*)"/usr/share/fonts/truetype/dejavu"));
  if(substituted)assert(FcConfigParseAndLoadFromMemory(config,(const FcChar8*)"<fontconfig><match target='pattern'><test name='family' compare='eq'><string>Ubuntu</string></test><edit name='family' mode='assign' binding='strong'><string>DejaVu Sans</string></edit></match><alias><family>QvolutionMissingAlias</family><prefer><family>DejaVu Sans</family></prefer></alias></fontconfig>",FcTrue));
  printf("CONFIG strong-substitution=%d\n",substituted);
  for(unsigned i=0;i<6;i++){
   FT_Face expected;assert(!FT_New_Face(library,files[i==2||i==3],indices[i],&expected));
   FT_Face got=i<4?catalogFace("Ubuntu",traits[i]):NULL;
   if(i>=4)assert(createExactPostScriptFace(names[i],&got)==1);
   assert(got);const char *actual=FT_Get_Postscript_Name(got);assert(actual);
   // Italic default PS spelling is observed from the actual open file.
   const char *ps=FT_Get_Postscript_Name(expected);assert(ps);
   check(!strcmp(actual,ps)&&got->face_index==indices[i],"catalog selection retains actual PostScript identity and instance");
   for(const char *cp="WiAm";*cp;cp++){
    assert(!FT_Set_Char_Size(got,0,20*64,72,72)&&!FT_Set_Char_Size(expected,0,20*64,72,72));
    assert(!FT_Load_Char(got,*cp,FT_LOAD_RENDER)&&!FT_Load_Char(expected,*cp,FT_LOAD_RENDER));
    printf("GLYPH ps=%s index=%ld cp=%c advance=%ld pixels=%u reference=%ld/%u\n",actual,got->face_index,*cp,got->glyph->advance.x,got->glyph->bitmap.width,expected->glyph->advance.x,expected->glyph->bitmap.width);
    check(got->glyph->advance.x==expected->glyph->advance.x&&got->glyph->bitmap.width==expected->glyph->bitmap.width,"rendered glyph width and advance match independent file/instance");
   }
   FT_Done_Face(got);FT_Done_Face(expected);
  }
  if(substituted){const char *alias=matchedFamily(config,"QvolutionMissingAlias");check(alias&&!strcmp(alias,"DejaVu Sans"),"uninstalled alias still substitutes");free((void*)alias);}
  FcConfigDestroy(config);
 }
 FT_Done_FreeType(library);printf("RESULT %u failures\n",failures);return failures?1:0;
}
'''
src=out/'fixture.c'; binary=out/'fixture'; src.write_text(pre+production+main)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','fontconfig','freetype2'], text=True))
command=['clang','-std=c11','-Wall','-Wextra','-UNDEBUG','-fsanitize=address,undefined',str(src),'-o',str(binary),*flags]
subprocess.run(command,check=True)
r=subprocess.run([str(binary)],text=True,capture_output=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
(out/'result.log').write_text(r.stdout+r.stderr)
(out/'result.json').write_text(json.dumps(dict(revision=a.revision or 'working-tree',exit=r.returncode,command=command,scope='native adapted production C, no NSFontManager runtime execution'),indent=2)+'\n')
print(r.stdout[-1500:]);raise SystemExit(r.returncode)
