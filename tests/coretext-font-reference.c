#include <stdio.h>
#include <string.h>
#include <ft2build.h>
#include FT_FREETYPE_H
int main(int argc,char **argv) {
 if(argc!=3)return 2;FT_Library library;if(FT_Init_FreeType(&library))return 3;
 const char *names[]={"DejaVuSansMono","DejaVuSans"};unsigned scalars[]={65,87,101,0xe9,0x301,0x378,0x1d538};puts("{\"fonts\":[");
 for(int i=0;i<2;i++){
  FT_Face face;if(FT_New_Face(library,argv[i+1],0,&face))return 4;const char *ps=FT_Get_Postscript_Name(face);if(!ps||strcmp(ps,names[i])||face->units_per_EM==0)return 5;
  printf("%s{\"postscript\":\"%s\",\"units\":%u,\"glyphs\":[",i?",":"",ps,face->units_per_EM);
  for(unsigned j=0;j<sizeof(scalars)/sizeof(scalars[0]);j++){
   FT_UInt glyph=FT_Get_Char_Index(face,scalars[j]);long advance=0;
   if(glyph){if(FT_Load_Glyph(face,glyph,FT_LOAD_NO_SCALE|FT_LOAD_NO_HINTING|FT_LOAD_IGNORE_TRANSFORM))return 6;advance=face->glyph->metrics.horiAdvance;}
   printf("%s{\"scalar\":%u,\"glyph\":%u,\"advance\":%ld}",j?",":"",scalars[j],glyph,advance);
  }puts("]}");FT_Done_Face(face);
 }puts("]}");FT_Done_FreeType(library);return 0;
}
