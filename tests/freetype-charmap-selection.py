#!/usr/bin/env python3
"""Exercise the actual initialization charmap-selection block with native FreeType.

Only NSLog is suppressed; font selection/ownership remain native. Pass font paths.
Set QV_CHARMAP_SOURCE to test an independently saved before-source file.
"""
import os, pathlib, resource, shlex, subprocess, sys, tempfile
source = pathlib.Path(os.environ.get('QV_CHARMAP_SOURCE', pathlib.Path(__file__).resolve().parents[1] / 'Onyx2D/O2Font_freetype.m')).read_text()
start = source.index('    int i, numberOfCharMaps = face->num_charmaps;')
end = source.index('\n    if (!(face->face_flags & FT_FACE_FLAG_SCALABLE))', start)
body = source[start:end]
program = r'''
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdio.h>
#include <stdlib.h>
typedef int BOOL;
#define TRUE 1
#define FALSE 0
#define NSLog(...) ((void)0)
static FT_Encoding actual(FT_Face face) {
 FT_Encoding _ftEncoding;
 ACTUAL_BODY
 return _ftEncoding;
}
int main(int argc, char **argv) {
 FT_Library library; if(argc<2 || FT_Init_FreeType(&library)) return 2;
 for(int f=1;f<argc;f++) {
  FT_Face face; if(FT_New_Face(library,argv[f],0,&face)) return 2;
  int hasUnicode=0; for(int i=0;i<face->num_charmaps;i++)
   hasUnicode |= face->charmaps[i]->encoding==FT_ENCODING_UNICODE;
  FT_Encoding selected=actual(face);
  if(!face->num_charmaps) {
   if(selected!=FT_ENCODING_NONE || face->charmap || FT_Get_Char_Index(face,'A')) return 1;
   puts("PASS: valid charmapless font keeps no mapping");
  } else if(hasUnicode) {
   if(selected!=FT_ENCODING_UNICODE || !face->charmap || face->charmap->encoding!=FT_ENCODING_UNICODE) return 1;
   puts("PASS: real Unicode mapping retained");
  } else {
   if(selected!=FT_ENCODING_APPLE_ROMAN && selected!=face->charmaps[0]->encoding) return 1;
   puts("PASS: real available mapping retained");
  }
  FT_Done_Face(face);
 }
 FT_Done_FreeType(library); return 0;
}
'''.replace('ACTUAL_BODY', body)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','freetype2'], text=True))
with tempfile.TemporaryDirectory(prefix='font-charmap-') as directory:
    path=pathlib.Path(directory)
    (path/'probe.c').write_text(program)
    subprocess.run(['cc','-O2',str(path/'probe.c'),*flags,'-o',str(path/'probe')],check=True)
    result=subprocess.run([str(path/'probe'),*sys.argv[1:]], preexec_fn=lambda:resource.setrlimit(resource.RLIMIT_CORE,(0,0)))
    sys.exit(result.returncode if result.returncode>=0 else 128-result.returncode)
