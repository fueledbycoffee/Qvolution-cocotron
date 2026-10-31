#!/usr/bin/env python3
"""Actual lookup/loader bodies and real native Fontconfig/FT, private configs only."""
from pathlib import Path
import subprocess,shlex,tempfile,os,struct
repo=Path(__file__).resolve().parents[1];source=(repo/'Onyx2D/O2Font_freetype.m').read_text()
def body(signature):
 start=source.index(signature);begin=source.index('{',start);depth=1;end=begin+1
 while depth:
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  end+=1
 return source[start:end]
pre=r'''
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef int BOOL;
#define YES 1
#define NO 0
static FT_Library library;static FcConfig *config;
static FT_Library O2FontSharedFreeTypeLibrary(void){return library;}
static FcConfig *O2FontSharedFontConfig(void){return config;}
'''
test=r'''
int main(int argc,char**argv){assert(argc==4);assert(!FT_Init_FreeType(&library));config=FcConfigCreate();assert(config&&FcConfigAppFontAddFile(config,(const FcChar8*)argv[1]));
 FT_Face face=NULL;assert(createExactPostScriptFace("DejaVuSans-BoldOblique",&face)==1&&face);assert(!strcmp(FT_Get_Postscript_Name(face),"DejaVuSans-BoldOblique"));assert((face->style_flags&FT_STYLE_FLAG_BOLD)&&(face->style_flags&FT_STYLE_FLAG_ITALIC));assert(FT_Set_Char_Size(face,0,17*64,72,72)==0);unsigned glyph=FT_Get_Char_Index(face,'W');assert(glyph&&FT_Load_Glyph(face,glyph,FT_LOAD_DEFAULT)==0&&face->glyph->advance.x>0);FT_Done_Face(face);
 assert(createExactPostScriptFace("QvolutionUnknownPostScriptName",&face)==0&&!face);assert(createExactPostScriptFace("",&face)==0&&!face);
 FcFontSet *owned=FcConfigGetFonts(config,FcSetApplication);assert(owned&&owned->nfont==1);FcPattern *entry=owned->fonts[0];
 assert(FcPatternDel(entry,FC_INDEX)&&FcPatternAddInteger(entry,FC_INDEX,1));assert(createExactPostScriptFace("DejaVuSans-BoldOblique",&face)==-1&&!face); // Invalid advertised face index must not open face0.
 assert(FcPatternDel(entry,FC_INDEX)&&FcPatternAddInteger(entry,FC_INDEX,0));assert(FcPatternDel(entry,FC_POSTSCRIPT_NAME)&&FcPatternAddString(entry,FC_POSTSCRIPT_NAME,(const FcChar8*)"QvolutionWrongCachedName"));assert(createExactPostScriptFace("QvolutionWrongCachedName",&face)==-1&&!face); // Actual face identity defeats contradictory configured metadata.
 assert(FcPatternDel(entry,FC_FILE)&&FcPatternAddString(entry,FC_FILE,(const FcChar8*)"/qvolution-original-missing-font-file"));assert(createExactPostScriptFace("QvolutionWrongCachedName",&face)==-1&&!face);
 FcPattern *nonunicode=FcPatternCreate();assert(nonunicode&&FcPatternAddString(nonunicode,FC_FILE,(const FcChar8*)argv[2])&&FcPatternAddInteger(nonunicode,FC_INDEX,0));
 face=createFaceForMatch(nonunicode,NO);assert(face&&face->num_glyphs>0&&FT_Set_Charmap(face,face->charmaps[0])==0&&FT_Get_Char_Index(face,65)>0);FT_Done_Face(face);assert(!createFaceForMatch(nonunicode,YES));FcPatternDestroy(nonunicode);
 FcConfigDestroy(config);config=FcConfigCreate();assert(config&&FcConfigAppFontAddFile(config,(const FcChar8*)argv[3]));
 assert(createExactPostScriptFace("DejaVuSans",&face)==1&&face&&face->face_index==1);FT_Done_Face(face);
 assert(createExactPostScriptFace("DejaVu Sans",&face)==0&&!face);assert(createExactPostScriptFace("dejavusans",&face)==0&&!face); // Normalized family spelling is not an exact advertised PS name.
 FT_Face first,second;assert(!FT_New_Face(library,argv[3],0,&first)&&!FT_New_Face(library,argv[3],1,&second));unsigned cp;for(cp=1;cp<0xd800;cp++)if(!FT_Get_Char_Index(first,cp)&&FT_Get_Char_Index(second,cp))break;assert(cp<0xd800);
 FcCharSet *chars=FcCharSetCreate();FcPattern *coverage=FcPatternCreate();assert(chars&&coverage&&FcCharSetAddChar(chars,cp)&&FcPatternAddCharSet(coverage,FC_CHARSET,chars));face=createMatchingFace(coverage);assert(face&&face->face_index==1&&FT_Get_Char_Index(face,cp));FT_Done_Face(face);FcPatternDestroy(coverage);FcCharSetDestroy(chars);FT_Done_Face(first);FT_Done_Face(second);
 FcConfigDestroy(config);config=NULL;assert(createExactPostScriptFace("DejaVuSans-BoldOblique",&face)==-1&&!face);FT_Done_FreeType(library);
 puts("PASS actual exact-PS/file-index/metadata-error lookup and generic non-Unicode vs strict loader; no guest API qualification");
}
'''
with tempfile.TemporaryDirectory(prefix='qv-ps-name-') as d:
 ttc=bytearray(b'ttcf'+struct.pack('>4I',0x10000,2,0,0))
 for index,path in enumerate(('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')):
  data=bytearray(Path(path).read_bytes());assert data[:4]==b'\x00\x01\x00\x00'
  while len(ttc)%4:ttc.append(0)
  offset=len(ttc);struct.pack_into('>I',ttc,12+index*4,offset)
  for table in range(struct.unpack_from('>H',data,4)[0]):
   location=12+table*16+8;struct.pack_into('>I',data,location,struct.unpack_from('>I',data,location)[0]+offset)
  ttc.extend(data)
 collection=Path(d)/'original-open-fonts.ttc';collection.write_bytes(ttc)
 f=Path(d)/'test.c';out=Path(d)/'test';f.write_text(pre+body('static FT_Face createFaceForMatchInLibrary(')+'\n'+body('static FT_Face createFaceForMatch(')+'\n'+body('static FT_Face createMatchingFaceWithEncodingRequirement(')+'\n'+body('static FT_Face createMatchingFace(')+'\n'+body('static int createExactPostScriptFace(')+test)
 flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','fontconfig','freetype2'],text=True));subprocess.run(['clang','-std=c11','-UNDEBUG','-fsanitize=address,undefined',str(f),'-o',str(out),*flags],check=True)
 subprocess.run([str(out),'/usr/share/fonts/truetype/dejavu/DejaVuSans-BoldOblique.ttf',str(repo/'tests/fixtures/qvolution-fontspecific.bdf'),str(collection)],check=True,timeout=20,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'})
